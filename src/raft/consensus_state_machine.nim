# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types
import log
import tracker
import state

import std/[times]
import std/random


randomize()

type
  RaftRpcMessageType* = enum
    VoteRequest = 0,
    VoteReplay = 1,
    AppendRequest = 2,
    AppendReplay = 3
  
  RaftRpcCode* = enum
    Rejected = 0,
    Accepted = 1

  DebugLogLevel* = enum
    Critical = 0,
    Error = 1,
    Warning = 2,
    Debug = 3,
    Info = 4,
  
  DebugLogEntry* = object
    level*: DebugLogLevel
    time*: times.DateTime
    nodeId*: RaftnodeId
    state*: RaftNodeState
    msg*: string


  RaftRpcAppendRequest* = object
    previousTerm*: RaftNodeTerm
    previousLogIndex*: RaftLogIndex
    commitIndex*: RaftLogIndex
    entries*: seq[LogEntry]
    
  RaftRpcAppendReplayRejected* = object
    nonMatchingIndex: RaftLogIndex
    lastIdx: RaftLogIndex

  RaftRpcAppendReplayAccepted* = object
    lastNewIndex: RaftLogIndex

  RaftRpcAppendReplay* = object
    commitIndex: RaftLogIndex
    term: RaftNodeTerm
    case result: RaftRpcCode:
      of Accepted: accepted: RaftRpcAppendReplayAccepted
      of Rejected: rejected: RaftRpcAppendReplayRejected 

  RaftRpcVoteRequest* = object
    currentTerm*: RaftNodeTerm
    lastLogIndex*: RaftLogIndex
    lastLogTerm*: RaftNodeTerm
    force*: bool
    
  RaftRpcVoteReplay* = object
    currentTerm*: RaftNodeTerm
    voteGranted*: bool

  RaftRpcMessage* = object
    currentTerm*: RaftNodeTerm
    sender*: RaftNodeId
    receiver*: RaftNodeId
    case kind*: RaftRpcMessageType
    of VoteRequest: voteRequest*: RaftRpcVoteRequest
    of VoteReplay: voteReplay*: RaftRpcVoteReplay
    of AppendRequest: appendRequest*: RaftRpcAppendRequest
    of AppendReplay: appendReplay*: RaftRpcAppendReplay 

  RaftStateMachineOutput* = object
    logEntries*: seq[LogEntry]
    # Entries that should be applyed to the "User" State machine
    committed*: seq[LogEntry]
    messages*: seq[RaftRpcMessage]
    debugLogs*: seq[DebugLogEntry]
    term*: RaftNodeTerm
    votedFor*: Option[RaftNodeId]
    stateChange*: bool

  RaftStateMachine* = object
    myId*: RaftNodeId
    term*: RaftNodeTerm
    commitIndex: RaftLogIndex
    toCommit: RaftLogIndex
    log: RaftLog
    output: RaftStateMachineOutput
    lastUpdate: times.Time
    votedFor: RaftNodeId
    currentLeader: RaftNodeId
    pingLeader: bool
    config: RaftConfig

    lastElectionTime: times.DateTime
    randomizedElectionTime: times.Duration
    heartbeatTime: times.Duration
    timeNow: times.DateTime
    startTime: times.DateTime
    electionTimeout: times.Duration

    state*: RaftStateMachineState

func leader*(sm: var RaftStateMachine): var LeaderState =
  return sm.state.leader

func follower*(sm: var RaftStateMachine): var FollowerState =
  return sm.state.follower

func candidate*(sm: var RaftStateMachine): var CandidateState =
  return sm.state.candidate

func addDebugLogEntry(sm: var RaftStateMachine, level: DebugLogLevel, msg: string) =
  sm.output.debugLogs.add(DebugLogEntry(time: sm.timeNow, level: level, msg: msg, nodeId: sm.myId))

func debug*(sm: var RaftStateMachine, log: string) = 
  sm.addDebugLogEntry(DebugLogLevel.Debug, log)

func warning*(sm: var RaftStateMachine, log: string) = 
  sm.addDebugLogEntry(DebugLogLevel.Warning, log)

func error*(sm: var RaftStateMachine, log: string) = 
  sm.addDebugLogEntry(DebugLogLevel.Error, log)

func info*(sm: var RaftStateMachine, log: string) = 
  sm.addDebugLogEntry(DebugLogLevel.Info, log)

func critical*(sm: var RaftStateMachine, log: string) = 
  sm.addDebugLogEntry(DebugLogLevel.Critical, log)



proc resetElectionTimeout*(sm: var RaftStateMachine) =
  # TODO actually pick random time
  sm.randomizedElectionTime = sm.electionTimeout + times.initDuration(milliseconds = 100 + rand(200))

proc initRaftStateMachine*(id: RaftnodeId, currentTerm: RaftNodeTerm, log: RaftLog, commitIndex: RaftLogIndex, config: RaftConfig, now: times.DateTime): RaftStateMachine = 
  var sm =  RaftStateMachine()
  sm.term = currentTerm
  sm.log = log
  sm.commitIndex = commitIndex
  sm.state = initFollower(RaftNodeId())
  sm.config = config
  sm.lastElectionTime = now
  sm.timeNow = now
  sm.startTime = now
  sm.myId = id
  sm.electionTimeout = times.initDuration(milliseconds = 100)
  sm.heartbeatTime = times.initDuration(milliseconds = 50)
  sm.resetElectionTimeout()
  return sm

func findFollowerProggressById(sm: var RaftStateMachine, id: RaftNodeId): Option[RaftFollowerProgressTracker] =
  return sm.leader.tracker.find(id)

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcAppendRequest) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.AppendRequest, appendRequest: request))

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcAppendReplay) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.AppendReplay, appendReplay: request))

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcVoteRequest) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.VoteRequest, voteRequest: request))

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcVoteReplay) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.VoteReplay, voteReplay: request))

func sendTo[MsgType](sm: var RaftStateMachine, id: RaftNodeId, request: MsgType) =
  sm.debug "Sent to" & $id & $request
  if sm.state.isLeader:
    var follower = sm.findFollowerProggressById(id)
    if follower.isSome:
      follower.get().lastMessageAt = sm.timeNow
    else:
      sm.warning "Follower not found: " & $id 
      sm.debug $sm.leader
  sm.sendToImpl(id, request)

func createVoteRequest*(sm: var RaftStateMachine): RaftRpcMessage = 
  return RaftRpcMessage(currentTerm: sm.term, sender: sm.myId, kind: VoteRequest, voteRequest: RaftRpcVoteRequest())

func replicateTo*(sm: var RaftStateMachine, follower: RaftFollowerProgressTracker) =
  if follower.nextIndex > sm.log.lastIndex:
    return

  var previousTerm = sm.log.termForIndex(follower.nextIndex - 1)
  sm.debug "replicate to " & $follower[]
  if previousTerm.isSome:
    let request = RaftRpcAppendRequest(
      previousTerm: previousTerm.get(),
      previousLogIndex: follower.nextIndex - 1,
      commitIndex: sm.commitIndex,
      entries: @[sm.log.getEntryByIndex(follower.nextIndex)])
    follower.nextIndex += 1
    sm.sendTo(follower.id, request)
  else: 
    # TODO: we add support for snapshots
    let request = RaftRpcAppendRequest(
      previousTerm: 0,
      previousLogIndex: 1,
      commitIndex: sm.commitIndex,
      entries: @[sm.log.getEntryByIndex(follower.nextIndex)])
    follower.nextIndex += 1
    sm.sendTo(follower.id, request)

func replicate*(sm: var RaftStateMachine) =
  if sm.state.isLeader:
    for followerIndex in 0..<sm.leader.tracker.progress.len:
      if sm.myId != sm.leader.tracker.progress[followerIndex].id:
        sm.replicateTo(sm.leader.tracker.progress[followerIndex])
 
func addEntry(sm: var RaftStateMachine, entry: LogEntry) =
  if not sm.state.isLeader:
    sm.error "only the leader can handle new entries"
  sm.log.appendAsLeader(entry)

func addEntry*(sm: var RaftStateMachine, command: Command) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletCommand, command: command))

func addEntry*(sm: var RaftStateMachine, config: Config) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletConfig, config: config))

func addEntry*(sm: var RaftStateMachine, dummy: Empty) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletEmpty, empty: true))

func becomeFollower*(sm: var RaftStateMachine, leaderId: RaftNodeId) =
  if sm.myId == leaderId:
    sm.error "Can't be follower of itself"
  sm.output.stateChange = not sm.state.isFollower
  sm.state = initFollower(leaderId)
  if leaderId != RaftnodeId():
    sm.pingLeader = false
    # TODO: Update last election time

func becomeLeader*(sm: var RaftStateMachine) =
  if sm.state.isLeader:
    sm.error "The leader can't become leader second time"
    return

  sm.output.stateChange = true
  
  # Because we will add new entry on the next line
  sm.state = initLeader(sm.config, sm.log.lastIndex + 1, sm.timeNow)
  sm.addEntry(Empty())
  sm.pingLeader = false
  #TODO: Update last election time  
  return

func becomeCandidate*(sm: var RaftStateMachine) =
  #TODO: implement
  if not sm.state.isCandidate:
    sm.output.stateChange = true

  sm.state = initCandidate(sm.config)
  sm.lastElectionTime = sm.timeNow
  # TODO: Add configuration change logic

  sm.term += 1
  for nodeId in sm.candidate.votes.voters:
    if nodeId == sm.myId:
      sm.debug "register vote for it self "
      discard sm.candidate.votes.registerVote(nodeId, true)
      sm.votedFor = nodeId
      continue

    let request = RaftRpcVoteRequest(currentTerm: sm.term, lastLogIndex: sm.log.lastIndex, lastLogTerm: sm.log.lastTerm, force: false)
    sm.sendTo(nodeId, request)
  sm.debug "Elecation won" & $(sm.candidate.votes) & $sm.myId
  if sm.candidate.votes.tallyVote == RaftElectionResult.Won:
      sm.becomeLeader()
  
  return

func heartbeat(sm: var RaftStateMachine, follower: var RaftFollowerProgressTracker) =
  sm.info "heartbeat " & $follower.nextIndex
  # TODO: we should just send empty array instead adding new empty entries on each heartbeat
  sm.addEntry(Empty())

func tickLeader*(sm: var RaftStateMachine, now: times.DateTime) =
  sm.timeNow = now

  # if sm.lastElectionTime - sm.timeNow > sm.electionTimeout:
  #   sm.becomeFollower(RaftnodeId())
  #   return 

  sm.lastElectionTime = now
  if not sm.state.isLeader:
    sm.error "tickLeader can be called only on the leader"
    return
  for followerIndex in 0..<sm.leader.tracker.progress.len:
    var follower = sm.leader.tracker.progress[followerIndex]
    if sm.myId != follower.id:
      if follower.matchIndex < sm.log.lastIndex or follower.commitIndex < sm.commitIndex:
        sm.replicateTo(follower)
        #sm.debug "replicate to" & $follower

      #sm.debug $(now - follower.lastMessageAt)
      if now - follower.lastMessageAt > sm.heartbeatTime:
        sm.heartbeat(follower)
    # TODO: implement step down logic

func tick*(sm: var RaftStateMachine, now: times.DateTime) =
    sm.info "Term: " & $sm.term & " commit idx " & $sm.commitIndex & " Time since last update: " & $(now - sm.timeNow).inMilliseconds & "ms time until election:" & $(sm.randomizedElectionTime - (sm.timeNow - sm.lastElectionTime)).inMilliseconds & "ms"
    sm.timeNow = now
    if sm.state.isLeader:
      sm.tickLeader(now);
    elif sm.state.isFollower and sm.timeNow - sm.lastElectionTime > sm.randomizedElectionTime:
      sm.debug "Become candidate"
      sm.becomeCandidate()
    
func poll*(sm: var RaftStateMachine):  RaftStateMachineOutput =
  # Should initiate replication if we have new entries
  if sm.state.isLeader:
    sm.replicate()
  sm.output.term = sm.term
  if sm.votedFor != RaftnodeId():
    sm.output.votedFor = some(sm.votedFor)

  let output = sm.output
  sm.output = RaftStateMachineOutput()
  return output

func commit*(sm: var RaftStateMachine) =
  if not sm.state.isLeader:
    return
  var newIndex = sm.commitIndex
  var nextIndex = sm.commitIndex + 1
  while nextIndex < sm.log.lastIndex:
    var replicationCnt = 0
    for p in sm.leader.tracker.progress:
      if p.matchIndex > newIndex:
         replicationCnt += 1
    if replicationCnt >= (sm.leader.tracker.progress.len div 2  + 1):
      sm.output.committed.add(sm.log.getEntryByIndex(nextIndex))
      sm.commitIndex += nextIndex;
      nextIndex += 1
    else:
      break 

func appendEntryReplay*(sm: var RaftStateMachine, fromId: RaftNodeId, replay: RaftRpcAppendReplay) =
  if not sm.state.isLeader:
    sm.debug "You can't append append replay to the follower"
    return
  var follower = sm.findFollowerProggressById(fromId)
  if not follower.isSome:
    sm.debug "Can't find the follower"
    return
  follower.get().commitIndex = max(follower.get().commitIndex, replay.commitIndex)
  case replay.result:
    of RaftRpcCode.Accepted:
      let lastIndex = replay.accepted.lastNewIndex
      sm.debug "Accpeted" & $fromId & " " & $lastIndex
      follower.get().accepted(lastIndex)
      # TODO: add leader stepping down logic here
      sm.commit()
      if not sm.state.isLeader:
        return
    of RaftRpcCode.Rejected:
      if replay.rejected.nonMatchingIndex == 0 and replay.rejected.lastIdx == 0:
        sm.replicateTo(follower.get())
        follower.get().nextIndex = min(replay.rejected.nonMatchingIndex, replay.rejected.lastIdx + 1)
  # if commit apply configuration that removes current follower 
  # we should take it again
  var follower2 = sm.findFollowerProggressById(fromId)
  if follower2.isSome:
    sm.replicateTo(follower2.get())

func advanceCommitIdx(sm: var RaftStateMachine, leaderIdx: RaftLogIndex) =
  let newIdx = min(leaderIdx, sm.log.lastIndex)
  if newIdx > sm.commitIndex:
    sm.commitIndex = newIdx
    # TODO: signal the output for the update

func appendEntry*(sm: var RaftStateMachine, fromId: RaftNodeId, request: RaftRpcAppendRequest) =
  if not sm.state.isFollower:
    sm.debug "You can't append append request to the non follower"
    return
  let (match, term) = sm.log.matchTerm(request.previousLogIndex, request.previousTerm)
  if not match:
    let rejected = RaftRpcAppendReplayRejected(nonMatchingIndex: request.previousLogIndex, lastIdx: sm.log.lastIndex)
    let responce = RaftRpcAppendReplay(term: sm.term, commitIndex: sm.commitIndex, result: RaftRpcCode.Rejected, rejected: rejected)
    sm.sendTo(fromId, responce)
    sm.debug "Reject to apply the entry"
  for entry in request.entries:
    sm.log.appendAsFollower(entry)
  sm.advanceCommitIdx(request.commitIndex)
  let accepted = RaftRpcAppendReplayAccepted(lastNewIndex: sm.log.lastIndex)
  let responce = RaftRpcAppendReplay(term: sm.term, commitIndex: sm.commitIndex, result: RaftRpcCode.Accepted, accepted: accepted)
  sm.sendTo(fromId, responce)  

func requestVote*(sm: var RaftStateMachine, fromId: RaftNodeId, request: RaftRpcVoteRequest) =
  let canVote = sm.votedFor == fromId or (sm.votedFor == RaftNodeId() and sm.currentLeader == RaftNodeId())
  if canVote and sm.log.isUpToDate(request.lastLogIndex, request.lastLogTerm):
    let responce = RaftRpcVoteReplay(currentTerm: sm.term, voteGranted: true)
    sm.sendTo(fromId, responce)
  else:
    let responce: RaftRpcVoteReplay = RaftRpcVoteReplay(currentTerm: sm.term, voteGranted: false)
    sm.sendTo(fromId, responce)

func requestVoteReply*(sm: var RaftStateMachine, fromId: RaftNodeId, request: RaftRpcVoteReplay) = 
  if not sm.state.isCandidate:
    sm.debug "Non candidate can't handle votes"
    return
  discard sm.candidate.votes.registerVote(fromId, request.voteGranted)

  case sm.candidate.votes.tallyVote:
    of RaftElectionResult.Unknown:
      return
    of RaftElectionResult.Won:
      sm.debug "Win election"
      sm.becomeLeader()
    of RaftElectionResult.Lost:
      sm.debug "Lost election"
      sm.becomeFollower(RaftNodeId())

func advance*(sm: var RaftStateMachine, msg: RaftRpcMessage, now: times.DateTime) =
  #sm.debug $msg
  if msg.currentTerm > sm.term:
    sm.debug "Current node is behind"
    var leaderId = RaftnodeId()
    if msg.kind == RaftRpcMessageType.AppendRequest:
      leaderId = msg.sender
    sm.becomeFollower(leaderId)
    # TODO: implement pre vote
    sm.term = msg.currentTerm
    sm.votedFor = RaftnodeId()
  elif msg.currentTerm < sm.term:
    if msg.kind == RaftRpcMessageType.AppendRequest:
      # Instruct leader to step down
      let rejected = RaftRpcAppendReplayRejected(nonMatchingIndex: 0, lastIdx: sm.log.lastIndex)
      let responce = RaftRpcAppendReplay(term: sm.term, commitIndex: sm.commitIndex, result: RaftRpcCode.Rejected, rejected: rejected)
      sm.sendTo(msg.sender, responce)

    sm.warning "Ignore message with lower term"
  else:
    # TODO: add also snapshot 
    if msg.kind == RaftRpcMessageType.AppendRequest:
      if sm.state.isCandidate:
          sm.becomeFollower(msg.sender)
      elif sm.state.isFollower:
          sm.follower.leader = msg.sender
    # TODO: fix time   
  if sm.state.isCandidate:
    if msg.kind == RaftRpcMessageType.VoteRequest:
      sm.requestVote(msg.sender, msg.voteRequest)
    elif msg.kind == RaftRpcMessageType.VoteReplay:
      sm.debug "Apply vote"
      sm.requestVoteReply(msg.sender, msg.voteReplay)
    else:
      sm.warning "Candidate ignore message"
  elif sm.state.isFollower:
    if msg.sender == sm.follower.leader:
      sm.lastElectionTime = now
    if msg.kind == RaftRpcMessageType.AppendRequest:
      sm.appendEntry(msg.sender, msg.appendRequest)
    elif msg.kind == RaftRpcMessageType.VoteRequest:
      sm.requestVote(msg.sender, msg.voteRequest)
    else:
      sm.warning "Follower ignore message" & $msg
    # TODO: imelement the rest of the state transitions
  elif sm.state.isLeader:
    if msg.kind == RaftRpcMessageType.AppendRequest:
      sm.warning "Ignore message leader append his entries directly"
    elif msg.kind == RaftRpcMessageType.AppendReplay:
      sm.appendEntryReplay(msg.sender, msg.appendReplay)
    elif msg.kind == RaftRpcMessageType.VoteRequest:
      sm.requestVote(msg.sender, msg.voteRequest)
    else:
      sm.warning "Leader ignore message"
