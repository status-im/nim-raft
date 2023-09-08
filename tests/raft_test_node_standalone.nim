import ../raft
import basic_state_machine
import std/json
import uuids
import chronicles

type
  RaftPeerConf = object
    id: UUID
    host: string
    port: int

  RaftPeersConfContainer = seq[RaftPeerConf]

var
  conf: RaftPeersConfContainer

proc loadConfig() =
  let jsonFile = "raft_node_config.json"
  # read and parse file
  let jsConf = parseFile(jsonFile)
  for n in jsConf["raftPeers"]:
    conf.add(RaftPeerConf(id: parseUUID(n["id"].astToStr), host: n["host"].astToStr, port: int(n["port"].astToStr)))
  info "Conf", config=repr(conf)

if isMainModule:
  var node = RaftNode[SmCommand, SmState].new()