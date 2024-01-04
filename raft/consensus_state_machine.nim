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

type
  RaftRpcMessageType* = enum
    Vote = 0,
    VoteReplay = 1,
    Append = 2,
    AppendReplay = 3
    

  RaftRpcAppendRequest* = object
    previousTerm: RaftNodeTerm
    
  RaftRpcAppendReplay* = object

  RaftRpcVoteRequest* = object
  
  RaftRpcVoteReplay* = object
  
  LeaderState* = object

  CandidateState* = object
    votes: seq[RaftNodeId]

  FollowerState* = object
    leader: RaftNodeId

  RaftRpcMessage* = object
    currentTerm: RaftNodeTerm
    sender: RaftNodeId
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

func append(rf: var RaftLog, entry: LogEntry) = 
  rf.logEntries.add(entry)

func debug*(sm: var RaftStateMachine, log: string) = 
  sm.output.debugLogs.add(log)
    
func initRaftStateMachine*(config: RaftStateMachineConfig): RaftStateMachine = 
  var st =  RaftStateMachine()
  st.term = 0
  st.commitIndex = 0
  st.state = RaftNodeState.rnsFollower
  return st


func createVoteRequest*(sm: var RaftStateMachine): RaftRpcMessage = 
  return RaftRpcMessage(currentTerm: sm.term, sender: sm.myId, kind: Vote, voteRequest: RaftRpcVoteRequest())

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
  sm.log.append(entry)

func poll*(sm: var RaftStateMachine):  RaftStateMachineOutput =
  # Should initiate replication if we have new entries
  let output = sm.output
  sm.output = RaftStateMachineOutput()
  return output