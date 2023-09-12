import basic_state_machine
import basic_cluster

import std/json
import msgpack4nim
import strutils
import std/strformat
import httpclient

type
  RaftPeerConf* = object
    id*: UUID
    host*: string
    port*: int

  RaftPeersConfContainer* = seq[RaftPeerConf]

var
  conf: RaftPeersConfContainer

proc loadConfig() =
  let jsonFile = "raft_node_config.json"
  # read and parse file
  let jsConf = parseFile(jsonFile)
  for n in jsConf["raftPeers"]:
    conf.add(RaftPeerConf(id: parseUUID(n["id"].astToStr), host: n["host"].astToStr, port: parseInt(n["port"].astToStr)))
    debug "Conf", conf=conf
  info "Conf", config=repr(conf)

proc TestRaftMessageSendCallbackCreate(): RaftMessageSendCallback =
  proc (msg: RaftMessageBase): Future[RaftMessageResponseBase] {.async, gcsafe.} =
    var
      host: string
      port: int
    for c in conf:
      if c.id == msg.receiverId:
        host = c.host
        port = c.port
    var
      client = newHttpClient()
      s = MsgStream.init() # besides MsgStream, you can also use Nim StringStream or FileStream

    s.pack(msg) #here the magic happened

    var
      resp = client.post(fmt"http://{host}:{port}", s.data)

    echo resp.status

    var
      ss = MsgStream.init(resp.body)
      xx: RaftMessageResponseBase

    ss.unpack(xx) #and here too
    result = xx

if isMainModule:
  loadConfig()
  var
    nodesIds: seq[UUID]
    node: BasicRaftNode

  for c in conf:
    debug "single conf", single_conf=c
    nodesIds.add(c.id)

  var
    nodeId = parseUUID("f9695ea4-4f37-11ee-8e75-8ff5a48faa42")
    peersIds = nodesIds

  peersIds.del(peersIds.find(nodeId))

  node = BasicRaftNode.new(nodeId, peersIds, TestRaftMessageSendCallbackCreate())