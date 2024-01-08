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

proc consensusstatemachineMain*() =
  

  suite "Basic state machine tests":
    test "create state machine":
      let config = RaftStateMachineConfig()
      let sm = initRaftStateMachine(config)
      echo sm

    test "advance empty state machine":
      var sm =  RaftStateMachine()
      var msg = sm.createVoteRequest()
      sm.advance(msg ,getTime())
      echo sm.poll()
      echo sm.poll()
      echo getTime()

    test "two machines":
      var sm =  RaftStateMachine()
      var sm2 = RaftStateMachine(myId: genUUID())
      var msg = sm2.createVoteRequest()
      sm.advance(msg ,getTime())
      echo sm2
      echo getTime()

    test "something":
      var arr = @[1,2,3,4,5]
      arr.delete(3..<len(arr))
      echo arr

  suite "Entry log tests":
    test "append entry as leadeer":
      var log = initRaftLog()
      log.appendAsLeader(0, 1, Command())
      log.appendAsLeader(0, 2, Command())
      check log.lastTerm() == 0
      log.appendAsLeader(1, 2, Command())
      check log.lastTerm() == 1
    test "append entry as follower":
      var log = initRaftLog()
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


if isMainModule:
  consensusstatemachineMain()