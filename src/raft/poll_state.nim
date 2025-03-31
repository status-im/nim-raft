import types

type RaftLastPollState* = object
  term: RaftNodeTerm
  votedFor: RaftNodeId
  commitIndex: RaftLogIndex
  persistedIndex: RaftLogIndex

proc `=copy`*(d: var RaftLastPollState, src: RaftLastPollState) {.error.} =
  discard

template personEqErr*{
  `=copy`(p, i)}(p: RaftLastPollState, i: RaftLastPollState{lit | lvalue | `let`}) =
  {.error: "Person doesn't allow implicit copy".}

template setTerm*(d: var RaftLastPollState, aTerm: RaftNodeTerm) =
  d.term = aTerm

template setVotedFor*(d: var RaftLastPollState, aVoteFor: RaftNodeId) =
  d.votedFor = aVoteFor

template setCommitIndex*(d: var RaftLastPollState, aCommitIndex: RaftLogIndex) =
  d.commitIndex = aCommitIndex

template setPersistedIndex*(d: var RaftLastPollState, aPersistedIndex: RaftLogIndex) =
  d.persistedIndex = aPersistedIndex

template term*(d: RaftLastPollState): RaftNodeTerm =
  d.term

template votedFor*(d: RaftLastPollState): RaftNodeId =
  d.votedFor

template commitIndex*(d: RaftLastPollState): RaftLogIndex =
  d.commitIndex

template persistedIndex*(d: RaftLastPollState): RaftLogIndex =
  d.persistedIndex
