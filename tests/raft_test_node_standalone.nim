import ../raft
import basic_state_machine


if isMainModule:
  var node = RaftNode[SmCommand, SmState].new()