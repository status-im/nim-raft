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

type
    # RAFT Node Messages definitions
    RAFTMessageId* = object                     # Some Kind of UUID assigned to every RAFT Node Message,
                                                # so it can be matched with it's coresponding response etc.

    RAFTMessageOps* = enum
        REQUEST_VOTE        = 0,
        APPEND_LOG_ENTRY    = 1,
        INSTALL_SNAPSHOT    = 2                 # For dynamic adding of new RAFT Nodes

    RAFTMessagePayloadChecksum* = object        # Checksum probably will be a SHA3 hash not sure about this at this point
    RAFTMessagePayload* = ref object
        data*: RAFTNodeLogEntry
        checksum*: RAFTMessagePayloadChecksum

    RAFTMessageBase* = ref object of RootObj    # Base Type for RAFT Node Messages
        msg_id*: RAFTMessageId                  # Message UUID
        sender_id*: RAFTNodeId                  # Sender RAFT Node ID
        sender_term*: RAFTNodeTerm              # Sender RAFT Node Term
        peers*: RAFTNodePeers                   # List of RAFT Node IDs, which should receive this message

    RAFTMessage* = ref object of RAFTMessageBase
        op*: RAFTMessageOps                     # Message Op - Ask For Votes, Append Entry(ies) or Install Snapshot
        payload*: seq[RAFTMessagePayload]       # Message Payload(s) - e.g. log entry(ies) etc. Will be empty for a Heart-Beat                                            # Heart-Beat will be a message with Append Entry(ies) Op and empty payload

    RAFTMessageResponse* = ref object of RAFTMessageBase
        success*: bool                          # Indicates success/failure

    RAFTMessageSendCallback* = proc (raft_message: RAFTMessageBase) {.nimcall, gcsafe.} # Callback for Sending RAFT Node Messages
                                                                                        # out of this RAFT Node. Can be used for broadcasting
                                                                                        # (a Heart-Beat for example)
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