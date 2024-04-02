import types


func isJoint*(cfg: RaftConfig): bool = 
    return cfg.previousSet.len > 0

func enterJoint*(cfg: var RaftConfig, newSet: ConfigMemberSet) =
    cfg.previousSet = cfg.currentSet
    cfg.currentSet = newSet

func leaveJoint*(cfg: var RaftConfig) =
    cfg.previousSet = @[]

func contains*(cfg: RaftConfig, id:RaftNodeId): bool =
    return cfg.currentSet.contains(id) or cfg.previousSet.contains(id)


func diff*(cfg: RaftConfig, newSet: ConfigMemberSet): ConfigDiff =
    var diff: ConfigDiff
    for n in newSet:
        let idx = cfg.currentSet.find(n)
        if idx != -1:
            diff.joining.add(n)
    
    for n in cfg.currentSet:
        let idx = newSet.find(n)
        if idx != -1:
            diff.leaving.add(n)
    return diff