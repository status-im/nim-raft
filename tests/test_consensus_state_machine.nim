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
import basic_state_machine
import ../raft/consensus_state_machine

suite "Create and test Consensus State Machine":

  test "Create Consensus State Machine":
    var
      csm = ConsensusFsm[RaftNodeState, EventType, RaftNode[SmCommand, SmState], RaftMessageBase[SmCommand, SmState]].new(rnsFollower)

    check csm != nil