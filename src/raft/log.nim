import types
import std/sequtils
import std/strformat
import strutils
import tracker
type
  RaftLogEntryType* = enum
    rletCommand = 0,
    rletConfig = 1,
    rletEmpty = 2
  Command* = object
    data*: seq[byte]
  Empty* = object

  LogEntry* = object         # Abstarct Raft Node Log entry containing opaque binary data (Blob etc.)
    term*: RaftNodeTerm
    index*: RaftLogIndex
    # TODO: Add configuration too
    case kind*: RaftLogEntryType:
    of rletCommand: command*: Command
    of rletConfig: config*: RaftConfig
    of rletEmpty: empty*: bool

  RaftLog* = object
    logEntries: seq[LogEntry]
    firstIndex: RaftLogIndex
    lastConfigIndex*: RaftLogIndex
    prevConfigIndex*: RaftLogIndex
    snapshot*: RaftSnapshot

  RaftSnapshot* = object
    index*: RaftLogIndex
    term*: RaftNodeTerm
    config*: RaftConfig
    snapshotId*: RaftSnapshotId

func init*(T: type RaftLog, snapshot: RaftSnapshot, entires: seq[LogEntry] = @[]): T =
  var log = T()
  if entires.len == 0:
    log.firstIndex = snapshot.index + 1
  else:
    log.firstIndex = entires[0].index
    assert log.firstIndex <= snapshot.index + 1
  log.snapshot = snapshot
  log.logEntries = entires
  log.lastConfigIndex = RaftLogIndex(0)
  log.prevConfigIndex = RaftLogIndex(0)
  for i in countdown(log.logEntries.len-1, 0):
    if log.logEntries[i].index == snapshot.index:
      break
    if log.logEntries[i].kind == RaftLogEntryType.rletConfig:
      if log.lastConfigIndex == RaftLogIndex(0):
        log.lastConfigIndex = log.logEntries[i].index
      else:
        log.prevConfigIndex = log.logEntries[i].index
    
  assert log.firstIndex > 0
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

func truncateUncomitted*(rf: var RaftLog, index: RaftLogIndex) = {.cast(noSideEffect).}: 
  assert index >= rf.firstIndex
  if rf.logEntries.len == 0:
    return
  rf.logEntries.delete((index - rf.firstIndex)..<rf.logEntries.len)
  if rf.lastConfigIndex > rf.lastIndex:
    assert rf.prevConfigIndex < rf.lastConfigIndex
    rf.lastConfigIndex = rf.prevConfigIndex
    rf.prevConfigIndex = 0

func isUpToDate*(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): bool = 
  return term > rf.lastTerm or (term == rf.lastTerm and index >= rf.lastIndex)

func getEntryByIndex*(rf: RaftLog, index: RaftLogIndex): LogEntry = 
  return rf.logEntries[index - rf.firstIndex]

func append(rf: var RaftLog, entry: LogEntry) =
  rf.logEntries.add(entry)
  if entry.kind == rletConfig:
    rf.prevConfigIndex = rf.lastConfigIndex
    rf.lastConfigIndex = rf.lastIndex

func appendAsLeader*(rf: var RaftLog, entry: LogEntry) = 
  rf.append(entry)

func appendAsFollower*(rf: var RaftLog, entry: LogEntry) =
  assert entry.index > 0
  let currentIdx = rf.lastIndex
  if entry.index <= currentIdx:
    if entry.index < rf.firstIndex:
      # SKip 
      return 
    if entry.term == rf.getEntryByIndex(entry.index).term:
      # Skip
      return

    assert entry.index > rf.snapshot.index
    rf.truncateUncomitted(entry.index)
  
  assert entry.index == rf.nextIndex, fmt"entry.index: {entry.index} not eq to rf.nextIndex: {rf.nextIndex}"
  rf.append(entry)

func appendAsLeader*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command) = 
  rf.appendAsLeader(LogEntry(term: term, index: index, kind: rletCommand,  command: data))

func appendAsLeader*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, empty: bool) = 
  rf.appendAsLeader(LogEntry(term: term, index: index, kind: rletEmpty, empty: true))

func appendAsFollower*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command) = 
  rf.appendAsFollower(LogEntry(term: term, index: index, kind: rletCommand,  command: data))

func matchTerm*(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): (bool, RaftNodeTerm) = 
  if index == 0:
    return (true, 0)
  
  if index < rf.snapshot.index:
    return (true, rf.lastTerm)

  var myTerm = RaftNodeTerm(0)
  if index == rf.snapshot.index:
    myTerm = rf.snapshot.term
  else:
    let i = index - rf.firstIndex
    if i >= len(rf.logEntries):
      # The follower doesn't have all etries
      return (false, 0)
    myTerm = rf.logEntries[i].term
  
  if myTerm == term:
    return (true, 0)
  else:
    return (false, myTerm)

func termForIndex*(rf: RaftLog, index: RaftLogIndex): Option[RaftNodeTerm] =
  assert rf.logEntries.len > index - rf.firstIndex, $rf.logEntries.len  & " " & $index & "" & $rf
  if rf.logEntries.len > 0 and index >= rf.firstIndex:
    return some(rf.logEntries[index - rf.firstIndex].term)
  if index == rf.snapshot.index:
    return some(rf.snapshot.term)
  return none(RaftNodeTerm)

func configuration*(rf: RaftLog): RaftConfig = 
  if rf.lastConfigIndex > 0:
    return rf.logEntries[rf.lastConfigIndex - rf.firstIndex].config
  else:
    return rf.snapshot.config

func applySnapshot*(rf: var RaftLog, snapshot: RaftSnapshot) =
  assert snapshot.index > rf.snapshot.index
  if snapshot.index > rf.lastIndex:
    rf.logEntries = @[]
    rf.firstIndex = snapshot.index + 1
  else:
    let entriesToRemove = rf.logEntries.len - rf.lastIndex - snapshot.index
    rf.logEntries = rf.logEntries[entriesToRemove..<rf.logEntries.len]
    rf.firstIndex = rf.firstIndex + entriesToRemove

  if snapshot.index >= rf.prevConfigIndex:
    rf.prevConfigIndex = 0
    if snapshot.index >= rf.lastConfigIndex:
      rf.lastConfigIndex = 0
  rf.snapshot = snapshot

func toString*(entry: LogEntry, commandToString: proc(c: Command):string {.noSideEffect.}): string =
  case entry.kind:
    of RaftLogEntryType.rletCommand:
      return fmt"term:{entry.term}, index:{entry.index}, type:{$entry.kind}, command: {commandToString(entry.command)}"
    of RaftLogEntryType.rletEmpty:
      return fmt"term:{entry.term}, index:{entry.index}, type:{$entry.kind}, empty: null"
    of RaftLogEntryType.rletConfig:
      return fmt"term:{entry.term}, index:{entry.index}, type:{$entry.kind}, config: {$entry.config}"

func toString*(rf: RaftLog, commandToString: proc(c: Command): string {.noSideEffect.}): string =
  for e in rf.logEntries:
    result = result & e.toString(commandToString) & "\n"
  return result

func toString(bytes: openarray[byte]): string =
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len)

func commandToHex(c: Command): string =
  for b in c.data:
    result = result & b.toHex()
  return result

func `$`*(rf: RaftLog): string =
  result = "\n Log state:\n"
  for e in rf.logEntries:
    result = result & e.toString(commandToHex) & "\n"
  return result