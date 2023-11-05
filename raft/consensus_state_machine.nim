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
  ConsensusFSMTransActionType*[NodeType] = proc(node: NodeType) {.gcsafe.}

  # Define logical functions (conditions) computed from our NodeType etc. (Truth Table)
  LogicalFunctionConditionValueType* = bool
  LogicalFunctionCondition*[EventType, NodeTytpe, RaftMessageBase] =
    proc(e: EventType, n: NodeTytpe, msg: Option[RaftMessageBase]): bool
  LogicalFunctionConditionsLUT*[RaftNodeState, EventType, NodeType, RaftMessageBase] =
    Table[(RaftNodeState, EventType), seq[LogicalFunctionCondition[EventType, NodeType, Option[RaftMessageBase]]]]

  # Define Terminals as a tuple of a Event and a sequence of logical functions (conditions) and their respective values computed from NodeType, NodeTytpe and RaftMessageBase
  # (kind of Truth Table)
  TerminalSymbol*[EventType, NodeType, RaftMessageBase] =
    (EventType, seq[LogicalFunctionConditionValueType])

  # Define State Transition Rules LUT of the form ( NonTerminal -> Terminal ) -> NonTerminal )
  StateTransitionsRulesLUT*[RaftNodeState, EventType, NodeType, RaftMessageBase] = Table[
    (RaftNodeState, TerminalSymbol[NodeType, EventType, Option[RaftMessageBase]]),
    (RaftNodeState, Option[ConsensusFSMTransActionType])
  ]

  # FSM type definition
  ConsensusFSM*[RaftNodeState, EventType, NodeType, RaftMessageBase] = ref object
    mtx: RLock
    state: RaftNodeState
    stateTransitionsLUT: StateTransitionsRulesLUT[RaftNodeState, EventType, NodeType, RaftMessageBase]
    logicalFunctionsLut: LogicalFunctionConditionsLUT[RaftNodeState, EventType, NodeType, RaftMessageBase]

# FSM type constructor
proc new*[RaftNodeState, EventType, NodeType, RaftNodeStates](
  T: type ConsensusFSM[RaftNodeState, EventType, NodeType, RaftMessageBase], startSymbol: RaftNodeState): T =

  result = new(ConsensusFSM[NodeType, EventType, RaftNodeStates])
  initRLock(result.mtx)
  result.state = startSymbol
  debug "new: ", fsm=repr(result)

proc addNewFsmTransition*[RaftNodeState, EventType, NodeType, RaftMessageBase](
  fsm: ConsensusFSM[RaftNodeState, EventType, NodeType, RaftMessageBase],
  fromState: RaftNodeState,
  toState: RaftNodeState) =

  fsm.stateTransitionsLUT[fromState.state] = (toState, none)

proc computeFSMLogicFunctionsPermutationValue[RaftNodeState, NodeType, EventType, RaftMessageBase](
  fsm: ConsensusFSM[RaftNodeState, EventType, NodeType, RaftMessageBase],
  nts: RaftNodeState,
  termSymb: TerminalSymbol,
  msg: Option[RaftMessageBase]): TerminalSymbol =

  let
    e = termSymb[0]

  debug "computeFSMLogicFunctionsPermutationValue: ", eventType=e, " ", nonTermSymb=nts, " ", msg=msg

  var
    logicFunctionsConds = fsm.logicalFunctionsLut[(e, NodeType)]
    logicFunctionsCondsValues = seq[LogicalFunctionConditionValueType]

  debug "computeFSMLogicFunctionsPermutationValue: ", logicFunctionsConds=logicFunctionsConds

  for f in logicFunctionsConds:
    logicFunctionsCondsValues.add f(nts, e, msg)

  debug "computeFSMLogicFunctionsPermutationValue: ", logicFunctionsCondsValues=logicFunctionsCondsValues

  termSymb[1] = logicFunctionsConds
  result = termSymb

proc consensusFSMAdvance[RaftNodeState, EventType, NodeType, RaftMessageBase](
  fsm: ConsensusFSM[RaftNodeState, EventType, NodeType, RaftMessageBase],
  node: NodeType,
  event: EventType,
  rawInput: TerminalSymbol[EventType, NodeType, RaftMessageBase],
  msg: Option[RaftMessageBase]): RaftNodeState =

  withRLock():
    var
      input = computeFSMLogicFunctionsPermutationValue(fsm, node, event, rawInput)
    let trans = fsm.stateTransitionsLUT[(fsm.state, input)]
    let action = trans[1]

    fsm.state = trans[0]
    debug "consensusFSMAdvance", fsmState=fsm.state, " ", input=input, " ", action=repr(action)
    if action.isSome:
      action(node)
    result = fsm.state
