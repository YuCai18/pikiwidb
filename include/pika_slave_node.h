// Copyright (c) 2015-present, Qihoo, Inc.  All rights reserved.
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.

#ifndef PIKA_SLAVE_NODE_H_
#define PIKA_SLAVE_NODE_H_

#include <map>
#include <mutex>
#include <string>
#include <vector>
#include <deque>
#include <memory>

#include "include/pika_binlog_reader.h"
#include "include/pika_define.h"

struct SyncWinItem {
  LogOffset offset_;
  std::size_t binlog_size_{};
  bool acked_{};

  SyncWinItem() = default;

  explicit SyncWinItem(const LogOffset& offset, std::size_t binlog_size = 0)
      : offset_(offset), binlog_size_(binlog_size), acked_(false) {}

  SyncWinItem(const SyncWinItem& item) = default;
  bool operator==(const SyncWinItem& other) const {
    return offset_.b_offset.filenum == other.offset_.b_offset.filenum &&
           offset_.b_offset.offset == other.offset_.b_offset.offset &&
           offset_.l_offset.term == other.offset_.l_offset.term &&
           offset_.l_offset.index == other.offset_.l_offset.index;
  }
  bool operator<(const SyncWinItem& other) const {
    if (offset_.b_offset.filenum != other.offset_.b_offset.filenum) {
      return offset_.b_offset.filenum < other.offset_.b_offset.filenum;
    }
    return offset_.b_offset.offset < other.offset_.b_offset.offset;
  }
  std::string ToString() const {
    return "filenum:" + std::to_string(offset_.b_offset.filenum) + 
           " offset:" + std::to_string(offset_.b_offset.offset) + 
           " term:" + std::to_string(offset_.l_offset.term) + 
           " index:" + std::to_string(offset_.l_offset.index) + 
           " size:" + std::to_string(binlog_size_) + 
           " acked:" + std::to_string(static_cast<int>(acked_));
  }
};

class SyncWindow {
 public:
  SyncWindow() = default;
  ~SyncWindow() = default;
  void Push(const SyncWinItem& item);
  bool Update(const SyncWinItem& start_item, const SyncWinItem& end_item, LogOffset* acked_offset);
  int Remaining();

  std::string ToStringStatus();
  size_t Size();
  std::size_t GetTotalBinlogSize() { return total_size_; }
  void Reset() {
    win_.clear();
    total_size_ = 0;
  }

 private:
  std::string _ToStringStatus();
  size_t _Size();
  std::map<LogOffset, SyncWinItem> win_;
  // std::deque<SyncWinItem> win_;
  size_t total_size_ = 0;
  std::mutex win_mu_;
};

// role master use
class SlaveNode : public RmNode {
 public:
  SlaveNode(const std::string& ip, int port, const std::string& db_name, int session_id);
  ~SlaveNode() override;
  void Lock() { slave_mu.lock(); }
  void Unlock() { slave_mu.unlock(); }
  SlaveState slave_state{kSlaveNotSync};

  BinlogSyncState b_state{kNotSync};
  SyncWindow sync_win;
  LogOffset sent_offset = LogOffset();
  LogOffset acked_offset = LogOffset();
  LogOffset target_offset = LogOffset();

  std::string ToStringStatus();

  std::shared_ptr<PikaBinlogReader> binlog_reader;
  pstd::Status InitBinlogFileReader(const std::shared_ptr<Binlog>& binlog, const BinlogOffset& offset);
  pstd::Status Update(const LogOffset& start, const LogOffset& end, LogOffset* updated_offset);
  LogOffset SentOffset();
  void SetSentOffset(const LogOffset& offset);
  std::mutex slave_mu;
  std::condition_variable slave_cv;
};

#endif  // PIKA_SLAVE_NODE_H
