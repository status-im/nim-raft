# nim-raft
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
import stew/results
import eth/keyfile

export results

type
    # RAFT Node basic definitions
    Blob* = seq[byte]

    RAFTNodeState* = enum
      UNKNOWN     = 0,
      FOLLOWER    = 1,
      LEADER      = 2

    RAFTNodeId* = UUID                          # UUID uniquely identifying every RAFT Node
    RAFTNodePeers* = seq[RAFTNodeId]            # List of RAFT Node Peers IDs
    RAFTNodeTerm* = uint64                      # RAFT Node Term Type
    RAFTLogIndex* = uint64                      # RAFT Node Log Index Type

    # RAFT Node Abstract State Machine type
    RAFTNodeStateMachine*[LogEntryDataType, SMStateType] = ref object          # Some probably opaque State Machine Impelementation to be used by the RAFT Node
                                                # providing at minimum operations for initialization, querying the current state
                                                # and RAFTNodeLogEntry application
      state: SMStateType

    # RAFT Node Persistent Storage basic definition
    RAFTNodePersistentStorage* = ref object     # Should be some kind of Persistent Transactional Store Wrapper

    # Basic modules (algos) definitions
    RAFTNodeAccessCallback[LogEntryDataType] = proc: RAFTNode[LogEntryDataType] {.nimcall, gcsafe.}     # This should be implementes as a closure holding the RAFTNode

    RAFTConsensusModule*[LogEntryDataType] = object of RootObj
      stateTransitionsFsm: seq[byte]            # I plan to use nim.fsm https://github.com/ba0f3/fsm.nim
      raftNodeAccessCallback: RAFTNodeAccessCallback[LogEntryDataType]

    RAFTLogCompactionModule*[LogEntryDataType] = object of RootObj
      raftNodeAccessCallback: RAFTNodeAccessCallback[LogEntryDataType]

    RAFTMembershipChangeModule*[LogEntryDataType] = object of RootObj
      raftNodeAccessCallback: RAFTNodeAccessCallback[LogEntryDataType]

    # Callback for sending messages out of this RAFT Node
    RAFTMessageId* = UUID                       # UUID assigned to every RAFT Node Message,
                                                # so it can be matched with it's corresponding response etc.

    RAFTMessageSendCallback* = proc (raft_message: RAFTMessageBase) {.nimcall, gcsafe.} # Callback for Sending RAFT Node Messages
                                                                                        # out of this RAFT Node. Can be used for broadcasting
                                                                                        # (a Heart-Beat for example)

    # RAFT Node basic Log definitions
    RAFTNodeLogEntry*[LogEntryDataType] = ref object     # Abstarct RAFT Node Log entry containing opaque binary data (Blob etc.)
      term*: RAFTNodeTerm
      data*: LogEntryDataType

    RAFTNodeLog*[LogEntryDataType] = ref object          # Needs more elaborate definition.
                                                         # Probably this will be a RocksDB/MDBX/SQLite Store Wrapper etc.
      logData*: seq[RAFTNodeLogEntry[LogEntryDataType]]  # RAFT Node Log Data

    # Base type for RAFT message objects
    RAFTMessageBase* = ref object of RootObj             # Base Type for RAFT Node Messages
      msgId*: RAFTMessageId                  # Message UUID
      senderId*: RAFTNodeId                  # Sender RAFT Node ID
      senderTerm*: RAFTNodeTerm              # Sender RAFT Node Term
      peers*: RAFTNodePeers                  # List of RAFT Node IDs, which should receive this message

    # RAFT Node Object type
    RAFTNode*[LogEntryDataType, SMStateType] = ref object
      # Timers
      votingTimout: uint64
      heartBeatTimeout: uint64
      # etc. timers

      # Mtx definitions go here
      raftStateMutex: Lock
      raftLogMutex: Lock
      raftCommMutexReceiveMsg: Lock
      raftCommMutexClientResponse: Lock

      # Modules (Algos)
      consensusModule: RAFTConsensusModule[LogEntryDataType]
      logCompactionModule: RAFTLogCompactionModule[LogEntryDataType]
      membershipChangeModule: RAFTMembershipChangeModule[LogEntryDataType]

      # Misc
      msgSendCallback: RAFTMessageSendCallback
      persistentStorage: RAFTNodePersistentStorage

      # Persistent state
      id: RAFTNodeId                          # This RAFT Node ID
      state: RAFTNodeState                    # This RAFT Node State
      currentTerm: RAFTNodeTerm               # Latest term this RAFT Node has seen (initialized to 0 on first boot, increases monotonically)
      log: RAFTNodeLog[LogEntryDataType]      # This RAFT Node Log
      votedFor: RAFTNodeId                    # Candidate RAFTNodeId that received vote in current term (or nil/zero if none),
                                              # also used to redirect Client Requests in case this RAFT Node is not the leader
      peers: RAFTNodePeers                    # This RAFT Node Peers IDs. I am not sure if this must be persistent or volatile but making it persistent
                                              # makes sense for the moment
      stateMachine: RAFTNodeStateMachine[LogEntryDataType, SMStateType]  # Not sure for now putting it here. I assume that persisting the State Machine's
                                                                          # state is enough to consider it 'persisted'
      # Volatile state
      commitIndex: RAFTLogIndex               # Index of highest log entry known to be committed (initialized to 0, increases monotonically)
      lastApplied: RAFTLogIndex               # Index of highest log entry applied to state machine (initialized to 0, increases monotonically)

      # Volatile state on leaders
      nextIndex: seq[RAFTLogIndex]            # For each peer RAFT Node, index of the next log entry to send to that Node
                                              # (initialized to leader last log index + 1)
      matchIndex: seq[RAFTLogIndex]           # For each peer RAFT Node, index of highest log entry known to be replicated on Node
                                              # (initialized to 0, increases monotonically)