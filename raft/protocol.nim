# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

                        #                                       #
                        #   Raft Messages Protocol definition   #
                        #                                       #
import types
import options

type
  # Raft Node Messages OPs
  RaftMessageOps* = enum
    rmoRequestVote = 0,
    rmoAppendLogEntry = 1,
    rmoInstallSnapshot = 2                    # For dynamic adding of new Raft Nodes

  RaftMessagePayloadChecksum* = object        # Checksum probably will be a SHA3 hash not sure about this at this point
  RaftMessagePayload*[LogEntryDataType] = ref object
    data*: RaftNodeLogEntry[LogEntryDataType]
    checksum*: RaftMessagePayloadChecksum

  RaftMessage*[LogEntryDataType] = ref object of RaftMessageBase
    op*: RaftMessageOps                       # Message Op - Ask For Votes, Append Entry(ies), Install Snapshot etc.
    payload*: Option[seq[RaftMessagePayload[LogEntryDataType]]]       # Optional Message Payload(s) - e.g. log entry(ies). Will be empty for a Heart-Beat                                            # Heart-Beat will be a message with Append Entry(ies) Op and empty payload

  RaftMessageResponse*[SmStateType] = ref object of RaftMessageBase
    success*: bool                          # Indicates success/failure
    state*: Option[SmStateType]             # Raft Abstract State Machine State

  # Raft Node Client Request/Response definitions
  RaftNodeClientRequestOps = enum
    rncroRequestState = 0,
    rncroAppendNewEntry = 1

  RaftNodeClientRequest*[LogEntryDataType] = ref object
    op*: RaftNodeClientRequestOps
    payload*: Option[RaftMessagePayload[LogEntryDataType]]  # Optional RaftMessagePayload carrying a Log Entry

  RaftNodeClientResponse*[SmStateType] = ref object
    success*: bool                                      # Indicate succcess
    state*: Option[SmStateType]                         # Optional Raft Abstract State Machine State
    raftNodeRedirectId*: Option[RaftNodeId]             # Optional Raft Node ID to redirect the request to in case of failure