# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

mode = ScriptMode.Verbose

packageName   = "raft"
version       = "0.0.1"
author        = "Status Research & Development GmbH"
description   = "raft consensus in nim"
license       = "Apache License 2.0"
skipDirs      = @["tests"]

requires "nim >= 1.6.0"
requires "stew >= 0.1.0"
requires "unittest2 >= 0.0.4"
requires "uuid4 >= 0.9.3"

# Helper functions