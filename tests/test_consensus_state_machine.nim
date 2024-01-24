# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2
import ../raft/types
import ../raft/consensus_state_machine
import std/[times, sequtils]
import uuids
import tables

type
  TestCluster* = object
    nodes: Table[RaftnodeId, RaftStateMachine]
    messages: Table[RaftnodeId, seq[RaftRpcMessage]]

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
  cluster.messages = initTable[RaftnodeId, seq[RaftRpcMessage]]()
  cluster.nodes = initTable[RaftnodeId, RaftStateMachine]()
  for i in 0..<config.currentSet.len:
      let id = config.currentSet[i]
      var log = initRaftLog(0)
      var node = initRaftStateMachine(id, 0, log, 0, config, now)
      cluster.nodes[id] = node
      cluster.messages[id] = @[]
  return cluster

func routeMessages(tc: var TestCluster, now: times.DateTime) =
  for id, queue in tc.messages:
    for msg in queue:
      tc.nodes[msg.receiver].advance(msg, now)
   
    tc.messages[id] = @[]


func advance(tc: var TestCluster, now: times.DateTime) = 
  var outputs = initTable[RaftnodeId, RaftStateMachineOutput]()
  for id, node in tc.nodes:
    tc.nodes[id].tick(now)
    outputs[id] = tc.nodes[id].poll()

  for id, output in outputs:
    for msg in output.messages:
      tc.messages[id].add(msg)


proc consensusstatemachineMain*() =
  

  suite "Basic state machine tests":
    test "create state machine":
      var cluster = createCluster(test_ids_1, times.now())
      echo cluster

    test "advance empty state machine":
      var sm =  RaftStateMachine()
      var msg = sm.createVoteRequest()
      sm.advance(msg, times.now())
      echo sm.poll()
      echo sm.poll()
      echo getTime()

    test "two machines":
      var sm =  RaftStateMachine()
      var sm2 = RaftStateMachine(myId: genUUID())
      var msg = sm2.createVoteRequest()
      sm.advance(msg, times.now())
      echo sm2
      echo getTime()

    test "something":
      var arr = @[1,2,3,4,5]
      arr.delete(3..<len(arr))
      echo arr

  suite "Entry log tests":
    test "append entry as leadeer":
      var log = initRaftLog(0)
      log.appendAsLeader(0, 1, Command())
      log.appendAsLeader(0, 2, Command())
      check log.lastTerm() == 0
      log.appendAsLeader(1, 2, Command())
      check log.lastTerm() == 1
    test "append entry as follower":
      var log = initRaftLog(0)
      log.appendAsFollower(0, 0, Command())
      check log.lastTerm() == 0
      check log.lastIndex() == 0
      check log.entriesCount == 1
      log.appendAsFollower(0, 1, Command())
      check log.lastTerm() == 0
      check log.lastIndex() == 1
      check log.entriesCount == 2
      log.appendAsFollower(1, 1, Command())
      check log.lastTerm() == 1
      check log.lastIndex() == 1
      check log.entriesCount == 2
      log.appendAsFollower(2, 0, Command())
      check log.lastTerm() == 2
      check log.lastIndex() == 0
      check log.entriesCount == 1

  suite "3 node cluster":
    var timeNow = times.now()
    var cluster = createCluster(test_ids_3, timeNow)
    var t = now()
    # cluster.advance(t)
    # cluster.routeMessages(t)

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
      var log = initRaftLog(0)
      var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
      check sm.state.isFollower
      timeNow +=  99.milliseconds
      sm.tick(timeNow)
      var output = sm.poll()
      check output.logEntries.len == 0
      check output.committed.len == 0
      check output.messages.len == 0
      check sm.state.isFollower
      timeNow +=  300.milliseconds
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
      var log = initRaftLog(0)
      var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
      check sm.state.isFollower
      timeNow +=  300.milliseconds
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
      var log = initRaftLog(0)
      var timeNow = times.now()
      var sm = initRaftStateMachine(test_ids_1[0], 0, log, 0, config, timeNow)
      check sm.state.isFollower
      timeNow += 301.milliseconds
      sm.tick(timeNow)
      check sm.state.isCandidate
      var output = sm.poll()
      check output.votedFor.isSome
      check output.votedFor.get() == id1

      timeNow += 1.milliseconds
      block:
        let voteRaplay = RaftRpcVoteReplay(currentTerm: output.term, voteGranted: true, isPrevote: false)
        let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:id1, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
        check sm.state.isCandidate
        sm.advance(msg, timeNow)
        output = sm.poll()
        check output.stateChange == true
        check sm.state.isLeader

      timeNow += 1.milliseconds

      # Older messages should be ignored
      block:
        let voteRaplay = RaftRpcVoteReplay(currentTerm: (output.term - 1), voteGranted: true, isPrevote: false)
        let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:id1, kind: RaftRpcMessageType.VoteReplay, voteReplay: voteRaplay)
        sm.advance(msg, timeNow)
        output = sm.poll()
        check output.stateChange == false
        check sm.state.isLeader

      block:
        output = sm.poll()
        timeNow += 100.milliseconds
        echo sm
        echo "lol" & $output
        sm.tick(timeNow)
        output = sm.poll()
        echo sm
        echo "lol" & $output
      # if the leader get a message with higher term it should become follower
      block:
        timeNow += 201.milliseconds
        sm.tick(timeNow)
        output = sm.poll()
        let entry = LogEntry(term: (output.term + 1), index: 101, kind: RaftLogEntryType.rletEmpty, empty: true)
        let appendRequest = RaftRpcAppendRequest(previousTerm: (output.term + 1), previousLogIndex: 100, commitIndex: 99, entries: @[entry])
        let msg = RaftRpcMessage(currentTerm: (output.term + 1), sender: id2, receiver:id1, kind: RaftRpcMessageType.Append, appendRequest: appendRequest)
        sm.advance(msg, timeNow)
        output = sm.poll()
        check output.stateChange == true
        check sm.state.isFollower

if isMainModule:
  consensusstatemachineMain()