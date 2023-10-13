# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2
import basic_state_machine

proc basicStateMachineMain*() =
  var
    sm: RaftBasicSm
    smCommandsLog: seq[SmCommand]

  suite "Test Basic State Machine Implementation ":

    test "Test Init":
      raftSmInit(sm)

      check sm != nil and sm.state != nil and sm.state.len == 0

    test "Init commands Log":
      smCommandsLog.add(SmCommand(cmd: scSet, key: "a", val: "a"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "b", val: "b"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "c", val: "c"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "d", val: "d"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "e", val: "e"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "f", val: "f"))
      smCommandsLog.add(SmCommand(cmd: scDel, key: "a"))
      smCommandsLog.add(SmCommand(cmd: scDel, key: "a"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "a", val: "a"))
      smCommandsLog.add(SmCommand(cmd: scDel, key: "a"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "g", val: "g"))
      smCommandsLog.add(SmCommand(cmd: scDel, key: "d"))
      smCommandsLog.add(SmCommand(cmd: scSet, key: "h", val: "h"))

      check smCommandsLog.len == 13

    test "Apply commands from the Log and check result":
      for c in smCommandsLog:
        raftSmApply(sm, c)

      check sm.state[] == {"b": "b", "c": "c", "e": "e", "f": "f", "g": "g", "h": "h"}.toTable

if isMainModule:
  basicStateMachineMain()