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
import consensus_module
import log_ops
import ../db/kvstore_mdbx
import chronicles
import std/random

export
  types,
  protocol,
  consensus_module,
  log_ops,
  chronicles,
  random

# Forward declarations
proc raftNodeSmInit*[SmCommandType, SmStateType](stateMachine: var RaftNodeStateMachine[SmCommandType, SmStateType])

# Raft Node Public API
proc new*[SmCommandType, SmStateType](T: type RaftNode[SmCommandType, SmStateType];
                  id: RaftNodeId; peersIds: seq[RaftNodeId];
                  # persistentStorage: RaftNodePersistentStorage,
                  msgSendCallback: RaftMessageSendCallback;
                  electionTimeout: int=150;
                  heartBeatTimeout: int=150;
                  appendEntriesRespTimeout: int=20;
                  votingRespTimeout: int=20;
                  heartBeatRespTimeout: int=10
  ): T =
  var
    peers: RaftNodePeers

  for peerId in peersIds:
    peers.add(RaftNodePeer(id: peerId, nextIndex: 1, matchIndex: 0, hasVoted: false, canVote: true))

  result = T(
    id: id, state: rnsFollower, currentTerm: 0, peers: peers, commitIndex: 0, lastApplied: 0,
    msgSendCallback: msgSendCallback, votedFor: DefaultUUID, currentLeaderId: DefaultUUID,
    electionTimeout: electionTimeout, heartBeatTimeout: heartBeatTimeout, appendEntriesRespTimeout: appendEntriesRespTimeout,
    heartBeatRespTimeout: heartBeatRespTimeout, votingRespTimeout: votingRespTimeout, hrtBtSuccess: false
  )

  raftNodeSmInit(result.stateMachine)
  initRLock(result.raftStateMutex)

proc raftNodeLoad*[SmCommandType, SmStateType](
                  persistentStorage: RaftNodePersistentStorage,            # Load Raft Node From Storage
                  msgSendCallback: RaftMessageSendCallback): Result[RaftNode[SmCommandType, SmStateType], string] =
  discard

proc raftNodeIdGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeId {.gcsafe.} =        # Get Raft Node ID
  withRLock(node.raftStateMutex):
    result = node.id

proc raftNodeStateGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeState =             # Get Raft Node State
  withRLock(node.raftStateMutex):
    result = node.state

proc raftNodeTermGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeTerm =               # Get Raft Node Term
  withRLock(node.raftStateMutex):
    result = node.currentTerm

func raftNodePeersGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodePeers =             # Get Raft Node Peers
  withRLock(node.raftStateMutex):
    result = node.peers

func raftNodeIsLeader*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =                      # Check if Raft Node is Leader
  withRLock(node.raftStateMutex):
    result = node.state == rnsLeader

# Deliver Raft Message to the Raft Node and dispatch it
proc raftNodeMessageDeliver*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], raftMessage: RaftMessageBase[SmCommandType, SmStateType]):
      Future[RaftMessageResponseBase[SmCommandType, SmStateType]] {.async, gcsafe.} =
    var
      rm = RaftMessage[SmCommandType, SmStateType](raftMessage)

    case rm.op          # Dispatch different Raft Message types based on the operation code
    of rmoRequestVote:
      result = raftNodeHandleRequestVote(node, rm)
    of rmoAppendLogEntry:
      if rm.logEntries.isSome:
        result = raftNodeHandleAppendEntries(node, rm)
      else:
        result = raftNodeHandleHeartBeat(node, rm)
    else: discard

# Process Raft Node Client Requests
proc raftNodeServeClientRequest*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], req: RaftNodeClientRequest[SmCommandType]):
    Future[RaftNodeClientResponse[SmStateType]] {.async, gcsafe.} =

  withRLock(node.raftStateMutex):
    if not raftNodeIsLeader(node):
      return RaftNodeClientResponse(nodeId: node.id, error: rncreNotLeader, currentLeaderId: node.currentLeaderId)

    case req.op
      of rncroExecSmCommand:

        let resFut = await raftNodeReplicateSmCommand(node, req.smCommand)

        if resFut.read:
          return RaftNodeClientResponse(nodeId: node.id, error: rncreSuccess, state: raftNodeStateGet(node))
        else:
          return RaftNodeClientResponse(nodeId: node.id, error: rncreFail, state: raftNodeStateGet(node))

      of rncroRequestSmState:
        return RaftNodeClientResponse(nodeId: node.id, error: rncreSuccess, state: raftNodeStateGet(node))

      else:
        raiseAssert "Unknown client request operation."

# Abstract State Machine Ops
func raftNodeSmStateGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): SmStateType =
  withRLock(node.raftStateMutex):
    node.stateMachine.state

proc raftNodeSmInit*[SmCommandType, SmStateType](stateMachine: var RaftNodeStateMachine[SmCommandType, SmStateType]) =
  mixin raftSmInit

  raftSmInit(stateMachine)

proc raftNodeSmApply*[SmCommandType, SmStateType](stateMachine: RaftNodeStateMachine[SmCommandType, SmStateType], command: SmCommandType) =
  mixin raftSmApply

  raftSmApply(stateMachine, command)

# Private Abstract Timer creation
template raftTimerCreate*(timerInterval: int, timerCallback: RaftTimerCallback): Future[void] =
  mixin raftTimerCreateCustomImpl

  raftTimerCreateCustomImpl(timerInterval, timerCallback)

# Timers scheduling stuff etc.
proc raftNodeScheduleHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  withRLock(node.raftStateMutex):
    node.heartBeatTimer = raftTimerCreate(node.heartBeatTimeout, proc() = asyncSpawn raftNodeSendHeartBeat(node))

proc raftNodeSendHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) {.async.} =
  debug "Raft Node sending Heart-Beat to peers", node_id=node.id

  withRLock(node.raftStateMutex):
    var hrtBtFuts: seq[Future[RaftMessageResponseBase[SmCommandType, SmStateType]]]

    for raftPeer in node.peers:
      let msgHrtBt = RaftMessage[SmCommandType, SmStateType](
        op: rmoAppendLogEntry, senderId: node.id, receiverId: raftPeer.id,
        senderTerm: raftNodeTermGet(node), commitIndex: node.commitIndex,
        prevLogIndex: raftNodeLogIndexGet(node) - 1, prevLogTerm: if raftNodeLogIndexGet(node) > 0: raftNodeLogEntryGet(node, raftNodeLogIndexGet(node) - 1).term else: 0
      )
      hrtBtFuts.add(node.msgSendCallback(msgHrtBt))
    let allHrtBtFuts = allFutures(hrtBtFuts)
    await allHrtBtFuts or raftTimerCreate(node.heartBeatRespTimeout, proc()=discard)

    var successCnt = 0
    for fut in hrtBtFuts:
      if fut.finished:
        let resp = RaftMessageResponse[SmCommandType, SmStateType](fut.read)
        if resp.success:
          successCnt.inc

    if successCnt >= (node.peers.len div 2 + node.peers.len mod 2):
      node.hrtBtSuccess = true

  raftNodeScheduleHeartBeat(node)

proc raftNodeScheduleElectionTimeout*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  withRLock(node.raftStateMutex):
    node.electionTimeoutTimer = raftTimerCreate(node.electionTimeout + rand(node.electionTimeout), proc =
      asyncSpawn raftNodeStartElection(node)
    )
    node.hrtBtSuccess = false

# Raft Node Control
proc raftNodeCancelTimers*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  withRLock(node.raftStateMutex):
    if node.heartBeatTimer != nil:
      asyncSpawn cancelAndWait(node.heartBeatTimer)
    if node.electionTimeoutTimer != nil:
      asyncSpawn cancelAndWait(node.electionTimeoutTimer )

proc raftNodeStop*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  # Try to stop gracefully
  withRLock(node.raftStateMutex):
    # Abort election if in election
    if node.state == rnsCandidate:
      raftNodeAbortElection(node)s
    # Cancel pending timers (if any)
    raftNodeCancelTimers(node)

proc raftNodeStart*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  randomize()
  withRLock(node.raftStateMutex):
    node.state = rnsFollower
    debug "Start Raft Node", node_id=node.id, state=node.state
    raftNodeScheduleElectionTimeout(node)
