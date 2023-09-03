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
    nodes*: Table[RaftNodeId, BasicRaftNode]

proc BasicRaftClusterRaftMessageSendCallbackCreate(cluster: BasicRaftCluster): RaftMessageSendCallback =
  proc (msg: RaftMessageBase): Future[RaftMessageResponseBase] {.async, gcsafe.} =
    var
      nodeIdx: int = -1

    result = await cluster.nodes[msg.receiverId].RaftNodeMessageDeliver(msg)

proc BasicRaftClusterStart*(cluster: BasicRaftCluster) =
  for id, node in cluster.nodes:
    RaftNodeStart(node)

proc BasicRaftClusterGetLeader*(cluster: BasicRaftCluster): UUID =
  result = DefaultUUID
  for id, node in cluster.nodes:
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
    result.nodes[nodeId] = BasicRaftNode.new(nodeId, peersIds, BasicRaftClusterRaftMessageSendCallbackCreate(result))

