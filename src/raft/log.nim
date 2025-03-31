import types
import std/strformat
import strutils

type
  RaftLogEntryType* = enum
    rletCommand = 0
    rletConfig = 1
    rletEmpty = 2

  Command* = object
    data*: seq[byte]

  Empty* = object

  LogEntry* = object
    term*: RaftNodeTerm
    index*: RaftLogIndex
    case kind*: RaftLogEntryType
    of rletCommand: command*: Command
    of rletConfig: config*: RaftConfig
    of rletEmpty: discard

  RaftSnapshot* = object
    index*: RaftLogIndex
    term*: RaftNodeTerm
    config*: RaftConfig

  RaftLog* = object
    logEntries: seq[LogEntry]
    firstIndex: RaftLogIndex
    lastConfigIndex*: RaftLogIndex
    prevConfigIndex*: RaftLogIndex
    snapshot*: RaftSnapshot

proc updateConfigIndices(rf: var RaftLog) =
  rf.lastConfigIndex = 0
  rf.prevConfigIndex = 0
  for i in countdown(rf.logEntries.high, 0):
    if rf.logEntries[i].kind == RaftLogEntryType.rletConfig:
      if rf.lastConfigIndex == 0:
        rf.lastConfigIndex = rf.logEntries[i].index
      else:
        rf.prevConfigIndex = rf.logEntries[i].index

func init*(T: type RaftLog, snapshot: RaftSnapshot, entries: seq[LogEntry] = @[]): T =
  var log = T()
  log.snapshot = snapshot
  log.firstIndex = snapshot.index + 1
  log.logEntries = @[]
  for entry in entries:
    if entry.index >= log.firstIndex:
      log.logEntries.add(entry)
  log.updateConfigIndices()
  log

func lastTerm*(rf: RaftLog): RaftNodeTerm =
  if rf.logEntries.len == 0:
    return rf.snapshot.term
  rf.logEntries[^1].term

func entriesCount*(rf: RaftLog): int =
  rf.logEntries.len

func lastIndex*(rf: RaftLog): RaftLogIndex =
  if rf.logEntries.len == 0:
    return rf.snapshot.index
  rf.logEntries[^1].index

func nextIndex*(rf: RaftLog): RaftLogIndex =
  return rf.lastIndex + 1

func getRelativeIndex*(rf: RaftLog, index: RaftLogIndex): Option[int] =
  if index < rf.firstIndex or index > rf.lastIndex:
    return none(int)
  some(int(index - rf.firstIndex))

func hasIndex*(rf: RaftLog, index: RaftLogIndex): bool =
  rf.getRelativeIndex(index).isSome

func truncateUncommitted*(rf: var RaftLog, index: RaftLogIndex) =
  let relIndexOpt = rf.getRelativeIndex(index)
  if relIndexOpt.isNone or rf.logEntries.len == 0:
    return
  let relIndex = relIndexOpt.get()
  if relIndex < rf.logEntries.len:
    rf.logEntries.setLen(relIndex)
    rf.updateConfigIndices()

func isUpToDate*(rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm): bool =
  let lastTerm = rf.lastTerm
  let lastIndex = rf.lastIndex
  term > lastTerm or (term == lastTerm and index >= lastIndex)

func getEntryByIndex*(rf: RaftLog, index: RaftLogIndex): LogEntry =
  rf.logEntries[index - rf.firstIndex]

func append(rf: var RaftLog, entry: LogEntry) =
  rf.logEntries.add(entry)
  if entry.kind == rletConfig:
    rf.prevConfigIndex = rf.lastConfigIndex
    rf.lastConfigIndex = entry.index

func appendAsLeader*(rf: var RaftLog, entry: LogEntry) =
  rf.append(entry)

func appendAsFollower*(rf: var RaftLog, entry: LogEntry) =
  if entry.index < rf.firstIndex:
    return
  if entry.index <= rf.lastIndex:
    let existingEntryOpt = rf.getEntryByIndex(entry.index)
    if existingEntryOpt.term == entry.term:
      # Entry already exists with the same term; skip
      return
    rf.truncateUncommitted(entry.index)
  elif entry.index > rf.nextIndex:
    return
  rf.append(entry)

func appendAsLeader*(
    rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command
) =
  rf.appendAsLeader(
    LogEntry(term: term, index: index, kind: rletCommand, command: data)
  )

func appendAsLeader*(rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex) =
  rf.appendAsLeader(LogEntry(term: term, index: index, kind: rletEmpty))

func appendAsFollower*(
    rf: var RaftLog, term: RaftNodeTerm, index: RaftLogIndex, data: Command
) =
  rf.appendAsFollower(
    LogEntry(term: term, index: index, kind: rletCommand, command: data)
  )

func matchTerm*(
    rf: RaftLog, index: RaftLogIndex, term: RaftNodeTerm
): (bool, RaftNodeTerm) =
  if index == 0:
    return (true, 0)
  if index == rf.snapshot.index:
    let myTerm = rf.snapshot.term
    return (myTerm == term, myTerm)
  let relIndexOpt = rf.getRelativeIndex(index)
  if relIndexOpt.isSome:
    let relIndex = relIndexOpt.get()
    let myTerm = rf.logEntries[relIndex].term
    return (myTerm == term, myTerm)
  (false, 0)

func termForIndex*(rf: RaftLog, index: RaftLogIndex): Option[RaftNodeTerm] =
  if index == rf.snapshot.index:
    return some(rf.snapshot.term)
  let relIndexOpt = rf.getRelativeIndex(index)
  if relIndexOpt.isSome:
    return some(rf.logEntries[relIndexOpt.get()].term)
  none(RaftNodeTerm)

func configuration*(rf: RaftLog): RaftConfig =
  if rf.lastConfigIndex > 0:
    let relIndexOpt = rf.getRelativeIndex(rf.lastConfigIndex)
    if relIndexOpt.isSome:
      return rf.logEntries[relIndexOpt.get()].config
  rf.snapshot.config

func updateConfigIndicesAfterSnapshot(rf: var RaftLog, snapshotIndex: RaftLogIndex) =
  if snapshotIndex >= rf.lastConfigIndex:
    rf.lastConfigIndex = 0
    rf.prevConfigIndex = 0
  elif snapshotIndex >= rf.prevConfigIndex:
    rf.prevConfigIndex = 0

func applySnapshot*(rf: var RaftLog, snapshot: RaftSnapshot) =
  assert snapshot.index > rf.snapshot.index
  if snapshot.index >= rf.lastIndex:
    rf.logEntries = @[]
    rf.firstIndex = snapshot.index + 1
  else:
    let newFirstIndex = snapshot.index + 1
    let entriesToRemove = int(newFirstIndex - rf.firstIndex)
    rf.logEntries = rf.logEntries[entriesToRemove ..^ 1]
    rf.firstIndex = newFirstIndex
  rf.updateConfigIndicesAfterSnapshot(snapshot.index)
  rf.snapshot = snapshot

func toString*(
    entry: LogEntry, commandToString: proc(c: Command): string {.noSideEffect.}
): string =
  case entry.kind
  of RaftLogEntryType.rletCommand:
    return
      fmt"term: {entry.term}, index: {entry.index}, type: {entry.kind}, command: {commandToString(entry.command)}"
  of RaftLogEntryType.rletEmpty:
    return
      fmt"term: {entry.term}, index: {entry.index}, type: {entry.kind}, empty: true"
  of RaftLogEntryType.rletConfig:
    return
      fmt"term: {entry.term}, index: {entry.index}, type: {entry.kind}, config: {entry.config}"

func toString*(
    rf: RaftLog, commandToString: proc(c: Command): string {.noSideEffect.}
): string =
  for e in rf.logEntries:
    result.add(e.toString(commandToString) & "\n")
  result

func toString(bytes: openarray[byte]): string =
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len)

func commandToHex(c: Command): string =
  for b in c.data:
    result.add(b.toHex() & " ")
  result.strip()

func `$`*(rf: RaftLog): string =
  result = "\nLog state:\n"
  for e in rf.logEntries:
    result.add(e.toString(commandToHex) & "\n")
