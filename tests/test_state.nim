import unittest
import ../src/raft/tracker
import ../src/raft/state
import ../src/raft
import std/[times]

proc stateMain() =
    suite "RaftStateMachineRefState Tests":

        test "initLeader should initialize the state as Leader":
            var cfg = RaftConfig()
            var index = RaftLogIndex(0)
            var now = times.now()
            var state = initLeader(cfg, index, now)
            check state.state == RaftNodeState.rnsLeader
            check state.isLeader
            check not state.isFollower
            check not state.isCandidate

        test "initFollower should initialize the state as Follower":
            var leaderId = RaftnodeId(id: "a8409b39-f17b-4682-aaef-a19cc9f356fb")
            var state = initFollower(leaderId)
            check state.state == RaftNodeState.rnsFollower
            check not state.isLeader
            check state.isFollower
            check not state.isCandidate

        test "initCandidate should initialize the state as Candidate":
            var cfg = RaftConfig()
            var state = initCandidate(cfg)
            check state.state == RaftNodeState.rnsCandidate
            check not state.isLeader
            check not state.isFollower
            check state.isCandidate


if isMainModule:
  stateMain()