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

proc raftPipesRead[SmCommandType, SmStateType](node: BasicRaftNode, port: int) =
  var
    fifoRead = fmt"RAFTNODERECEIVEMSGPIPE{port}"
    fifoWrite = fmt"RAFTNODESENDMSGRESPPIPE{port}"
    frFD = open(fifoRead, fmRead)
    fwFD = open(fifoWrite, fmAppend)

  var
    ss = MsgStream.init(frFD.readAll)
    xx: RaftMessage[SmCommandType, SmStateType]

  ss.unpack(xx) #and here too

  debug "Received Req: ", req=repr(xx)

  var
    r = waitFor raftNodeMessageDeliver(node, xx)
    resp = RaftMessageResponse[SmCommandType, SmStateType](r)
    rs = MsgStream.init()

  rs.pack(resp)
  fwFD.write(rs.data)

proc testRaftMessageSendCallbackCreate[SmCommandType, SmStateType](conf: RaftPeersConfContainer): RaftMessageSendCallback[SmCommandType, SmStateType] =
  proc (msg: RaftMessageBase[SmCommandType, SmStateType]): Future[RaftMessageResponseBase[SmCommandType, SmStateType]] {.async, gcsafe.} =
    var
      host: string
      port: int
      resp: Response
      xx: RaftMessageResponse[SmCommandType, SmStateType]
      client = newHttpClient(timeout=50)
      m = RaftMessage[SmCommandType, SmStateType](msg)
      s = MsgStream.init() # besides MsgStream, you can also use Nim StringStream or FileStream

    for c in conf:
      if c.id == msg.receiverId:
        host = c.host
        port = c.port

    s.pack(m) #here the magic happened
    debug "Sending Req: ", req=fmt"http://{host}:{port}", data=s.data
    resp = client.post(fmt"http://{host}:{port}", s.data)

    s = MsgStream.init(resp.body)
    s.unpack(xx) #and here too
    result = xx

proc main() =
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
  node = BasicRaftNode.new(nodeId, peersIds, testRaftMessageSendCallbackCreate[SmCommand, SmState](conf))

  raftNodeStart(node)
  spawn raftPipesRead[SmCommand, SmState](node, port)
  runForever()

if isMainModule:
  main()