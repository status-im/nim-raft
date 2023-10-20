# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

                        # **************************** #
                        #   Raft Protocol definition   #
                        # **************************** #
import types

type
  RaftMessage*[SmCommandType, SmStateType] = ref object of RaftMessageBase[SmCommandType, SmStateType]
    senderTerm*: RaftNodeTerm                                     # Sender Raft Node Term
    case op*: RaftMessageOps
    of rmoRequestVote:
      lastLogTerm*: RaftNodeTerm
      lastLogIndex*: RaftLogIndex
    of rmoAppendLogEntry:
      prevLogIndex*: RaftLogIndex
      prevLogTerm*: RaftNodeTerm
      commitIndex*: RaftLogIndex
      logEntries*: Option[seq[RaftNodeLogEntry[SmCommandType]]]   # Optional log entry(ies). Will be empty for a Heart-Beat
    of rmoInstallSnapshot:
      discard

  RaftMessageResponse*[SmCommandType, SmStateType] = ref object of RaftMessageResponseBase[SmCommandType, SmStateType]
    case op*: RaftMessageOps
    of rmoRequestVote:
      granted*: bool                 # Is vote granted by the Raft node, from we requested vote?
    of rmoAppendLogEntry:
      success*: bool
      lastLogIndex*: RaftLogIndex
      state*: Option[SmStateType]    # Optional Raft Abstract State Machine State
    of rmoInstallSnapshot:
      discard

  # Raft Node Client Request/Response definitions
  RaftNodeClientRequestOps* = enum
    rncroRequestSmState = 0,
    rncroExecSmCommand = 1

  RaftNodeClientResponseError* = enum
    rncreSuccess = 0,
    rncreFail = 1,
    rncreNotLeader = 2,
    rncreStopped = 3

  RaftNodeClientRequest*[SmCommandType] = ref object
    op*: RaftNodeClientRequestOps
    nodeId*: RaftNodeId
    payload*: Option[SmCommandType]  # Optional RaftMessagePayload carrying a Log Entry

  RaftNodeClientResponse*[SmStateType] = ref object
    nodeId*: RaftNodeId
    error*: RaftNodeClientResponseError
    state*: Option[SmStateType]                         # Optional Raft Abstract State Machine State
    raftNodeRedirectId*: Option[RaftNodeId]             # Optional Raft Node ID to redirect the request to in case of failure