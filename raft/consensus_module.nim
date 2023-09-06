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
  withRLock(node.raftStateMutex):
    var cnt = 0
    for peer in node.peers:
      if peer.hasVoted:
        cnt.inc
    if cnt >= (node.peers.len div 2 + 1):
      result = true

proc RaftNodeStartElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) {.async.} =
  withRLock(node.raftStateMutex):
    node.currentTerm.inc
    node.state = rnsCandidate
    node.votedFor = node.id
    debug "Raft Node started election", node_id=node.id, state=node.state, voted_for=node.votedFor

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
    debug "Received vote", node_id=node.id, sender_id=respVote.senderId, granted=respVote.granted

    withRLock(node.raftStateMutex):
      for p in node.peers:
        if p.id == respVote.senderId:
          p.hasVoted = respVote.granted

  withRLock(node.raftStateMutex):
    while node.votesFuts.len > 0:
      discard node.votesFuts.pop

  withRLock(node.raftStateMutex):
    if node.state == rnsCandidate:
      if RaftNodeQuorumMin(node):
        debug "Raft Node transition to leader", node_id=node.id
        node.state = rnsLeader  # Transition to leader and send Heart-Beat to establish this node as the cluster leader
        asyncSpawn RaftNodeSendHeartBeat(node)
      else:
        asyncSpawn RaftNodeStartElection(node)

proc RaftNodeHandleRequestVote*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageRequestVote): RaftMessageRequestVoteResponse =
  withRLock(node.raftStateMutex):
    result = RaftMessageRequestVoteResponse(msgId: msg.msgId, senderId: node.id, receiverId: msg.senderId, granted: false)
    if node.state != rnsCandidate and node.state != rnsStopped and msg.senderTerm > node.currentTerm and node.votedFor == DefaultUUID:
      if msg.lastLogIndex >= RaftNodeLogIndexGet(node) and msg.lastLogTerm >= RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node)).term:
        node.votedFor = msg.senderId
        result.granted = true

proc RaftNodeHandleAppendEntries*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessageAppendEntries): RaftMessageAppendEntriesResponse[SmStateType] =
  discard

proc RaftNodeReplicateSmCommand*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], cmd: SmCommandType) =
  discard

proc RaftNodeLogAppend[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], logEntry: RaftNodeLogEntry[SmCommandType]) =
  discard

proc RaftNodeLogTruncate[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], truncateIndex: uint64) =
  discard