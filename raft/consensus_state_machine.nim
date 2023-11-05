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
  EventType* = enum
    VotingTimeout,
    ElectionTimeout,
    HeartbeatTimeout,
    AppendEntriesTimeout
    HeartbeatReceived,
    HeartbeatSent,
    AppendEntriesReceived,
    AppendEntriesSent,
    RequestVoteReceived,
    RequestVoteSent,
    ClientRequestReceived,
    ClientRequestProcessed

  # Define callback to use with transitions. It is a function that takes a node as an argument and returns nothing.
  # It is used to perform some action when a transition is triggered. For example, when a node becomes a leader,
  # it should start sending heartbeats to other nodes.
  ConsensusFsmTransitionActionType*[NodeType] = proc(node: NodeType) {.gcsafe.}

  # Define logical functions (conditions) computed from our NodeType etc. (Truth Table)
  LogicalConditionValueType* = bool
  LogicalCondition*[NodeTytpe, RaftMessageType] =
    proc(node: NodeTytpe, msg: Option[RaftMessageType]): LogicalConditionValueType
  LogicalConditionsLut*[RaftNodeState, EventType, NodeType, RaftMessageType] =
    Table[(RaftNodeState, EventType), seq[LogicalCondition[NodeType, RaftMessageType]]]

  # Define Terminals as a tuple of a Event and a sequence of logical functions (conditions) and their respective values computed from NodeType, NodeTytpe and RaftMessageType
  # (kind of Truth Table)
  TerminalSymbol*[EventType, NodeType, RaftMessageType] =
    (EventType, seq[LogicalConditionValueType])

  # Define State Transition Rules LUT of the form ( NonTerminal -> Terminal ) -> NonTerminal )
  # NonTerminal is a NodeState and Terminal is a TerminalSymbol - the tuple (EventType, seq[LogicalConditionValueType])
  StateTransitionsRulesLut*[RaftNodeState, EventType, NodeType, RaftMessageType] = Table[
    (RaftNodeState, TerminalSymbol[NodeType, EventType, RaftMessageType]),
    (RaftNodeState, Option[ConsensusFsmTransitionActionType[NodeType]])
  ]

  # FSM type definition
  ConsensusFsm*[RaftNodeState, EventType, NodeType, RaftMessageType] = ref object
    mtx: RLock
    state: RaftNodeState
    logicalFunctionsLut: LogicalConditionsLut[RaftNodeState, EventType, NodeType, RaftMessageType]
    stateTransitionsLut: StateTransitionsRulesLut[RaftNodeState, EventType, NodeType, RaftMessageType]

# FSM type constructor
proc new*[RaftNodeState, EventType, NodeType, RaftMessageType](
  T: type ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageType], startSymbol: RaftNodeState = rnsFollower): T =

  result = T(mtx: RLock(), state: startSymbol)
  initRLock(result.mtx)
  result.state = startSymbol

  debug "new: ", fsm=repr(result)

proc addFsmTransition*[RaftNodeState, EventType, NodeType, RaftMessageType](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageType],
  fromState: RaftNodeState,
  termSymb: TerminalSymbol[EventType, NodeType, RaftMessageType],
  toState: RaftNodeState,
  action: Option[ConsensusFsmTransitionActionType]) =

  fsm.stateTransitionsLut[(fromState.state, termSymb)] = (toState, action)

proc addFsmTransitionLogicalConditions*[RaftNodeState, EventType, NodeType, RaftMessageType](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageType],
  state: RaftNodeState,
  event: EventType,
  logicalConditions: seq[LogicalCondition[NodeType, RaftMessageType]]) =

  fsm.logicalFunctionsLut[(state, event)] = logicalConditions

proc computeFsmLogicFunctionsPermutationValuе*[RaftNodeState, NodeType, EventType, RaftMessageType](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageType],
  node: NodeType,
  termSymb: TerminalSymbol,
  msg: Option[RaftMessageType]): TerminalSymbol =

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

proc fsmAdvance*[RaftNodeState, EventType, NodeType, RaftMessageType](
  fsm: ConsensusFsm[RaftNodeState, EventType, NodeType, RaftMessageType],
  node: NodeType,
  termSymb: TerminalSymbol[EventType, NodeType, RaftMessageType],
  msg: Option[RaftMessageType]): RaftNodeState =

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
