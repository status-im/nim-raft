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
    previousTerm: RaftNodeTerm
    previousLogIndex: RaftLogIndex
    commitIndex: RaftLogIndex
    entry: LogEntry
    
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
    currentTerm: RaftNodeTerm
    lastLogIndex: RaftLogIndex
    lastLogTerm: RaftNodeTerm
    isPrevote: bool
    force: bool
    
  RaftRpcVoteReplay* = object
    currentTerm: RaftNodeTerm
    voteGranted: bool
    isPrevote: bool

  LeaderState* = object
    followersProgress: seq[RaftFollowerProgressTracker]

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
    currentTerm: RaftNodeTerm
    sender: RaftNodeId
    receiver: RaftNodeId
    case kind: RaftRpcMessageType
    of Vote: voteRequest: RaftRpcVoteRequest
    of VoteReplay: voteReplay: RaftRpcVoteReplay
    of Append: appendRequest: RaftRpcAppendRequest
    of AppendReplay: appendReplay: RaftRpcAppendReplay 

  Command* = object
    data: seq[byte]
  Config* = object

  LogEntry* = object         # Abstarct Raft Node Log entry containing opaque binary data (Blob etc.)
    term: RaftNodeTerm
    index: RaftLogIndex
    # TODO: Add configuration too
    case kind: RaftLogEntryType:
    of rletCommand: command: Command
    of rletConfig: config: Config
    of rletEmpty: empty: bool

  RaftLog* = object
    logEntries: seq[LogEntry]
  
  RaftStateMachineOutput* = object
    logEntries: seq[LogEntry]
    # Entries that should be applyed to the "User" State machine
    committed: seq[LogEntry]
    messages: seq[RaftRpcMessage]
    debugLogs: seq[string]
    stateChange: bool

  RaftConfig* = object
    currentSet*: seq[RaftNodeId]


  RaftStateMachine* = object
    myId*: RaftNodeId
    term: RaftNodeTerm
    commitIndex: RaftLogIndex
    toCommit: RaftLogIndex
    log: RaftLog
    output: RaftStateMachineOutput
    lastUpdate: Time
    votedFor: RaftNodeId
    currentLeader: RaftNodeId
    pingLeader: bool
    config: RaftConfig

    lastElectionTime: times.Duration
    randomizedElectionTime: times.Duration
    timeNow: times.Duration
    electionTimeout: times.Duration

    case state: RaftNodeState
    of rnsFollower: follower : FollowerState
    of rnsCandidate: candidate: CandidateState
    of rnsLeader: leader: LeaderState


  RaftFollowerProgressTracker* = object
    id: RaftNodeId
    nextIndex: RaftLogIndex
    # Index of the highest log entry known to be replicated to this server.
    matchIndex: RaftLogIndex
    commitIndex: RaftLogIndex
    replayedIndex: RaftLogIndex


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
    ret.granted += 1
  
  return true

func tallyVote*(ret: var RaftElectionTracker): RaftElectionResult =
  let quorym = int(len(ret.all) / 2) + 1
  if ret.granted > quorym:
    return RaftElectionResult.Won
  let unkown = len(ret.all) - len(ret.responded)
  if  ret.granted + unkown > quorym:
    return RaftElectionResult.Unknown
  else:
    return RaftElectionResult.Lost

func initVotes*(nodes: seq[RaftNodeId]): RaftVotes =
  var r = RaftVotes(voters: nodes, current: initElectionTracker(nodes))
  return r

func registerVote*(rv: var RaftVotes, nodeId: RaftNodeId, granted: bool): bool =
  # TODO: Add support for configuration
  return rv.current.registerVote(nodeId, granted)

func tallyVote*(rv: var RaftVotes): RaftElectionResult =
  # TODO: Add support for configuration
  return rv.current.tallyVote()


func initFollowerProgressTracker*(follower: RaftNodeId, nextIndex: RaftLogIndex): RaftFollowerProgressTracker =
  return RaftFollowerProgressTracker(id: follower, nextIndex: nextIndex, matchIndex: 0, commitIndex: 0, replayedIndex: 0)

func accepted*(fpt: var RaftFollowerProgressTracker, index: RaftLogIndex)=
  fpt.matchIndex = max(fpt.matchIndex, index)
  fpt.nextIndex = max(fpt.nextIndex, index)

func initRaftLog*(): RaftLog =
  return RaftLog()

func lastTerm*(rf: RaftLog): RaftNodeTerm =
  # Not sure if it's ok, maybe we should return optional value
  if len(rf.logEntries) == 0:
    return 0
  let idx = len(rf.logEntries) 
  return rf.logEntries[idx - 1].term

func entriesCount*(rf: RaftLog): int =
  return len(rf.logEntries)

func lastIndex*(rf: RaftLog): RaftNodeTerm =
  # Not sure if it's ok, maybe we should return optional value
  if len(rf.logEntries) == 0:
    return 0
  let idx = len(rf.logEntries) 
  return rf.logEntries[idx - 1].index

func nextIndex*(rf: RaftLog): int =
  return rf.lastIndex + 1

func truncateUncomitted*(rf: var RaftLog, index: RaftLogIndex) =
  # TODO: We should add support for configurations and snapshots
  rf.logEntries.delete(index..<len(rf.logEntries))

func isUpToDate(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): bool = 
  return term > rf.lastTerm or (term == rf.lastTerm and index >= rf.lastIndex)


func getEntryByIndex(rf: RaftLog, index: RaftLogIndex): LogEntry = 
  return rf.logEntries[index]

func appendAsLeader(rf: var RaftLog, entry: LogEntry) = 
  rf.logEntries.add(entry)

func appendAsFollower*(rf: var RaftLog, entry: LogEntry) = 
  let currentIdx = rf.lastIndex()
  if entry.index <= currentIdx:
    # TODO: The indexing hold only if we keep all entries in memory
    # we should change it when we add support for snapshots
    if len(rf.logEntries) > 0 and entry.term != rf.logEntries[entry.index].term:
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

  if rf.logEntries[index].term == term:
    return (true, 0)
  else:
    return (false, rf.logEntries[index].term)

func termForIndex*(rf: RaftLog, index: RaftLogIndex): RaftNodeTerm =
  # TODO: We should add support for snapshots
  return rf.logEntries[index].term

func debug*(sm: var RaftStateMachine, log: string) = 
  sm.output.debugLogs.add(log)

func resetElectionTimeout*(sm: var RaftStateMachine) =
  # TODO actually pick random time
  sm.randomizedElectionTime = sm.electionTimeout + times.initDuration(milliseconds = 42)

func initRaftStateMachine*(id: RaftnodeId, currentTerm: RaftNodeTerm, log: RaftLog, commitIndex: RaftLogIndex, config: RaftConfig): RaftStateMachine = 
  var sm =  RaftStateMachine()
  sm.term = currentTerm
  sm.log = log
  sm.commitIndex = commitIndex
  sm.state = RaftNodeState.rnsFollower
  sm.config = config

  sm.resetElectionTimeout()
  return sm

func sendTo*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcAppendRequest) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.Append, appendRequest: request))

func sendTo*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcAppendReplay) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.AppendReplay, appendReplay: request))

func sendTo*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcVoteRequest) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.Vote, voteRequest: request))

func sendTo*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcVoteReplay) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: RaftRpcMessageType.VoteReplay, voteReplay: request))

func createVoteRequest*(sm: var RaftStateMachine): RaftRpcMessage = 
  return RaftRpcMessage(currentTerm: sm.term, sender: sm.myId, kind: Vote, voteRequest: RaftRpcVoteRequest())

func replicateTo*(sm: var RaftStateMachine, follower: var RaftFollowerProgressTracker) =
  if follower.nextIndex > sm.log.lastIndex():
    return
    
  let request = RaftRpcAppendRequest(
    previousTerm: follower.nextIndex - 1,
    previousLogIndex: sm.log.termForIndex(follower.nextIndex - 1),
    commitIndex: sm.commitIndex,
    entry: sm.log.getEntryByIndex(follower.nextIndex))
  follower.nextIndex += 1

  sm.sendTo(follower.id, request)

func replicate*(sm: var RaftStateMachine) =
  if sm.state == RaftNodeState.rnsLeader:
    for followerIndex in 0..sm.leader.followersProgress.len:
      if sm.myId != sm.leader.followersProgress[followerIndex].id:
        sm.replicateTo(sm.leader.followersProgress[followerIndex])
 

func advance*(sm: var RaftStateMachine, msg: RaftRpcMessage,currentTime: Time) =
  if sm.term > msg.currentTerm:
    sm.debug "Current node is behind"
  elif sm.term < msg.currentTerm: 
    sm.debug "The leader is behind"
  else:
    case sm.state:
      of rnsCandidate:
        sm.state = rnsFollower
        sm.follower.leader = msg.sender
      of rnsFollower:
        sm.follower.leader = msg.sender
      of rnsLeader:
        sm.debug "For now it should be impossible to have msg from a non leader to a leader"

  case msg.kind:
    of RaftRpcMessageType.Vote:
      sm.debug "Handle vote request"
    else:
      sm.debug "Unhandle msg type"


func addEntry*(sm: var RaftStateMachine, entry: LogEntry) =
  if sm.state != RaftNodeState.rnsLeader:
    sm.debug "Error: only the leader can handle new entries"
  sm.log.appendAsLeader(entry)

func addEntry*(sm: var RaftStateMachine, command: Command) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletCommand, command: command))

func addEntry*(sm: var RaftStateMachine, config: Config) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletConfig, config: config))

func addEmptyEntry*(sm: var RaftStateMachine) =
  sm.addEntry(LogEntry(term: sm.term, index: sm.log.nextIndex, kind: rletEmpty, empty: true))

func becomeFollower*(sm: var RaftStateMachine, leaderId: RaftNodeId) =
  if sm.myId == leaderId:
    sm.debug "Can't be follower of itself"
  sm.output.stateChange = sm.state != RaftNodeState.rnsFollower
  sm.state = RaftNodeState.rnsFollower
  sm.follower = FollowerState(leader: leaderId)
  if leaderId != RaftnodeId():
    sm.pingLeader = false
    # TODO: Update last election time

func becomeLeader*(sm: var RaftStateMachine) =
  if sm.state == RaftNodeState.rnsLeader:
    sm.debug "The leader can't become leader second time"
    return

  sm.output.stateChange = true
  sm.state = RaftnodeState.rnsLeader
  sm.leader = LeaderState()

  sm.pingLeader = false
  #TODO: Update last election time

  #TODO: setup the tracket 
  
  sm.addEmptyEntry()
  return
func becomeCandidate*(sm: var RaftStateMachine, isPrevote: bool) =
  #TODO: implement
  return

func tickLeader*(sm: var RaftStateMachine, now: times.Duration) =
  sm.timeNow = now
  if sm.lastElectionTime - sm.timeNow > sm.electionTimeout:
    sm.becomeFollower(RaftnodeId())
    return 
  if sm.state != RaftNodeState.rnsLeader:
    sm.debug "tick_leader can be called only on the leader"
    return
  for followerIndex in 0..sm.leader.followersProgress.len:
    var follower = sm.leader.followersProgress[followerIndex]
    if sm.myId != follower.id:
      if follower.matchIndex < sm.log.lastIndex or follower.commitIndex < sm.commitIndex:
        sm.replicateTo(follower)
    # TODO: implement step down logic

func tick*(sm: var RaftStateMachine, now: times.Duration) =
    sm.timeNow = now
    if sm.state != RaftNodeState.rnsLeader:
      sm.tickLeader(now);
    elif sm.lastElectionTime - sm.timeNow > sm.randomizedElectionTime:
      sm.becomeCandidate(false)
    

func poll*(sm: var RaftStateMachine):  RaftStateMachineOutput =
  # Should initiate replication if we have new entries
  if sm.state == RaftNodeState.rnsLeader:
    sm.replicate()
  let output = sm.output
  sm.output = RaftStateMachineOutput()
  return output


func commit*(sm: var RaftStateMachine) =
  if sm.state != RaftNodeState.rnsLeader:
    return
  var new_index = sm.commitIndex
  var next_index = sm.commitIndex + 1
  while next_index < sm.log.lastIndex:
    var replicationCnt = 0
    for p in sm.leader.followersProgress:
      if p.matchIndex > new_index:
         replicationCnt += 1
    if replicationCnt > len(sm.leader.followersProgress):
      sm.output.committed.add(sm.log.getEntryByIndex(next_index))
      sm.commitIndex += next_index;
      next_index += 1

func findFollowerProggressById(sm: var RaftStateMachine, id: RaftNodeId): Option[RaftFollowerProgressTracker] =
    for follower in sm.leader.followersProgress:
      if follower.id == id:
        return some(follower)
      return none(RaftFollowerProgressTracker)
    

func appendEntryReply*(sm: var RaftStateMachine, from_id: RaftNodeId, replay: RaftRpcAppendReplay) =
  if sm.state != RaftNodeState.rnsLeader:
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
      if sm.state != RaftNodeState.rnsLeader:
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
  if sm.state != RaftNodeState.rnsFollower:
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
  sm.log.appendAsFollower(request.entry)
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
    sm.sendTo(sm.myId, responce)
  else:
    let responce = RaftRpcVoteReplay(currentTerm: sm.term, voteGranted: false, isPrevote: request.is_prevote)
    sm.sendTo(sm.myId, responce)


func requestVoteReply*(sm: var RaftStateMachine, from_id: RaftNodeId, request: RaftRpcVoteReplay) = 
  if sm.state != RaftNodeState.rnsCandidate:
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
