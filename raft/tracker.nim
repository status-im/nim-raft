import types
import std/sequtils
import std/[times]

type
  RaftElectionResult* = enum
    Unknown = 0,
    Won = 1,
    Lost = 2

  RaftElectionTracker* = object
    all: seq[RaftNodeId]
    responded: seq[RaftNodeId]
    granted: int

  RaftVotes* = object
    voters*: seq[RaftNodeId]
    current: RaftElectionTracker

  RaftFollowerProgress = seq[RaftFollowerProgressTracker]

  RaftTracker* = object
    progress*: RaftFollowerProgress
    current: seq[RaftNodeId]
  
  RaftFollowerProgressTracker* = ref object
    id*: RaftNodeId
    nextIndex*: RaftLogIndex
    # Index of the highest log entry known to be replicated to this server.
    matchIndex*: RaftLogIndex
    commitIndex*: RaftLogIndex
    replayedIndex: RaftLogIndex
    lastMessageAt*: times.DateTime


func initElectionTracker*(nodes: seq[RaftNodeId]): RaftElectionTracker =
  var r = RaftElectionTracker()
  r.all = nodes
  r.granted = 0
  return r

func registerVote*(ret: var RaftElectionTracker, nodeId: RaftNodeId, granted: bool): bool =
  if not ret.all.contains nodeId:
    return false

  if not ret.responded.contains nodeId:
    ret.responded.add(nodeId)
    if granted:
      ret.granted += 1
  
  return true

func tallyVote*(ret: var RaftElectionTracker): RaftElectionResult =
  let quorym = int(len(ret.all) / 2) + 1
  if ret.granted >= quorym:
    return RaftElectionResult.Won
  let unkown = len(ret.all) - len(ret.responded)
  if  ret.granted + unkown >= quorym:
    return RaftElectionResult.Unknown
  else:
    return RaftElectionResult.Lost

func initVotes*(nodes: seq[RaftNodeId]): RaftVotes =
  var r = RaftVotes(voters: nodes, current: initElectionTracker(nodes))
  return r

func initVotes*(config: RaftConfig): RaftVotes =
  var r = RaftVotes(voters: config.currentSet, current: initElectionTracker(config.currentSet))
  return r

func registerVote*(rv: var RaftVotes, nodeId: RaftNodeId, granted: bool): bool =
  # TODO: Add support for configuration
  return rv.current.registerVote(nodeId, granted)

func tallyVote*(rv: var RaftVotes): RaftElectionResult =
  # TODO: Add support for configuration
  return rv.current.tallyVote()


func find*(ls: RaftTracker, id: RaftnodeId): Option[RaftFollowerProgressTracker] =
  for follower in ls.progress:
    if follower.id == id:
      return some(follower)
  return none(RaftFollowerProgressTracker)

func initFollowerProgressTracker*(follower: RaftNodeId, nextIndex: RaftLogIndex, now: times.DateTime): RaftFollowerProgressTracker =
  return RaftFollowerProgressTracker(id: follower, nextIndex: nextIndex, matchIndex: 0, commitIndex: 0, replayedIndex: 0, lastMessageAt: now)

func initTracker*(config: RaftConfig, nextIndex: RaftLogIndex, now: times.DateTime): RaftTracker =
  var tracker = RaftTracker()
  
  for node in config.currentSet:
    tracker.progress.add(initFollowerProgressTracker(node, nextIndex, now))
    tracker.current.add(node)
  return tracker

func accepted*(fpt: var RaftFollowerProgressTracker, index: RaftLogIndex)=
  fpt.matchIndex = max(fpt.matchIndex, index)
  fpt.nextIndex = max(fpt.nextIndex, index)