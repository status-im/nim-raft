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
import std/tables

export raft_api

type
  BasicRaftNode* = RaftNode[SmCommand, SmState]

  BasicRaftCluster* = ref object
    nodes*: Table[RaftNodeId, BasicRaftNode]
    nodesLock*: RLock
    networkDelay*: int

proc basicRaftClusterRaftMessageSendCallbackCreate[SmCommandType, SmStateType](cluster: BasicRaftCluster): RaftMessageSendCallback[SmCommandType, SmStateType] =
  proc (msg: RaftMessageBase[SmCommandType, SmStateType]): Future[RaftMessageResponseBase[SmCommandType, SmStateType]] {.async, gcsafe.} =
    await raftTimerCreate(rand(cluster.networkDelay), proc()=discard)     # Simulate network delay
    result = await cluster.nodes[msg.receiverId].raftNodeMessageDeliver(msg)

proc basicRaftClusterStart*(cluster: BasicRaftCluster) =
  for id, node in cluster.nodes:
    raftNodeStart(node)

proc basicRaftClusterGetLeaderId*(cluster: BasicRaftCluster): UUID =
  result = DefaultUUID
  withRLock(cluster.nodesLock):
    for id, node in cluster.nodes:
      if raftNodeIsLeader(node):
        return raftNodeIdGet(node)

proc basicRaftClusterClientRequest*(cluster: BasicRaftCluster, req: RaftNodeClientRequest): Future[RaftNodeClientResponse] {.async.} =
  case req.op:
    of rncroRequestSmState:
      var
        nodeId = cluster.nodesIds[basicRaftClusterGetLeaderId(cluster)]

      result = await cluster.nodes[nodeId].raftNodeServeClientRequest(req)

    of rncroExecSmCommand:
      discard

proc basicRaftClusterInit*(nodesIds: seq[RaftNodeId], networkDelay: int=25, electionTimeout: int=150, heartBeatTimeout: int=150, appendEntriesRespTimeout: int=20, votingRespTimeout: int=20,
                           heartBeatRespTimeout: int=10): BasicRaftCluster =
  new(result)
  for nodeId in nodesIds:
    var
      peersIds = nodesIds

    peersIds.del(peersIds.find(nodeId))
    result.networkDelay = networkDelay
    result.nodes[nodeId] = BasicRaftNode.new(nodeId, peersIds,
                                             basicRaftClusterRaftMessageSendCallbackCreate[SmCommand, SmState](result),
                                             electionTimeout, heartBeatTimeout, appendEntriesRespTimeout, votingRespTimeout, heartBeatRespTimeout)

