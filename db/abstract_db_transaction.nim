import stew/results

type
  ADbTResult*[T] = Result[T, string]

  AbstractDbTransaction* = ref object
    obj: RootRef
    commitProc: AbstractDbTransactionCommitProc
    rollbackProc: AbstractDbTransactionRollbackProc
    putProc: AbstractDbTransactionPutProc
    delProc: AbstractDbTransactionDelProc

  AbstractDbTransactionCommitProc = proc (t: RootRef): ADbTResult[void] {.nimcall, gcsafe, raises: [Defect].}
  AbstractDbTransactionRollbackProc = proc (t: RootRef): ADbTResult[void] {.nimcall, gcsafe, raises: [Defect].}
  AbstractDbTransactionPutProc = proc (db: RootRef, key, val: openArray[byte]): ADbTResult[void] {.nimcall, gcsafe, raises: [Defect].}
  AbstractDbTransactionDelProc = proc (db: RootRef, key: openArray[byte]): ADbTResult[void] {.nimcall, gcsafe, raises: [Defect].}

proc abstractTransactionCommitImpl[T](x: RootRef): ADbTResult[void] =
  mixin commit
  commit(T(x))

proc abstractTransactionRollbackImpl[T](x: RootRef): ADbTResult[void] =
  mixin rollback
  rollback(T(x))

proc abstractTransactionPutImpl[T](x: RootRef, key, val: openArray[byte]): ADbTResult[void] =
  mixin put
  put(T(x), key, val)

proc abstractTransactionDelImpl[T](x: RootRef, key: openArray[byte]): ADbTResult[void] =
  mixin del
  del(T(x), key)

proc init*[T: RootRef](_:type AbstractDbTransaction, x: T): AbstractDbTransaction =
  mixin commit, rollback, put, del
  new result
  result.obj = x
  result.commitProc = abstractTransactionCommitImpl[T]
  result.rollbackProc = abstractTransactionRollbackImpl[T]
  result.putProc = abstractTransactionPutImpl[T]
  result.delProc = abstractTransactionDelImpl[T]

proc commit*(t: AbstractDbTransaction): ADbTResult[void] =
  t.commitProc(t.obj)

proc rollback*(t: AbstractDbTransaction): ADbTResult[void] =
  t.rollbackProc(t.obj)

proc put*(t: AbstractDbTransaction, key, val: openArray[byte]): ADbTResult[void] =
  t.putProc(t.obj, key, val)

proc del*(t: AbstractDbTransaction, key: openArray[byte]): ADbTResult[void] =
  t.delProc(t.obj, key)
