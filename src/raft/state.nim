
import types
import tracker

import std/[times]
type
  RaftNodeState* = enum
    rnsFollower = 0,                        # Follower state
    rnsCandidate = 1                        # Candidate state
    rnsLeader = 2                           # Leader state

  RaftStateMachineRefState* = object
    case state*: RaftNodeState
    of rnsFollower: follower: FollowerState
    of rnsCandidate: candidate: CandidateState
    of rnsLeader: leader: LeaderState

  LeaderState* = object
    tracker*: RaftTracker

  CandidateState* = object
    votes*: RaftVotes

  FollowerState* = object
    leader*: RaftNodeId

proc `=copy`*(d: var RaftStateMachineRefState; src: RaftStateMachineRefState) {.error.} =
   discard

func `$`*(s: RaftStateMachineRefState): string =
  return $s.state

func initLeader*(cfg: RaftConfig, index: RaftLogIndex, now: times.DateTime): RaftStateMachineRefState =
  var state = RaftStateMachineRefState(state: RaftnodeState.rnsLeader, leader: LeaderState())
  state.leader.tracker = RaftTracker.init(cfg, index, now)
  return state

func initFollower*(leaderId: RaftNodeId): RaftStateMachineRefState =
  return RaftStateMachineRefState(state: RaftNodeState.rnsFollower, follower: FollowerState(leader: leaderId))

func initCandidate*(cfg: RaftConfig): RaftStateMachineRefState =
  return RaftStateMachineRefState(state: RaftnodeState.rnsCandidate, candidate: CandidateState(votes: RaftVotes.init(cfg)))

func isLeader*(s: RaftStateMachineRefState): bool =
  return s.state == RaftNodeState.rnsLeader

func isFollower*(s: RaftStateMachineRefState): bool =
  return s.state == RaftNodeState.rnsFollower

func isCandidate*(s: RaftStateMachineRefState): bool =
  return s.state == RaftNodeState.rnsCandidate

func leader*(s: var RaftStateMachineRefState): var LeaderState =
  return s.leader

func follower*(s: var RaftStateMachineRefState): var FollowerState =
  return s.follower

func candidate*(s: var RaftStateMachineRefState): var CandidateState =
  return s.candidate
