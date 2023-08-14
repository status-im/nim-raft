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

  RaftMessageResponseBase* = ref object of RootObj
    msgId*: RaftMessageId                  # Original Message ID
    senderId*: RaftNodeId                  # Sender Raft Node ID
    respondentId: RaftNodeId               # Responding RaftNodeId
    senderTerm*: RaftNodeTerm              # Sender Raft Node Term

  RaftMessageRequestVote* = ref object of RaftMessageBase
    lastLogTerm*: RaftNodeTerm
    lastLogIndex*: RaftLogIndex

  RaftMessageRequestVoteResponse* = ref object of RaftMessageResponseBase
    granted*: bool

  RaftMessageAppendEntries*[SmCommandType] = ref object of RaftMessageBase
    prevLogIndex*: RaftLogIndex
    prevLogTerm*: RaftNodeTerm
    commitIndex*: RaftLogIndex
    logEntries*: Option[seq[RaftNodeLogEntry[SmCommandType]]]         # Optional log entry(ies). Will be empty for a Heart-Beat

  RaftMessageAppendEntriesResponse*[SmStateType] = ref object of RaftMessageResponseBase
    success*: bool
    lastLogIndex*: RaftLogIndex
    state*: Option[SmStateType]                                       # Optional Raft Abstract State Machine State

  # Raft Node Client Request/Response definitions
  RaftNodeClientRequestOps* = enum
    rncroRequestSmState = 0,
    rncroExecSmCommand = 1

  RaftNodeClientResponseError = enum
    rncrSuccess = 0,
    rncrFail = 1,
    rncrNotLeader = 2

  RaftNodeClientRequest*[SmCommandType] = ref object
    op*: RaftNodeClientRequestOps
    payload*: Option[SmCommandType]  # Optional RaftMessagePayload carrying a Log Entry

  RaftNodeClientResponse*[SmStateType] = ref object
    error*: RaftNodeClientResponseError
    state*: Option[SmStateType]                         # Optional Raft Abstract State Machine State
    raftNodeRedirectId*: Option[RaftNodeId]             # Optional Raft Node ID to redirect the request to in case of failure