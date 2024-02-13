
import types
import tracker

import std/[times]
type
  RaftNodeState* = enum
    rnsFollower = 0,                        # Follower state
    rnsCandidate = 1                        # Candidate state
    rnsLeader = 2                           # Leader state

  RaftStateMachineState* = object
    case state: RaftNodeState
    of rnsFollower: follower: FollowerState
    of rnsCandidate: candidate: CandidateState
    of rnsLeader: leader: LeaderState

  LeaderState* = object
    tracker*: RaftTracker

  CandidateState* = object
    votes*: RaftVotes

  FollowerState* = object
    leader*: RaftNodeId

func `$`*(s: RaftStateMachineState): string =
  return $s.state

func initLeader*(cfg: RaftConfig, index: RaftLogIndex, now: times.DateTime): RaftStateMachineState =
  var state = RaftStateMachineState(state: RaftnodeState.rnsLeader, leader: LeaderState())
  state.leader.tracker = initTracker(cfg, index, now)
  return state

func initFollower*(leaderId: RaftNodeId): RaftStateMachineState =
  return RaftStateMachineState(state: RaftNodeState.rnsFollower, follower: FollowerState(leader: leaderId))

func initCandidate*(cfg: RaftConfig): RaftStateMachineState =
  return RaftStateMachineState(state: RaftnodeState.rnsCandidate, candidate: CandidateState(votes: initVotes(cfg)))

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
