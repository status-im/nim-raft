# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

func vmName(): string =
  when defined(evmc_enabled):
    "evmc"
  else:
    "nimvm"

const
  VmName* = vmName()
  warningMsg = block:
    var rc = "*** Compiling with " & VmName
    when defined(legacy_eth66_enabled):
      rc &= ", legacy-eth/66"
    when defined(chunked_rlpx_enabled):
      rc &= ", chunked-rlpx"
    when defined(boehmgc):
      rc &= ", boehm/gc"
    rc &= " enabled"
    rc

{.warning: warningMsg.}

{.used.}
