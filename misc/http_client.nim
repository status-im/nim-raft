# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import asyncdispatch, httpclient

proc nonAsyncHttp() =
    var client = newHttpClient()
    echo "Non async started"
    for i in 0 .. 30:
        let resp = client.get("http://example.com")
        echo resp.status
    echo "Non async finished"

proc asyncHttp() {.async.} =
    var client = newAsyncHttpClient()
    echo "Async started"
    for i in 0 .. 30:
        let resp = await client.get("http://example.com")
        echo resp.status
    echo "Async finished"


waitFor asyncHttp()
nonAsyncHttp()
