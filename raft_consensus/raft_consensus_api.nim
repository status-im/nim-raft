# nim-raft-consesnsus
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types
import protocol
import stew/results

export types, protocol

# RAFT Node Public API procedures / functions
proc RAFTNodeCreateNew*(id: RAFTNodeId, peers: RAFTNodePeers, state_machine: RAFTNodeStateMachine,                       # Create New RAFT Node
                       log: RAFTNodeLog, persistent_storage: RAFTNodePersistentStorage,
                       msg_send_callback: RAFTMessageSendCallback): RAFTNode =
    discard

proc RAFTNodeLoad*(state_machine: RAFTNodeStateMachine, log: RAFTNodeLog,                                                # Load RAFT Node From Storage
                  persistent_storage: RAFTNodePersistentStorage, msg_send_callback: RAFTMessageSendCallback): Result[RAFTNode, string] =
    discard

proc RAFTNodeStop*(node: RAFTNode) =
    discard

proc RAFTNodeStart*(node: RaftNode) =
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

proc RAFTNodeLogLenGet*(node: RAFTNode): RAFTLogIndex =
    discard

proc RAFTNodeLogEntryGet*(node: RAFTLogIndex): Result[RAFTNodeLogEntry, string] =
    discard

proc RAFTNodeStateMachineStateGet*(node: RAFTNode): RAFTNodeStateMachineState =
    discard

