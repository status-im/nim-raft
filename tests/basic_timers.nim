# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import ../raft/raft_api

export raft_api

proc raftTimerCreateCustomImpl*(timerInterval: int, timerCallback: RaftTimerCallback): Future[void] {.async.} =
  var f = sleepAsync(milliseconds(timerInterval))
  await f
  if f.finished and not f.cancelled:
    timerCallback()