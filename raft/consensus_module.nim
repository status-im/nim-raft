# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types, protocol

proc RaftNodeStartElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  discard

proc RaftNodeProcessRequestVote*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageRequestVote): RaftMessageRequestVoteResponse =
  discard

proc RaftNodeProcessAppendEntries*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageAppendEntries): RaftMessageAppendEntriesResponse =
  discard

proc RaftNodeQuorumMin[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =
  discard

proc RaftNodeReplicateSmCommand*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], cmd: SmCommandType) =
  discard

proc RaftNodeScheduleElectionTimeOut*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  discard

proc RaftNodeScheduleRequestVotesCleanUpTimeout*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  discard