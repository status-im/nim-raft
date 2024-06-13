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
import std/sets
import std/[sets, times, sequtils, random, algorithm,
strformat, sugar]
import stew/byteutils

import uuids
import tables

proc green*(s: string): string = "\e[32m" & s & "\e[0m"
proc grey*(s: string): string = "\e[90m" & s & "\e[0m"
proc purple*(s: string): string = "\e[95m" & s & "\e[0m"
proc yellow*(s: string): string = "\e[33m" & s & "\e[0m"
proc red*(s: string): string = "\e[31m" & s & "\e[0m"

type
  TestNode* = object
    sm: RaftStateMachineRef
    markedForDelection: bool

  TestCluster* = object
    nodes: Table[RaftnodeId, TestNode]
    commited: seq[LogEntry]
    blockedTickSet: HashSet[RaftnodeId]
    blockedMsgRoutingSet: HashSet[RaftnodeId]

    # callbacks
    onEntryCommit: proc(nodeId: RaftnodeId, entry: LogEntry)

var test_ids_3 = @[
  RaftnodeId(id: "a8409b39-f17b-4682-aaef-a19cc9f356fb"),
  RaftnodeId(id: "2a98fc33-6559-44c0-b130-fc3e9df80a69"),
  RaftnodeId(id: "9156756d-697f-4ffa-9b82-0c86720344bd")
]

var test_second_ids_3 = @[
  RaftnodeId(id: "aaaaaaaa-f17b-4682-aaef-a19cc9f356fb"),
  RaftnodeId(id: "bbbbbbbb-6559-44c0-b130-fc3e9df80a69"),
  RaftnodeId(id: "cccccccc-697f-4ffa-9b82-0c86720344bd")
]

var test_ids_1 = @[
  RaftnodeId(id: "a8409b39-f17b-4682-aaef-a19cc9f356fb"),
]

var test_second_ids_1 = @[
  RaftnodeId(id: "aaaaaaaa-f17b-4682-aaef-a19cc9f356fb"),
]

func poll(node: var TestNode): RaftStateMachineRefOutput =
  return node.sm.poll()

func advance(node: var TestNode, msg: RaftRpcMessage, now: times.DateTime) =
  node.sm.advance(msg, now)

func tick(node: var TestNode, now: times.DateTime) =
  node.sm.tick(now)


func createConfigFromIds(ids: seq[RaftnodeId]): RaftConfig =
  var config = RaftConfig()
  for id in ids:
    config.currentSet.add(id)
  return config

proc createCluster(ids: seq[RaftnodeId], now: times.DateTime) : TestCluster =
  var config = createConfigFromIds(ids)
  var cluster = TestCluster()
  cluster.blockedTickSet.init()
  cluster.blockedMsgRoutingSet.init()
  cluster.nodes = initTable[RaftnodeId, TestNode]()
  for i in 0..<config.currentSet.len:
      let id = config.currentSet[i]
      var log = RaftLog.init(RaftSnapshot(index: 0, config: config))
      var node = TestNode(sm: RaftStateMachineRef.new(id, 0, log, 0, now, initRand(i + 42)), markedForDelection: false)
      cluster.nodes[id] = node
  return cluster

proc addNodeToCluster(tc: var TestCluster, id: RaftnodeId, now: times.DateTime, config: RaftConfig, randomGenerator: Rand = initRand(42)) =
  var log = RaftLog.init(RaftSnapshot(index: 0, config: config))
  var node = TestNode(sm: RaftStateMachineRef.new(id, 0, log, 0, now, randomGenerator), markedForDelection: false)
  if tc.nodes.contains(id):
    raise newException(AssertionDefect, "Adding node to the cluster that already exist")
  tc.nodes[id] = node

proc addNodeToCluster(tc: var TestCluster, ids: seq[RaftnodeId], now: times.DateTime, config: RaftConfig, randomGenerator: Rand = initRand(42)) =
  var rng = randomGenerator
  for id in ids:
    let nodeSeed = rng.rand(1000)
    tc.addNodeToCluster(id, now, config, initRand(nodeSeed))

proc markNodeForDelection(tc: var TestCluster, id: RaftnodeId) = 
  tc.nodes[id].markedForDelection = true

proc removeNodeFromCluster(tc: var TestCluster, id: RaftnodeId) =
  tc.nodes.del(id)

proc removeNodeFromCluster(tc: var TestCluster, ids: seq[RaftnodeId]) =
  for id in ids:
    if tc.nodes.contains(id):
      tc.nodes.del(id)

proc ids(tc: var TestCluster): seq[RaftnodeId] =
  for k, v in tc.nodes:
    result.add(k)
  return result

proc blockTick(tc: var TestCluster, id: RaftnodeId) =
  tc.blockedTickSet.incl(id)

func blockMsgRouting(tc: var TestCluster, id: RaftnodeId) =
  tc.blockedMsgRoutingSet.incl(id)

func allowTick(tc: var TestCluster, id: RaftnodeId) =
  tc.blockedTickSet.excl(id)

func allowMsgRouting(tc: var TestCluster, id: RaftnodeId) =
  tc.blockedMsgRoutingSet.excl(id)

proc cmpLogs(x, y: DebugLogEntry): int =
  cmp(x.time, y.time)

func `$`*(de: DebugLogEntry, ): string = 
  return "[" & $de.level & "][" & de.time.format("HH:mm:ss:fff") & "][" & (($de.nodeId)[0..7]) & "...][" & $de.state & "]: " & de.msg

proc handleMessage(tc: var TestCluster, now: times.DateTime, msg: RaftRpcMessage, logLevel: DebugLogLevel) = 
  if not tc.blockedMsgRoutingSet.contains(msg.sender) and not tc.blockedMsgRoutingSet.contains(msg.receiver):
    if DebugLogLevel.Debug <= logLevel:
      echo now.format("HH:mm:ss:fff") & "rpc:" & $msg
    
    if tc.nodes.contains(msg.receiver):
      tc.nodes[msg.receiver].advance(msg, now)
    else:
      echo fmt"Node with id {msg.receiver} is not in the cluster"
  else:
    if DebugLogLevel.Debug <= logLevel:
      echo "[" & now.format("HH:mm:ss:fff") & "] rpc message is blocked: "  & $msg & $tc.blockedMsgRoutingSet

proc advance(tc: var TestCluster, now: times.DateTime, logLevel: DebugLogLevel = DebugLogLevel.Error) = 
  var debugLogs : seq[DebugLogEntry]
  
  for id, node in tc.nodes:
    if node.markedForDelection:
      continue
    if tc.blockedTickSet.contains(id):
      continue
    tc.nodes[id].tick(now)
    var output = tc.nodes[id].poll()
    debugLogs.add(output.debugLogs)
    for msg in output.messages:
      tc.handleMessage(now, msg, logLevel)       
    for entry in output.committed:
      tc.commited.add(entry)
      if not tc.onEntryCommit.isNil:
        tc.onEntryCommit(id, entry)

  let toDelete = toSeq(tc.nodes.values).filter(node => node.markedForDelection)
  for node in toDelete:
    tc.removeNodeFromCluster(node.sm.myId)
  
  debugLogs.sort(cmpLogs)
  for msg in debugLogs:
    if msg.level <= logLevel:
      echo $msg

proc advanceUntil(tc: var TestCluster, now: times.DateTime, until: times.DateTime, step: times.TimeInterval = 5.milliseconds, logLevel: DebugLogLevel = DebugLogLevel.Error): times.DateTime =
  var timeNow = now
  while timeNow < until:
    timeNow += step
    tc.advance(timeNow, logLevel)
  return timeNow

proc advanceConfigChange(tc: var TestCluster, now: times.DateTime, until: times.DateTime, step: times.TimeInterval = 5.milliseconds, logLevel: DebugLogLevel = DebugLogLevel.Error): times.DateTime =
  var timeNow = now
  while timeNow < until:
    timeNow += step
    tc.advance(timeNow, logLevel)
  return timeNow

func getLeader(tc: TestCluster): Option[RaftStateMachineRef] =
  var leader = none(RaftStateMachineRef)
  for id, node in tc.nodes:
    if node.sm.state.isLeader:
      if not leader.isSome() or leader.get().term < node.sm.term:
        leader = some(node.sm)
  return leader

proc configuration(tc: var TestCluster): Option[RaftConfig] =
  var leader = tc.getLeader()
  if leader.isSome():
    return some(leader.get.configuration())
  return none(RaftConfig)

proc submitCommand(tc: var TestCluster, cmd: Command): bool = 
  var leader = tc.getLeader()
  if leader.isSome():
    leader.get().addEntry(cmd)
    return true
  return false

proc hasCommitedEntry(tc: var TestCluster, cmd: Command): bool =
  for ce in tc.commited:
    if ce.kind == RaftLogEntryType.rletCommand and ce.command == cmd:
      return true
  return false

proc hasCommitedEntry(tc: var TestCluster, cfg: RaftConfig): bool =
  for ce in tc.commited:
    if ce.kind == RaftLogEntryType.rletConfig and ce.config == cfg:
      return true
  return false

proc advanceUntilNoLeader(tc: var TestCluster, start: times.DateTime, step: times.TimeInterval = 5.milliseconds, timeoutInterval: times.TimeInterval = 1.seconds, logLevel: DebugLogLevel = DebugLogLevel.Error): times.DateTime =
  var timeNow = start
  var timeoutAt = start + timeoutInterval
  while timeNow < timeoutAt:
    timeNow += step
    tc.advance(timeNow, logLevel)
    var maybeLeader = tc.getLeader()
    if not maybeLeader.isSome():
      return timeNow
  raise newException(AssertionDefect, "Timeout")
  
proc establishLeader(tc: var TestCluster, start: times.DateTime, step: times.TimeInterval = 5.milliseconds, timeoutInterval: times.TimeInterval = 1.seconds, logLevel: DebugLogLevel = DebugLogLevel.Error): times.DateTime =
  var timeNow = start
  var timeoutAt = start + timeoutInterval
  while timeNow < timeoutAt:
    timeNow += step
    tc.advance(timeNow, logLevel)
    var maybeLeader = tc.getLeader()
    if maybeLeader.isSome():
      return timeNow
  raise newException(AssertionDefect, "Timeout")
  

proc submitNewConfig(tc: var TestCluster, cfg: RaftConfig) = 
  var leader = tc.getLeader()
  if leader.isSome():
    leader.get().addEntry(cfg)
  else:
    raise newException(AssertionDefect, "Can submit new configuration")

proc toCommand(data: string): Command =
  return Command(data: data.toBytes)


proc consensusstatemachineMain*() =
  var config = createConfigFromIds(test_ids_1)
  suite "Basic state machine tests":
    test "create state machine":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var cluster = createCluster(test_ids_1, timeNow)

    test "tick empty state machine":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      
      var log = RaftLog.init(RaftSnapshot(index: 1, config: config))
      var sm = RaftStateMachineRef.new(test_ids_1[0], 0, log, 0, timeNow, initRand(42))
      timeNow += 5.milliseconds
      sm.tick(timeNow)

  suite "Entry log tests":
    test "append entry as leadeer":
      var log = RaftLog.init(RaftSnapshot(index: 2, config: config))
      check log.lastIndex == 2
    test "append entry as leadeer":
      var log = RaftLog.init(RaftSnapshot(index: 0, config: config))
      log.appendAsLeader(0, 1, Command())
      log.appendAsLeader(0, 2, Command())
      check log.lastTerm() == 0
      log.appendAsLeader(1, 2, Command())
      check log.lastTerm() == 1
    test "append entry as follower":
      var log = RaftLog.init(RaftSnapshot(index: 0, config: config))
      check log.nextIndex == 1
      log.appendAsFollower(0, 1, Command())
      check log.lastTerm() == 0
      check log.nextIndex == 2
      check log.lastIndex() == 1
      check log.entriesCount == 1
      discard log.matchTerm(1, 1)
      log.appendAsFollower(1, 2, Command())
      check log.lastTerm() == 1
      check log.nextIndex == 3
      check log.lastIndex() == 2
      check log.entriesCount == 2
      log.appendAsFollower(1, 3, Command())
      check log.lastTerm() == 1
      check log.nextIndex == 4
      check log.lastIndex() == 3
      check log.entriesCount == 3
      # log should trancate old entries because the term is bigger
      log.appendAsFollower(2, 2, Command())
      check log.lastTerm() == 2
      check log.nextIndex == 3
      check log.lastIndex() == 2
      check log.entriesCount == 2
      # log should be trancated because 
      log.appendAsFollower(2, 1, Command())
      check log.lastTerm() == 2
      check log.nextIndex == 2
      check log.lastIndex() == 1
      check log.entriesCount == 1

  suite "3 node cluster":
    var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
    var cluster = createCluster(test_ids_3, timeNow)
    var t = now()

  suite "Single node election tracker":
    test "unknown":
      var votes = RaftVotes.init(test_ids_1.createConfigFromIds)
      check votes.tallyVote == RaftElectionResult.Unknown

    test "win election":
      var votes = RaftVotes.init(test_ids_1.createConfigFromIds)
      discard votes.registerVote(test_ids_1[0], true)

      check votes.tallyVote == RaftElectionResult.Won
    test "lost election":
      var votes = RaftVotes.init(test_ids_1.createConfigFromIds)
      discard votes.registerVote(test_ids_1[0], false)
      echo votes.tallyVote
      check votes.tallyVote == RaftElectionResult.Lost

  suite "3 nodes election tracker":
    test "win election":
      var votes = RaftVotes.init(test_ids_3.createConfigFromIds)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], true)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], true)
      check votes.tallyVote == RaftElectionResult.Won

    test "lose election":
      var votes = RaftVotes.init(test_ids_3.createConfigFromIds)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], false)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], true)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[2], true)
      check votes.tallyVote == RaftElectionResult.Won

    test "lose election":
      var votes = RaftVotes.init(test_ids_3.createConfigFromIds)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], false)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], false)
      check votes.tallyVote == RaftElectionResult.Lost

    test "lose election":
      var votes = RaftVotes.init(test_ids_3.createConfigFromIds)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[0], true)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[1], false)
      check votes.tallyVote == RaftElectionResult.Unknown
      discard votes.registerVote(test_ids_3[2], false)
      check votes.tallyVote == RaftElectionResult.Lost  


  suite "Single node cluster":
    test "election":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var config = createConfigFromIds(test_ids_1)
      var log = RaftLog.init(RaftSnapshot(index: 1, config: config))
      var sm = RaftStateMachineRef.new(test_ids_1[0], 0, log, 0, timeNow, initRand(42))
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
      check output.logEntries.len == 1
      check output.committed.len == 0
      check output.messages.len == 0
      timeNow += 1.milliseconds
      output = sm.poll()
      check output.logEntries.len == 0
      check output.committed.len == 1
      check output.messages.len == 0
      check sm.state.isLeader
      check sm.term == 1

    test "append entry":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var config = createConfigFromIds(test_ids_1)
      var log = RaftLog.init(RaftSnapshot(index: 1, config: config))
      var sm = RaftStateMachineRef.new(test_ids_1[0], 0, log, 0, timeNow, initRand(42))
      check sm.state.isFollower
      timeNow +=  1000.milliseconds
      sm.tick(timeNow)
      var output = sm.poll()
      # When the node became a leader it will produce empty message in the log 
      # and because we have single node in the cluster the empty message will be commited on the next tick
      check output.logEntries.len == 1
      check output.committed.len == 0
      check output.messages.len == 0
      check sm.state.isLeader
      
      timeNow +=  1.milliseconds
      sm.tick(timeNow)
      output = sm.poll()
      check output.logEntries.len == 0
      check output.committed.len == 1
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
      var log = RaftLog.init(RaftSnapshot(index: 1, config: config))
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var sm = RaftStateMachineRef.new(test_ids_1[0], 0, log, 0, timeNow, initRand(42))
      check sm.state.isFollower
      timeNow += 601.milliseconds
      sm.tick(timeNow)
      check sm.state.isCandidate
      var output = sm.poll()
      check output.votedFor.isSome
      check output.votedFor.get() == id1

      timeNow += 1.milliseconds
      block:
        let voteRaplay = RaftRpcVoteReply(currentTerm: output.term, voteGranted: true)
        let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:id1, kind: RaftRpcMessageType.VoteReply, voteReply: voteRaplay)
        check sm.state.isCandidate
        sm.advance(msg, timeNow)
        output = sm.poll()
        check output.stateChange == true
        check sm.state.isLeader

      timeNow += 1.milliseconds

      # Older messages should be ignored
      block:
        let voteRaplay = RaftRpcVoteReply(currentTerm: (output.term - 1), voteGranted: true)
        let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:id1, kind: RaftRpcMessageType.VoteReply, voteReply: voteRaplay)
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
        let entry = LogEntry(term: (output.term + 1), index: 1, kind: RaftLogEntryType.rletEmpty, empty: true)
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
        var log = RaftLog.init(RaftSnapshot(index: 1, config: config))
        var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
        var sm = RaftStateMachineRef.new(test_ids_1[0], 0, log, 0, timeNow, initRand(42))
        check sm.state.isFollower
        timeNow += 501.milliseconds
        sm.tick(timeNow)
        check sm.state.isCandidate
        var output = sm.poll()
        check output.votedFor.isSome
        check output.votedFor.get() == mainNodeId
        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReply(currentTerm: output.term, voteGranted: false)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReply, voteReply: voteRaplay)
          check sm.state.isCandidate
          sm.advance(msg, timeNow)
          output = sm.poll()
          check output.stateChange == false
          check sm.state.isCandidate

        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReply(currentTerm: output.term, voteGranted: false)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id3, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReply, voteReply: voteRaplay)
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
        var log = RaftLog.init(RaftSnapshot(index: 1, config: config))
        var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
        var sm = RaftStateMachineRef.new(test_ids_1[0], 0, log, 0, timeNow, initRand(42))
        check sm.state.isFollower
        timeNow += 501.milliseconds
        sm.tick(timeNow)
        check sm.state.isCandidate
        var output = sm.poll()
        check output.votedFor.isSome
        check output.votedFor.get() == mainNodeId
        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReply(currentTerm: output.term, voteGranted: false)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id2, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReply, voteReply: voteRaplay)
          check sm.state.isCandidate
          sm.advance(msg, timeNow)
          output = sm.poll()
          check output.stateChange == false
          check sm.state.isCandidate

        timeNow += 1.milliseconds
        block:
          let voteRaplay = RaftRpcVoteReply(currentTerm: output.term, voteGranted: true)
          let msg = RaftRpcMessage(currentTerm: output.term, sender: id3, receiver:mainNodeId, kind: RaftRpcMessageType.VoteReply, voteReply: voteRaplay)
          check sm.state.isCandidate
          sm.advance(msg, timeNow)
          output = sm.poll()
          check output.stateChange == true
          check sm.state.isLeader

        timeNow += 1.milliseconds

  suite "3 nodes cluster":
    test "election":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var cluster = createCluster(test_ids_3, timeNow)
      var leader: RaftnodeId
      var hasLeader = false
      for i in 0..<105:
        timeNow += 5.milliseconds
        cluster.advance(timeNow)
        var maybeLeader = cluster.getLeader()
        if leader == RaftnodeId():
          if maybeLeader.isSome:
            leader = maybeLeader.get().myId
            hasLeader = true
        else:
          if maybeLeader.isSome:
            check leader == maybeLeader.get().myId
          else:
            check false
      # we should elect atleast 1 leader
      check hasLeader

    test "1 node is not responding":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var cluster = createCluster(test_ids_3, timeNow)
      cluster.blockMsgRouting(test_ids_3[0])
      var leader: RaftnodeId
      var hasLeader = false
      for i in 0..<105:
        timeNow += 5.milliseconds
        cluster.advance(timeNow)
        var maybeLeader = cluster.getLeader()
        if leader == RaftnodeId():
          if maybeLeader.isSome:
            leader = maybeLeader.get().myId
            hasLeader = true
        else:
          if maybeLeader.isSome:
            check leader == maybeLeader.get().myId
          else:
            check false
      # we should elect atleast 1 leader
      check hasLeader

    test "2 nodes is not responding":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var cluster = createCluster(test_ids_3, timeNow)
      cluster.blockMsgRouting(test_ids_3[0])
      cluster.blockMsgRouting(test_ids_3[1])
      var leader: RaftnodeId
      for i in 0..<105:
        timeNow += 5.milliseconds
        cluster.advance(timeNow)
        var maybeLeader = cluster.getLeader()
        # We should never elect a leader
        check leader == RaftnodeId()
    

    test "1 nodes is not responding new leader reelection": 
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var cluster = createCluster(test_ids_3, timeNow)
      var leader: RaftnodeId
      var firstLeaderId = RaftnodeId()
      var secondLeaderId = RaftnodeId()
      for i in 0..<305:
        timeNow += 5.milliseconds
        cluster.advance(timeNow)
        var maybeLeader = cluster.getLeader()
        if maybeLeader.isSome() and firstLeaderId == RaftNodeId():
          # we will block the comunication and will try to elect new leader
          firstLeaderId = maybeLeader.get().myId
          cluster.blockMsgRouting(firstLeaderId)
          echo "Block comunication with: " & $firstLeaderId
        if firstLeaderId != RaftnodeId() and maybeLeader.isSome() and maybeLeader.get().myId != firstLeaderId:
          secondLeaderId = maybeLeader.get().myId
      check secondLeaderId != RaftnodeId() and firstLeaderId != secondLeaderId


    test "After reaelection leader should become follower": 
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var cluster = createCluster(test_ids_3, timeNow)
      var leader: RaftnodeId
      var firstLeaderId = RaftnodeId()
      var secondLeaderId = RaftnodeId()
      for i in 0..<305:
        timeNow += 5.milliseconds
        cluster.advance(timeNow)
        var maybeLeader = cluster.getLeader()
        if maybeLeader.isSome() and firstLeaderId == RaftNodeId():
          # we will block the comunication and will try to elect new leader
          firstLeaderId = maybeLeader.get().myId
          cluster.blockMsgRouting(firstLeaderId)
          echo "Block comunication with: " & $firstLeaderId
        if firstLeaderId != RaftnodeId() and maybeLeader.isSome() and maybeLeader.get().myId != firstLeaderId:
          secondLeaderId = maybeLeader.get().myId
          cluster.allowMsgRouting(firstLeaderId)

  suite "config change":
    test "1 node":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      
      var cluster = createCluster(test_second_ids_1, timeNow)
      timeNow = cluster.establishLeader(timeNow)

      var config = createConfigFromIds(test_ids_1)
      cluster.submitNewConfig(config)
      var currentConfig = cluster.configuration()
      check currentConfig.isSome
      var cfg = currentConfig.get()
      cluster.addNodeToCluster(test_ids_1[0], timeNow, currentConfig.get())
      timeNow = cluster.advanceUntil(timeNow, timeNow + 50.milliseconds)
      cluster.removeNodeFromCluster(test_second_ids_1[0])
      timeNow = cluster.advanceUntil(timeNow, timeNow + 500.milliseconds)
      
      currentConfig = cluster.configuration()
      check currentConfig.isSome
      cfg = currentConfig.get()

      var l = cluster.getLeader()
      check l.isSome()
      check l.get().myId == test_ids_1[0]

    test "3 nodes":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      
      var cluster = createCluster(test_second_ids_3, timeNow)
      timeNow = cluster.establishLeader(timeNow)

      check cluster.submitCommand("abc".toCommand)
      var newConfig = createConfigFromIds(test_ids_3)
      cluster.submitNewConfig(newConfig)
      var currentConfig = cluster.configuration()
      check currentConfig.isSome
      var cfg = currentConfig.get()
      cluster.addNodeToCluster(test_ids_3, timeNow, cfg)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 25.milliseconds)
      cluster.removeNodeFromCluster(test_second_ids_3)
      timeNow = cluster.establishLeader(timeNow)
      check cluster.submitCommand("bcd".toCommand)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 25.milliseconds)
      currentConfig = cluster.configuration()
      check currentConfig.isSome
      cfg = currentConfig.get()

      check cluster.hasCommitedEntry("abc".toCommand)
      check cluster.hasCommitedEntry("bcd".toCommand)

    test "add node":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      
      var cluster = createCluster(test_second_ids_1, timeNow)
      timeNow = cluster.establishLeader(timeNow)
      var newSet =  test_second_ids_1 & test_ids_1
      var newConfig = createConfigFromIds(newSet)
      cluster.submitNewConfig(newConfig)
      var currentConfig = cluster.configuration()
      check currentConfig.isSome
      var cfg = currentConfig.get()
      check cfg.previousSet == test_second_ids_1
      check cfg.currentSet == test_second_ids_1 & test_ids_1
      cluster.addNodeToCluster(test_ids_1, timeNow, cfg)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 25.milliseconds)

      currentConfig = cluster.configuration()
      check currentConfig.isSome

    test "remove node":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      
      var newSet = test_second_ids_1 & test_ids_1
      var cluster = createCluster(newSet, timeNow)
      timeNow = cluster.establishLeader(timeNow)
      var newConfig = createConfigFromIds(test_second_ids_1)
      cluster.submitNewConfig(newConfig)
      var currentConfig = cluster.configuration()
      check currentConfig.isSome
      var cfg = currentConfig.get()
      check cfg.currentSet == test_second_ids_1
      check cfg.previousSet == test_second_ids_1 & test_ids_1
      timeNow = cluster.advanceUntil(timeNow, timeNow + 25.milliseconds)
      cluster.removeNodeFromCluster(test_ids_1)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 25.milliseconds)
      check cluster.submitCommand("abc".toCommand)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 25.milliseconds)
      check cluster.hasCommitedEntry("abc".toCommand)

    test "add entrie during config chage":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())    
      var cluster = createCluster(test_second_ids_1, timeNow)
      timeNow = cluster.establishLeader(timeNow)
      var newConfig = createConfigFromIds(test_second_ids_1 & test_ids_1)
      cluster.submitNewConfig(newConfig)
      check cluster.submitCommand("abc".toCommand)
      check cluster.submitCommand("fgh".toCommand)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 250.milliseconds)
      # The second node is not added
      check not cluster.hasCommitedEntry("abc".toCommand)
      check not cluster.hasCommitedEntry("fgh".toCommand)


      var currentConfig = cluster.configuration()
      check currentConfig.isSome
      var cfg = currentConfig.get()
      cluster.addNodeToCluster(test_ids_1, timeNow, cfg)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 250.milliseconds)
      check cluster.hasCommitedEntry("abc".toCommand)
      check cluster.hasCommitedEntry("fgh".toCommand)

      newConfig = createConfigFromIds(test_ids_1)
      cluster.submitNewConfig(newConfig)

      check cluster.submitCommand("phg".toCommand)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 250.milliseconds)
      check cluster.hasCommitedEntry("phg".toCommand)
      
      timeNow = cluster.advanceUntil(timeNow, timeNow + 250.milliseconds)
      currentConfig = cluster.configuration()
      check currentConfig.isSome
      cfg = currentConfig.get()
      cluster.removeNodeFromCluster(test_second_ids_1)
      # The cluster don't have leader yet
      check not cluster.getLeader().isSome
      check not cluster.submitCommand("xyz".toCommand)

      timeNow = cluster.advanceUntil(timeNow, timeNow + 500.milliseconds)
      
      check cluster.submitCommand("xyz".toCommand)
      check cluster.getLeader().isSome
      timeNow = cluster.advanceUntil(timeNow, timeNow + 250.milliseconds)
      check cluster.hasCommitedEntry("phg".toCommand)
      check cluster.hasCommitedEntry("abc".toCommand)
      check cluster.hasCommitedEntry("fgh".toCommand)
      check cluster.hasCommitedEntry("xyz".toCommand)

    test "Leader stop responding config change":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      
      var cluster = createCluster(test_second_ids_3, timeNow)
      timeNow = cluster.establishLeader(timeNow)
      check cluster.submitCommand("abc".toCommand)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 50.milliseconds)
      check cluster.hasCommitedEntry("abc".toCommand)

      var newConfig = createConfigFromIds(test_ids_1)
      cluster.submitNewConfig(newConfig)
      check cluster.getLeader.isSome()
      cluster.removeNodeFromCluster(cluster.getLeader.get.myId)
      timeNow = cluster.advanceUntilNoLeader(timeNow)
      check not cluster.getLeader.isSome()
      # Cluster refuse to accept the message
      timeNow = cluster.establishLeader(timeNow)
      
      # Resubmit config
      cluster.submitNewConfig(newConfig)
      # Wait to replicate the new config
      timeNow = cluster.advanceUntil(timeNow, timeNow + 50.milliseconds)

      var currentConfig = cluster.configuration()
      check currentConfig.isSome
      var cfg = currentConfig.get()
      cluster.addNodeToCluster(test_ids_1, timeNow, cfg)
      
      check cluster.submitCommand("phg".toCommand)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 500.milliseconds)
      check cluster.hasCommitedEntry("phg".toCommand)
      timeNow = cluster.establishLeader(timeNow)

      cluster.removeNodeFromCluster(test_second_ids_3)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 50.milliseconds)

      check cluster.submitCommand("qwe".toCommand)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 50.milliseconds)
      check cluster.hasCommitedEntry("qwe".toCommand)
      check cluster.hasCommitedEntry("phg".toCommand)
      check not cluster.hasCommitedEntry("xyz".toCommand)
      check cluster.hasCommitedEntry("abc".toCommand)

    test "Leader stop responding during config change":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      
      var cluster = createCluster(test_second_ids_3, timeNow)

      var removed = false
      cluster.onEntryCommit = proc(nodeId: RaftnodeId, entry: LogEntry) =
        if entry.kind == rletConfig and not removed:
          check cluster.getLeader.isSome()
          var currentConfig = cluster.configuration()
          check currentConfig.isSome
          var cfg = currentConfig.get()
          cluster.markNodeForDelection(cluster.getLeader.get.myId)
          removed = true
        
      timeNow = cluster.establishLeader(timeNow)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 25.milliseconds)
      
      var newConfig = createConfigFromIds(test_ids_3)
      cluster.submitNewConfig(newConfig)

      var currentConfig = cluster.configuration()
      check currentConfig.isSome
      var cfg = currentConfig.get()
      cluster.addNodeToCluster(test_ids_3, timeNow, cfg)
      timeNow = cluster.advanceUntil(timeNow, timeNow + 105.milliseconds)      
      timeNow = cluster.establishLeader(timeNow)
      check cluster.getLeader.isSome()


if isMainModule:
  consensusstatemachineMain()