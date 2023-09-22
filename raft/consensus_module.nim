# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types
import protocol
import log_ops
import chronicles
import async_util

proc RaftNodeQuorumMin[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =
  result = false
  var cnt = 0
  for peer in node.peers:
    if peer.hasVoted:
      cnt.inc
  if cnt >= (node.peers.len div 2 + 1):
    result = true

proc RaftNodeHandleHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessage[SmCommandType, SmStateType]):
    RaftMessageResponse[SmCommandType, SmStateType] =
  debug "Received heart-beat", node_id=node.id, sender_id=msg.sender_id, node_current_term=node.currentTerm, sender_term=msg.senderTerm
  result = RaftMessageResponse[SmCommandType, SmStateType](op: rmoAppendLogEntry, senderId: node.id, receiverId: msg.senderId, msgId: msg.msgId, success: false)
  withRLock(node.raftStateMutex):
    if node.state == rnsStopped:
      return

    if msg.senderTerm >= node.currentTerm:
      RaftNodeCancelAllTimers(node)
      if node.state == rnsCandidate:
        RaftNodeAbortElection(node)
      result.success = true
      node.currentTerm = msg.senderTerm
      node.votedFor = DefaultUUID
      node.currentLeaderId = msg.senderId
      RaftNodeScheduleElectionTimeout(node)

proc RaftNodeHandleRequestVote*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessage[SmCommandType, SmStateType]):
    RaftMessageResponse[SmCommandType, SmStateType] =
  result = RaftMessageResponse[SmCommandType, SmStateType](op: rmoRequestVote, msgId: msg.msgId, senderId: node.id, receiverId: msg.senderId, granted: false)
  withRLock(node.raftStateMutex):
    if node.state == rnsStopped:
      return

    if msg.senderTerm > node.currentTerm and node.votedFor == DefaultUUID:
      if msg.lastLogTerm > RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node)).term or
        (msg.lastLogTerm == RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node)).term and msg.lastLogIndex >= RaftNodeLogIndexGet(node)):
        if node.electionTimeoutTimer != nil:
          asyncSpawn cancelAndWait(node.electionTimeoutTimer)
        node.votedFor = msg.senderId
        result.granted = true
        RaftNodeScheduleElectionTimeout(node)

proc RaftNodeAbortElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  withRLock(node.raftStateMutex):
    node.state = rnsFollower
    for fut in node.votesFuts:
        waitFor cancelAndWait(fut)

proc RaftNodeStartElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) {.async.} =
  mixin RaftNodeScheduleElectionTimeout
  RaftNodeScheduleElectionTimeout(node)

  withRLock(node.raftStateMutex):
    while node.votesFuts.len > 0:
     discard node.votesFuts.pop
    node.currentTerm.inc
    node.state = rnsCandidate
    node.votedFor = node.id
    debug "Raft Node started election", node_id=node.id, state=node.state, voted_for=node.votedFor

  for peer in node.peers:
    peer.hasVoted = false
    node.votesFuts.add(node.msgSendCallback(
        RaftMessage[SmCommandType, SmStateType](
          op: rmoRequestVote, msgId: genUUID(), senderId: node.id,
          receiverId: peer.id, lastLogTerm: RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node)).term,
          lastLogIndex: RaftNodeLogIndexGet(node), senderTerm: node.currentTerm)
      )
    )

  withRLock(node.raftStateMutex):
    # Process votes (if any)
    for voteFut in node.votesFuts:
      try:
        await voteFut or sleepAsync(milliseconds(node.votingTimeout))
        if not voteFut.finished:
          await cancelAndWait(voteFut)
        else:
          if not voteFut.cancelled:
            let respVote = RaftMessageResponse[SmCommandType, SmStateType](voteFut.read)
            debug "Received vote", node_id=node.id, sender_id=respVote.senderId, granted=respVote.granted

            for p in node.peers:
              if p.id == respVote.senderId:
                p.hasVoted = respVote.granted
      except Exception as e:
        discard

  withRLock(node.raftStateMutex):
    if node.state == rnsCandidate:
      if RaftNodeQuorumMin(node):
        await cancelAndWait(node.electionTimeoutTimer)
        debug "Raft Node transition to leader", node_id=node.id
        node.state = rnsLeader        # Transition to leader state and send Heart-Beat to establish this node as the cluster leader
        RaftNodeSendHeartBeat(node)

proc RaftNodeHandleAppendEntries*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessage[SmCommandType, SmStateType]):
    RaftMessageResponse[SmCommandType, SmStateType] =
  discard

proc RaftNodeReplicateSmCommand*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], cmd: SmCommandType) =
  discard