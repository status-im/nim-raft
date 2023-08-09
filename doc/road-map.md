# RAFT Consensus Nim library Road-map

## Proposed milestones during the library development

1. Create Nim library package. Implement basic functionality: fully functional RAFT Node and it’s API. The RAFT Node should be abstract working without network communication by the means of API calls and Callback calls only. The RAFT Node should cover all the functionality described in the RAFT Paper excluding Dynamic Adding/Removing of RAFT Node Peers and Log Compaction. Create appropriate tests.

    *Duration: 3 weeks (2 weeks for implementation, 1 week for test creation/testing)*

2. Implement advanced functionality: Log Compaction and Dynamic Adding/Removing of RAFT Node Peers and the corresponding tests. Implement Anti Entropy measures observed in other projects (if appropriate).
    
    *Duration: 3 weeks (2 weeks for implementation, 1 week for test creation/testing)*

3. Integrate the RAFT library in the Nimbus project - define p2p networking deal with serialization etc. Create relevant tests.  I guess it is a good idea to add some kind of basic RAFT Node metrics. Optionally implement some of the following enhancements (if relevant):
    - Optimistic pipelining to reduce log replication latency
    - Writing to leader's disk in parallel
    - Automatic stepping down when the leader loses quorum
    - Leadership transfer extension
    - Pre-vote protocol
    
    *Duration: 1+ week (?)[^note]*

4. Final testing of the solution. Fix unexpected bugs.
    
    *Duration: 1 week (?)[^note]*

5. Implement any new requirements aroused after milestone 4 completion.
    
    *Duration: 0+ week(s) (?)[^note]*

6. End

---
[^note] Durations marked with an (?) means I am not pretty sure how much this will take.
