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
proc raftNodeLogIndexGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftLogIndex =
  len(node.log.logData)

proc raftNodeLogEntryGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logIndex: RaftLogIndex): RaftNodeLogEntry[SmCommandType] =
  if logIndex > 0:
    result = node.log.logData[logIndex]

proc raftNodeLogAppend*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logEntry: RaftNodeLogEntry[SmCommandType]) =
  node.log.logData.add(logEntry)

proc raftNodeLogTruncate*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], truncateIndex: uint64) =
  node.log.logData.truncate(truncateIndex)

proc raftNodeApplyLogEntry*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logEntry: RaftNodeLogEntry[SmCommandType]) =
  mixin raftNodeSmApply

  raftNodeSmApply(node.stateMachine, logEntry.command)