import types
import config
import std/[times]
import std/algorithm
import std/strformat

type
  RaftElectionResult* = enum
    Unknown = 0
    Won = 1
    Lost = 2

  RaftElectionTracker* = object
    all: seq[RaftNodeId]
    responded: seq[RaftNodeId]
    granted: int

  RaftVotes* = object
    voters*: seq[RaftNodeId]
    current*: RaftElectionTracker
    previous*: Option[RaftElectionTracker]

  RaftFollowerProgress = seq[RaftFollowerProgressTrackerRef]

  RaftTracker* = ref object
    progress*: RaftFollowerProgress
    current*: seq[RaftNodeId]
    previous*: seq[RaftNodeId]

  RaftFollowerProgressTrackerRef* = ref object
    id*: RaftNodeId
    nextIndex*: RaftLogIndex
    # Index of the highest log entry known to be replicated to this server.
    matchIndex*: RaftLogIndex
    commitIndex*: RaftLogIndex
    replayedIndex: RaftLogIndex
    lastMessageAt*: times.DateTime

  MatchSeqRef = ref object
    match: seq[RaftLogIndex]
    count: int
    previousCommitIndex: RaftLogIndex

func new(T: type MatchSeqRef, previousCommitIndex: RaftLogIndex): T =
  T(previousCommitIndex: previousCommitIndex, count: 0)

func add(ms: var MatchSeqRef, index: RaftLogIndex) =
  if index > ms.previousCommitIndex:
    ms.count += 1
  ms.match.add(index)

func committed(ms: var MatchSeqRef): bool =
  ms.count >= int(ms.match.len / 2) + 1

func commitIndex(ms: var MatchSeqRef): RaftLogIndex =
  var p = int((ms.match.len - 1) / 2)
  var matchCopy = ms.match
  matchCopy.sort()
  matchCopy[p]

func init*(T: type RaftElectionTracker, nodes: seq[RaftNodeId]): T =
  RaftElectionTracker(all: nodes, granted: 0)

func registerVote*(
    ret: var RaftElectionTracker, nodeId: RaftNodeId, granted: bool
): bool =
  if not ret.all.contains(nodeId):
    return false

  if not ret.responded.contains(nodeId):
    ret.responded.add(nodeId)
    if granted:
      ret.granted += 1

  true

func tallyVote*(ret: var RaftElectionTracker): RaftElectionResult =
  let quorum = int(len(ret.all) / 2) + 1
  if ret.granted >= quorum:
    return RaftElectionResult.Won
  let unknown = len(ret.all) - len(ret.responded)
  if ret.granted + unknown >= quorum:
    return RaftElectionResult.Unknown
  RaftElectionResult.Lost

func contains(ret: var RaftElectionTracker, id: RaftNodeId): bool =
  ret.all.contains(id)

func init*(T: type RaftVotes, config: RaftConfig): T =
  let allNodes = config.currentSet & config.previousSet
  var r = T(voters: allNodes, current: RaftElectionTracker.init(config.currentSet))
  if config.isJoint:
    r.previous = some(RaftElectionTracker.init(config.previousSet))
  r

proc `=copy`*(d: var RaftVotes, src: RaftVotes) {.error.} =
  discard

func registerVote*(rv: var RaftVotes, nodeId: RaftNodeId, granted: bool): bool =
  var success = rv.current.registerVote(nodeId, granted)
  if rv.previous.isSome:
    success = success or rv.previous.get().registerVote(nodeId, granted)
  success

func tallyVote*(rv: var RaftVotes): RaftElectionResult =
  # TODO: Add support for configuration
  if rv.previous.isSome:
    var electionResult = rv.previous.get.tallyVote()
    if electionResult != RaftElectionResult.Won:
      return electionResult
  rv.current.tallyVote()

func contains*(rv: var RaftVotes, id: RaftNodeId): bool =
  if rv.current.contains(id):
    return true
  rv.previous.isSome and rv.previous.get.contains(id)

func find*(ls: RaftTracker, id: RaftNodeId): Option[RaftFollowerProgressTrackerRef] =
  for follower in ls.progress:
    if follower.id == id:
      return some(follower)
  none(RaftFollowerProgressTrackerRef)

func new*(
    T: type RaftFollowerProgressTrackerRef,
    follower: RaftNodeId,
    nextIndex: RaftLogIndex,
    now: times.DateTime,
): T =
  T(
    id: follower,
    nextIndex: nextIndex,
    matchIndex: 0,
    commitIndex: 0,
    replayedIndex: 0,
    lastMessageAt: now,
  )

func new*(
    T: type RaftFollowerProgressTrackerRef,
    follower: RaftNodeId,
    nextIndex: RaftLogIndex,
): T =
  T(id: follower, nextIndex: nextIndex, matchIndex: 0, commitIndex: 0, replayedIndex: 0)

func find(s: var RaftFollowerProgress, what: RaftNodeId): int =
  for i, x in s:
    if x.id == what:
      return i
  -1

func setConfig*(
    tracker: var RaftTracker,
    config: RaftConfig,
    nextIndex: RaftLogIndex,
    now: times.DateTime,
) =
  tracker.current = @[]
  tracker.previous = @[]

  var oldProgress = tracker.progress
  tracker.progress = @[]

  for s in config.currentSet:
    # TODO: Add can_vote prop
    tracker.current.add(s)
    let oldp = oldProgress.find(s)
    if oldp != -1:
      tracker.progress.add(oldProgress[oldp])
    else:
      let progress = RaftFollowerProgressTrackerRef.new(s, nextIndex, now)
      tracker.progress.add(progress)

  if config.isJoint:
    for s in config.previousSet:
      tracker.previous.add(s)
      var newp = tracker.progress.find(s)
      if newp != -1:
        # It already exists in the current set
        continue
      let oldp = oldProgress.find(s)
      if oldp != -1:
        tracker.progress.add(oldProgress[oldp])
      else:
        tracker.progress.add(RaftFollowerProgressTrackerRef.new(s, nextIndex, now))

func init*(
    T: type RaftTracker,
    config: RaftConfig,
    nextIndex: RaftLogIndex,
    now: times.DateTime,
): T =
  var tracker = T()
  tracker.setConfig(config, nextIndex, now)
  tracker

func committed*(tracker: RaftTracker, previousCommitIndex: RaftLogIndex): RaftLogIndex =
  var current = MatchSeqRef.new(previousCommitIndex)
  if tracker.previous.len != 0:
    var previous = MatchSeqRef.new(previousCommitIndex)
    for progress in tracker.progress:
      if tracker.current.contains(progress.id):
        current.add(progress.matchIndex)
      if tracker.previous.contains(progress.id):
        previous.add(progress.matchIndex)
    if not current.committed() or not previous.committed():
      return previousCommitIndex
    return min(current.commitIndex(), previous.commitIndex())
  else:
    for progress in tracker.progress:
      if tracker.current.contains(progress.id):
        current.add(progress.matchIndex)
    if not current.committed():
      return previousCommitIndex
    return current.commitIndex()

func accepted*(fpt: var RaftFollowerProgressTrackerRef, index: RaftLogIndex) =
  fpt.matchIndex = max(fpt.matchIndex, index)
  fpt.nextIndex = max(fpt.nextIndex, index + 1)

func `$`*(progress: RaftFollowerProgressTrackerRef): string =
  fmt"""
    Progress status
    id: {progress.id}
    nextIndex: {progress.nextIndex}
    matchIndex: {progress.matchIndex}
    commitIndex: {progress.commitIndex}
    replayedIndex: {progress.replayedIndex}
    lastMessageAt: {progress.lastMessageAt.format("YYYY:MM:dd:HH:mm:ss:fff")}
  """

func `$`*(election: RaftElectionTracker): string =
  fmt"""
    Election status
    all: {election.all}
    responded: {election.responded}
    granted: {election.granted}
  """
func `$`*(tracker: RaftTracker): string =
  fmt"""
    Tracker status  
    current: {tracker.current}
    previous: {tracker.previous}
    progress: {tracker.progress}
  """

func `$`*(cfg: RaftConfig): string =
  result = "\nConfig State: \n"
  result = result & $"  Current set:\n"
  for member in cfg.currentSet:
    result = result & $member & "\n"
  result = result & " Previous set:\n"
  for member in cfg.previousSet:
    result = result & $member & "\n"
