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

requires "nim >= 1.6.14"
requires "stew >= 0.1.0"
requires "unittest2 >= 0.0.4"
requires "uuids >= 0.1.11"
requires "chronicles >= 0.10.3"
requires "chronos >= 3.0.11"

proc buildBinary(name: string, srcDir = "./", params = "", lang = "c") =
  if not dirExists "build":
    mkDir "build"
  # allow something like "nim nimbus --verbosity:0 --hints:off nimbus.nims"
  var extra_params = params
  for i in 2..<paramCount():
    extra_params &= " " & paramStr(i)
  exec "nim " & lang & " --threads:on " & extra_params & " --out:build/" & name & " " & srcDir & name & ".nim"

proc test(path: string, name: string, params = "", lang = "c") =
  # Verify stack usage is kept low by setting 750k stack limit in tests.
  const stackLimitKiB = 750
  when not defined(windows):
    const (buildOption, runPrefix) = ("", "ulimit -s " & $stackLimitKiB & " && ")
  else:
    # No `ulimit` in Windows.  `ulimit -s` in Bash is accepted but has no effect.
    # See https://public-inbox.org/git/alpine.DEB.2.21.1.1709131448390.4132@virtualbox/
    # Also, the command passed to NimScript `exec` on Windows is not a shell script.
    # Instead, we can set stack size at link time.
    const (buildOption, runPrefix) =
      (" -d:windowsNoSetStack --passL:-Wl,--stack," & $(stackLimitKiB * 2048), "")

  buildBinary name, (path & "/"), params & buildOption
  exec runPrefix & "build/" & name

task test, "Run tests":
  test "tests", "all_tests", "-d:chronicles_sinks=textlines -d:chronicles_log_level=ERROR -d:unittest2DisableParamFiltering"


# Helper functions