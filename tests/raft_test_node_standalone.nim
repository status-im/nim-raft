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

proc loadConfig(): RaftPeersConfContainer =
  var
    conf: RaftPeersConfContainer

  let jsonFile = "raft_node_config.json"
  # read and parse file
  let jsConf = parseFile(jsonFile)
  for n in jsConf["raftPeers"]:
    conf.add(RaftPeerConf(id: parseUUID(n["id"].getStr), host: n["host"].getStr, port: n["port"].getInt))
  result = conf

proc RaftPipesRead(node: BasicRaftNode, port: int) {.async.}=
  var
    fifoRead = fmt"RAFTNODERECEIVEMSGPIPE{port}"
    fifoWrite = fmt"RAFTNODESENDMSGRESPPIPE{port}"
    frFD = open(fifoRead, fmRead)
    fwFD = open(fifoWrite, fmAppend)

  var
    ss = MsgStream.init(frFD.readAll)
    xx: RaftMessageBase

  ss.unpack(xx) #and here too

  var
    r: RaftMessageResponseBase = await RaftNodeMessageDeliver(node, xx)
    rs = MsgStream.init()

  rs.pack(r)
  fwFD.write(rs.data)

proc TestRaftMessageSendCallbackCreate(conf: RaftPeersConfContainer, node: BasicRaftNode, port: int): RaftMessageSendCallback =
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

    await RaftPipesRead(node, port)

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
    nodeId = parseUUID("0edc0976-4f38-11ee-b1ad-5b3b0f690e65")
    peersIds = nodesIds
    port: int
    idx = peersIds.find(nodeId)
  port = conf[idx].port
  peersIds.del(idx)

  node = BasicRaftNode.new(nodeId, peersIds, TestRaftMessageSendCallbackCreate(conf, node, port))
  RaftNodeStart(node)

if isMainModule:
  waitFor main()
  runForever()