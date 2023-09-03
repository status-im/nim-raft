# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2
import basic_timers
import random

const
  MAX_TIMERS = 50
  SLOW_TIMERS_MIN = 300
  SLOW_TIMERS_MAX = 400
  FAST_TIMERS_MIN = 10
  FAST_TIMERS_MAX = 100
  WAIT_FOR_SLOW_TIMERS = 200
  FINAL_WAIT = 300

proc basicTimersMain*() =
  var
    slowTimers: array[0..MAX_TIMERS, Future[void]]
    fastTimers: array[0..MAX_TIMERS, Future[void]]

  var
    slowCnt: ref int
    RaftDummyTimerCallback = proc () {.nimcall, gcsafe.} = discard
    RaftTimerCallbackCnt = proc (cnt: ref int): RaftTimerCallback =
      proc () {.gcsafe.} = cnt[].inc

  slowCnt = new(int)
  slowCnt[] = 0

  suite "Create and test basic timers":

    test "Create 'slow' and 'fast' timers":
      for i in 0..MAX_TIMERS:
        slowTimers[i] = RaftTimerCreateCustomImpl(max(SLOW_TIMERS_MIN, rand(SLOW_TIMERS_MAX)), true, RaftTimerCallbackCnt(slowCnt))

      for i in 0..MAX_TIMERS:
        fastTimers[i] = RaftTimerCreateCustomImpl(max(FAST_TIMERS_MIN, rand(FAST_TIMERS_MAX)), true, RaftDummyTimerCallback)

    test "Wait for and cancel 'slow' timers":
      waitFor sleepAsync(WAIT_FOR_SLOW_TIMERS)
      for i in 0..MAX_TIMERS:
        if not slowTimers[i].finished:
          cancel(slowTimers[i])

    test "Final wait timers":
      waitFor sleepAsync(FINAL_WAIT)

    test "Check timers consistency":
      var
        pass = true

      for i in 0..MAX_TIMERS:
        if not fastTimers[i].finished:
          debugEcho repr(fastTimers[i])
          pass = false
          break

      check pass
      check slowCnt[] == 0

if isMainModule:
  basicTimersMain()