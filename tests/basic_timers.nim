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
import uuids

export asyncdispatch

var
  pollThr: Thread[void]
  runningMtx: Lock
  running: bool

  timersChan: seq[RaftTimer]
  timersChanMtx: Lock

proc RaftTimerCreateCustomImpl*(timerInterval: int, oneshot: bool, timerCallback: RaftTimerCallback): RaftTimer {.nimcall, gcsafe.} =
  var
    timer = RaftTimer(mtx: Lock(), canceled: false, expired: false, timeout: timerInterval, oneshot: oneshot)

  initLock(timer.mtx)

  addTimer(timer.timeout, timer.oneshot, proc (fd: AsyncFD): bool {.closure, gcsafe.} =
    withLock(timer.mtx):
      if not timer.canceled:
        timerCallback(timer)
        if timer.oneshot:
          timer.expired = true
          return true
        else:
          return false
      else:
        return true
  )
  timer

proc RaftTimerCancelCustomImpl*(timer: RaftTimer): bool {.nimcall, gcsafe, discardable.} =
  withLock(timer.mtx):
    if not timer.expired and not timer.canceled:
      timer.canceled = true
    else:
      return false

proc RaftTimerPollThread() {.thread, nimcall, gcsafe.} =
  while running:
    try:
      poll()
    except ValueError as e:
      # debugEcho e.msg
      # Add a 'dummy' timer if no other handles are present to prevent more
      # ValueError exceptions this is a workaround for a asyncdyspatch bug
      # see - https://github.com/nim-lang/Nim/issues/14564
      addTimer(1, false, proc (fd: AsyncFD): bool {.closure, gcsafe.} = false)

proc RaftTimerJoinPollThread*() {.nimcall, gcsafe.} =
  joinThread(pollThr)

proc RaftTimerStartCustomImpl*(joinThread: bool = true) {.nimcall, gcsafe.} =
  withLock(runningMtx):
    running = true
  createThread(pollThr, RaftTimerPollThread)
  if joinThread:
    RaftTimerJoinPollThread()

proc RaftTimerStopCustomImpl*(joinThread: bool = true) {.nimcall, gcsafe.} =
  withLock(runningMtx):
    running = false
  if joinThread:
    RaftTimerJoinPollThread()