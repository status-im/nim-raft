# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import basic_timers
import basic_state_machine

export raft_api

type
  BasicRaftNode* = RaftNode[SmCommand, SmState]

  BasicRaftCluster* = ref object
    nodes*: seq[BasicRaftNode]

proc BasicRaftClusterRaftMessageSendCallbackCreate(cluster: BasicRaftCluster): RaftMessageSendCallback =
  proc (msg: RaftMessageBase): RaftMessageResponseBase {.closure.} =
    var
      nodeIdx: int = -1

    for i in 0..cluster.nodes.len:
      if RaftNodeIdGet(cluster.nodes[i]) == msg.receiverId:
        nodeIdx = i
        break

    cluster.nodes[nodeIdx].RaftNodeMessageDeliver(msg)

proc BasicRaftClusterStart*(cluster: BasicRaftCluster) =
  for node in cluster.nodes:
    RaftNodeStart(node)

proc BasicRaftClusterGetLeader*(cluster: BasicRaftCluster): UUID =
  result = DefaultUUID
  for node in cluster.nodes:
    if RaftNodeIsLeader(node):
      return RaftNodeIdGet(node)

proc BasicRaftClusterClientRequest*(cluster: BasicRaftCluster, req: RaftNodeClientRequest): RaftNodeClientResponse =
  discard

proc BasicRaftClusterInit*(nodesIds: seq[RaftNodeId]): BasicRaftCluster =
  new(result)
  for nodeId in nodesIds:
    var
      peersIds = nodesIds

    peersIds.del(peersIds.find(nodeId))
    result.nodes.add(BasicRaftNode.new(nodeId, peersIds, BasicRaftClusterRaftMessageSendCallbackCreate(result)))

