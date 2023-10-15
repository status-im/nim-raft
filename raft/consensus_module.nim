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

proc raftNodeQuorumMin[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =
  result = false
  var cnt = 0
  for peer in node.peers:
    if peer.hasVoted:
      cnt.inc
  if cnt >= (node.peers.len div 2 + node.peers.len mod 2):
    result = true

proc raftNodeHandleHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessage[SmCommandType, SmStateType]):
    RaftMessageResponse[SmCommandType, SmStateType] =
  debug "Received heart-beat", node_id=node.id, sender_id=msg.sender_id, node_current_term=node.currentTerm, sender_term=msg.senderTerm
  result = RaftMessageResponse[SmCommandType, SmStateType](op: rmoAppendLogEntry, senderId: node.id, receiverId: msg.senderId, msgId: msg.msgId, success: false)
  withRLock(node.raftStateMutex):
    if node.state == rnsStopped:
      return

    if msg.senderTerm >= node.currentTerm:
      raftNodeCancelTimers(node)
      if node.state == rnsCandidate:
        raftNodeAbortElection(node)
      result.success = true
      node.currentTerm = msg.senderTerm
      node.votedFor = DefaultUUID
      node.currentLeaderId = msg.senderId
      raftNodeScheduleElectionTimeout(node)

proc raftNodeHandleRequestVote*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessage[SmCommandType, SmStateType]):
    RaftMessageResponse[SmCommandType, SmStateType] =
  result = RaftMessageResponse[SmCommandType, SmStateType](op: rmoRequestVote, msgId: msg.msgId, senderId: node.id, receiverId: msg.senderId, granted: false)
  withRLock(node.raftStateMutex):
    if node.state == rnsStopped:
      return

    if msg.senderTerm > node.currentTerm and node.votedFor == DefaultUUID:
      if msg.lastLogTerm > raftNodeLogEntryGet(node, raftNodeLogIndexGet(node)).term or
        (msg.lastLogTerm == raftNodeLogEntryGet(node, raftNodeLogIndexGet(node)).term and msg.lastLogIndex >= raftNodeLogIndexGet(node)):
        if node.electionTimeoutTimer != nil:
          asyncSpawn cancelAndWait(node.electionTimeoutTimer)
        node.votedFor = msg.senderId
        node.currentLeaderId = DefaultUUID
        result.granted = true
        raftNodeScheduleElectionTimeout(node)

proc raftNodeAbortElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  withRLock(node.raftStateMutex):
    node.state = rnsFollower
    for fut in node.votesFuts:
        asyncSpawn cancelAndWait(fut)

proc raftNodeStartElection*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) {.async.} =
  mixin raftNodeScheduleElectionTimeout, raftTimerCreate
  raftNodeScheduleElectionTimeout(node)

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
            receiverId: peer.id, lastLogTerm: raftNodeLogEntryGet(node, raftNodeLogIndexGet(node)).term,
            lastLogIndex: raftNodeLogIndexGet(node), senderTerm: node.currentTerm)
        )
      )

  withRLock(node.raftStateMutex):
    # Wait for votes or voting timeout
    await allFutures(node.votesFuts) or raftTimerCreate(node.votingTimeout, proc()=discard)

    # Process votes (if any)
    for voteFut in node.votesFuts:
      if voteFut.finished and not voteFut.cancelled:
        let respVote = RaftMessageResponse[SmCommandType, SmStateType](voteFut.read)
        debug "Received vote", node_id=node.id, sender_id=respVote.senderId, granted=respVote.granted

        for p in node.peers:
          if p.id == respVote.senderId:
            p.hasVoted = respVote.granted

  withRLock(node.raftStateMutex):
    if node.state == rnsCandidate:
      if raftNodeQuorumMin(node):
        await cancelAndWait(node.electionTimeoutTimer)
        debug "Raft Node transition to leader", node_id=node.id
        node.state = rnsLeader        # Transition to leader state and send Heart-Beat to establish this node as the cluster leader
        asyncSpawn raftNodeSendHeartBeat(node)

proc raftNodeHandleAppendEntries*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], msg: RaftMessage[SmCommandType, SmStateType]):
    RaftMessageResponse[SmCommandType, SmStateType] =
  result = RaftMessageResponse[SmCommandType, SmStateType](op: rmoAppendLogEntry, senderId: node.id, receiverId: msg.senderId, msgId: msg.msgId, success: false)
  withRLock(node.raftStateMutex):
    if node.state == rnsStopped:
      return

    if msg.senderTerm >= node.currentTerm:
      raftNodeCancelTimers(node)
      if node.state == rnsCandidate:
        raftNodeAbortElection(node)
      node.currentTerm = msg.senderTerm
      node.votedFor = DefaultUUID
      node.state = rnsFollower
      node.currentLeaderId = msg.senderId
      raftNodeScheduleElectionTimeout(node)

    if msg.senderTerm < node.currentTerm:
      return

    if msg.prevLogIndex > raftNodeLogIndexGet(node):
      return

    if msg.prevLogIndex == raftNodeLogIndexGet(node):
      if msg.prevLogTerm != raftNodeLogEntryGet(node, raftNodeLogIndexGet(node)).term:
        return

    if msg.prevLogIndex < raftNodeLogIndexGet(node):
      if msg.prevLogTerm != raftNodeLogEntryGet(node, msg.prevLogIndex).term:
        raftNodeLogTruncate(node, msg.prevLogIndex)
        return

    if msg.logEntries.isSome:
      for entry in msg.logEntries.get:
        raftNodeLogAppend(node, entry)

    if msg.commitIndex > node.commitIndex:
      node.commitIndex = min(msg.commitIndex, raftNodeLogIndexGet(node))
      raftNodeApplyLogEntry(node, raftNodeLogEntryGet(node, node.commitIndex))

    result.success = true


proc raftNodeReplicateSmCommand*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], cmd: SmCommandType) =
  mixin RaftLogEntry, raftTimerCreate

  withRLock(node.raftStateMutex):
    var
      logEntry: RaftLogEntry[SmCommandType](term: node.currentTerm, data: cmd, entryType: etData)

    raftNodeLogAppend(node, logEntry)

    for peer in node.peers:
      var
        msg: RaftMessage[SmCommandType, SmStateType] = RaftMessage[SmCommandType, SmStateType](
          op: rmoAppendLogEntry, msgId: genUUID(), senderId: node.id, receiverId: peer.id,
          senderTerm: node.currentTerm, prevLogIndex: raftNodeLogIndexGet(node),
          prevLogTerm: raftNodeLogEntryGet(node, raftNodeLogIndexGet(node)).term,
          commitIndex: node.commitIndex, entries: @[logEntry]
        )

      node.replicateFuts.add(node.msgSendCallback(msg))
