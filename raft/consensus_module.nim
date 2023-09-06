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

proc RaftNodeQuorumMin[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =
  result = false
  withLock(node.raftStateMutex):
    var cnt = 0
    for peer in node.peers:
      if peer.hasVoted:
        cnt.inc
    if cnt >= (node.peers.len div 2 + 1):
      result = true

proc RaftNodeStartElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) {.async.} =
  withLock(node.raftStateMutex):
    debug "Raft Node started election. Node ID: ", node_id=node.id
    node.currentTerm.inc
    node.state = rnsCandidate
    node.votedFor = node.id

    for peer in node.peers:
      peer.hasVoted = false
      node.votesFuts.add(node.msgSendCallback(
          RaftMessageRequestVote(
            op: rmoRequestVote, msgId: genUUID(), senderId: node.id,
            receiverId: peer.id, lastLogTerm: RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node)).term,
            lastLogIndex: RaftNodeLogIndexGet(node), senderTerm: node.currentTerm)
        )
      )

  # Process votes (if any)
  for voteFut in node.votesFuts:
    let r = await voteFut
    let respVote = RaftMessageRequestVoteResponse(r)

    debugEcho "r: ", repr(r)
    debug "voteFut.finished", voteFut_finished=voteFut.finished

    withLock(node.raftStateMutex):
      for p in node.peers:
        debug "voteFut: ", Response=repr(r)
        debug "senderId: ", sender_id=respVote.senderId
        debug "granted: ", granted=respVote.granted
        if p.id == respVote.senderId:
          p.hasVoted = respVote.granted

  withLock(node.raftStateMutex):
    while node.votesFuts.len > 0:
      discard node.votesFuts.pop

  withLock(node.raftStateMutex):
    if node.state == rnsCandidate:
      if RaftNodeQuorumMin(node):
        node.state = rnsLeader  # Transition to leader and send Heart-Beat to establish this node as the cluster leader
        RaftNodeSendHeartBeat(node)
      else:
        asyncSpawn RaftNodeStartElection(node)

proc RaftNodeHandleRequestVote*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageRequestVote): RaftMessageRequestVoteResponse =
  withLock(node.raftStateMutex):
    result = RaftMessageRequestVoteResponse(msgId: msg.msgId, senderId: node.id, receiverId: msg.senderId, granted: false)
    if node.state != rnsCandidate and node.state != rnsStopped and msg.senderTerm > node.currentTerm:
      if msg.lastLogIndex >= RaftNodeLogIndexGet(node) and msg.lastLogTerm >= RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node)).term:
        result.granted = true

proc RaftNodeHandleAppendEntries*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageAppendEntries): RaftMessageAppendEntriesResponse[SmStateType] =
  discard

proc RaftNodeReplicateSmCommand*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], cmd: SmCommandType) =
  discard

proc RaftNodeLogAppend[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logEntry: RaftNodeLogEntry[SmCommandType]) =
  discard

proc RaftNodeLogTruncate[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], truncateIndex: uint64) =
  discard