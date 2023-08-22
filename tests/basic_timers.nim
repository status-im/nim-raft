# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/asyncdispatch
import std/locks
import ../raft/types

export asyncdispatch

var
  pollThr: Thread[void]
  runningMtx: Lock
  running: bool

proc RaftTimerCreateCustomImpl*(timerInterval: int, repeat: bool, timerCallback: RaftTimerCallback): RaftTimer =
  var
    timer = RaftTimer(canceled: false, expired: false, timeout: timerInterval, repeat: repeat)
  initLock(timer.mtx)

  proc CallbackClosureProc(): Callback =
    result = proc (fd: AsyncFD): bool {.closure, gcsafe.} =
      withLock(timer.mtx):
        if not timer.canceled:
          timerCallback(timer)
          if not timer.repeat:
            timer.expired = true
          return true
        else:
          return false

  debugEcho repr(CallbackClosureProc())
  addTimer(timer.timeout, timer.repeat, CallbackClosureProc())
  timer

proc RaftTimerCancelCustomImpl*(timer: var RaftTimer): bool {.discardable.} =
    withLock(timer.mtx):
      if not timer.expired and not timer.canceled:
        timer.canceled = true
        return true
      else:
        return false

proc RaftTimerPollThread() {.thread, nimcall, gcsafe.} =
  while running:
    try:
      poll()
    except ValueError as e:
      debugEcho e.msg

proc RaftTimerJoinPollThread*() =
  joinThread(pollThr)

proc RaftTimerStartCustomImpl*(joinThread: bool = true) =
  withLock(runningMtx):
    running = true
  createThread(pollThr, RaftTimerPollThread)
  if joinThread:
    RaftTimerJoinPollThread()

proc RaftTimerStopCustomImpl*(joinThread: bool = true) =
  withLock(runningMtx):
    running = false
  if joinThread:
    RaftTimerJoinPollThread()