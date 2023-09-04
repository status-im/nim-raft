# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

{.hint[XDeclaredButNotUsed]: off.}

import types
import protocol
import log_ops
import chronicles

proc RaftNodeStartElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) {.async.} =
  withLock(node.raftStateMutex):
    debug "Raft Node started election. Node ID: ", node_id=node.id
    node.currentTerm.inc
    node.state = rnsCandidate
    node.votedFor = node.id

    for peer in node.peers:
      peer.hasVoted = false
      node.votesFuts.add(node.msgSendCallback(
          RaftMessageRequestVote(lastLogTerm: RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node)).value.term, lastLogIndex: RaftNodeLogIndexGet(node), senderTerm: node.currentTerm)
        )
      )

  # Process votes (if any)
  for voteFut in node.votesFuts:
    var
      r: RaftMessageRequestVoteResponse

    r = RaftMessageRequestVoteResponse(waitFor voteFut)

    debug "voteFut.finished", voteFut_finished=voteFut.finished

    withLock(node.raftStateMutex):
      for p in node.peers:
        debug "voteFut: ", Response=repr(r)
        debug "senderId: ", sender_id=r.senderId
        debug "granted: ", granted=r.granted
        if p.id == r.senderId:
          p.hasVoted = r.granted

  withLock(node.raftStateMutex):
    node.votesFuts.clear

proc RaftNodeAbortElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  withLock(node.raftStateMutex):
    for fut in node.voteFuts:
      if not fut.finished and not fut.failed:
        cancel(fut)

proc RaftNodeProcessRequestVote*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageRequestVote): RaftMessageRequestVoteResponse =
  withLock(node.raftStateMutex):
    result = RaftMessageRequestVoteResponse(msgId: msg.msgId, senderId: msg.senderId, receiverId: msg.reciverId, granted: false)
    if msg.senderTerm > node.term:
      if msg.lastLogIndex >= RaftNodeLogIndexGet(node) and msg.lastLogTerm >= RaftNodeLogEntryGet(RaftNodeLogIndexGet(node)).term:
        result.granted = true

proc RaftNodeProcessAppendEntries*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageAppendEntries): RaftMessageAppendEntriesResponse =
  discard

proc RaftNodeProcessHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageAppendEntries): RaftMessageAppendEntriesResponse =
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