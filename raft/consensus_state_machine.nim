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

type
  # Define callback to use with Terminals
  ConsensusFSMCallbackType*[NodeType] = proc(node: NodeType) {.gcsafe.}
  # Define Non-Terminals as a (unique) tuples of the internal state and a sequence of callbacks
  NonTerminalSymbol*[NodeType, NodeStates] = (NodeStates, seq[ConsensusFSMCallbackType[NodeType]])
  # Define loose conditions computed from our NodeType
  Condition*[NodeType] = proc(node: NodeType): bool
  # Define Terminals as a tuple of a Event and (Hash) Table of sequences of (loose) conditions and their respective values computed from NodeType (Truth Table)
  TerminalSymbol*[NodeType, EventType] = (Table[EventType, (seq[Condition[NodeType]], seq[bool])])
  # Define State Transition Rules LUT of the form ( NonTerminal -> Terminal ) -> NonTerminal )
  StateTransitionsRulesLUT*[NodeType, EventType, NodeStates] = Table[
    (NonTerminalSymbol[NodeType, NodeStates], TerminalSymbol[NodeType, EventType]),
    NonTerminalSymbol[NodeType, NodeStates]]

  # FSM type definition
  ConsensusFSM*[NodeType, EventType, NodeStates] = ref object
    mtx: RLock
    state: NonTerminalSymbol[NodeType, NodeStates]
    stateTransitionsLUT: StateTransitionsRulesLUT[NodeType, EventType, NodeStates]

# FSM type constructor
proc new*[NodeType, EventType, NodeStates](T: type ConsensusFSM[NodeType, EventType, NodeStates],
          lut: StateTransitionsRulesLUT[NodeType, EventType, NodeStates],
          startSymbol: NonTerminalSymbol[NodeType, NodeStates]
  ): T =
  result = new(ConsensusFSM[NodeType, EventType, NodeStates])
  initRLock(result.mtx)
  result.state = startSymbol
  result.stateTransitionsLUT = lut

proc computeFSMInputRobustLogic[NodeType, EventType](node: NodeType, event: EventType, rawInput: TerminalSymbol[NodeType, EventType]):
    TerminalSymbol[NodeType, EventType] =
  var
    robustLogicEventTerminal = rawInput[event]
  for f, v in robustLogicEventTerminal:
    v = f(node)
  rawInput[event] = robustLogicEventTerminal
  result = rawInput

proc consensusFSMAdvance[NodeType, EventType, NodeStates](fsm: ConsensusFSM[NodeType, EventType, NodeStates], node: NodeType, event: EventType,
                         rawInput: TerminalSymbol[NodeType, EventType]): NonTerminalSymbol[NodeType, NodeStates] =
  withRLock():
    var
      input = computeFSMInputRobustLogic(node, event, rawInput)
    fsm.state = fsm.stateTransitionsLUT[fsm.state, input]
    result = fsm.state