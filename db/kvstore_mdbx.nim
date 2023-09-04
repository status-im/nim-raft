{.push raises: [].}

import std/os
import stew/results
import ./abstract_db_transaction

import nimdbx/[Database, CRUD, Collection, Transaction, Cursor, Error, Index, Collatable, Data]

export Database, CRUD, Collection, Transaction, Cursor, Error, Index, Collatable, Data

type
  MDBXStoreRef* = ref object of RootObj
    database* {.requiresInit.}: Database
    raftNodeData* {.requiresInit.}: Collection

  MDBXTransaction* = ref object of RootObj
    transaction: CollectionTransaction

const
  MaxFileSize = 1024 * 1024 * 400   #r: 100MB (MDBX default is 400 MB)

# ----------------------------------------------------------------------------------------
#                         MDBX exception handling helper templates
# ----------------------------------------------------------------------------------------

template handleEx(body: untyped) =
  ## Handle and convert MDBX exceptions to Result
  try:
    body
  except MDBXError as e:
    return err(e.msg)
  except OSError as e:
    return err(e.msg)
  except CatchableError as e:
    return err(e.msg)

template handleExEx(body: untyped) =
  ## Handle and convert MDBX exceptions to Result
  try:
    body
  except MDBXError as e:
    return err(e.msg)
  except OSError as e:
    return err(e.msg)
  except CatchableError as e:
    return err(e.msg)
  except Exception as e:
    return err(e.msg)

# ----------------------------------------------------------------------------------------
#                           MDBX transactions methods
# ----------------------------------------------------------------------------------------

proc commit*(t: MDBXTransaction): ADbTResult[void] =
  handleEx():
    t.transaction.commit()
  ok()

proc rollback*(t: MDBXTransaction): ADbTResult[void] =
  handleEx():
    t.transaction.abort()
  ok()

proc beginDbTransaction*(db: MDBXStoreRef): ADbTResult[MDBXTransaction] =
  if db.raftNodeData != nil:
    handleEx():
      ok(MDBXTransaction(transaction: db.raftNodeData.beginTransaction()))
  else:
    err("MDBXStoreRef.raftNodesData is nil")

proc put*(t: MDBXTransaction, key, value: openArray[byte]): ADbTResult[void] =
  handleExEx():
    t.transaction.put(asData(key), asData(value))
  ok()

proc del*(t: MDBXTransaction, key: openArray[byte]): ADbTResult[void] =
  handleExEx():
    t.transaction.del(asData(key))
  ok()

# ----------------------------------------------------------------------------------------
#                       MDBX transactions convenience templates
# ----------------------------------------------------------------------------------------

template checkDbChainsNotNil(db: MDBXStoreRef, body: untyped) =
  ## Check if db.raftNodesData is not nil and execute the body
  ## if it is not nil. Otherwise, raise an assert.
  ##
  if db.raftNodeData != nil:
    body
  else:
    raiseAssert "MDBXStoreRef.raftNodesData is nil"

template withDbSnapshot*(db: MDBXStoreRef, body: untyped) =
  ## Create an MDBX snapshot and execute the body providing
  ## a snapshot variable cs for the body statements to operate on.
  ## Finish the snapshot after the body is executed.
  ##
  ##
  checkDbChainsNotNil(db):
    handleEx():
      let cs {.inject.} = db.raftNodeData.beginSnapshot()
      defer: cs.finish()
      body

template withDbTransaction*(db: MDBXStoreRef, body: untyped) =
  ## Create an MDBX transaction and execute the body and inject
  ## a transaction variable dbTransaction in the body statements.
  ## Handle MDBX errors and abort the transaction on error.
  ##
  checkDbChainsNotNil(db):
    handleEx():
      var dbTransaction {.inject.} = db.raftNodeData.beginTransaction()
      defer: dbTransaction.commit()
      try:
        body
      except MDBXError as e:
        dbTransaction.abort()
        return err(e.msg)
      except OSError as e:
        dbTransaction.abort()
        return err(e.msg)
      except Exception as e:
        dbTransaction.abort()
        return err(e.msg)

# ------------------------------------------------------------------------------------------
#                        MDBX KvStore interface implementation
# ------------------------------------------------------------------------------------------
type
  DataProc = proc(data: seq[byte])
  FindProc = proc(data: seq[byte])

proc get*(db: MDBXStoreRef, key: openArray[byte], onData: DataProc): Result[bool, string] =
  if key.len <= 0:
    return err("mdbx: key cannot be empty on get")

  withDbSnapshot(db):
    let mdbxData = asByteSeq(cs.get(asData(key)))
    if mdbxData.len > 0:
      onData(mdbxData)
      return ok(true)
    else:
      return ok(false)

proc find*(db: MDBXStoreRef, prefix: openArray[byte], onFind: FindProc): Result[int, string] =
  raiseAssert "Unimplemented"

proc put*(db: MDBXStoreRef, key, value: openArray[byte]): Result[void, string] =
  if key.len <= 0:
    return err("mdbx: key cannot be empty on get")

  withDbTransaction(db):
    dbTransaction.put(asData(key), asData(value))
  ok()

proc contains*(db: MDBXStoreRef, key: openArray[byte]): Result[bool, string] =
  if key.len <= 0:
    return err("mdbx: key cannot be empty on get")

  withDbSnapshot(db):
    let mdbxData = asByteSeq(cs.get(asData(key)))
    if mdbxData.len > 0:
      return ok(true)
    else:
      return ok(false)

proc del*(db: MDBXStoreRef, key: openArray[byte]): Result[bool, string] =
  if key.len <= 0:
    return err("mdbx: key cannot be empty on del")

  withDbTransaction(db):
    let mdbxData = asByteSeq(dbTransaction.get(asData(key)))
    if mdbxData.len > 0:
      dbTransaction.del(asData(key))
      return ok(true)
    else:
      return ok(false)

proc clear*(db: MDBXStoreRef): Result[bool, string] =
  raiseAssert "Unimplemented"

proc close*(db: MDBXStoreRef) =
  try:
    db.database.close()
  except MDBXError as e:
    raiseAssert e.msg
  except OSError as e:
    raiseAssert e.msg

# ------------------------------------------------------------------------------------------
# .End.                       MDBX KvStore interface implementation
# ------------------------------------------------------------------------------------------

# proc bulkPutSortedData*[KT: ByteArray32 | ByteArray33](db: MDBXStoreRef, keys: openArray[KT], vals: openArray[seq[byte]]): Result[int64] =
#   if keys.len <= 0:
#      return err("mdbx: keys cannot be empty on bulkPutSortedData")

#   if keys.len != vals.len:
#     return err("mdbx: keys and vals must have the same length")

#   withDbTransaction(db):
#     for i in 0 ..< keys.len:
#       dbTransaction.put(asData(keys[i]), asData(vals[i]))
#   return ok(0)

proc init*(
    T: type MDBXStoreRef, basePath: string, name: string,
    readOnly = false): Result[T, string] =
  let
    dataDir = basePath / name / "data"
    backupsDir = basePath / name / "backups" # Do we need that in case of MDBX? Should discuss this with @zah

  try:
    createDir(dataDir)
    createDir(backupsDir)
  except OSError as e:
    return err(e.msg)
  except IOError as e:
    return err(e.msg)

  var
    mdbxFlags = {Exclusive, SafeNoSync}
  if readOnly:
    mdbxFlags.incl(ReadOnly)

  handleEx():
    let
      db = openDatabase(dataDir, flags=mdbxFlags, maxFileSize=MaxFileSize)
      raftNodeData = createCollection(db, "raftNodeData", StringKeys, BlobValues)
    ok(T(database: db, raftNodeData: raftNodeData))
