import basic_state_machine
import basic_cluster

import std/json
import msgpack4nim
import strutils
import std/strformat
import httpclient
import os
import std/threadpool

type
  RaftPeerConf* = object
    id*: UUID
    host*: string
    port*: int

  RaftPeersConfContainer* = seq[RaftPeerConf]

proc loadConfig(): RaftPeersConfContainer =
  var
    conf: RaftPeersConfContainer

  let jsonFile = "raft_node_config.json"
  # read and parse file
  let jsConf = parseFile(jsonFile)
  for n in jsConf["raftPeers"]:
    conf.add(RaftPeerConf(id: parseUUID(n["id"].getStr), host: n["host"].getStr, port: n["port"].getInt))
  result = conf

proc RaftPipesRead(node: BasicRaftNode, port: int) =
  var
    fifoRead = fmt"RAFTNODERECEIVEMSGPIPE{port}"
    fifoWrite = fmt"RAFTNODESENDMSGRESPPIPE{port}"
    frFD = open(fifoRead, fmRead)
    fwFD = open(fifoWrite, fmAppend)

  var
    ss = MsgStream.init(frFD.readAll)
    xx: RaftMessageBase

  ss.unpack(xx) #and here too

  debug "reqqqq: ", req=repr(xx)

  var
    r = waitFor RaftNodeMessageDeliver(node, RaftMessageRequestVote(xx))
    rs = MsgStream.init()

  rs.pack(r)
  fwFD.write(rs.data)

proc TestRaftMessageSendCallbackCreate(conf: RaftPeersConfContainer): RaftMessageSendCallback =
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

    debug "req: ", req=fmt"http://{host}:{port}", data=s.data
    var
      resp = client.post(fmt"http://{host}:{port}", s.data)
    echo resp.status

    var
      ss = MsgStream.init(resp.body)
      xx: RaftMessageResponseBase

    ss.unpack(xx) #and here too
    result = xx

proc main() {.async.} =
  var conf = loadConfig()

  var
    nodesIds: seq[UUID]
    node: BasicRaftNode

  for c in conf:
    debug "single conf", single_conf=c
    nodesIds.add(c.id)

  var
    nodeId = parseUUID(paramStr(1))
    peersIds = nodesIds
    port: int
    idx = peersIds.find(nodeId)
  port = conf[idx].port
  peersIds.del(idx)

  node = BasicRaftNode.new(nodeId, peersIds, TestRaftMessageSendCallbackCreate(conf))
  RaftNodeStart(node)
  spawn RaftPipesRead(node, port)

if isMainModule:
  waitFor main()
  runForever()