# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import types
import std/[times]
import std/sequtils
import std/random

randomize()

type
  RaftRpcMessageType* = enum
    Vote = 0,
    VoteReplay = 1,
    Append = 2,
    AppendReplay = 3
  
  RaftRpcCode* = enum
    Rejected = 0,
    Accepted = 1

  RaftElectionResult* = enum
    Unknown = 0,
    Won = 1,
    Lost = 2

  RaftLogEntryType* = enum
    rletCommand = 0,
    rletConfig = 1,
    rletEmpty = 2


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
    isPrevote*: bool
    force*: bool
    
  RaftRpcVoteReplay* = object
    currentTerm*: RaftNodeTerm
    voteGranted*: bool
    isPrevote*: bool

  LeaderState* = object
    tracker: RaftTracker

  RaftElectionTracker* = object
    all: seq[RaftNodeId]
    responded: seq[RaftNodeId]
    granted: int

  RaftVotes* = object
    voters: seq[RaftNodeId]
    current: RaftElectionTracker

  CandidateState* = object
    votes: RaftVotes
    isPrevote: bool

  FollowerState* = object
    leader: RaftNodeId

  RaftRpcMessage* = object
    currentTerm*: RaftNodeTerm
    sender*: RaftNodeId
    receiver*: RaftNodeId
    case kind*: RaftRpcMessageType
    of Vote: voteRequest*: RaftRpcVoteRequest
    of VoteReplay: voteReplay*: RaftRpcVoteReplay
    of Append: appendRequest*: RaftRpcAppendRequest
    of AppendReplay: appendReplay*: RaftRpcAppendReplay 

  Command* = object
    data: seq[byte]
  Config* = object
  Empty* = object

  LogEntry* = object         # Abstarct Raft Node Log entry containing opaque binary data (Blob etc.)
    term*: RaftNodeTerm
    index*: RaftLogIndex
    # TODO: Add configuration too
    case kind*: RaftLogEntryType:
    of rletCommand: command*: Command
    of rletConfig: config*: Config
    of rletEmpty: empty*: bool

  RaftLog* = object
    logEntries: seq[LogEntry]
    firstIndex: RaftLogIndex
  
  RaftStateMachineOutput* = object
    logEntries*: seq[LogEntry]
    # Entries that should be applyed to the "User" State machine
    committed*: seq[LogEntry]
    messages*: seq[RaftRpcMessage]
    debugLogs*: seq[string]
    term*: RaftNodeTerm
    votedFor*: Option[RaftNodeId]
    stateChange*: bool

  RaftConfig* = object
    currentSet*: seq[RaftNodeId]

  RaftStateMachineState* = object
    case state: RaftNodeState
    of rnsFollower: follower : FollowerState
    of rnsCandidate: candidate: CandidateState
    of rnsLeader: leader: LeaderState

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

  RaftFollowerProgress = seq[RaftFollowerProgressTracker]

  RaftTracker* = object
    progress: RaftFollowerProgress
    current: seq[RaftNodeId]
  
  RaftFollowerProgressTracker* = object
    id: RaftNodeId
    nextIndex: RaftLogIndex
    # Index of the highest log entry known to be replicated to this server.
    matchIndex: RaftLogIndex
    commitIndex: RaftLogIndex
    replayedIndex: RaftLogIndex
    lastMessageAt: times.DateTime

func isLeader*(s: RaftStateMachineState): bool =
  return s.state == RaftNodeState.rnsLeader

func isFollower*(s: RaftStateMachineState): bool =
  return s.state == RaftNodeState.rnsFollower

func isCandidate*(s: RaftStateMachineState): bool =
  return s.state == RaftNodeState.rnsCandidate

func leader*(s: var RaftStateMachineState): var LeaderState =
  return s.leader

func follower*(s: var RaftStateMachineState): var FollowerState =
  return s.follower

func candidate*(s: var RaftStateMachineState): var CandidateState =
  return s.candidate

func find(ls: RaftTracker, id: RaftnodeId): RaftFollowerProgressTracker =
  for follower in ls.progress:
    if follower.id == id:
      return follower


func initFollowerProgressTracker*(follower: RaftNodeId, nextIndex: RaftLogIndex, now: times.DateTime): RaftFollowerProgressTracker =
  return RaftFollowerProgressTracker(id: follower, nextIndex: nextIndex, matchIndex: 0, commitIndex: 0, replayedIndex: 0, lastMessageAt: now)

func accepted*(fpt: var RaftFollowerProgressTracker, index: RaftLogIndex)=
  fpt.matchIndex = max(fpt.matchIndex, index)
  fpt.nextIndex = max(fpt.nextIndex, index)

func initTracker(config: RaftConfig, nextIndex: RaftLogIndex, now: times.DateTime): RaftTracker =
  var tracker = RaftTracker()
  
  for node in config.currentSet:
    tracker.progress.add(initFollowerProgressTracker(node, nextIndex, now))
    tracker.current.add(node)
  return tracker


func leader*(sm: var RaftStateMachine): var LeaderState =
  return sm.state.leader

func follower*(sm: var RaftStateMachine): var FollowerState =
  return sm.state.follower

func candidate*(sm: var RaftStateMachine): var CandidateState =
  return sm.state.candidate


func contains(a: seq[RaftNodeId], id: RaftNodeId): bool =
  var found = false
  for n in a:
    if n == id:
      found = true
      break
  return found

func initElectionTracker*(nodes: seq[RaftNodeId]): RaftElectionTracker =
  var r = RaftElectionTracker()
  r.all = nodes
  r.granted = 0
  return r

func registerVote*(ret: var RaftElectionTracker, nodeId: RaftNodeId, granted: bool): bool =
  if not ret.all.contains nodeId:
    return false

  if not ret.responded.contains nodeId:
    ret.responded.add(nodeId)
    if granted:
      ret.granted += 1
  
  return true

func tallyVote*(ret: var RaftElectionTracker): RaftElectionResult =
  let quorym = int(len(ret.all) / 2) + 1
  if ret.granted >= quorym:
    return RaftElectionResult.Won
  let unkown = len(ret.all) - len(ret.responded)
  if  ret.granted + unkown >= quorym:
    return RaftElectionResult.Unknown
  else:
    return RaftElectionResult.Lost

func initVotes*(nodes: seq[RaftNodeId]): RaftVotes =
  var r = RaftVotes(voters: nodes, current: initElectionTracker(nodes))
  return r

func initVotes*(config: RaftConfig): RaftVotes =
  var r = RaftVotes(voters: config.currentSet, current: initElectionTracker(config.currentSet))
  return r

func registerVote*(rv: var RaftVotes, nodeId: RaftNodeId, granted: bool): bool =
  # TODO: Add support for configuration
  return rv.current.registerVote(nodeId, granted)

func tallyVote*(rv: var RaftVotes): RaftElectionResult =
  # TODO: Add support for configuration
  return rv.current.tallyVote()

func initRaftLog*(firstIndex: RaftLogIndex): RaftLog =
  var log = RaftLog()
  assert firstIndex > 0
  log.firstIndex = firstIndex
  return log

func lastTerm*(rf: RaftLog): RaftNodeTerm =
  # Not sure if it's ok, maybe we should return optional value
  let size = rf.logEntries.len
  if size == 0:
    return 0
  return rf.logEntries[size - 1].term

func entriesCount*(rf: RaftLog): int =
  return rf.logEntries.len

func lastIndex*(rf: RaftLog): RaftNodeTerm =
  return rf.logEntries.len + rf.firstIndex - 1

func nextIndex*(rf: RaftLog): int =
  return rf.lastIndex + 1

func truncateUncomitted*(rf: var RaftLog, index: RaftLogIndex) =
  # TODO: We should add support for configurations and snapshots
  if rf.logEntries.len == 0:
    return
  rf.logEntries.delete((index - rf.firstIndex)..<len(rf.logEntries))

func isUpToDate(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): bool = 
  return term > rf.lastTerm or (term == rf.lastTerm and index >= rf.lastIndex)

func getEntryByIndex(rf: RaftLog, index: RaftLogIndex): LogEntry = 
  return rf.logEntries[index - rf.firstIndex]

func appendAsLeader(rf: var RaftLog, entry: LogEntry) = 
  rf.logEntries.add(entry)

func appendAsFollower*(rf: var RaftLog, entry: LogEntry) = 
  assert entry.index > 0
  let currentIdx = rf.lastIndex
  if entry.index <= currentIdx:
    # TODO: The indexing hold only if we keep all entries in memory
    # we should change it when we add support for snapshots
    
    if entry.index >= rf.firstIndex or entry.term != rf.getEntryByIndex(entry.index).term:
      rf.truncateUncomitted(entry.index)
  rf.logEntries.add(entry)

func appendAsLeader*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command) = 
  rf.appendAsLeader(LogEntry(term: term, index: index, kind: rletCommand,  command: data))

func appendAsLeader*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, empty: bool) = 
  rf.appendAsLeader(LogEntry(term: term, index: index, kind: rletEmpty, empty: true))

func appendAsFollower*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command) = 
  rf.appendAsFollower(LogEntry(term: term, index: index, kind: rletCommand,  command: data))


func matchTerm*(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): (bool, RaftNodeTerm) = 
  if len(rf.logEntries) == 0:
    return (true, 0)
  # TODO: We should add support for snapshots
  if index > len(rf.logEntries):
    # The follower doesn't have all etries
    return (false, 0)

  let i = index - rf.firstIndex
  if rf.logEntries[i].term == term:
    return (true, 0)
  else:
    return (false, rf.logEntries[i].term)

func termForIndex*(rf: RaftLog, index: RaftLogIndex): Option[RaftNodeTerm] =
  # TODO: snapshot support
  if rf.logEntries.len > 0 and index >= rf.firstIndex:
    return some(rf.logEntries[index].term)
  return none(RaftNodeTerm)

func debug*(sm: var RaftStateMachine, log: string) = 
  sm.output.debugLogs.add("[" & $(sm.timeNow - sm.startTime).inMilliseconds & "ms] [" & (($sm.myId)[0..7]) & "...] [" & $sm.state.state & "]: " & log)

proc resetElectionTimeout*(sm: var RaftStateMachine) =
  # TODO actually pick random time
  sm.randomizedElectionTime = sm.electionTimeout + times.initDuration(milliseconds = 100 + rand(200))

proc initRaftStateMachine*(id: RaftnodeId, currentTerm: RaftNodeTerm, log: RaftLog, commitIndex: RaftLogIndex, config: RaftConfig, now: times.DateTime): RaftStateMachine = 
  var sm =  RaftStateMachine()
  sm.term = currentTerm
  sm.log = log
  sm.commitIndex = commitIndex
  sm.state = RaftStateMachineState(state: RaftnodeState.rnsFollower)
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
    for follower in sm.leader.tracker.progress:
      if follower.id == id:
        return some(follower)
      return none(RaftFollowerProgressTracker)

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcAppendRequest) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.Append, appendRequest: request))

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcAppendReplay) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.AppendReplay, appendReplay: request))

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcVoteRequest) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.Vote, voteRequest: request))

func sendToImpl*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcVoteReplay) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.VoteReplay, voteReplay: request))

func sendTo[MsgType](sm: var RaftStateMachine, id: RaftNodeId, request: MsgType) =
  if sm.state.isLeader:
    var follower = sm.findFollowerProggressById(id)
    if follower.isSome:
      follower.get().lastMessageAt = sm.timeNow
    else:
      sm.debug "Follower not found"
  sm.sendToImpl(id, request)

func createVoteRequest*(sm: var RaftStateMachine): RaftRpcMessage = 
  return RaftRpcMessage(currentTerm: sm.term, sender: sm.myId, kind: Vote, voteRequest: RaftRpcVoteRequest())

func replicateTo*(sm: var RaftStateMachine, follower: var RaftFollowerProgressTracker) =
  if follower.nextIndex > sm.log.lastIndex:
    return

  var previousTerm = sm.log.termForIndex(follower.nextIndex - 1)
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
    sm.debug "Error: only the leader can handle new entries"
  sm.log.appendAsLeader(entry)

func addEntry*(sm: var RaftStateMachine, command: Command) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletCommand, command: command))

func addEntry*(sm: var RaftStateMachine, config: Config) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletConfig, config: config))

func addEntry*(sm: var RaftStateMachine, dummy: Empty) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletEmpty, empty: true))

func becomeFollower*(sm: var RaftStateMachine, leaderId: RaftNodeId) =
  if sm.myId == leaderId:
    sm.debug "Can't be follower of itself"
  sm.output.stateChange = not sm.state.isFollower
  sm.state = RaftStateMachineState(state: RaftNodeState.rnsFollower, follower: FollowerState(leader: leaderId))
  if leaderId != RaftnodeId():
    sm.pingLeader = false
    # TODO: Update last election time

func becomeLeader*(sm: var RaftStateMachine) =
  if sm.state.isLeader:
    sm.debug "The leader can't become leader second time"
    return

  sm.output.stateChange = true
  sm.state = RaftStateMachineState(state: RaftnodeState.rnsLeader, leader: LeaderState())
  sm.addEntry(Empty())
  sm.leader.tracker = initTracker(sm.config, sm.log.lastIndex, sm.timeNow)
  sm.pingLeader = false
  #TODO: Update last election time  
  return

func becomeCandidate*(sm: var RaftStateMachine, isPrevote: bool) =
  #TODO: implement
  if not sm.state.isCandidate:
    sm.output.stateChange = true

  sm.state = RaftStateMachineState(state: RaftnodeState.rnsCandidate, candidate: CandidateState(votes: initVotes(sm.config)))
  sm.lastElectionTime = sm.timeNow
  # TODO: Add configuration change logic

  sm.term += 1
  for nodeId in sm.candidate.votes.voters:
    if nodeId == sm.myId:
      sm.debug "reguster vote for it self "
      discard sm.candidate.votes.registerVote(nodeId, true)
      sm.votedFor = nodeId
      continue

    let request = RaftRpcVoteRequest(currentTerm: sm.term, lastLogIndex: sm.log.lastIndex, lastLogTerm: sm.log.lastTerm, isPrevote: isPrevote, force: false)
    sm.sendTo(nodeId, request)
  sm.debug "Elecation won" & $(sm.candidate.votes) & $sm.myId
  if sm.candidate.votes.tallyVote == RaftElectionResult.Won:
    
    if isPrevote:
      sm.becomeCandidate(false)
    else:
      sm.becomeLeader()
  
  return

func hearthbeat(sm: var RaftStateMachine, follower: var RaftFollowerProgressTracker) =
  sm.debug "hearthbear" & $follower.nextIndex
  var previousTerm = sm.log.termForIndex(follower.nextIndex - 1)
  if previousTerm.isSome:
    let request = RaftRpcAppendRequest(
      previousTerm: previousTerm.get(),
      previousLogIndex: follower.nextIndex - 1,
      commitIndex: sm.commitIndex,
      entries: @[])
    sm.sendTo(follower.id, request)

func tickLeader*(sm: var RaftStateMachine, now: times.DateTime) =
  sm.timeNow = now

  # if sm.lastElectionTime - sm.timeNow > sm.electionTimeout:
  #   sm.becomeFollower(RaftnodeId())
  #   return 

  sm.lastElectionTime = now
  if not sm.state.isLeader:
    sm.debug "tick_leader can be called only on the leader"
    return
  sm.debug "Tick leader"
  for followerIndex in 0..<sm.leader.tracker.progress.len:
    var follower = sm.leader.tracker.progress[followerIndex]
    if sm.myId != follower.id:
      sm.debug "Tick leader" & $follower.matchIndex & $sm.log.lastIndex & $sm.log.lastIndex 
      if follower.matchIndex < sm.log.lastIndex or follower.commitIndex < sm.commitIndex:
        sm.replicateTo(follower)
        sm.debug "replicate to" & $follower

      #sm.debug $(now - follower.lastMessageAt)
      if now - follower.lastMessageAt > sm.heartbeatTime:
        sm.debug "heartbeat"
        sm.hearthbeat(follower)
    # TODO: implement step down logic

func tick*(sm: var RaftStateMachine, now: times.DateTime) =
    sm.debug "Time since last update: " & $(now - sm.timeNow).inMilliseconds & "ms time until election:" & $(sm.randomizedElectionTime - (sm.timeNow - sm.lastElectionTime)).inMilliseconds & "ms"
    sm.timeNow = now
    if sm.state.isLeader:
      sm.tickLeader(now);
    elif sm.state.isFollower and sm.timeNow - sm.lastElectionTime > sm.randomizedElectionTime:
      sm.debug "Become candidate"
      sm.becomeCandidate(false)
    

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
  var new_index = sm.commitIndex
  var next_index = sm.commitIndex + 1
  while next_index < sm.log.lastIndex:
    var replicationCnt = 0
    for p in sm.leader.tracker.progress:
      if p.matchIndex > new_index:
         replicationCnt += 1
    if replicationCnt > sm.leader.tracker.progress.len:
      sm.output.committed.add(sm.log.getEntryByIndex(next_index))
      sm.commitIndex += next_index;
      next_index += 1

    

func appendEntryReplay*(sm: var RaftStateMachine, from_id: RaftNodeId, replay: RaftRpcAppendReplay) =
  if not sm.state.isLeader:
    sm.debug "You can't append append replay to the follower"
    return
  var follower = sm.findFollowerProggressById(from_id)
  if not follower.isSome:
    sm.debug "Can't find the follower"
    return
  follower.get().commitIndex = max(follower.get().commitIndex, replay.commitIndex)
  case replay.result:
    of RaftRpcCode.Accepted:
      let lestIndex = replay.accepted.lastNewIndex
      follower.get().accepted(lestIndex)
      # TODO: add leader stepping down logic here
      sm.commit()
      if not sm.state.isLeader:
        return
    of RaftRpcCode.Rejected:
      if replay.rejected.nonMatchingIndex == 0 and replay.rejected.lastIdx == 0:
        sm.replicateTo(follower.get())
        follower.get().next_index = min(replay.rejected.nonMatchingIndex, replay.rejected.lastIdx + 1)
  # if commit apply configuration that removes current follower 
  # we should take it again
  var follower2 = sm.findFollowerProggressById(from_id)
  if follower2.isSome:
    sm.replicateTo(follower2.get())

func advanceCommitIdx(sm: var RaftStateMachine, leaderIdx: RaftLogIndex) =
  let new_idx = min(leaderIdx, sm.log.lastIndex)
  if new_idx > sm.commitIndex:
    sm.commitIndex = new_idx
    # TODO: signal the output for the update


func appendEntry*(sm: var RaftStateMachine, from_id: RaftNodeId, request: RaftRpcAppendRequest) =
  if not sm.state.isFollower:
    sm.debug "You can't append append request to the non follower"
    return
  let (match, term) = sm.log.matchTerm(request.previousLogIndex, request.previousTerm)
  if not match:
    let rejected = RaftRpcAppendReplayRejected(nonMatchingIndex: request.previousLogIndex, lastIdx: sm.log.lastIndex)
    let responce = RaftRpcAppendReplay(term: sm.term, commitIndex: sm.commitIndex, result: RaftRpcCode.Rejected, rejected: rejected)
    sm.sendTo(sm.myId, responce)
    sm.debug "Reject to apply the entry"
    # reject to apply
    #sentTo()
  for entry in request.entries:
    sm.log.appendAsFollower(entry)
  sm.advanceCommitIdx(request.commitIndex)
  let accepted = RaftRpcAppendReplayAccepted(lastNewIndex: sm.log.lastIndex)
  let responce = RaftRpcAppendReplay(term: sm.term, commitIndex: sm.commitIndex, result: RaftRpcCode.Accepted, accepted: accepted)
  sm.sendTo(sm.myId, responce)  

func requestVote*(sm: var RaftStateMachine, from_id: RaftNodeId, request: RaftRpcVoteRequest, ) =
  let canVote = sm.votedFor == from_id or (sm.votedFor == RaftNodeId() and sm.currentLeader == RaftNodeId()) or (request.isPrevote and request.currentTerm > sm.term)
  if canVote and sm.log.isUpToDate(request.lastLogIndex, request.lastLogTerm):
    if not request.is_prevote:
      # TODO: Update election time 
      sm.votedFor = from_id

    let responce = RaftRpcVoteReplay(currentTerm: sm.term, voteGranted: true, isPrevote: request.is_prevote)
    sm.sendTo(from_id, responce)
  else:
    let responce = RaftRpcVoteReplay(currentTerm: sm.term, voteGranted: false, isPrevote: request.is_prevote)
    sm.sendTo(from_id, responce)


func requestVoteReply*(sm: var RaftStateMachine, from_id: RaftNodeId, request: RaftRpcVoteReplay) = 
  if not sm.state.isCandidate:
    sm.debug "Non candidate can't handle votes"
    return
  discard sm.candidate.votes.registerVote(from_id, request.voteGranted)

  case sm.candidate.votes.tallyVote:
    of RaftElectionResult.Unknown:
      return
    of RaftElectionResult.Won:
      sm.debug "Win election"
      if (sm.candidate.isPrevote):
        sm.becomeCandidate(false)
      else:
        sm.becomeLeader()
    of RaftElectionResult.Lost:
      sm.debug "Lost election"
      sm.becomeFollower(RaftNodeId())
      # TODO: become foller

func advance*(sm: var RaftStateMachine, msg: RaftRpcMessage, now: times.DateTime) =
  #sm.debug $msg
  if msg.currentTerm > sm.term:
    sm.debug "Current node is behind"
    var leaderId = RaftnodeId()
    if msg.kind == RaftRpcMessageType.Append:
      leaderId = msg.sender
    sm.becomeFollower(leaderId)
    # TODO: implement pre vote
    sm.term = msg.currentTerm
    sm.votedFor = RaftnodeId()
  elif msg.currentTerm < sm.term:
    if msg.kind == RaftRpcMessageType.Append:
      # Instruct leader to step down
      let rejected = RaftRpcAppendReplayRejected(nonMatchingIndex: 0, lastIdx: sm.log.lastIndex)
      let responce = RaftRpcAppendReplay(term: sm.term, commitIndex: sm.commitIndex, result: RaftRpcCode.Rejected, rejected: rejected)
      sm.sendTo(msg.sender, responce)

    sm.debug "Ignore message with lower term"
  else:
    
    # TODO: add also snapshot 
    if msg.kind == RaftRpcMessageType.Append:
      if sm.state.isCandidate:
          sm.becomeFollower(msg.sender)
      elif sm.state.isFollower:
          sm.follower.leader = msg.sender
    # TODO: fix time
    
     
  if sm.state.isCandidate:
    if msg.kind == RaftRpcMessageType.Vote:
      sm.requestVote(msg.sender, msg.voteRequest)
    elif msg.kind == RaftRpcMessageType.VoteReplay:
      sm.debug "Apply vote"
      sm.requestVoteReply(msg.sender, msg.voteReplay)
    else:
      sm.debug "Candidate ignore message"
  elif sm.state.isFollower:
    if msg.sender == sm.follower.leader:
      sm.lastElectionTime = now
    if msg.kind == RaftRpcMessageType.Append:
      sm.appendEntry(msg.sender, msg.appendRequest)
    if msg.kind == RaftRpcMessageType.Vote:
      sm.requestVote(msg.sender, msg.voteRequest)
    else:
      sm.debug "Follower ignore message"
    # TODO: imelement the rest of the state transitions
  elif sm.state.isLeader:
    if msg.kind == RaftRpcMessageType.Append:
      sm.debug "Ignore message leader append his entries directly"
    elif msg.kind == RaftRpcMessageType.AppendReplay:
      sm.appendEntryReplay(msg.sender, msg.appendReplay)
    elif msg.kind == RaftRpcMessageType.Vote:
      sm.requestVote(msg.sender, msg.voteRequest)
    else:
      sm.debug "Leader ignore message"
