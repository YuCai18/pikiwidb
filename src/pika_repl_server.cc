// Copyright (c) 2019-present, Qihoo, Inc.  All rights reserved.
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.

#include "include/pika_repl_server.h"

#include <glog/logging.h>

#include "include/pika_conf.h"
#include "include/pika_rm.h"
#include "include/pika_server.h"

using pstd::Status;

extern PikaServer* g_pika_server;
extern std::unique_ptr<PikaReplicaManager> g_pika_rm;

PikaReplServer::PikaReplServer(const std::set<std::string>& ips, int port, int cron_interval) {
  server_tp_ = std::make_unique<net::ThreadPool>(PIKA_REPL_SERVER_TP_SIZE, 100000, "PikaReplServer");
  pika_repl_server_thread_ = std::make_unique<PikaReplServerThread>(ips, port, cron_interval);
  pika_repl_server_thread_->set_thread_name("PikaReplServer");
}

PikaReplServer::~PikaReplServer() {
  LOG(INFO) << "PikaReplServer exit!!!";
}

int PikaReplServer::Start() {
  pika_repl_server_thread_->set_thread_name("PikaReplServer");
  int res = pika_repl_server_thread_->StartThread();
  if (res != net::kSuccess) {
    LOG(FATAL) << "Start Pika Repl Server Thread Error: " << res
               << (res == net::kBindError
                       ? ": bind port " + std::to_string(pika_repl_server_thread_->ListenPort()) + " conflict"
                       : ": create thread error ")
               << ", Listen on this port to handle the request sent by the Slave";
  }
  res = server_tp_->start_thread_pool();
  if (res != net::kSuccess) {
    LOG(FATAL) << "Start ThreadPool Error: " << res
               << (res == net::kCreateThreadError ? ": create thread error " : ": other error");
  }
  return res;
}

int PikaReplServer::Stop() {
  server_tp_->stop_thread_pool();
  pika_repl_server_thread_->StopThread();
  pika_repl_server_thread_->Cleanup();
  return 0;
}

pstd::Status PikaReplServer::SendSlaveBinlogChips(const std::string& ip, int port,
                                                  const std::vector<WriteTask>& tasks) {
  InnerMessage::InnerResponse response;
  BuildBinlogSyncResp(tasks, &response);

  std::string binlog_chip_pb;
  if (!response.SerializeToString(&binlog_chip_pb)) {
    return Status::Corruption("Serialized Failed");
  }

  if (binlog_chip_pb.size() > static_cast<size_t>(g_pika_conf->max_conn_rbuf_size())) {
    for (const auto& task : tasks) {
      InnerMessage::InnerResponse response;
      std::vector<WriteTask> tmp_tasks;
      tmp_tasks.push_back(task);
      BuildBinlogSyncResp(tmp_tasks, &response);
      if (!response.SerializeToString(&binlog_chip_pb)) {
        return Status::Corruption("Serialized Failed");
      }
      pstd::Status s = Write(ip, port, binlog_chip_pb);
      if (!s.ok()) {
        return s;
      }
    }
    return pstd::Status::OK();
  }
  return Write(ip, port, binlog_chip_pb);
}

// 优化的批量发送方法，直接处理db_name和批量任务
pstd::Status PikaReplServer::SendSlaveBinlogChipsRequest(const std::string& ip_port, const std::string& db_name,
                                                const std::vector<WriteTask>& tasks) {
  if (tasks.empty()) {
    return Status::OK();
  }

  // 解析ip和port
  std::string ip;
  int port = 0;
  if (!pstd::ParseIpPortString(ip_port, ip, port)) {
    return Status::InvalidArgument("Invalid ip_port format: " + ip_port);
  }

  // 估算消息大小，提前预留空间
  size_t estimated_size = 0;
  for (const auto& task : tasks) {
    estimated_size += task.binlog_chip_.binlog_.size() + 100; // 100字节用于其他协议开销
  }
  
  // 大型批次日志，需要拆分
  const size_t MAX_CHUNK_SIZE = g_pika_conf->max_conn_rbuf_size() * 0.9; // 留10%的缓冲
  
  // 如果估计大小超过限制，拆分成多个请求发送
  if (estimated_size > MAX_CHUNK_SIZE && tasks.size() > 1) {
    // 分批次发送
    size_t current_size = 0;
    std::vector<WriteTask> batch;
    batch.reserve(std::min(tasks.size(), size_t(100)));
    
    for (const auto& task : tasks) {
      size_t task_size = task.binlog_chip_.binlog_.size() + 100;
      
      // 如果单个任务就超过最大大小，单独处理
      if (task_size > MAX_CHUNK_SIZE) {
        // 先发送当前批次
        if (!batch.empty()) {
          Status s = SendSlaveBinlogChips(ip, port, batch);
          if (!s.ok()) {
            return s;
          }
          batch.clear();
          current_size = 0;
        }
        
        // 单独发送这个大任务
        std::vector<WriteTask> single_task = {task};
        Status s = SendSlaveBinlogChips(ip, port, single_task);
        if (!s.ok()) {
          return s;
        }
        continue;
      }
      
      // 如果添加当前任务会超过大小限制，先发送当前批次
      if (!batch.empty() && current_size + task_size > MAX_CHUNK_SIZE) {
        Status s = SendSlaveBinlogChips(ip, port, batch);
        if (!s.ok()) {
          return s;
        }
        batch.clear();
        current_size = 0;
      }
      
      // 添加到当前批次
      batch.push_back(task);
      current_size += task_size;
    }
    
    // 发送剩余批次
    if (!batch.empty()) {
      return SendSlaveBinlogChips(ip, port, batch);
    }
    return Status::OK();
  }
  
  // 正常情况，直接发送
  return SendSlaveBinlogChips(ip, port, tasks);
}

void PikaReplServer::BuildBinlogOffset(const LogOffset& offset, InnerMessage::BinlogOffset* boffset) {
  // 直接设置字段，减少不必要的临时变量和赋值操作
  boffset->set_filenum(offset.b_offset.filenum);
  boffset->set_offset(offset.b_offset.offset);
  boffset->set_term(offset.l_offset.term);
  boffset->set_index(offset.l_offset.index);
}

void PikaReplServer::BuildBinlogSyncResp(const std::vector<WriteTask>& tasks, InnerMessage::InnerResponse* response) {
  response->set_code(InnerMessage::kOk);
  response->set_type(InnerMessage::Type::kBinlogSync);
  
  // 预分配空间，避免频繁内存分配
  response->mutable_binlog_sync()->Reserve(tasks.size());
  
  for (const auto& task : tasks) {
    InnerMessage::InnerResponse::BinlogSync* binlog_sync = response->add_binlog_sync();
    binlog_sync->set_session_id(task.rm_node_.SessionId());
    InnerMessage::Slot* db = binlog_sync->mutable_slot();
    db->set_db_name(task.rm_node_.DBName());
    /*
     * Since the slot field is written in protobuffer,
     * slot_id is set to the default value 0 for compatibility
     * with older versions, but slot_id is not used
     */
    db->set_slot_id(0);
    InnerMessage::BinlogOffset* boffset = binlog_sync->mutable_binlog_offset();
    BuildBinlogOffset(task.binlog_chip_.offset_, boffset);
    if(g_pika_server->IsConsistency()){
      InnerMessage::BinlogOffset* committed_id = binlog_sync->mutable_committed_id();
      BuildBinlogOffset(task.committed_id_, committed_id);
    }
    // 避免额外的内存拷贝，使用move或直接引用
    binlog_sync->set_binlog(task.binlog_chip_.binlog_);
  }
}

pstd::Status PikaReplServer::Write(const std::string& ip, const int port, const std::string& msg) {
  std::shared_lock l(client_conn_rwlock_);
  const std::string ip_port = pstd::IpPortString(ip, port);
  auto it = client_conn_map_.find(ip_port);
  if (it == client_conn_map_.end()) {
    return Status::NotFound("Connection " + ip_port + " not found");
  }
  int fd = it->second;

  std::shared_ptr<net::PbConn> conn = std::dynamic_pointer_cast<net::PbConn>(pika_repl_server_thread_->get_conn(fd));
  if (!conn) {
    return Status::NotFound("Connection " + ip_port + " not available");
  }

  // 只有在写入失败时才记录错误日志并关闭连接
  if (conn->WriteResp(msg)) {
    conn->NotifyClose();
    return Status::Corruption("Failed to write to " + ip_port);
  }
  
  conn->NotifyWrite();
  return Status::OK();
}

void PikaReplServer::Schedule(net::TaskFunc func, void* arg) { server_tp_->Schedule(func, arg); }

void PikaReplServer::UpdateClientConnMap(const std::string& ip_port, int fd) {
  std::lock_guard l(client_conn_rwlock_);
  client_conn_map_[ip_port] = fd;
}

void PikaReplServer::RemoveClientConn(int fd) {
  std::lock_guard l(client_conn_rwlock_);
  auto iter = client_conn_map_.begin();
  while (iter != client_conn_map_.end()) {
    if (iter->second == fd) {
      iter = client_conn_map_.erase(iter);
      break;
    }
    iter++;
  }
}

void PikaReplServer::KillAllConns() { return pika_repl_server_thread_->KillAllConns(); }
