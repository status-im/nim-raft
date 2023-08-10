# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types
import protocol

export types, protocol

# Raft Node Public API procedures / functions
proc RaftNodeCreateNew*[LogEntryDataType, SmStateType](                     # Create New Raft Node
                  id: RaftNodeId, peers: RaftNodePeers,
                  persistentStorage: RaftNodePersistentStorage,
                  msgSendCallback: RaftMessageSendCallback): RaftNode[LogEntryDataType, SmStateType] =
  discard

proc RaftNodeLoad*[LogEntryDataType, SmStateType](
                  persistentStorage: RaftNodePersistentStorage,            # Load Raft Node From Storage
                  msgSendCallback: RaftMessageSendCallback): Result[RaftNode[LogEntryDataType, SmStateType], string] =
  discard

proc RaftNodeStop*(node: RaftNode) =
  discard

proc RaftNodeStart*(node: RaftNode) =
  discard

func RaftNodeIdGet*(node: RaftNode): RaftNodeId =                   # Get Raft Node ID
  discard

func RaftNodeStateGet*(node: RaftNode): RaftNodeState =             # Get Raft Node State
    discard

func RaftNodeTermGet*(node: RaftNode): RaftNodeTerm =               # Get Raft Node Term
  discard

func RaftNodePeersGet*(node: RaftNode): RaftNodePeers =             # Get Raft Node Peers
  discard

func RaftNodeIsLeader*(node: RaftNode): bool =                      # Check if Raft Node is Leader
  discard

proc RaftNodeMessageDeliver*(node: RaftNode, raftMessage: RaftMessageBase): RaftMessageResponse {.discardable.} =      # Deliver Raft Message to the Raft Node
  discard

proc RaftNodeRequest*(node: RaftNode, req: RaftNodeClientRequest): RaftNodeClientResponse =                             # Process RaftNodeClientRequest
  discard

proc RaftNodeLogIndexGet*(node: RaftNode): RaftLogIndex =
  discard

proc RaftNodeLogEntryGet*(node: RaftNode, logIndex: RaftLogIndex): Result[RaftNodeLogEntry, string] =
  discard

# Abstract State Machine Ops
func RaftNodeSmStateGet*[LogEntryDataType, SmStateType](node: RaftNode[LogEntryDataType, SmStateType]): SmStateType =
  node.stateMachine.state

proc RaftNodeSmInit[LogEntryDataType, SmStateType](stateMachine: var RaftNodeStateMachine[LogEntryDataType, SmStateType]) =
  mixin RaftSmInit
  RaftSmInit(stateMachine)

proc RaftNodeSmApply[LogEntryDataType, SmStateType](stateMachine: RaftNodeStateMachine[LogEntryDataType, SmStateType], logEntry: LogEntryDataType) =
  mixin RaftSmApply
  RaftSmApply(stateMachine, logEntry)

# Timer manipulation
proc RaftCreateTimer*[TimerDurationType](d: TimerDurationType, repeat: bool, timer_callback: RaftTimerCallback): TimerId =   # I guess Duration should be monotonic
  mixin RaftCreateTimerCustomImpl
  RaftCreateTimerCustomImpl(d, repeat, timer_callback)

template RaftCancelTimer*(TimerId) =
  mixin RaftCancelTimerCustomImpl
  RaftCancelTimerCustomImpl(TimerId)
