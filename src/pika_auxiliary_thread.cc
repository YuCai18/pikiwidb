// Copyright (c) 2019-present, Qihoo, Inc.  All rights reserved.
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.

#include "include/pika_auxiliary_thread.h"

#include "include/pika_define.h"
#include "include/pika_rm.h"
#include "include/pika_server.h"
#include "include/pika_conf.h"

extern PikaServer* g_pika_server;
extern std::unique_ptr<PikaReplicaManager> g_pika_rm;

using namespace std::chrono_literals;

PikaAuxiliaryThread::~PikaAuxiliaryThread() {
  StopThread();
  LOG(INFO) << "PikaAuxiliary thread " << thread_id() << " exit!!!";
}

void* PikaAuxiliaryThread::ThreadMain() {
  while (!should_stop()) {
    if (g_pika_server->ShouldMetaSync()) {
      g_pika_rm->SendMetaSyncRequest();
    } else if (g_pika_server->MetaSyncDone()) {
      g_pika_rm->RunSyncSlaveDBStateMachine();
    }

    pstd::Status s = g_pika_rm->CheckSyncTimeout(pstd::NowMicros());
    if (!s.ok()) {
      LOG(WARNING) << s.ToString();
    }

    g_pika_server->CheckLeaderProtectedMode();

    // send to peer first if there are queued packets
    int res = g_pika_server->SendToPeer();
    if (res == 0) {
      // idle: wait for a short period (consensus-timeout) or notification
      std::unique_lock lock(mu_);
      auto to = std::chrono::milliseconds(g_pika_conf->consensus_timeout());
      if (to.count() <= 0) {
        to = 10ms;
      }
      cv_.wait_for(lock, to);
      // after wait, trigger replication send once (size/timeout gating will decide to send or not)
      s = g_pika_server->TriggerSendBinlogSync();
      if (!s.ok()) {
        LOG(WARNING) << s.ToString();
      }
      // consume what may have been produced by trigger
      g_pika_server->SendToPeer();
    } else {
      // LOG_EVERY_N(INFO, 1000) << "Consume binlog number " << res;
    }
  }
  return nullptr;
}
