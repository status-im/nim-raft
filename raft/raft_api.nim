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

# RAFT Node Public API procedures / functions
proc RAFTNodeCreateNew*[LogEntryDataType, SMStateType](                     # Create New RAFT Node
                  id: RAFTNodeId, peers: RAFTNodePeers,
                  persistent_storage: RAFTNodePersistentStorage,
                  msg_send_callback: RAFTMessageSendCallback): RAFTNode[LogEntryDataType, SMStateType] =
    discard

proc RAFTNodeLoad*[LogEntryDataType, SMStateType](
                  persistent_storage: RAFTNodePersistentStorage,            # Load RAFT Node From Storage
                  msg_send_callback: RAFTMessageSendCallback): Result[RAFTNode[LogEntryDataType, SMStateType], string] =
    discard

proc RAFTNodeStop*(node: RAFTNode) =
    discard

proc RAFTNodeStart*(node: RAFTNode) =
    discard

func RAFTNodeIdGet*(node: RAFTNode): RAFTNodeId =                   # Get RAFT Node ID
    discard

func RAFTNodeStateGet*(node: RAFTNode): RAFTNodeState =             # Get RAFT Node State
    discard

func RAFTNodeTermGet*(node: RAFTNode): RAFTNodeTerm =               # Get RAFT Node Term
    discard

func RAFTNodePeersGet*(node: RAFTNode): RAFTNodePeers =             # Get RAFT Node Peers
    discard

func RAFTNodeIsLeader*(node: RAFTNode): bool =                      # Check if RAFT Node is Leader
    discard

proc RAFTNodeMessageDeliver*(node: RAFTNode, raft_message: RAFTMessageBase): RAFTMessageResponse {.discardable.} =      # Deliver RAFT Message to the RAFT Node
    discard

proc RAFTNodeRequest*(node: RAFTNode, req: RAFTNodeClientRequest): RAFTNodeClientResponse =                             # Process RAFTNodeClientRequest
    discard

proc RAFTNodeLogIndexGet*(node: RAFTNode): RAFTLogIndex =
    node.log_index
    discard

proc RAFTNodeLogEntryGet*(node: RAFTNode, log_index: RAFTLogIndex): Result[RAFTNodeLogEntry, string] =
    discard

# Abstract State Machine Ops
func RAFTNodeSMStateGet*[LogEntryDataType, SMStateType](node: RAFTNode[LogEntryDataType, SMStateType]): SMStateType =
    node.state_machine.state

proc RAFTNodeSMInit[LogEntryDataType, SMStateType](state_machine: var RAFTNodeStateMachine[LogEntryDataType, SMStateType]) =
    mixin RAFTSMInit
    RAFTSMInit(state_machine)

proc RAFTNodeSMApply[LogEntryDataType, SMStateType](state_machine: RAFTNodeStateMachine[LogEntryDataType, SMStateType], log_entry: LogEntryDataType) =
    mixin RAFTSMApply
    RAFTSMApply(state_machine, log_entry)
