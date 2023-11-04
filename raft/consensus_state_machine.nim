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


type
  # Node events
  EventType = enum
    VotingTimeout, ElectionTimeout, HeartbeatTimeout, HeartbeatReceived, HeartbeatSent, AppendEntriesReceived,
    AppendEntriesSent, RequestVoteReceived, RequestVoteSent, ClientRequestReceived, ClientRequestProcessed
  # Define callback to use with Terminals. Node states are updated/read in-place in the node object
  ConsensusFSMCallbackType*[NodeType] = proc(node: NodeType) {.gcsafe.}

  # Define Non-Terminals as a (unique) tuples of the internal state and a sequence of callbacks
  NonTerminalSymbol*[RaftNodeState] = RaftNodeState

  # Define logical functions (conditions) computed from our NodeType etc. (Truth Table)
  LogicalFunctionConditionValueType* = bool
  LogicalFunctionCondition*[EventType, NodeTytpe, RaftMessageBase] = proc(e: EventType, n: NodeTytpe, msg: Option[RaftMessageBase]): bool
  LogicalFunctionConditionsLUT*[RaftNodeState, EventType, NodeType, RaftMessageBase] = Table[(RaftNodeState, EventType), seq[LogicalFunctionCondition[EventType, NodeType, Option[RaftMessageBase]]]]

  # Define Terminals as a tuple of a Event and a sequence of logical functions (conditions) and their respective values computed from NodeType, NodeTytpe and RaftMessageBase
  # (kind of Truth Table)
  TerminalSymbol*[EventType, NodeType, RaftMessageBase] = (EventType, seq[LogicalFunctionConditionValueType])

  # Define State Transition Rules LUT of the form ( NonTerminal -> Terminal ) -> NonTerminal )
  StateTransitionsRulesLUT*[RaftNodeState, EventType, NodeType, RaftMessageBase] = Table[
    (NonTerminalSymbol[RaftNodeState], TerminalSymbol[NodeType, EventType, RaftMessageBase]),
    NonTerminalSymbol[NodeType]]

  # FSM type definition
  ConsensusFSM*[RaftNodeState, EventType, NodeType, RaftMessageBase] = ref object
    mtx: RLock
    state: NonTerminalSymbol[NodeType]
    stateTransitionsLUT: StateTransitionsRulesLUT[RaftNodeState, EventType, NodeType, RaftMessageBase]
    logicalFunctionsLut: LogicalFunctionConditionsLUT[RaftNodeState, EventType, NodeType, RaftMessageBase]

# FSM type constructor
proc new*[RaftNodeState, EventType, NodeType, RaftNodeStates](T: type ConsensusFSM[RaftNodeState, EventType, NodeType, RaftMessageBase],
          lut: StateTransitionsRulesLUT[RaftNodeState, EventType, NodeType, RaftMessageBase],
          startSymbol: NonTerminalSymbol[NodeType]
  ): T =
  result = new(ConsensusFSM[NodeType, EventType, RaftNodeStates])
  initRLock(result.mtx)
  result.state = startSymbol
  result.stateTransitionsLUT = lut

proc computeFSMLogicFunctionsPermutationValue[NonTerminalSymbol, RaftNodeState, NodeType, EventType, RaftMessageBase](
    fsm: ConsensusFSM[RaftNodeState, EventType, NodeType, RaftMessageBase],
    nts: NonTerminalSymbol, rawInput: TerminalSymbol, msg: Option[RaftMessageBase]): TerminalSymbol =
  let
    e = rawInput[0]
  var
    logicFunctionsConds = fsm.logicalFunctionsLut[(e, NodeType)]

  for f in logicFunctionsConds:
    f = f(nts[1], e, msg)

  rawInput[1] = logicFunctionsConds
  result = rawInput

proc consensusFSMAdvance[RaftNodeState, EventType, NodeType, RaftMessageBase](fsm: ConsensusFSM[RaftNodeState, EventType, NodeType, RaftMessageBase], node: NodeType, event: EventType,
                         rawInput: TerminalSymbol[EventType, NodeType, RaftMessageBase], msg: Option[RaftMessageBase]): NonTerminalSymbol[NodeType] =
  withRLock():
    var
      input = computeFSMLogicFunctionsPermutationValue(fsm, node, event, rawInput)

    fsm.state = fsm.stateTransitionsLUT[(fsm.state, input)]
    result = fsm.state
