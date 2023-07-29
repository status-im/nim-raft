# nim-raft-consesnsus
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# RAFT Node Public Types.
# I guess that at some point these can be moved to a separate file called raft_consensus_types.nim for example

import std/locks

type
    # RAFT Node basic definitions
    Blob* = seq[byte]

    RAFTNodeState* = enum
        UNKNOWN     = 0,
        FOLLOWER    = 1,
        LEADER      = 2

    RAFTNodeId* = object                        # Some kind of UUID uniquely identifying every RAFT Node
    RAFTNodePeers* = seq[RAFTNodeId]            # List of RAFT Node Peers IDs
    RAFTNodeTerm* = uint64                      # RAFT Node Term Type
    RAFTLogIndex* = uint64                      # RAFT Node Log Index Type

    # RAFT Node basic Log definitions
    RAFTNodeLogEntry* = ref object              # Abstarct RAFT Node Log entry containing opaque binary data (Blob)
        term*: RAFTNodeTerm
        data*: Blob

    RAFTNodeLog* = ref object                   # Needs more elaborate definition. Probably this will be a RocksDB/MDBX/SQLite Store Wrapper etc.
        log_data*: seq[RAFTNodeLogEntry]        # RAFT Node Log Data

    # RAFT Node State Machine basic definitions
    RAFTNodeStateMachineState* = object         # State Machine State
    RAFTNodeStateMachine* = ref object          # Some probably opaque State Machine Impelementation to be used by the RAFT Node
                                                # providing at minimum operations for initialization, querying the current state
                                                # and RAFTNodeLogEntry application
        state: RAFTNodeStateMachineState

    # RAFT Node Persistent Storage basic definition
    RAFTNodePersistentStorage* = ref object     # Should be some kind of Persistent Transactional Store Wrapper

    # Basic modules (algos) definitions
    RAFTNodeAccessCallback = proc: RAFTNode {.nimcall, gcsafe.}     # This should be implementes as a closure holding the RAFTNode
    RAFTConsensusModule* = object of RootObj
        state_transitions_fsm: seq[byte]        # I plan to use nim.fsm https://github.com/ba0f3/fsm.nim
        raft_node_access_callback: RAFTNodeAccessCallback

    RAFTLogCompactionModule* = object of RootObj
        raft_node_access_callback: RAFTNodeAccessCallback
    
    RAFTMembershipChangeModule* = object of RootObj
        raft_node_access_callback: RAFTNodeAccessCallback

    # RAFT Node Object definitions
    RAFTNode* = object
        # Timers
        voting_timout: nil
        heart_beat_timeout: nil 
        # etc. timers

        # Mtx definitions go here
        raft_state_mutex: Lock
        raft_log_mutex: Lock
        raft_comm_mutex_receive_msg: Lock
        raft_comm_mutex_client_response: Lock

        # Modules
        consensus_module: RAFTConsensusModule
        log_compaction_module: RAFTLogCompactionModule
        membership_change_module: RAFTMembershipChangeModule

        # Misc
        msg_send_callback: RAFTMessageSendCallback
        persistent_storage: RAFTNodePersistentStorage

        # Node Persistent state
        id: RAFTNodeId                          # This RAFT Node ID
        state: RAFTNodeState                    # This RAFT Node State
        current_term: RAFTNodeTerm              # Latest term this RAFT Node has seen (initialized to 0 on first boot, increases monotonically)
        log: RAFTNodeLog                        # This RAFT Node Log
        voted_for: RAFTNodeId                   # Candidate RAFTNodeId that received vote in current term (or nil/zero if none)
        peers: RAFTNodePeers                    # This RAFT Node Peers IDs. I am not sure if this must be persistent or volatile but making it persistent
                                                # makes sense for the moment
        state_machine: RAFTNodeStateMachine     # Not sure for now putting it here. I assume that persisting the State Machine's state is enough
                                                # to consider it 'persisted'
        
        # Volatile state
        commit_index: RAFTLogIndex              # Index of highest log entry known to be committed (initialized to 0, increases monotonically)
        last_applied: RAFTLogIndex              # Index of highest log entry applied to state machine (initialized to 0, increases monotonically)
        current_leader_id: RAFTNodeId           # Current RAFT Node Leader ID (used to redirect Client Requests in case this RAFT Node is not the leader)
        
        # Volatile state on leaders
        next_index: seq[RAFTLogIndex]           # For each peer RAFT Node, index of the next log entry to send to that Node
                                                # (initialized to leader last log index + 1)
        match_index: seq[RAFTLogIndex]          # For each peer RAFT Node, index of highest log entry known to be replicated on Node
                                                # (initialized to 0, increases monotonically)

