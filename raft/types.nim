# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# Raft Node Public Types.
# I guess that at some point these can be moved to a separate file called raft_consensus_types.nim for example

import std/locks
import stew/results
import eth/keyfile

export results

type
  # Raft Node basic definitions
  Blob* = seq[byte]

  RaftNodeState* = enum
    UNKNOWN     = 0,
    FOLLOWER    = 1,
    LEADER      = 2

  RaftNodeId* = UUID                          # UUID uniquely identifying every Raft Node
  RaftNodePeers* = seq[RaftNodeId]            # List of Raft Node Peers IDs
  RaftNodeTerm* = uint64                      # Raft Node Term Type
  RaftLogIndex* = uint64                      # Raft Node Log Index Type

  # Raft Node Abstract State Machine type
  RaftNodeStateMachine*[LogEntryDataType, SmStateType] = ref object          # Some probably opaque State Machine Impelementation to be used by the Raft Node
                                              # providing at minimum operations for initialization, querying the current state
                                              # and RaftNodeLogEntry application
    state: SmStateType

  # Raft Node Persistent Storage basic definition
  RaftNodePersistentStorage* = ref object     # Should be some kind of Persistent Transactional Store Wrapper

  # Basic modules (algos) definitions
  RaftNodeAccessCallback[LogEntryDataType, SmStateType] = proc: RaftNode[LogEntryDataType, SmStateType] {.nimcall, gcsafe.}     # This should be implementes as a closure holding the RaftNode

  RaftConsensusModule*[LogEntryDataType, SmStateType] = object of RootObj
    stateTransitionsFsm: seq[byte]            # I plan to use nim.fsm https://github.com/ba0f3/fsm.nim
    raftNodeAccessCallback: RaftNodeAccessCallback[LogEntryDataType, SmStateType]

  RaftLogCompactionModule*[LogEntryDataType, SmStateType] = object of RootObj
    raftNodeAccessCallback: RaftNodeAccessCallback[LogEntryDataType, SmStateType]

  RaftMembershipChangeModule*[LogEntryDataType, SmStateType] = object of RootObj
    raftNodeAccessCallback: RaftNodeAccessCallback[LogEntryDataType, SmStateType]

  # Callback for sending messages out of this Raft Node
  RaftMessageId* = UUID                       # UUID assigned to every Raft Node Message,
                                              # so it can be matched with it's corresponding response etc.

  RaftMessageSendCallback* = proc (raftMessage: RaftMessageBase) {.nimcall, gcsafe.} # Callback for Sending Raft Node Messages
                                                                                      # out of this Raft Node. Can be used for broadcasting
                                                                                      # (a Heart-Beat for example)

  # Raft Node basic Log definitions
  RaftNodeLogEntry*[LogEntryDataType] = ref object     # Abstarct Raft Node Log entry containing opaque binary data (Blob etc.)
    term*: RaftNodeTerm
    data*: LogEntryDataType

  RaftNodeLog*[LogEntryDataType] = ref object          # Needs more elaborate definition.
                                                        # Probably this will be a RocksDB/MDBX/SQLite Store Wrapper etc.
    logData*: seq[RaftNodeLogEntry[LogEntryDataType]]  # Raft Node Log Data

  # Base type for Raft message objects
  RaftMessageBase* = ref object of RootObj             # Base Type for Raft Node Messages
    msgId*: RaftMessageId                  # Message UUID
    senderId*: RaftNodeId                  # Sender Raft Node ID
    senderTerm*: RaftNodeTerm              # Sender Raft Node Term
    peers*: RaftNodePeers                  # List of Raft Node IDs, which should receive this message

  # Raft Node Object type
  RaftNode*[LogEntryDataType, SmStateType] = ref object
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
    consensusModule: RaftConsensusModule[LogEntryDataType, SmStateType]
    logCompactionModule: RaftLogCompactionModule[LogEntryDataType, SmStateType]
    membershipChangeModule: RaftMembershipChangeModule[LogEntryDataType, SmStateType]

    # Misc
    msgSendCallback: RaftMessageSendCallback
    persistentStorage: RaftNodePersistentStorage

    # Persistent state
    id: RaftNodeId                          # This Raft Node ID
    state: RaftNodeState                    # This Raft Node State
    currentTerm: RaftNodeTerm               # Latest term this Raft Node has seen (initialized to 0 on first boot, increases monotonically)
    log: RaftNodeLog[LogEntryDataType]      # This Raft Node Log
    votedFor: RaftNodeId                    # Candidate RaftNodeId that received vote in current term (or nil/zero if none),
                                            # also used to redirect Client Requests in case this Raft Node is not the leader
    peers: RaftNodePeers                    # This Raft Node Peers IDs. I am not sure if this must be persistent or volatile but making it persistent
                                            # makes sense for the moment
    stateMachine: RaftNodeStateMachine[LogEntryDataType, SmStateType]  # Not sure for now putting it here. I assume that persisting the State Machine's
                                                                        # state is enough to consider it 'persisted'
    # Volatile state
    commitIndex: RaftLogIndex               # Index of highest log entry known to be committed (initialized to 0, increases monotonically)
    lastApplied: RaftLogIndex               # Index of highest log entry applied to state machine (initialized to 0, increases monotonically)

    # Volatile state on leaders
    nextIndex: seq[RaftLogIndex]            # For each peer Raft Node, index of the next log entry to send to that Node
                                            # (initialized to leader last log index + 1)
    matchIndex: seq[RaftLogIndex]           # For each peer Raft Node, index of highest log entry known to be replicated on Node
                                            # (initialized to 0, increases monotonically)