# nim-raft
# Copyright (c) 2023 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

                        #                                       #
                        #   RAFT Messages Protocol definition   #
                        #                                       #
import options
import types

type
    # RAFT Node Messages OPs
    RAFTMessageOps* = enum
      REQUEST_VOTE        = 0,
      APPEND_LOG_ENTRY    = 1,
      INSTALL_SNAPSHOT    = 2                 # For dynamic adding of new RAFT Nodes

    RAFTMessagePayloadChecksum* = object        # Checksum probably will be a SHA3 hash not sure about this at this point
    RAFTMessagePayload*[LogEntryDataType] = ref object
      data*: RAFTNodeLogEntry[LogEntryDataType]
      checksum*: RAFTMessagePayloadChecksum

    RAFTMessage*[LogEntryDataType] = ref object of RAFTMessageBase
      op*: RAFTMessageOps                     # Message Op - Ask For Votes, Append Entry(ies) or Install Snapshot
      payload*: Option[seq[RAFTMessagePayload[LogEntryDataType]]]       # Optional Message Payload(s) - e.g. log entry(ies). Will be empty for a Heart-Beat                                            # Heart-Beat will be a message with Append Entry(ies) Op and empty payload

    RAFTMessageResponse*[SMStateType] = ref object of RAFTMessageBase
      success*: bool                          # Indicates success/failure
      state*: Option[SMStateType]             # RAFT Abstract State Machine State

    # RAFT Node Client Request/Response definitions
    RAFTNodeClientRequestOps = enum
      REQUEST_STATE       = 0,
        APPEND_NEW_ENTRY    = 1

    RAFTNodeClientRequest*[LogEntryDataType] = ref object
      op*: RAFTNodeClientRequestOps
      payload*: Option[RAFTMessagePayload[LogEntryDataType]]  # Optional RAFTMessagePayload carrying a Log Entry

    RAFTNodeClientResponse*[SMStateType] = ref object
      success*: bool                                      # Indicate succcess
      state*: Option[SMStateType]                         # Optional RAFT Abstract State Machine State
      raft_node_redirect_id*: Option[RAFTNodeId]          # Optional RAFT Node ID to redirect the request to in case of failure