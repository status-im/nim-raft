# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# Raft Node Public Types

import std/locks
import options
import stew/results
import uuids
import asyncdispatch

export results, options, locks, uuids


const
  DefaultUUID* = initUUID(0, 0)             # 00000000-0000-0000-0000-000000000000

type
  RaftNodeState* = enum
    rnsUnknown = 0,
    rnsFollower = 1,
    rnsCandidate = 2
    rnsLeader = 3

  RaftNodeId* = UUID                        # uuid4 uniquely identifying every Raft Node
  RaftNodeTerm* = uint64                    # Raft Node Term Type
  RaftLogIndex* = uint64                    # Raft Node Log Index Type

  RaftNodePeer* = object                    # Raft Node Peer object
    id*: RaftNodeId
    nextIndex*: RaftLogIndex                # For each peer Raft Node, index of the next log entry to send to that Node
                                            # (initialized to leader last log index + 1)
    matchIndex*: RaftLogIndex               # For each peer Raft Node, index of highest log entry known to be replicated on Node
                                            # (initialized to 0, increases monotonically)
    hasVoted*: bool                         # Indicates if this peer have voted for this Raft Node During Election
    canVote*: bool                          # Indicates if this peer can vote

  RaftNodePeers* = seq[RaftNodePeer]        # List of Raft Node Peers


  # Raft Node Abstract State Machine type
  RaftNodeStateMachine*[SmCommandType, SmStateType] = ref object      # Some opaque State Machine Impelementation to be used by the Raft Node
                                                                  # providing at minimum operations for initialization, querying the current state
                                                                  # and RaftNodeLogEntry (SmCommandType) application
    state*: ref SmStateType

  # Raft Node Persistent Storage basic definition
  RaftNodePersistentStorage*[SmCommandType, SmStateType] = object     # Should be some kind of Persistent Transactional Store Wrapper

  # Basic modules (algos) definitions
  RaftNodeAccessCallback[SmCommandType, SmStateType] = proc: RaftNode[SmCommandType, SmStateType] {.nimcall, gcsafe.}     # This should be implementes as a closure holding the RaftNode

  RaftConsensusModule*[SmCommandType, SmStateType] = object of RootObj
    stateTransitionsFsm: seq[byte]                              # I plan to use nim.fsm https://github.com/ba0f3/fsm.nim
    gatheredVotesCount: int
    raftNodeAccessCallback: RaftNodeAccessCallback[SmCommandType, SmStateType]

  RaftLogCompactionModule*[SmCommandType, SmStateType] = object of RootObj
    raftNodeAccessCallback: RaftNodeAccessCallback[SmCommandType, SmStateType]

  RaftMembershipChangeModule*[SmCommandType, SmStateType] = object of RootObj
    raftNodeAccessCallback: RaftNodeAccessCallback[SmCommandType, SmStateType]

  # Callback for sending messages out of this Raft Node
  RaftMessageId* = UUID                    # UUID assigned to every Raft Node Message,
                                           # so it can be matched with it's corresponding response etc.

  RaftMessageBase* = ref object of RootObj # Base Type for Raft Protocol Messages
    msgId*: RaftMessageId                  # Message UUID
    senderId*: RaftNodeId                  # Sender Raft Node ID
    receiverId*: RaftNodeId                # Receiver Raft Node ID

  RaftMessageResponseBase* = ref object of RaftMessageBase

  RaftMessageSendCallback* = proc (raftMessage: RaftMessageBase): Future[RaftMessageResponseBase] {.async, gcsafe.}  # Callback for Sending Raft Node Messages
                                                                                                                     # out of this Raft Node.

  # For later use when adding/removing new nodes (dynamic configuration chganges)
  RaftNodeConfiguration* = object

  # Raft Node Log definition
  LogEntryType* = enum
    etUnknown = 0,
    etConfiguration = 1,
    etData = 2,
    etNoOp = 3

  RaftNodeLogEntry*[SmCommandType] = object     # Abstarct Raft Node Log entry containing opaque binary data (Blob etc.)
    term*: RaftNodeTerm
    index*: RaftLogIndex
    entryType*: LogEntryType                        # Type of entry - data to append, configuration or no op etc.
    data*: Option[SmCommandType]                    # Entry data (State Machine Command) - this is mutually exclusive with configuration
                                                    # depending on entryType field
    configuration*: Option[RaftNodeConfiguration]    # Node configuration

  RaftNodeLog*[SmCommandType] = object              # Needs more elaborate definition.
                                                    # Probably this will be a RocksDB/MDBX/SQLite Store Wrapper etc.
    logData*: seq[RaftNodeLogEntry[SmCommandType]]  # Raft Node Log Data

  # Timer types
  RaftTimer* = ref object
    mtx*: Lock
    canceled*: bool
    expired*: bool
    timeout*: int
    oneshot*: bool

  RaftTimerCallback* = proc (timer: RaftTimer) {.gcsafe.}   # Pass any function wrapped in a closure

  # Raft Node Object type
  RaftNode*[SmCommandType, SmStateType] = ref object
    # Timers
    requestVotesTimeout: int
    heartBeatTimeout: int
    appendEntriesTimeout: int

    requestVotesTimer: RaftTimer
    heartBeatTimer: RaftTimer
    appendEntriesTimer: RaftTimer

    # Mtx definition(s) go here
    raftStateMutex*: Lock

    # Modules (Algos)
    consensusModule: RaftConsensusModule[SmCommandType, SmStateType]
    logCompactionModule: RaftLogCompactionModule[SmCommandType, SmStateType]
    membershipChangeModule: RaftMembershipChangeModule[SmCommandType, SmStateType]

    # Misc
    msgSendCallback*: RaftMessageSendCallback
    persistentStorage: RaftNodePersistentStorage[SmCommandType, SmStateType]

    # Persistent state
    id*: RaftNodeId                          # This Raft Node ID
    state*: RaftNodeState                    # This Raft Node State
    currentTerm*: RaftNodeTerm               # Latest term this Raft Node has seen (initialized to 0 on first boot, increases monotonically)
    votedFor*: RaftNodeId                    # Candidate RaftNodeId that received vote in current term (or DefaultUUID if none),
                                             # also used to redirect Client Requests in case this Raft Node is not the leader
    log: RaftNodeLog[SmCommandType]          # This Raft Node Log
    stateMachine*: RaftNodeStateMachine[SmCommandType, SmStateType]      # Not sure for now putting it here. I assume that persisting the State Machine's
                                                                        # state is enough to consider it 'persisted'
    peers*: RaftNodePeers                    # This Raft Node Peers IDs. I am not sure if this must be persistent or volatile but making it persistent
                                             # makes sense for the moment

    # Volatile state
    commitIndex*: RaftLogIndex               # Index of highest log entry known to be committed (initialized to 0, increases monotonically)
    lastApplied*: RaftLogIndex               # Index of highest log entry applied to state machine (initialized to 0, increases monotonically)
    currentLeaderId*: RaftNodeId             # The ID of the current leader Raft Node or DefaultUUID if None is leader (election is in progress etc.)