import 'dart:ffi';
import 'package:ffi/ffi.dart';

typedef _PtySpawnC = Int32 Function(
    Pointer<Int32> masterFd, Pointer<Int32> childPid, Uint16 cols, Uint16 rows);
typedef _PtySpawnDart = int Function(
    Pointer<Int32> masterFd, Pointer<Int32> childPid, int cols, int rows);

typedef _PtyReadC = IntPtr Function(Int32 fd, Pointer<Uint8> buf, Size len);
typedef _PtyReadDart = int Function(int fd, Pointer<Uint8> buf, int len);

typedef _PtyWriteC = IntPtr Function(
    Int32 fd, Pointer<Uint8> buf, Size len);
typedef _PtyWriteDart = int Function(int fd, Pointer<Uint8> buf, int len);

typedef _PtyResizeC = Int32 Function(Int32 fd, Uint16 cols, Uint16 rows);
typedef _PtyResizeDart = int Function(int fd, int cols, int rows);

typedef _PtyCloseC = Void Function(Int32 fd, Int32 childPid);
typedef _PtyCloseDart = void Function(int fd, int childPid);

class PtyFfi {
  final _PtySpawnDart _spawn;
  final _PtyReadDart _read;
  final _PtyWriteDart _write;
  final _PtyResizeDart _resize;
  final _PtyCloseDart _close;

  PtyFfi() : this.fromLibrary(DynamicLibrary.open('libpty.dylib'));

  PtyFfi.fromLibrary(DynamicLibrary lib)
      : _spawn = lib.lookupFunction<_PtySpawnC, _PtySpawnDart>('pty_spawn'),
        _read = lib.lookupFunction<_PtyReadC, _PtyReadDart>('pty_read'),
        _write = lib.lookupFunction<_PtyWriteC, _PtyWriteDart>('pty_write'),
        _resize =
            lib.lookupFunction<_PtyResizeC, _PtyResizeDart>('pty_resize'),
        _close = lib.lookupFunction<_PtyCloseC, _PtyCloseDart>('pty_close');

  (int masterFd, int childPid) spawn(int cols, int rows) {
    final pMasterFd = calloc<Int32>();
    final pChildPid = calloc<Int32>();
    try {
      final rc = _spawn(pMasterFd, pChildPid, cols, rows);
      if (rc != 0) {
        throw StateError('pty_spawn failed with code $rc');
      }
      return (pMasterFd.value, pChildPid.value);
    } finally {
      calloc.free(pMasterFd);
      calloc.free(pChildPid);
    }
  }

  int read(int fd, Pointer<Uint8> buf, int len) => _read(fd, buf, len);

  int write(int fd, Pointer<Uint8> buf, int len) => _write(fd, buf, len);

  int resize(int fd, int cols, int rows) => _resize(fd, cols, rows);

  void close(int fd, int childPid) => _close(fd, childPid);
}
