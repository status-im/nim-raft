# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2
import ../src/raft/types
import ../src/raft/consensus_state_machine
import ../src/raft/log
import ../src/raft/tracker
import ../src/raft/state
import std/[times, sequtils]
import uuids
import tables

type
  TestCluster* = object
    nodes: Table[RaftnodeId, RaftStateMachine]

var test_ids_3 = @[
  RaftnodeId(parseUUID("a8409b39-f17b-4682-aaef-a19cc9f356fb")),
  RaftnodeId(parseUUID("2a98fc33-6559-44c0-b130-fc3e9df80a69")),
  RaftnodeId(parseUUID("9156756d-697f-4ffa-9b82-0c86720344bd"))
]

var test_ids_1 = @[
  RaftnodeId(parseUUID("a8409b39-f17b-4682-aaef-a19cc9f356fb")),
]

func createConfigFromIds(ids: seq[RaftnodeId]): RaftConfig =
  var config = RaftConfig()
  for id in ids:
    config.currentSet.add(id)
  return config

proc createCluster(ids: seq[RaftnodeId], now: times.DateTime) : TestCluster =
  var config = createConfigFromIds(ids)
  var cluster = TestCluster()
  cluster.nodes = initTable[RaftnodeId, RaftStateMachine]()
  for i in 0..<config.currentSet.len:
      let id = config.currentSet[i]
      var log = initRaftLog(1)
      var node = initRaftStateMachine(id, 0, log, 0, config, now)
      cluster.nodes[id] = node
  return cluster

proc advance(tc: var TestCluster, now: times.DateTime) = 
  for id, node in tc.nodes:
    tc.nodes[id].tick(now)
    var output = tc.nodes[id].poll()
    # for msg in output.debugLogs:
    #   echo $msg
    for msg in output.messages:
        #echo "rpc:" & $msg
        tc.nodes[msg.receiver].advance(msg, now)
    
func getLeader(tc: TestCluster): Option[RaftStateMachine] = 
  for id, node in tc.nodes:
    if node.state.isLeader:
      return some(node)
  return none(RaftStateMachine)
  
proc consensusstatemachineMain*() =

  suite "Basic state machine tests":
    test "create state machine":
      var cluster = createCluster(test_ids_1, times.now())
      echo cluster

    test "tick empty state machine":
      var timeNow = times.now()
      var config = createConfigFromIds(test_ids_1)
      var log = initRaftLog(1)
      var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
      sm.tick(times.now())
      echo sm.poll()
      echo sm.poll()
      echo getTime()

  suite "Entry log tests":
    test "append entry as leadeer":
      var log = initRaftLog(1)
      log.appendAsLeader(0, 1, Command())
      log.appendAsLeader(0, 2, Command())
      check log.lastTerm() == 0
      log.appendAsLeader(1, 2, Command())
      check log.lastTerm() == 1
    test "append entry as follower":
      var log = initRaftLog(1)
      log.appendAsFollower(0, 1, Command())
      check log.lastTerm() == 0
      check log.lastIndex() == 1
      check log.entriesCount == 1
      log.appendAsFollower(0, 1, Command())
      check log.lastTerm() == 0
      check log.lastIndex() == 1
      check log.entriesCount == 1
      discard log.matchTerm(1, 1)
      log.appendAsFollower(1, 2, Command())
      check log.lastTerm() == 1
      check log.lastIndex() == 2
      check log.entriesCount == 2
      log.appendAsFollower(1, 3, Command())
      check log.lastTerm() == 1
      check log.lastIndex() == 3
      check log.entriesCount == 3
      log.appendAsFollower(1, 2, Command())
      check log.lastTerm() == 1
      check log.lastIndex() == 2
      check log.entriesCount == 2
      log.appendAsFollower(2, 1, Command())
      check log.lastTerm() == 2
      check log.lastIndex() == 1
      check log.entriesCount == 1

  suite "3 node cluster":
    var timeNow = times.now()
    var cluster = createCluster(test_ids_3, timeNow)
    var t = now()

  suite "Single node election tracker":
    test "unknown":
      var votes = initVotes(test_ids_1)
      check votes.tallyVote == RaftElectionResult.Unknown

    test "win election":
      var votes = initVotes(test_ids_1)
      discard votes.registerVote(test_ids_1[0], true)

      check votes.tallyVote == RaftElectionResult.Won
    test "lost election":
      var votes = initVotes(test_ids_1)
      discard votes.registerVote(test_ids_1[0], false)
      echo votes.tallyVote
      check votes.tallyVote == RaftElectionResult.Lost

  suite "3 nodes election tracker":
    test "win election":
      var votes = initVotes(test_ids_3)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], true)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], true)
      check votes.tallyVote == RaftElectionResult.Won

    test "lose election":
      var votes = initVotes(test_ids_3)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], false)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], true)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[2], true)
      check votes.tallyVote == RaftElectionResult.Won

    test "lose election":
      var votes = initVotes(test_ids_3)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], false)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], false)
      check votes.tallyVote == RaftElectionResult.Lost

    test "lose election":
      var votes = initVotes(test_ids_3)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], true)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], false)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[2], false)
      check votes.tallyVote == RaftElectionResult.Lost


  suite "Single node cluster":
    test "election":
      var timeNow = times.now()
      var config = createConfigFromIds(test_ids_1)
      var log = initRaftLog(1)
      var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
      check sm.state.isFollower
      timeNow +=  99.milliseconds
      sm.tick(timeNow)
      var output = sm.poll()
      check output.logEntries.len == 0
      check output.committed.len == 0
      check output.messages.len == 0
      check sm.state.isFollower
      timeNow +=  500.milliseconds
      sm.tick(timeNow)
      output = sm.poll()
      check output.logEntries.len == 0
      check output.committed.len == 0
      check output.messages.len == 0
      check sm.state.isLeader
      check sm.term == 1

    test "append entry":
      var timeNow = times.now()
      var config = createConfigFromIds(test_ids_1)
      var log = initRaftLog(1)
      var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
      check sm.state.isFollower
      timeNow +=  1000.milliseconds
      sm.tick(timeNow)
      var output = sm.poll()
      check output.logEntries.len == 0
      check output.committed.len == 0
      check output.messages.len == 0
      check sm.state.isLeader
      sm.addEntry(Empty())
      check sm.poll().messages.len == 0
      timeNow +=  250.milliseconds
      sm.tick(timeNow)
      check sm.poll().messages.len == 0

  suite "Two nodes cluster":
    test "election":
      let id1 = test_ids_3[0]
      let id2 = test_ids_3[1]
      var config = createConfigFromIds(@[id1, id2])
      var log = initRaftLog(1)
      var timeNow = times.now()
      var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
      check sm.state.isFollower
      timeNow += 601.milliseconds
      sm.tick(timeNow)
      check sm.state.isCandidate
      var output = sm.poll()
      check output.votedFor.isSome
      check output.votedFor.get() == id1

      timeNow += 1.milliseconds
      block:
        let voteRaplay = RaftRpcVoteReplay(currentTerm: output.term, voteGranted: true)
        let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:id1, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
        check sm.state.isCandidate
        sm.advance(msg, timeNow)
        output = sm.poll()
        check output.stateChange == true
        check sm.state.isLeader

      timeNow += 1.milliseconds

      # Older messages should be ignored
      block:
        let voteRaplay = RaftRpcVoteReplay(currentTerm: (output.term - 1), voteGranted: true)
        let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:id1, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
        sm.advance(msg, timeNow)
        output = sm.poll()
        check output.stateChange == false
        check sm.state.isLeader

      block:
        output = sm.poll()
        timeNow += 100.milliseconds
        sm.tick(timeNow)
        output = sm.poll()
      # if the leader get a message with higher term it should become follower
      block:
        timeNow += 201.milliseconds
        sm.tick(timeNow)
        output = sm.poll()
        let entry = LogEntry(term: (output.term + 1), index: 101, kind: RaftLogEntryType.rletEmpty, empty: true)
        let appendRequest = RaftRpcAppendRequest(previousTerm: (output.term + 1), previousLogIndex: 100, commitIndex: 99, entries: @[entry])
        let msg = RaftRpcMessage(currentTerm: (output.term + 1), sender: id2, receiver:id1, kind: RaftRpcMessageType.AppendRequest, appendRequest: appendRequest)
        sm.advance(msg, timeNow)
        output = sm.poll()
        check output.stateChange == true
        check sm.state.isFollower
    suite "3 nodes cluster":
      test "election failed":
        let mainNodeId = test_ids_3[0]
        let id2 = test_ids_3[1]
        let id3 = test_ids_3[2]
        var config = createConfigFromIds(test_ids_3)
        var log = initRaftLog(1)
        var timeNow = times.now()
        var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
        check sm.state.isFollower
        timeNow += 501.milliseconds
        sm.tick(timeNow)
        check sm.state.isCandidate
        var output = sm.poll()
        check output.votedFor.isSome
        check output.votedFor.get() == mainNodeId
        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReplay(currentTerm: output.term, voteGranted: false)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
          check sm.state.isCandidate
          sm.advance(msg, timeNow)
          output = sm.poll()
          check output.stateChange == false
          check sm.state.isCandidate

        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReplay(currentTerm: output.term, voteGranted: false)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id3, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
          check sm.state.isCandidate
          sm.advance(msg, timeNow)
          output = sm.poll()
          check output.stateChange == true
          check sm.state.isFollower

        timeNow += 1.milliseconds

      test "election":
        let mainNodeId = test_ids_3[0]
        let id2 = test_ids_3[1]
        let id3 = test_ids_3[2]
        var config = createConfigFromIds(test_ids_3)
        var log = initRaftLog(1)
        var timeNow = times.now()
        var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
        check sm.state.isFollower
        timeNow += 501.milliseconds
        sm.tick(timeNow)
        check sm.state.isCandidate
        var output = sm.poll()
        check output.votedFor.isSome
        check output.votedFor.get() == mainNodeId
        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReplay(currentTerm: output.term, voteGranted: false)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
          check sm.state.isCandidate
          sm.advance(msg, timeNow)
          output = sm.poll()
          check output.stateChange == false
          check sm.state.isCandidate

        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReplay(currentTerm: output.term, voteGranted: true)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id3, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
          check sm.state.isCandidate
          sm.advance(msg, timeNow)
          output = sm.poll()
          check output.stateChange == true
          check sm.state.isLeader

        timeNow += 1.milliseconds

  suite "3 nodes cluester":
    test "election":
      var cluster = createCluster(test_ids_3, times.now())
      var timeNow = times.now()
      var leader: RaftnodeId
      for i in 0..<105:
        timeNow += 5.milliseconds
        cluster.advance(timeNow)
        var maybeLeader = cluster.getLeader()
        if leader == RaftnodeId():
          if maybeLeader.isSome:
            leader = maybeLeader.get().myId
        else:
          if maybeLeader.isSome:
            check leader == maybeLeader.get().myId
          else:
            check false

if isMainModule:
  consensusstatemachineMain()