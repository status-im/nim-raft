# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types
import chronicles

# Private Log Ops
proc raftNodeLogIndexGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftLogIndex =
  len(node.log.logData)

proc raftNodeLogEntryGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logIndex: RaftLogIndex): RaftNodeLogEntry[SmCommandType] =
  if logIndex > 0:
    result = node.log.logData[logIndex - 1]

proc raftNodeLogAppend*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logEntry: RaftNodeLogEntry[SmCommandType]) =
  node.log.logData.add(logEntry)

proc raftNodeLogTruncate*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], truncateIndex: RaftLogIndex) =
  debug "Truncating log to index: ", truncateIndex=truncateIndex, ld=repr(node.log.logData)
  # node.log.logData = node.log.logData[:truncateIndex]

proc raftNodeApplyLogEntry*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], entryIndex: RaftLogIndex) =
  mixin raftNodeSmApply

  let logEntry = raftNodeLogEntryGet(node, entryIndex)

  if entryIndex > node.lastApplied:
    debug "Applying log entry: ", node_id=node.id, entryIndex=entryIndex, entry=repr(logEntry)
    raftNodeSmApply(node.stateMachine, raftNodeLogEntryGet(node, entryIndex))
    node.lastApplied = entryIndex

  else:
    debug "Log entry already applied: ", node_id=node.id, entryIndex=entryIndex, entry=repr(logEntry)