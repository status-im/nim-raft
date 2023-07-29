# RAFT Node Public Types.
# I guess that at some point these can be moved to a separate file called raft_consensus_types.nim for example
import fsm

type
    # RAFT Node basic definitions
    Blob* = seq[byte]

    RAFTNodeState* = enum
        UNKNOWN     = 0,
        FOLLOWER    = 1,
        LEADER      = 2

    RAFTNodeId* = object                        # Some kind of UUID uniquely identifying every RAFT Node
    RAFTNodePeers* = seq[RAFTNodeId]            # List of RAFT Node Peers IDs
    RAFTNodeTerm* = uint64                      # RAFT Node Term Type
    RAFTLogIndex* = uint64                      # RAFT Node Log Index Type

    # RAFT Node basic Log definitions
    RAFTNodeLogEntry* = ref object              # Abstarct RAFT Node Log entry containing opaque binary data (Blob)
        term*: RAFTNodeTerm
        data*: Blob

    RAFTNodeLog* = ref object                   # Needs more elaborate definition. Probably this will be a RocksDB/MDBX/SQLite Store Wrapper etc.
        log_data*: seq[RAFTNodeLogEntry]        # RAFT Node Log Data

    # RAFT Node basic Messages definitions
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
    # RAFT Node Client Request/Response basic definitions
    RAFTNodeClientRequestOps = enum
        REQUEST_STATE       = 0,
        APPEND_NEW_ENTRY    = 1

    RAFTNodeClientRequest* = ref object
        op*: RAFTNodeClientRequestOps
        payload*: RAFTNodeLogEntry

    RAFTNodeClientResponse* = ref object
        success*: bool                              # Indicate succcess
        raft_node_redirect_id*: RAFTNodeId          # RAFT Node ID to redirect the request to in case of failure

    # RAFT Node State Machine basic definitions
    RAFTNodeStateMachineState* = object         # State Machine State
    RAFTNodeStateMachine* = ref object          # Some probably opaque State Machine Impelementation to be used by the RAFT Node
                                                # providing at minimum operations for initialization, querying the current state
                                                # and RAFTNodeLogEntry application
        state: RAFTNodeStateMachineState

    # RAFT Node Persistent Storage basic definition
    RAFTNodePersistentStorage* = ref object     # Should be some kind of Persistent Transactional Store Wrapper

    # Basic modules (algos) definitions
    RAFTConsensusModule* = ref object
        state_transitions_fsm: fsm          # I plan to use nim.fsm https://github.com/ba0f3/fsm.nim
        raft_node: RAFTNode

    RAFTLogCompactioModule* = ref object
        raft_node: RAFTNode
    
    RAFTMembershipChangeModule* = ref object
        raft_node: RAFTNode    

    # RAFT Node Object definitions
    RAFTNode* = object
        # Timers, mutexes definitions go here
        # ...

        # Modules
        consensus_module: RAFTConsensusModule
        log_compaction_module: RAFTLogCompactioModule
        membership_change_module: RAFTMembershipChangeModule

        # Misc
        msg_send_callback: RAFTMessageSendCallback
        persistent_storage: RAFTNodePersistentStorage

        # Persistent state
        id: RAFTNodeId                          # This RAFT Node ID
        state: RAFTNodeState                    # This RAFT Node State
        current_term: RAFTNodeTerm              # Latest term this RAFT Node has seen (initialized to 0 on first boot, increases monotonically)
        log: RAFTNodeLog                        # This RAFT Node Log
        voted_for: RAFTNodeId                   # Candidate RAFTNodeId that received vote in current term (or nil/zero if none)
        peers: RAFTNodePeers                    # This RAFT Node Peers IDs. I am not sure if this must be persistent or volatile but making it persistent
                                                # makes sense for the moment
        state_machine: RAFTNodeStateMachine     # Not sure for now putting it here. I assume that persisting the State Machine's state is enough
                                                # to consider it 'persisted'
        
        # Volatile state
        commit_index: RAFTLogIndex              # Index of highest log entry known to be committed (initialized to 0, increases monotonically)
        last_applied: RAFTLogIndex              # Index of highest log entry applied to state machine (initialized to 0, increases monotonically)
        current_leader_id: RAFTNodeId           # Current RAFT Node Leader ID (used to redirect Client Requests in case this RAFT Node is not the leader)
        
        # Volatile state on leaders
        next_index: seq[RAFTLogIndex]           # For each peer RAFT Node, index of the next log entry to send to that Node
                                                # (initialized to leader last log index + 1)
        match_index: seq[RAFTLogIndex]          # For each peer RAFT Node, index of highest log entry known to be replicated on Node
                                                # (initialized to 0, increases monotonically)
