# nim-raft

This project aims to develop an implementation of the Raft consensus protocol that allows for application-specific customizations of the protocol.

We plan to leverage the implementation to create a highly-efficient setup for operating a redundant set of Nimbus beacon nodes and/or validator clients that rely on BLS threshold signatures to achieve improved resilience and security. Further details can be found in our roadmap here:

https://github.com/status-im/nimbus-eth2/issues/3416

This project is heavily inspired by Raft implementation in ScyllaDB 

https://github.com/scylladb/scylladb/tree/master/raft

# Design goals

The main goal is to separate implementation of the raft state machin from the other implementation details like (storage, rpc etc)
In order to achive this we want to keep the State machine absolutly deterministic every interaction the the world like 
networking, logging, acquiring current time, random number generation, disc operation etc must happened trough the state machine interface.
It will ensure better testability and integrability.


# Run test

`nimble test`