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
  # Define callback to use with Terminals. Node states are updated/read in-place in the node object
  ConsensusFSMCallbackType*[NodeType] = proc(node: NodeType) {.gcsafe.}
  # Define Non-Terminals as a (unique) tuples of the internal state and a sequence of callbacks
  NonTerminalSymbol*[NodeType] = (NodeType, seq[ConsensusFSMCallbackType[NodeType]])
  # Define loose conditions computed from our NodeType (Truth Table)
  LogicalFunctionCondition*[EventType, NodeTytpe, RaftMessageBase] = proc(e: EventType, n: NodeTytpe, msg: Option[RaftMessageBase]): bool
  # Define Terminals as a tuple of a Event and a sequence of logical functions (conditions) and their respective values computed from NodeType, NodeTytpe and RaftMessageBase
  # (kind of Truth Table)
  TerminalSymbol*[EventType, NodeType, RaftMessageBase] = (EventType, seq[LogicalFunctionCondition[EventType, NodeType, Option[RaftMessageBase]]])
  # Define State Transition Rules LUT of the form ( NonTerminal -> Terminal ) -> NonTerminal )
  StateTransitionsRulesLUT*[NodeType, EventType, RaftMessageBase] = Table[
    (NonTerminalSymbol[NodeType], TerminalSymbol[NodeType, EventType, RaftMessageBase]),
    NonTerminalSymbol[NodeType]]

  # FSM type definition
  ConsensusFSM*[NodeType, EventType, BaseRaftMessage] = ref object
    mtx: RLock
    state: NonTerminalSymbol[NodeType]
    stateTransitionsLUT: StateTransitionsRulesLUT[NodeType, EventType, RaftMessageBase]

# FSM type constructor
proc new*[NodeType, EventType, NodeStates](T: type ConsensusFSM[NodeType, EventType, RaftMessageBase],
          lut: StateTransitionsRulesLUT[NodeType, EventType, RaftMessageBase],
          startSymbol: NonTerminalSymbol[NodeType]
  ): T =
  result = new(ConsensusFSM[NodeType, EventType, NodeStates])
  initRLock(result.mtx)
  result.state = startSymbol
  result.stateTransitionsLUT = lut

proc computeFSMLogicFunctionsPermutationValue[NonTerminalSymbol, EventType, RaftMessageBase](nts: NonTerminalSymbol, rawInput: TerminalSymbol, msg: Option[RaftMessageBase]): TerminalSymbol =
  var
    logicFunctionsConds = rawInput[1]

  let e = rawInput[0]

  for f in nts[2]:
    f = f(nts[1], e, msg)

  rawInput[1] = logicFunctionsConds
  result = rawInput

proc consensusFSMAdvance[NodeType, EventType](fsm: ConsensusFSM[NodeType, EventType, RaftMessageBase], node: NodeType, event: EventType,
                         rawInput: TerminalSymbol[EventType, NodeType, RaftMessageBase]): NonTerminalSymbol[NodeType] =
  withRLock():
    var
      input = computeFSMLogicFunctionsPermutationValue(node, event, rawInput)

    fsm.state = fsm.stateTransitionsLUT[(fsm.state, input)]
    result = fsm.state