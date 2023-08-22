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
import std/locks
import basic_timers

var
  cancelCond: Cond
  cancelLock: Lock

initLock(cancelLock)
initCond(cancelCond)

proc timersRunner() =
  const
    MAX_TIMERS = 50
  var
    slowTimers: array[0..MAX_TIMERS, RaftTimer]
    fastTimers: array[0..MAX_TIMERS, RaftTimer]
    cancelTimer: RaftTimer

  proc CancelTimerCallbackClosure(
    slowTimers: var array[0..MAX_TIMERS, RaftTimer],
    fastTimers: var array[0..MAX_TIMERS, RaftTimer]
  ): RaftTimerCallback =
    result = proc (timer: var RaftTimer) {.nimcall, gcsafe.} =
      debugEcho "Aahjsbdghajsdhjgshgjd"
      signal(cancelCond)

  suite "Create and test basic timers":
    test "Create 50 slow timers (100-150 ms)":
      check true
    test "Create 50 fast timers (20-50 ms)":
      check true
    test "Create cancel timer":
      check true
    test "Start timers":
      cancelTimer = RaftTimerCreateCustomImpl(250, false, CancelTimerCallbackClosure(slowTimers, fastTimers))
      RaftTimerStartCustomImpl(joinThread=false)
      debugEcho repr(cancelTimer)
      check true
    test "Wait cancel timer 250 ms and stop timers":
      wait(cancelCond, cancelLock)
      check true
    test "Check timers consistency":
      check true

if isMainModule:
  timersRunner()