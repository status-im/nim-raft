import binary_serialization
import std/sequtils
import consensus_state_machine
import types
import log

proc writeValue*(w: var BinaryWriter, value: string) =
  w.writeValue(value.toSeq.mapIt(cast[byte](it)))

proc writeValue*(w: var BinaryWriter, value: bool) =
  w.writeValue(uint8(value))

proc writeValue*(w: var BinaryWriter, value: RaftSnapshotId) =
  w.writeValue(uint32(value))

proc toBinary*(msg: RaftRpcMessage): seq[byte] =
  Binary.encode(msg)

proc toBinary*(msg: LogEntry): seq[byte] =
  Binary.encode(msg)
