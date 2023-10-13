# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/tables
import ../raft/raft_api

export tables, raft_api

type
  SmState* = Table[string, string]

  SmCommands* = enum
    scSet = 0,
    scDel = 1

  SmCommand* = object
    cmd*: SmCommands
    key*: string
    val*: string

  RaftBasicSm* = RaftNodeStateMachine[SmCommand, SmState]

proc raftSmInit*(stateMachine: var RaftBasicSm) =
  new(stateMachine)
  new(stateMachine.state)

proc raftSmApply*(stateMachine: RaftBasicSm, command: SmCommand) =
  case command.cmd:
    of scSet:
      stateMachine.state[command.key] = command.val
    of scDel:
      stateMachine.state.del(command.key)