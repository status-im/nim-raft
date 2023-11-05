# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import std/tables
import std/rlocks
import types
import chronicles

type
  # Node events
  EventType = enum
    VotingTimeout,
    ElectionTimeout,
    HeartbeatTimeout,
    HeartbeatReceived,
    HeartbeatSent,
    AppendEntriesReceived,
    AppendEntriesSent,
    RequestVoteReceived,
    RequestVoteSent,
    ClientRequestReceived,
    ClientRequestProcessed

  # Define callback to use with Terminals. Node states are updated/read in-place in the node object
  ConsensusFsmTransActionType*[NodeType] = proc(node: NodeType) {.gcsafe.}

  # Define logical functions (conditions) computed from our NodeType etc. (Truth Table)
  LogicalConditionValueType* = bool
  LogicalCondition*[NodeTytpe, RaftMessageBase] =
    proc(n: NodeTytpe, msg: Option[RaftMessageBase]): LogicalConditionValueType
  LogicalConditionsLut*[RaftNodeState, EventType, NodeType, RaftMessageBase] =
    Table[(RaftNodeState, EventType), seq[LogicalCondition[NodeType, Option[RaftMessageBase]]]]

  # Define Terminals as a tuple of a Event and a sequence of logical functions (conditions) and their respective values computed from NodeType, NodeTytpe and RaftMessageBase
  # (kind of Truth Table)
  TerminalSymbol*[EventType, NodeType, RaftMessageBase] =
    (EventType, seq[LogicalConditionValueType])

  # Define State Transition Rules LUT of the form ( NonTerminal -> Terminal ) -> NonTerminal )
  # NonTerminal is a NodeState and Terminal is a TerminalSymbol - the tuple (EventType, seq[LogicalConditionValueType])
  StateTransitionsRulesLut*[RaftNodeState, EventType, NodeType, RaftMessageBase] = Table[
    (RaftNodeState, TerminalSymbol[NodeType, EventType, Option[RaftMessageBase]]),
    (RaftNodeState, Option[ConsensusFsmTransActionType])
  ]

  # FSM type definition
  ConsensusFsm*[RaftNodeState, EventType, NodeType, RaftMessageBase] = ref object
    mtx: RLock
    state: RaftNodeState
    logicalFunctionsLut: LogicalConditionsLut[RaftNodeState, EventType, NodeType, RaftMessageBase]
    stateTransitionsLut: StateTransitionsRulesLut[RaftNodeState, EventType, NodeType, RaftMessageBase]

# FSM type constructor
proc new*[RaftNodeState, EventType, NodeType, RaftNodeStates](
  T: type ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageBase], startSymbol: RaftNodeState): T =

  result = new(ConsensusFsm[NodeType, EventType, RaftNodeStates])
  initRLock(result.mtx)
  result.state = startSymbol
  debug "new: ", fsm=repr(result)

proc addFsmTransition*[RaftNodeState, EventType, NodeType, RaftMessageBase](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageBase],
  fromState: RaftNodeState,
  termSymb: TerminalSymbol[EventType, NodeType, RaftMessageBase],
  toState: RaftNodeState,
  action: Option[ConsensusFsmTransActionType]) =

  fsm.stateTransitionsLut[(fromState.state, termSymb)] = (toState, action)

proc addFsmTransitionLogicalConditions*[RaftNodeState, EventType, NodeType, RaftMessageBase](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageBase],
  state: RaftNodeState,
  event: EventType,
  logicalConditions: seq[LogicalCondition[NodeType, Option[RaftMessageBase]]]) =

  fsm.logicalFunctionsLut[(state, event)] = logicalConditions

proc computeFsmLogicFunctionsPermutationValuе*[RaftNodeState, NodeType, EventType, RaftMessageBase](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageBase],
  node: NodeType,
  termSymb: TerminalSymbol,
  msg: Option[RaftMessageBase]): TerminalSymbol =

  let
    e = termSymb[0]

  debug "computeFSMLogicFunctionsPermutationValue: ", eventType=e, " ", nonTermSymb=nts, " ", msg=msg

  var
    logicFunctionsConds = fsm.logicalFunctionsLut[(e, NodeType)]
    logicFunctionsCondsValues = seq[LogicalConditionValueType]

  debug "computeFSMLogicFunctionsPermutationValue: ", logicFunctionsConds=logicFunctionsConds

  for f in logicFunctionsConds:
    logicFunctionsCondsValues.add f(node, msg)

  debug "computeFSMLogicFunctionsPermutationValue: ", logicFunctionsCondsValues=logicFunctionsCondsValues

  termSymb[1] = logicFunctionsConds
  result = termSymb

proc fsmAdvance*[RaftNodeState, EventType, NodeType, RaftMessageBase](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageBase],
  node: NodeType,
  termSymb: TerminalSymbol[EventType, NodeType, RaftMessageBase],
  msg: Option[RaftMessageBase]): RaftNodeState =

  withRLock():
    var
      input = computeFsmLogicFunctionsPermutationValue(fsm, node, termSymb, msg)
    let trans = fsm.stateTransitionsLut[(fsm.state, input)]
    let action = trans[1]

    fsm.state = trans[0]
    debug "ConsensusFsmAdvance", fsmState=fsm.state, " ", input=input, " ", action=repr(action)
    if action.isSome:
      action(node)
    result = fsm.state
