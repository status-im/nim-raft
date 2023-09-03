# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

                        #                              #
                        #   Raft Protocol definition   #
                        #                              #
import types

type
  # Raft Node Messages OPs
  RaftMessageOps* = enum
    rmoRequestVote = 0,
    rmoAppendLogEntry = 1,
    rmoInstallSnapshot = 2                    # For dynamic adding of new Raft Nodes

  RaftMessageRespoonseError* = enum           # Raft message response errors
    rmreSuccess = 0,
    rmreFail = 1

  RaftMessageRequestVote* = ref object of RaftMessageBase
    lastLogTerm*: RaftNodeTerm
    lastLogIndex*: RaftLogIndex
    senderTerm*: RaftNodeTerm               # Sender Raft Node Term

  RaftMessageRequestVoteResponse* = ref object of RaftMessageResponseBase
    granted*: bool                          # Is vote granted by the Raft node, from we requested vote?

  RaftMessageAppendEntries*[SmCommandType] = ref object of RaftMessageBase
    prevLogIndex*: RaftLogIndex
    prevLogTerm*: RaftNodeTerm
    commitIndex*: RaftLogIndex
    logEntries*: Option[seq[RaftNodeLogEntry[SmCommandType]]]         # Optional log entry(ies). Will be empty for a Heart-Beat
    senderTerm*: RaftNodeTerm                                         # Sender Raft Node Term

  RaftMessageAppendEntriesResponse*[SmStateType] = ref object of RaftMessageResponseBase
    success*: bool
    lastLogIndex*: RaftLogIndex
    state*: Option[SmStateType]                                       # Optional Raft Abstract State Machine State

  # Raft Node Client Request/Response definitions
  RaftNodeClientRequestOps* = enum
    rncroRequestSmState = 0,
    rncroExecSmCommand = 1

  RaftNodeClientResponseError* = enum
    rncreSuccess = 0,
    rncreFail = 1,
    rncreNotLeader = 2

  RaftNodeClientRequest*[SmCommandType] = ref object
    op*: RaftNodeClientRequestOps
    nodeId*: RaftNodeId
    payload*: Option[SmCommandType]  # Optional RaftMessagePayload carrying a Log Entry

  RaftNodeClientResponse*[SmStateType] = ref object
    error*: RaftNodeClientResponseError
    state*: Option[SmStateType]                         # Optional Raft Abstract State Machine State
    raftNodeRedirectId*: Option[RaftNodeId]             # Optional Raft Node ID to redirect the request to in case of failure