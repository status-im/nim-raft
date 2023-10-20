# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import unittest2
import basic_cluster

proc basicClusterElectionMain*() =
  var
    cluster: BasicRaftCluster
    nodesIds = newSeq[RaftNodeId](5)

  suite "Basic Raft Cluster Election Tests":

    test "Basic Raft Cluster Init (5 nodes)":
      for i in 0..4:
        nodesIds[i] = genUUID()
      cluster = basicRaftClusterInit(nodesIds, 150, 150, 20, 20, 10)
      check cluster != nil

    test "Start Basic Raft Cluster and wait it to converge for a 2 seconds interval (Elect a Leader)":
      basicRaftClusterStart(cluster)
      let dur = seconds(2)
      waitFor sleepAsync(dur)
      let
        leaderId = basicRaftClusterGetLeaderId(cluster)
      check leaderId != DefaultUUID

    test "Check for leader every second for a 10 second interval":
      let dur = seconds(1)
      for i in 0..117:
        waitFor sleepAsync(dur)
        let
          leaderId = basicRaftClusterGetLeaderId(cluster)
        check leaderId != DefaultUUID

if isMainModule:
  basicClusterElectionMain()