# nim-raft-consesnsus
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
import types

type
    # RAFT Node Messages definitions
    RAFTMessageOps* = enum
        REQUEST_VOTE        = 0,
        APPEND_LOG_ENTRY    = 1,
        INSTALL_SNAPSHOT    = 2                 # For dynamic adding of new RAFT Nodes

    RAFTMessagePayloadChecksum* = object        # Checksum probably will be a SHA3 hash not sure about this at this point
    RAFTMessagePayload* = ref object
        data*: RAFTNodeLogEntry
        checksum*: RAFTMessagePayloadChecksum

    RAFTMessage* = ref object of RAFTMessageBase
        op*: RAFTMessageOps                     # Message Op - Ask For Votes, Append Entry(ies) or Install Snapshot
        payload*: seq[RAFTMessagePayload]       # Message Payload(s) - e.g. log entry(ies) etc. Will be empty for a Heart-Beat                                            # Heart-Beat will be a message with Append Entry(ies) Op and empty payload

    RAFTMessageResponse* = ref object of RAFTMessageBase
        success*: bool                          # Indicates success/failure

    # RAFT Node Client Request/Response definitions
    RAFTNodeClientRequestOps = enum
        REQUEST_STATE       = 0,
        APPEND_NEW_ENTRY    = 1

    RAFTNodeClientRequest* = ref object
        op*: RAFTNodeClientRequestOps
        payload*: RAFTNodeLogEntry

    RAFTNodeClientResponse* = ref object
        success*: bool                              # Indicate succcess
        raft_node_redirect_id*: RAFTNodeId          # RAFT Node ID to redirect the request to in case of failure