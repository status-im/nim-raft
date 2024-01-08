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
    

  RaftRpcAppendRequest* = object
    previousTerm: RaftNodeTerm
    previousLogIndex: RaftLogIndex
    commitIndex: RaftLogIndex
    entry: LogEntry
    
  RaftRpcAppendReplay* = object

  RaftRpcVoteRequest* = object
  
  RaftRpcVoteReplay* = object
  
  LeaderState* = object
    followersProgress: seq[RaftFollowerProgressTracker]

  CandidateState* = object
    votes: seq[RaftNodeId]

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
  LogEntry* = object         # Abstarct Raft Node Log entry containing opaque binary data (Blob etc.)
    term: RaftNodeTerm
    index: RaftLogIndex
    # TODO: Add configuration too
    data: Command

  RaftLog* = object
    logEntries: seq[LogEntry]
  
  RaftStateMachineOutput* = object
    logEntries: seq[LogEntry]
    # Entries that should be applyed to the "User" State machine
    committed: seq[LogEntry]
    messages: seq[RaftRpcMessage]
    debugLogs: seq[string]

  RaftStateMachine* = object
    myId*: RaftNodeId
    term: RaftNodeTerm
    commitIndex: RaftLogIndex
    log: RaftLog
    output: RaftStateMachineOutput
    electionTimeout: times.Duration
    lastUpdate: Time
    case state: RaftNodeState
    of rnsFollower: follower : FollowerState
    of rnsCandidate: candidate: CandidateState
    of rnsLeader: leader: LeaderState

  RaftStateMachineConfig* = object

  RaftFollowerProgressTracker* = object
    id: RaftNodeId
    nextIndex: RaftLogIndex
    matchIndex: RaftLogIndex
    commitIndex: RaftLogIndex
    replayedIndex: RaftLogIndex

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

func truncateUncomitted*(rf: var RaftLog, index: RaftLogIndex) =
  # TODO: We should add support for configurations and snapshots
  rf.logEntries.delete(index..<len(rf.logEntries))
  

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
  rf.appendAsLeader(LogEntry(term: term, index: index, data: data))


func appendAsFollower*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command) = 
  rf.appendAsFollower(LogEntry(term: term, index: index, data: data))


func matchTerm*(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): bool = 
  if len(rf.logEntries) == 0:
    return true
  # TODO: We should add support for snapshots
  if index > len(rf.logEntries):
    # The follower doesn't have all etries
    return false

  if rf.logEntries[index].term == term:
    return true
  else:
    return false

func termForIndex*(rf: RaftLog, index: RaftLogIndex): RaftNodeTerm =
  # TODO: We should add support for snapshots
  return rf.logEntries[index].term

func debug*(sm: var RaftStateMachine, log: string) = 
  sm.output.debugLogs.add(log)

func initRaftStateMachine*(config: RaftStateMachineConfig): RaftStateMachine = 
  var st =  RaftStateMachine()
  st.term = 0
  st.commitIndex = 0
  st.state = RaftNodeState.rnsFollower
  return st

func sendTo*(sm: var RaftStateMachine, id: RaftNodeId, request: RaftRpcAppendRequest) =
  sm.output.messages.add(RaftRpcMessage(currentTerm: sm.term, receiver: id, sender: sm.myId, kind: Append, appendRequest: request))


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


func tick* (sm: var RaftStateMachine) =
  sm.debug "TODO:implement tick"
  # TODO: here we should keep track of the replications progress

func poll*(sm: var RaftStateMachine):  RaftStateMachineOutput =
  # Should initiate replication if we have new entries
  if sm.state == RaftNodeState.rnsLeader:
    sm.replicate()
  let output = sm.output
  sm.output = RaftStateMachineOutput()
  return output


func commit*(sm: var RaftStateMachine) =
  if sm.state != RaftNodeState.rnsLeader
    return
  
