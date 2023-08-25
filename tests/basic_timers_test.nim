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
import random

const
  MAX_TIMERS = 50
  SLOW_TIMERS_MIN = 300
  SLOW_TIMERS_MAX = 350
  FAST_TIMERS_MIN = 20
  FAST_TIMERS_MAX = 150
  WAIT_FOR_SLOW_TIMERS = 225
  FINAL_WAIT = 125

proc timersRunner() =
  var
    slowTimers: array[0..MAX_TIMERS, RaftTimer]
    fastTimers: array[0..MAX_TIMERS, RaftTimer]

  var
    RaftDummyTimerCallback = proc (timer: RaftTimer) {.nimcall, gcsafe.} =
      discard

  suite "Create and test basic timers":
    test "Start timers":
      RaftTimerStartCustomImpl(false)
      check true
    test "Create 'slow' timers":
      for i in 0..MAX_TIMERS:
        slowTimers[i] = RaftTimerCreateCustomImpl(max(SLOW_TIMERS_MIN, rand(SLOW_TIMERS_MAX)), true, RaftDummyTimerCallback)
      check true
    test "Create 'fast' timers":
      for i in 0..MAX_TIMERS:
        fastTimers[i] = RaftTimerCreateCustomImpl(max(FAST_TIMERS_MIN, rand(FAST_TIMERS_MAX)), true, RaftDummyTimerCallback)
      check true
    test "Wait for and cancel 'slow' timers":
      waitFor sleepAsync(WAIT_FOR_SLOW_TIMERS)
      for i in 0..MAX_TIMERS:
        RaftTimerCancelCustomImpl(slowTimers[i])
      check true
    test "Wait and stop timers":
      waitFor sleepAsync(FINAL_WAIT)
      RaftTimerStopCustomImpl(true)
      check true
    test "Check timers consistency":
      for i in 0..MAX_TIMERS:
        if not fastTimers[i].expired or not slowTimers[i].canceled:
          check false
      check true

if isMainModule:
  timersRunner()