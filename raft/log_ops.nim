# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types

# Private Log Ops
proc RaftNodeLogIndexGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftLogIndex =
  discard

proc RaftNodeLogEntryGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logIndex: RaftLogIndex): RaftNodeLogEntry[SmCommandType] =
  discard

proc RaftNodeLogAppend*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logEntry: RaftNodeLogEntry[SmCommandType]) =
  discard

proc RaftNodeLogTruncate*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], truncateIndex: uint64) =
  discard