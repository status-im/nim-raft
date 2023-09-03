# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types, protocol, log_ops

proc RaftNodeStartElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  var
    votesFuts: seq[Future[void]]

  node.state = rnsCandidate
  for p in node.peers:
    p.votedFor = DefaultUUID
  node.votedFor = node.id

  for peer in node.peers:
    votesFuts.add(node.msgSendCallback(
        RaftMessageRequestVote(lastLogTerm: RaftNodeLogEntry(RaftNodeLogIndexGet(node)).term, lastLogIndex: RaftNodeLogIndexGet(node), senderTerm: node.currentTerm)
      )
    )

    # Process votes
  for voteFut in votesFuts:
    await voteFut
    if voteFut.finished and not voteFut.failed:
      for p in node.peers:
        if p.id == voteFut.senderId:
          if voteFut.granted:
            p.votedFor = node.id
          else:
            if voteFut.votedFor.initialized:
              p.votedFor = voteFut.votedFor

proc RaftNodeAbortElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  discard

proc RaftNodeProcessRequestVote*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageRequestVote): Future[RaftMessageRequestVoteResponse] =
  if msg.senderTerm > node.term:
    if msg.lastLogIndex >= RaftNodeLogIndexGet(node) and msg.lastLogTerm >= RaftNodeLogEntryGet(RaftNodeLogIndexGet(node)).term:
      # grant vote
      discard

proc RaftNodeProcessAppendEntries*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageAppendEntries): Future[RaftMessageAppendEntriesResponse] =
  discard

proc RaftNodeQuorumMin[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =
  discard

proc RaftNodeReplicateSmCommand*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], cmd: SmCommandType) =
  discard

proc RaftNodeScheduleRequestVotesCleanUpTimeout*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  discard

proc RaftNodeLogAppend[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logEntry: RaftNodeLogEntry[SmCommandType]) =
  discard

proc RaftNodeLogTruncate[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], truncateIndex: uint64) =
  discard