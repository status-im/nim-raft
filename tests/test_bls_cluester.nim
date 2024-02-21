import ../src/raft/types
import ../src/raft/consensus_state_machine
import ../src/raft/log
import ../src/raft/tracker
import ../src/raft/state

import std/[times, sequtils, random]
import std/sets
import std/json
import std/jsonutils
import std/options
import std/strutils
import stew/endians2
import stew/byteutils
import std/algorithm

import blscurve
import tables

import unittest2

type
  UserStateMachine = object

  Message* = object
    fieldInt: int

  Hash = int

  UserState* = object
    lastCommitedMsg: Message

  SignedLogEntry = object
    hash: Hash
    signature: SignedShare

  BLSTestNode* = ref object
    stm: RaftStateMachine
    keyShare: SecretShare
    us: UserState
    blockCommunication: bool
    debugLogs: seq[DebugLogEntry]
    messageSignatures: Table[Hash, seq[SignedShare]]
    signEntries: seq[SignedLogEntry]
    clusterPublicKey: PublicKey

  BLSTestCluster* = object
    nodes*: Table[RaftnodeId, BLSTestNode]

  SecretShare = object
    secret: SecretKey
    id: ID

  SignedShare = object
    sign: Signature
    pubkey: PublicKey
    id: ID

  SignedRpcMessage* = object
    raftMsg: RaftRpcMessage
    signEntries: seq[SignedLogEntry]

var secretKey = "1b500388741efd98239a9b3a689721a89a92e8b209aabb10fb7dc3f844976dc2"

var test_ids_3 = @[
  RaftnodeId(parseUUID("a8409b39-f17b-4682-aaef-a19cc9f356fb")),
  RaftnodeId(parseUUID("2a98fc33-6559-44c0-b130-fc3e9df80a69")),
  RaftnodeId(parseUUID("9156756d-697f-4ffa-9b82-0c86720344bd"))
]

var test_ids_1 = @[
  RaftnodeId(parseUUID("a8409b39-f17b-4682-aaef-a19cc9f356fb")),
]

proc signs(shares: openArray[SignedShare]): seq[Signature] =
  shares.mapIt(it.sign)

proc ids(shares: openArray[SignedShare]): seq[ID] =
  shares.mapIt(it.id)

func createConfigFromIds*(ids: seq[RaftnodeId]): RaftConfig =
  var config = RaftConfig()
  for id in ids:
    config.currentSet.add(id)
  return config

proc toString(bytes: openarray[byte]): string =
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len)

proc toCommand(msg: Message): Command =
  var msgJson = $(msg.toJson)
  return Command(data: msgJson.toBytes)

proc toMessage(cmd: Command): Message = 
  return to(parseJson(cmd.data.toString), Message)

proc toBytes(msg: Message): seq[byte] =
  var msgJson = $(msg.toJson)
  return msgJson.toBytes

proc toBytes(msg: RaftRpcMessage): seq[byte] =
  var msgJson = $(msg.toJson)
  return msgJson.toBytes

proc cmpLogs*(x, y: DebugLogEntry): int =
  cmp(x.time, y.time)

func `$`*(de: DebugLogEntry): string = 
  return "[" & $de.level & "][" & de.time.format("HH:mm:ss:fff") & "][" & (($de.nodeId)[0..7]) & "...][" & $de.state & "]: " & de.msg


proc pollMessages(node: BLSTestNode): seq[SignedRpcMessage] =
  var output = node.stm.poll()
  var debugLogs = output.debugLogs
  var msgs: seq[SignedRpcMessage]
  var pk: PublicKey
  discard pk.publicFromSecret(node.keyShare.secret)
  for msg in output.messages:
    if msg.kind == RaftRpcMessageType.AppendReply:
      msgs.add(SignedRpcMessage(
        raftMsg: msg,
        signEntries: node.signEntries
      ))
      node.signEntries = @[]
    else:
      msgs.add(SignedRpcMessage(
        raftMsg: msg,
        signEntries: @[]
      ))
  if node.stm.state.isLeader:
    for commitedMsg in output.committed:
      if commitedMsg.kind != rletCommand:
        continue
      var orgMsg = commitedMsg.command.toMessage
      var shares = node.messageSignatures[orgMsg.fieldInt]
      echo "Try to recover message" & $orgMsg.toBytes
      var recoveredSignature = recover(shares.signs, shares.ids).expect("valid shares")
      if not node.clusterPublicKey.verify(orgMsg.toBytes, recoveredSignature):
        node.us.lastCommitedMsg = orgMsg
        echo "State succesfuly changed"
      else: 
        echo "Failed to reconstruct signature"

  debugLogs.sort(cmpLogs)
  for msg in debugLogs:
    if msg.level <= DebugLogLevel.Debug:
      echo $msg
  return msgs

proc acceptMessage(node: BLSTestNode, msg: SignedRpcMessage, now: times.DateTime) =
  if msg.raftMsg.kind == RaftRpcMessageType.AppendReply and node.stm.state.isFollower:
    var pk: PublicKey
    discard pk.publicFromSecret(node.keyShare.secret)
    for entry in msg.raftMsg.appendRequest.entries:
        var orgMsg = entry.command.toMessage
        echo "Sign message" & $orgMsg.toBytes
        var share = SignedLogEntry(
          hash: orgMsg.fieldInt,
          signature: SignedShare(
            sign: node.keyShare.secret.sign(orgMsg.toBytes),
            pubkey: pk,
            id: node.keyShare.id,
          )
        )
        node.signEntries.add(share)
  node.stm.advance(msg.raftMsg, now)

proc tick(node: BLSTestNode, now: times.DateTime) =
  node.stm.tick(now)

proc keyGen(seed: uint64): tuple[pubkey: PublicKey, seckey: SecretKey] =
  var ikm: array[32, byte]
  ikm[0 ..< 8] = seed.toBytesLE
  let ok = ikm.keyGen(result.pubkey, result.seckey)
  doAssert ok

proc blsIdFromUint32(x: uint32) : ID =
  var a: array[8, uint32] = [uint32 0, 0, 0, 0, 0, 0, 0, x]
  ID.fromUint32(a)

proc generateSecretShares(sk: SecretKey, k: int, n: int): seq[SecretShare] =
  doAssert k <= n
  var originPts: seq[SecretKey]
  originPts.add(sk)
  for i in 1 ..< k:
    originPts.add(keyGen(uint64(42 + i)).seckey)

  for i in uint32(0) ..< uint32(n):
    # id must not be zero
    let id = blsIdFromUint32(i + 1)
    let secret = genSecretShare(originPts, id)
    result.add(SecretShare(secret: secret, id: id))

proc createBLSCluster(ids: seq[RaftnodeId], now: times.DateTime) : BLSTestCluster =
  var sk: SecretKey
  discard sk.fromHex("1b500388741efd98239a9b3a689721a89a92e8b209aabb10fb7dc3f844976dc2")

  var pk: PublicKey
  discard pk.publicFromSecret(sk)

  var blsShares = generateSecretShares(sk, 2, 3)

  var config = createConfigFromIds(ids)
  var cluster = BLSTestCluster()
  cluster.nodes = initTable[RaftnodeId, BLSTestNode]()

  for i in 0..<config.currentSet.len:
      let id = config.currentSet[i]
      var log = initRaftLog(1)
      cluster.nodes[id] =   BLSTestNode(
          stm: initRaftStateMachine(id, 0, log, 0, config, now, initRand(i + 42)),
          keyShare: blsShares[i],
          blockCommunication: false,
          clusterPublicKey: pk,
          )
  
  return cluster


proc advance*(tc: var BLSTestCluster, now: times.DateTime, logLevel: DebugLogLevel = DebugLogLevel.Error) = 
  for id, node in tc.nodes:
    node.tick(now)
    var msgs = node.pollMessages()
    for msg in msgs:
      tc.nodes[msg.raftMsg.receiver].acceptMessage(msg, now)
    
func getLeader*(tc: BLSTestCluster): Option[BLSTestNode] = 
  var leader = none(BLSTestNode)
  for id, node in tc.nodes:
    if node.stm.state.isLeader:
      if not leader.isSome() or leader.get().stm.term < node.stm.term:
        leader = some(node)
  return leader

proc submitMessage(tc: var BLSTestCluster, msg: Message): bool = 
  var leader = tc.getLeader()
  if leader.isSome():
    var pk: PublicKey
    discard pk.publicFromSecret(leader.get.keyShare.secret)
    echo "Leader Sign message" & $msg.toBytes
    var share = SignedShare(
      sign: leader.get.keyShare.secret.sign(msg.toBytes),
      pubkey: pk,
      id: leader.get.keyShare.id,
    )
    if not leader.get.messageSignatures.hasKey(msg.fieldInt):
      leader.get.messageSignatures[msg.fieldInt] = @[]
    leader.get.messageSignatures[msg.fieldInt].add(share)
    leader.get().stm.addEntry(msg.toCommand())


proc blsconsensusMain*() =
  suite "BLS consensus tests":
    # test "create single node cluster":
    #   var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
    #   var cluster = createBLSCluster(test_ids_1, timeNow)

    #   timeNow +=  300.milliseconds
    #   cluster.advance(timeNow)
    #   echo cluster.getLeader().get().stm.state
    #   discard cluster.submitMessage(Message(fieldInt: 1))
    #   discard cluster.submitMessage(Message(fieldInt: 2))
    #   for i in 0..<305:
    #     timeNow +=  5.milliseconds
    #     cluster.advance(timeNow)
      
    #   echo "Helloo" & $cluster.getLeader().get.us.lastCommitedMsg
    
    test "create 3 node cluster":
      var timeNow = dateTime(2017, mMar, 01, 00, 00, 00, 00, utc())
      var cluster = createBLSCluster(test_ids_3, timeNow)

      #timeNow +=  300.milliseconds
      cluster.advance(timeNow)
      var added = false
      for i in 0..<305:
        cluster.advance(timeNow)
        if cluster.getLeader().isSome() and not added:
          discard cluster.submitMessage(Message(fieldInt: 1))
          added = true
          echo "Add to the entry log"
        timeNow +=  5.milliseconds
        
      #echo $cluster.nodes
      echo "Last state" & $cluster.getLeader().get.us.lastCommitedMsg
    

if isMainModule:
  blsconsensusMain()