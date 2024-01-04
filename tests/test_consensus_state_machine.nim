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
import std/[times]

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


if isMainModule:
  consensusstatemachineMain()