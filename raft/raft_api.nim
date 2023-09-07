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
  chronicles

# Forward declarations
proc RaftNodeSmInit[SmCommandType, SmStateType](stateMachine: var RaftNodeStateMachine[SmCommandType, SmStateType])

# Raft Node Public API
proc new*[SmCommandType, SmStateType](T: type RaftNode[SmCommandType, SmStateType];   # Create New Raft Node
                  id: RaftNodeId; peersIds: seq[RaftNodeId];
                  # persistentStorage: RaftNodePersistentStorage,
                  msgSendCallback: RaftMessageSendCallback): T =
  var
    peers: RaftNodePeers

  for peerId in peersIds:
    peers.add(RaftNodePeer(id: peerId, nextIndex: 0, matchIndex: 0, hasVoted: false, canVote: true))

  result = T(
    id: id, state: rnsFollower, currentTerm: 0, peers: peers, commitIndex: 0, lastApplied: 0,
    msgSendCallback: msgSendCallback, votedFor: DefaultUUID, currentLeaderId: DefaultUUID,

  )

  RaftNodeSmInit(result.stateMachine)
  initRLock(result.raftStateMutex)

proc RaftNodeLoad*[SmCommandType, SmStateType](
                  persistentStorage: RaftNodePersistentStorage,            # Load Raft Node From Storage
                  msgSendCallback: RaftMessageSendCallback): Result[RaftNode[SmCommandType, SmStateType], string] =
  discard

proc RaftNodeIdGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeId {.gcsafe.} =        # Get Raft Node ID
  withRLock(node.raftStateMutex):
    result = node.id

proc RaftNodeStateGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeState =             # Get Raft Node State
  withRLock(node.raftStateMutex):
    result = node.state

proc RaftNodeTermGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeTerm =               # Get Raft Node Term
  withRLock(node.raftStateMutex):
    result = node.currentTerm

func RaftNodePeersGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodePeers =             # Get Raft Node Peers
  withRLock(node.raftStateMutex):
    result = node.peers

func RaftNodeIsLeader*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =                      # Check if Raft Node is Leader
  withRLock(node.raftStateMutex):
    result = node.state == rnsLeader

# Deliver Raft Message to the Raft Node and dispatch it
proc RaftNodeMessageDeliver*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], raftMessage: RaftMessageBase): Future[RaftMessageResponseBase] {.async, gcsafe.} =
    case raftMessage.op
    of rmoRequestVote:    # Dispatch different Raft Message types based on the operation code
      result = RaftNodeHandleRequestVote(node, RaftMessageRequestVote(raftMessage))
    of rmoAppendLogEntry:
      var appendMsg = RaftMessageAppendEntries[SmCommandType](raftMessage)
      if appendMsg.logEntries.isSome:
        result = RaftNodeHandleAppendEntries(node, appendMsg)
      else:
        result = RaftNodeHandleHeartBeat(node, appendMsg)
    else: discard

# Process Raft Node Client Requests
proc RaftNodeServeClientRequest*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], req: RaftNodeClientRequest[SmCommandType]): Future[RaftNodeClientResponse[SmStateType]] {.async, gcsafe.} =
  case req.op
    of rncroExecSmCommand:
      # TODO: implemenmt command handling
      discard
    of rncroRequestSmState:
      if RaftNodeIsLeader(node):
        return RaftNodeClientResponse(nodeId: node.id, error: rncreSuccess, state: RaftNodeStateGet(node))
      else:
        return RaftNodeClientResponse(nodeId: node.id, error: rncreNotLeader, currentLeaderId: node.currentLeaderId)
    else:
      raiseAssert "Unknown client request operation."

# Abstract State Machine Ops
func RaftNodeSmStateGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): SmStateType =
  withRLock(node.raftStateMutex):
    node.stateMachine.state

proc RaftNodeSmInit[SmCommandType, SmStateType](stateMachine: var RaftNodeStateMachine[SmCommandType, SmStateType]) =
  mixin RaftSmInit
  RaftSmInit(stateMachine)

proc RaftNodeSmApply[SmCommandType, SmStateType](stateMachine: RaftNodeStateMachine[SmCommandType, SmStateType], command: SmCommandType) =
  mixin RaftSmApply
  withRLock(node.raftStateMutex):
    RaftSmApply(stateMachine, command)

# Private Abstract Timer creation
template RaftTimerCreate(timerInterval: int, timerCallback: RaftTimerCallback): Future[void] =
  mixin RaftTimerCreateCustomImpl
  RaftTimerCreateCustomImpl(timerInterval, timerCallback)

# Timers scheduling stuff etc.
proc RaftNodeScheduleHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  node.heartBeatTimer = RaftTimerCreate(130, proc() = asyncSpawn RaftNodeSendHeartBeat(node))

proc RaftNodeSendHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) {.async.} =
  debug "Raft Node sending Heart-Beat to peers", node_id=node.id
  for raftPeer in node.peers:
    let msgHrtBt = RaftMessageAppendEntries[SmCommandType](
      op: rmoAppendLogEntry, senderId: node.id, receiverId: raftPeer.id,
      senderTerm: RaftNodeTermGet(node), commitIndex: node.commitIndex,
      prevLogIndex: RaftNodeLogIndexGet(node) - 1, prevLogTerm: if RaftNodeLogIndexGet(node) > 0: RaftNodeLogEntryGet(node, RaftNodeLogIndexGet(node) - 1).term else: 0
    )
    let r = await node.msgSendCallback(msgHrtBt)
    discard r
    debug "Sent Heart-Beat", sender=node.id, to=raftPeer.id
  RaftNodeScheduleHeartBeat(node)

proc RaftNodeScheduleElectionTimeout*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  node.electionTimeoutTimer = RaftTimerCreate(150 + rand(150), proc =
    asyncSpawn RaftNodeStartElection(node)
  )

# Raft Node Control
proc RaftNodeCancelAllTimers*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  withRLock(node.raftStateMutex):
    if node.heartBeatTimer != nil:
      waitFor cancelAndWait(node.heartBeatTimer)
    if node.electionTimeoutTimer != nil:
      waitFor cancelAndWait(node.electionTimeoutTimer )
    if node.appendEntriesTimer != nil:
      waitFor cancelAndWait(node.appendEntriesTimer)

proc RaftNodeStop*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  # Try to stop gracefully
  withRLock(node.raftStateMutex):
    # Abort election if in election
    if node.state == rnsCandidate:
      RaftNodeAbortElection(node)s
    node.state = rnsStopped
  # Cancel pending timers (if any)
  RaftNodeCancelAllTimers(node)

proc RaftNodeStart*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  node.state = rnsFollower
  debug "Start Raft Node", node_id=node.id, state=node.state
  RaftNodeScheduleElectionTimeout(node)
