import types

type
  RaftLastPollState* = object
    term: RaftNodeTerm
    votedFor: RaftNodeId
    commitIndex: RaftLogIndex
    persistedIndex: RaftLogIndex

proc `=copy`*(d: var RaftLastPollState; src: RaftLastPollState) {.error.} =
 discard

template personEqErr*{`=copy`(p, i)}(p: RaftLastPollState, i: RaftLastPollState{lit|lvalue|`let`}) =
  {.error: "Person doesn't allow implicit copy".}

func setTerm*(d: var RaftLastPollState, term: RaftNodeTerm) {.inline.} =
    d.term = term
func setVotedFor*(d: var RaftLastPollState, voteFor: RaftNodeId) {.inline.} =
    d.votedFor = voteFor
func setCommitIndex*(d: var RaftLastPollState, commitIndex: RaftLogIndex) {.inline.} =
    d.commitIndex = commitIndex
func setPersistedIndex*(d: var RaftLastPollState, persistedIndex: RaftLogIndex) {.inline.} =
    d.persistedIndex = persistedIndex

func term*(d: RaftLastPollState) : RaftNodeTerm {.inline.}=
    return d.term

func votedFor*(d: RaftLastPollState) : RaftNodeId {.inline.}=
    return d.votedFor

func commitIndex*(d: RaftLastPollState) : RaftLogIndex {.inline.}=
    return d.commitIndex

func persistedIndex*(d: RaftLastPollState) : RaftLogIndex {.inline.}=
    return d.persistedIndex