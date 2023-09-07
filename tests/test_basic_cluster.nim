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

proc basicClusterMain*() =
  var
    cluster: BasicRaftCluster
    nodesIds = newSeq[RaftNodeId](5)

  suite "Basic Raft Cluster Tests":

    test "Basic Raft Cluster Init (5 nodes)":
      for i in 0..4:
        nodesIds[i] = genUUID()

      cluster = BasicRaftClusterInit(nodesIds)

    test "Generate Random Client SmCommands Queue":
      discard

    test "Start Basic Raft Cluster And wait it to converge (Elect a Leader)":
      BasicRaftClusterStart(cluster)
      let dur = seconds(60)
      waitFor sleepAsync(dur)

    test "Simulate Basic Raft Cluster Client SmCommands Execution / Log Replication":
      discard

    test "Evaluate results":
      discard

if isMainModule:
  basicClusterMain()