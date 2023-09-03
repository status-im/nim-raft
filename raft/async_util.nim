# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import asyncdispatch
import std/times

template awaitWithTimeout[T](operation: Future[T],
                              deadline: Future[void],
                              onTimeout: untyped): T =
  let f = operation
  await f or deadline
  if not f.finished:
    # If we don't wait for for the cancellation here, it's possible that
    # the "next" operation will run concurrently to this one, messing up
    # the order of operations (since await/async is not fair)
    await cancelAndWait(f)
    onTimeout
  else:
    f.read

template awaitWithTimeout[T](operation: Future[T],
                              timeout: Duration,
                              onTimeout: untyped): T =
  awaitWithTimeout(operation, sleepAsync(timeout), onTimeout)

template awaitWithTimeout(operation: Future[void],
                           deadline: Future[void],
                           onTimeout: untyped) =
  let f = operation
  await f or deadline
  if not f.finished:
    # If we don't wait for for the cancellation here, it's possible that
    # the "next" operation will run concurrently to this one, messing up
    # the order of operations (since await/async is not fair)
    await cancelAndWait(f)
    onTimeout

template awaitWithTimeout(operation: Future[void],
                           timeout: Duration,
                           onTimeout: untyped) =
  awaitWithTimeout(operation, sleepAsync(timeout), onTimeout)