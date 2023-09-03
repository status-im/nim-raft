# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import chronicles

import types
import protocol
import consensus_module
import log_ops
import ../db/kvstore_mdbx

export types, protocol, consensus_module, log_ops

proc RaftNodeSmInit[SmCommandType, SmStateType](stateMachine: var RaftNodeStateMachine[SmCommandType, SmStateType])
proc RaftNodeSendHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType])
proc RaftNodeScheduleHeartBeatTimeout*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): Future[void] {.async.}

# Raft Node Public API procedures / functions
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
    msgSendCallback: msgSendCallback, votedFor: DefaultUUID, currentLeaderId: DefaultUUID
  )

  RaftNodeSmInit(result.stateMachine)
  initLock(result.raftStateMutex)

proc RaftNodeLoad*[SmCommandType, SmStateType](
                  persistentStorage: RaftNodePersistentStorage,            # Load Raft Node From Storage
                  msgSendCallback: RaftMessageSendCallback): Result[RaftNode[SmCommandType, SmStateType], string] =
  discard

proc RaftNodeIdGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeId {.gcsafe.} =        # Get Raft Node ID
  result = node.id

proc RaftNodeStateGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeState =             # Get Raft Node State
  node.state

proc RaftNodeTermGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodeTerm =               # Get Raft Node Term
  node.currentTerm

func RaftNodePeersGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): RaftNodePeers =             # Get Raft Node Peers
  node.peers

func RaftNodeIsLeader*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): bool =                      # Check if Raft Node is Leader
  node.state == rnsLeader

# Deliver Raft Message to the Raft Node and dispatch it
proc RaftNodeMessageDeliver*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], raftMessage: RaftMessageBase): Future[RaftMessageResponseBase] {.async, gcsafe.} =
    # case raftMessage.type
    # of RaftMessageAppendEntries:  # Dispatch different Raft Message types
    #   discard
    # of RaftMessageRequestVote:
    #   discard
    # else: discard
    discard

# Process RaftNodeClientRequests
proc RaftNodeClientRequest*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType], req: RaftNodeClientRequest[SmCommandType]): Future[RaftNodeClientResponse[SmStateType]] {.async, gcsafe.} =
  case req.op
    of rncroExecSmCommand:
      # TODO: implemenmt command handling
      discard
    of rncroRequestSmState:
      if RaftNodeIsLeader(node):
        return RaftNodeClientResponse(error: rncreSuccess, state: RaftNodeStateGet(node))
    else: discard

# Abstract State Machine Ops
func RaftNodeSmStateGet*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): SmStateType =
  node.stateMachine.state

proc RaftNodeSmInit[SmCommandType, SmStateType](stateMachine: var RaftNodeStateMachine[SmCommandType, SmStateType]) =
  mixin RaftSmInit
  RaftSmInit(stateMachine)

proc RaftNodeSmApply[SmCommandType, SmStateType](stateMachine: RaftNodeStateMachine[SmCommandType, SmStateType], command: SmCommandType) =
  mixin RaftSmApply
  RaftSmApply(stateMachine, command)

# Private Abstract Timer manipulation Ops
template RaftTimerCreate(timerInterval: int, oneshot: bool, timerCallback: RaftTimerCallback): RaftTimer =
  mixin RaftTimerCreateCustomImpl
  RaftTimerCreateCustomImpl(timerInterval, oneshot, timerCallback)

# Timers scheduling stuff etc.
proc RaftNodeScheduleHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  var fut = sleepAsync(node.heartBeatTimeout)
  fut.callback = proc () = RaftNodeSendHeartBeat(node)

proc RaftNodeScheduleHeartBeatTimeout*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]): Future[void] {.async.} =
  node.heartBeatTimeoutTimer = sleepAsync(node.heartBeatTimeout)
  await node.heartBeatTimeoutTimer
  node.state = rnsCandidate   # Transition to candidate state and initiate new Election
  var f = RaftNodeStartElection(node)
  cancel(f)

proc RaftNodeSendHeartBeat*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  for raftPeer in node.peers:
    let msgHrtBt = RaftMessageAppendEntries(
      senderId: node.id, receiverId: raftPeer.id,
      senderTerm: RaftNodeTermGet(node), commitIndex: node.commitIndex,
      prevLogIndex: RaftNodeLogIndexGet(node) - 1, prevLogTerm: if RaftNodeLogIndexGet(node) > 0: RaftNodeLogEntry(node, RaftNodeLogIndexGet(node) - 1).term else: 0
    )
    asyncCheck node.msgSendCallback(msgHrtBt)
    RaftNodeScheduleHeartBeat(node)

# Raft Node Control
proc RaftNodeCancelAllTimers[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  node.requestVotesTimer.fail(newException(Exception, "fail"))
  node.heartBeatTimer.fail(newException(Exception, "fail"))
  node.heartBeatTimeoutTimer.fail(newException(Exception, "fail"))
  node.appendEntriesTimer.fail(newException(Exception, "fail"))

proc RaftNodeStop*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  # Try to stop gracefully
  node.state = rnsStopped
  # Cancel pending timers (if any)
  var f = RaftNodeCancelAllTimers(node)

proc RaftNodeStart*[SmCommandType, SmStateType](node: RaftNode[SmCommandType, SmStateType]) =
  node.state = rnsFollower
  asyncSpawn RaftNodeScheduleHeartBeatTimeout(node)
  debug "Start Raft Node with ID: ", nodeid=node.id