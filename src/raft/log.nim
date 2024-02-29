import types
import std/sequtils

type
  RaftLogEntryType* = enum
    rletCommand = 0,
    rletConfig = 1,
    rletEmpty = 2
  Command* = object
    data*: seq[byte]
  Config* = object
  Empty* = object

  LogEntry* = object         # Abstarct Raft Node Log entry containing opaque binary data (Blob etc.)
    term*: RaftNodeTerm
    index*: RaftLogIndex
    # TODO: Add configuration too
    case kind*: RaftLogEntryType:
    of rletCommand: command*: Command
    of rletConfig: config*: Config
    of rletEmpty: empty*: bool

  RaftLog* = object
    logEntries: seq[LogEntry]
    firstIndex: RaftLogIndex

func initRaftLog*(firstIndex: RaftLogIndex): RaftLog =
  var log = RaftLog()
  assert firstIndex > 0
  log.firstIndex = firstIndex
  return log
  
func lastTerm*(rf: RaftLog): RaftNodeTerm =
  # Not sure if it's ok, maybe we should return optional value
  let size = rf.logEntries.len
  if size == 0:
    return 0
  return rf.logEntries[size - 1].term

func entriesCount*(rf: RaftLog): int =
  return rf.logEntries.len

func lastIndex*(rf: RaftLog): RaftNodeTerm =
  return rf.logEntries.len + rf.firstIndex - 1

func nextIndex*(rf: RaftLog): int =
  return rf.lastIndex + 1

func truncateUncomitted*(rf: var RaftLog, index: RaftLogIndex) =
  # TODO: We should add support for configurations and snapshots
  if rf.logEntries.len == 0:
    return
  rf.logEntries.delete((index - rf.firstIndex)..<len(rf.logEntries))

func isUpToDate*(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): bool = 
  return term > rf.lastTerm or (term == rf.lastTerm and index >= rf.lastIndex)

func getEntryByIndex*(rf: RaftLog, index: RaftLogIndex): LogEntry = 
  return rf.logEntries[index - rf.firstIndex]

func appendAsLeader*(rf: var RaftLog, entry: LogEntry) = 
  rf.logEntries.add(entry)

func appendAsFollower*(rf: var RaftLog, entry: LogEntry) = 
  assert entry.index > 0
  let currentIdx = rf.lastIndex
  if entry.index <= currentIdx:
    # TODO: The indexing hold only if we keep all entries in memory
    # we should change it when we add support for snapshots
    if entry.index >= rf.firstIndex or entry.term != rf.getEntryByIndex(entry.index).term:
      rf.truncateUncomitted(entry.index)
  rf.logEntries.add(entry)

func appendAsLeader*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command) = 
  rf.appendAsLeader(LogEntry(term: term, index: index, kind: rletCommand,  command: data))

func appendAsLeader*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, empty: bool) = 
  rf.appendAsLeader(LogEntry(term: term, index: index, kind: rletEmpty, empty: true))

func appendAsFollower*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command) = 
  rf.appendAsFollower(LogEntry(term: term, index: index, kind: rletCommand,  command: data))


func matchTerm*(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): (bool, RaftNodeTerm) = 
  if len(rf.logEntries) == 0:
    return (true, 0)
  # TODO: We should add support for snapshots
  if index > len(rf.logEntries):
    # The follower doesn't have all etries
    return (false, 0)

  let i = index - rf.firstIndex
  if rf.logEntries[i].term == term:
    return (true, 0)
  else:
    return (false, rf.logEntries[i].term)

func termForIndex*(rf: RaftLog, index: RaftLogIndex): Option[RaftNodeTerm] =
  # TODO: snapshot support
  assert rf.logEntries.len > index - rf.firstIndex, $rf.logEntries.len  & " " & $index & "" & $rf
  if rf.logEntries.len > 0 and index >= rf.firstIndex:
    return some(rf.logEntries[index - rf.firstIndex].term)
  return none(RaftNodeTerm)
