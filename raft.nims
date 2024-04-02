proc buildLibrary(name: string, srcDir = "./", params = "", `type` = "static") =
  if not dirExists "build":
    mkDir "build"
  # allow something like "nim nimbus --verbosity:0 --hints:off nimbus.nims"
  var extra_params = params
  for i in 2..<paramCount():
    extra_params &= " " & paramStr(i)
  if `type` == "static":
    exec "nim c" & " --out:build/" & name & ".a --threads:on --app:staticlib --opt:size --noMain --header --styleCheck:usages --styleCheck:error" & extra_params & " " & srcDir & name & ".nim"
  else:
    exec "nim c" & " --out:build/" & name & ".so --threads:on --app:lib --opt:size --noMain --header --styleCheck:usages --styleCheck:error" & extra_params & " " & srcDir & name & ".nim"


task build, "Build static lib":
  buildLibrary "raft", "src/"

task test, "Run tests":
  exec "nim c -r tests/test_consensus_state_machine.nim"
