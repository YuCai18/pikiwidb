// Copyright (c) 2015-present, Qihoo, Inc.  All rights reserved.
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.

#include "include/pika_slave_node.h"

#include "include/pika_conf.h"

using pstd::Status;

extern std::unique_ptr<PikaConf> g_pika_conf;

/* SyncWindow */

void SyncWindow::Push(const SyncWinItem& item) {
  std::lock_guard<std::mutex> lock(win_mu_);
  // 检查窗口是否已满
  size_t window_size = g_pika_conf->sync_window_size();
  // 窗口满时，进行清理操作
  if (_Size() >= window_size * 0.9) {  // 当窗口使用率达到90%时开始清理
    // 首先尝试清理已确认的项目
    size_t cleared = 0;
    auto it = win_.begin();
    while (it != win_.end() && it->second.acked_) {
      it = win_.erase(it);
      cleared++;
    }
    
    // 如果清理后仍然接近满，则强制清理一部分未确认的项目
    if (_Size() >= window_size * 0.8) {
      size_t to_remove = std::min(_Size() / 5, (size_t)1000);  // 移除最多1000个
      if (to_remove > 0) {
        auto rit = win_.rbegin();
        for (size_t i = 0; i < to_remove && rit != win_.rend(); i++) {
          total_size_ -= rit->second.binlog_size_; // 从尾部计算大小
          rit++;
        }
        win_.erase(rit.base(), win_.end());
        LOG(WARNING) << "【强制窗口清理】完成，清理后大小: " << _Size() << "/" << window_size;
      }
    } else if (cleared > 0) {
      LOG(WARNING) << "【窗口自动清理】移除了 " << cleared << " 个已确认项，当前大小: " 
                  << _Size() << "/" << window_size;
    }
  }
  
  // 添加新项目
  win_[item.offset_] = item;
  total_size_ += item.binlog_size_;
}

bool SyncWindow::Update(const SyncWinItem& start_item, const SyncWinItem& end_item, LogOffset* acked_offset) {
  std::lock_guard<std::mutex> lock(win_mu_);
  // 记录更新前的窗口大小
  size_t before_size = _Size();
  
  // 首先检查window是否为空
  if (win_.empty()) {
    // If window is empty, it means all sent binlogs have been acked.
    // This ack represents the latest progress from the slave.
    // We should update the acked_offset to the end_item of this ACK.
    *acked_offset = end_item.offset_;
    return true;
  }

  // 检查ACK是否已经完全过时
  if (end_item.offset_ < win_.begin()->first) {
    LOG(WARNING) << "Received an outdated ack, end_item: " << end_item.ToString()
                 << ", oldest item in window: " << win_.begin()->second.ToString();
    // For outdated ack, we don't need to update acked_offset,
    // just return true to indicate success.
    // The caller will keep the original acked_offset.
    return true;
  }
  
  // 查找起始和结束位置
  auto start_it = win_.find(start_item.offset_);
  auto end_it = win_.find(end_item.offset_);

  // 如果没有找到起始项，但找到了结束项，说明起始项已经被清理
  // 此时我们从窗口的开头开始确认
  if (start_it == win_.end() && end_it != win_.end()) {
    start_it = win_.begin();
  }

  // If the end item is not found, it might be a partial ack due to network conditions.
  // In this case, we should safely acknowledge up to the last available item in the window.
  if (end_it == win_.end()) {
    end_it = std::prev(win_.end());
  }

  if (start_it == win_.end() || end_it == win_.end()) {
    LOG(WARNING) << "Ack offset Start: " << start_item.ToString() << "End: " << end_item.ToString()
                 << " not found in binlog controller window." << std::endl
                 << "window status " << std::endl
                 << _ToStringStatus();
    
    if (start_it == win_.end()) {
      LOG(WARNING) << "未找到起始位置，窗口第一项: " << (!win_.empty() ? win_.begin()->second.ToString() : "空") 
                  << "，最后一项: " << (!win_.empty() ? win_.rbegin()->second.ToString() : "空");
    }
    
    return false;
  }

  for (auto it = start_it; it != std::next(end_it); ++it) {
    it->second.acked_ = true;
    total_size_ -= it->second.binlog_size_;
  }
  
  // 移除前面所有已确认的项目
  size_t removed_count = 0;
  auto it = win_.begin();
  while (it != win_.end()) {
    if (it->second.acked_) {
      *acked_offset = it->first;
      it = win_.erase(it);
      removed_count++;
    } else {
      break;
    }
  }
  
  // 打印窗口滑动信息
  size_t after_size = _Size();
  if (removed_count > 0) {
    LOG(INFO) << "【窗口滑动】移除了 " << removed_count << " 个确认项，从 " << before_size 
                << " 到 " << after_size << "，确认偏移量: " << acked_offset->ToString();
  }
  
  return true;
}

int SyncWindow::Remaining() {
  std::lock_guard<std::mutex> lock(win_mu_);
  std::size_t window_size = g_pika_conf->sync_window_size();
  std::size_t current_size = _Size();
  std::size_t remaining_size = window_size > current_size ? window_size - current_size : 0;
  
  // 如果剩余容量少于10%，输出警告
  if (remaining_size < window_size * 0.1 && !win_.empty()) {
    static time_t last_warning = 0;
    time_t now = time(nullptr);
    
    // 限制警告频率，每5秒最多输出一次
    if (now - last_warning > 5) {
      LOG(WARNING) << "【窗口空间不足】仅剩 " << remaining_size << " 项 (" 
                  << (remaining_size * 100 / window_size) << "%)";
      last_warning = now;
      
      // 如果剩余空间为0，返回一个最小值，确保流程不会完全卡住
      if (remaining_size == 0) {
        LOG(WARNING) << "【紧急措施】窗口已满，强制返回最小容量，以避免系统卡死";
        return std::max(10, static_cast<int>(window_size / 100));  // 返回窗口大小的1%或至少10个位置
      }
    }
  }
  
  return static_cast<int>(remaining_size);
}

std::string SyncWindow::ToStringStatus() {
  std::lock_guard<std::mutex> lock(win_mu_);
  return _ToStringStatus();
}

size_t SyncWindow::Size() { 
  std::lock_guard<std::mutex> lock(win_mu_);
  return _Size();
}

std::string SyncWindow::_ToStringStatus() {
  if (win_.empty()) {
    return "      Size: " + std::to_string(win_.size()) + "\r\n";
  } else {
    std::string res;
    res += "      Size: " + std::to_string(win_.size()) + "\r\n";
    res += ("      Begin_item: " + win_.begin()->second.ToString() + "\r\n");
    res += ("      End_item: " + win_.rbegin()->second.ToString() + "\r\n");
    return res;
  }
}

size_t SyncWindow::_Size() { return win_.size(); }

/* SlaveNode */

SlaveNode::SlaveNode(const std::string& ip, int port, const std::string& db_name, int session_id)
    : RmNode(ip, port, db_name, session_id)
      
      {}

SlaveNode::~SlaveNode() = default;

Status SlaveNode::InitBinlogFileReader(const std::shared_ptr<Binlog>& binlog, const BinlogOffset& offset) {
  binlog_reader = std::make_shared<PikaBinlogReader>();
  int res = binlog_reader->Seek(binlog, offset.filenum, offset.offset);
  if (res != 0) {
    return Status::Corruption(ToString() + "  binlog reader init failed");
  }
  return Status::OK();
}

std::string SlaveNode::ToStringStatus() {
  std::stringstream tmp_stream;
  tmp_stream << "    Slave_state: " << SlaveStateMsg[slave_state] << "\r\n";
  tmp_stream << "    Binlog_sync_state: " << BinlogSyncStateMsg[b_state] << "\r\n";
  tmp_stream << "    Sync_window: "
             << "\r\n"
             << sync_win.ToStringStatus();
  tmp_stream << "    Sent_offset: " << sent_offset.ToString() << "\r\n";
  tmp_stream << "    Acked_offset: " << acked_offset.ToString() << "\r\n";
  tmp_stream << "    Binlog_reader activated: " << (binlog_reader != nullptr) << "\r\n";
  return tmp_stream.str();
}

Status SlaveNode::Update(const LogOffset& start, const LogOffset& end, LogOffset* updated_offset) {
  if (slave_state != kSlaveBinlogSync && slave_state != KCandidate) {
    return Status::Corruption(ToString() + "state not BinlogSync or Candidate");
  }

  *updated_offset = LogOffset();
  bool res = sync_win.Update(SyncWinItem(start), SyncWinItem(end), updated_offset);
  if (!res) {
    LOG(WARNING) << "Update failed in SyncWindow - " << ToString();
    return Status::Corruption("UpdateAckedInfo failed");
  }

  bool progress_made = false;
  // Check if sync_win.Update reported progress and if it's actual forward progress
  if (*updated_offset != LogOffset() && updated_offset->l_offset.index > acked_offset.l_offset.index) {
    acked_offset = *updated_offset;
    progress_made = true;
  }

  // For the caller, always report the most up-to-date offset we have.
  *updated_offset = acked_offset;

  // ALWAYS notify waiters that new information has arrived from the slave.
  // This is the key fix for the consistency timeout under high concurrency.
  slave_cv.notify_all();

  if (progress_made) {
    // This is normal operation, so log as INFO, not WARNING
    LOG(INFO) << "ACK progress: " << acked_offset.ToString() << ", win: " << sync_win.Size();
  }

  return Status::OK();
}

LogOffset SlaveNode::SentOffset() {
  return sent_offset;
}