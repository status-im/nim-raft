# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

# Raft Node Public Types

import std/rlocks
import options
import stew/results
import uuids
import chronos

export
  results,
  options,
  rlocks,
  uuids,
  chronos

const
  DefaultUUID* = initUUID(0, 0)             # 00000000-0000-0000-0000-000000000000

type
  RaftNodeId* = object
    id*: string                              # uuid4 uniquely identifying every Raft Node
  RaftNodeTerm* = int                       # Raft Node Term Type
  RaftLogIndex* = int                       # Raft Node Log Index Type
  RaftSnapshotId* = int
  ConfigMemberSet* = seq[RaftNodeId]
  ConfigDiff* = object
    joining*: ConfigMemberSet
    leaving*: ConfigMemberSet

  RaftConfig* = object
    currentSet*: ConfigMemberSet
    previousSet*: ConfigMemberSet

  ReftConfigRef* = ref RaftConfig

func `$`*(r: RaftNodeId): string =
  return $r.id