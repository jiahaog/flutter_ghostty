import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<
  Int32 Function(
    Pointer<Int32> masterFd,
    Pointer<Int32> childPid,
    Uint16 cols,
    Uint16 rows,
  )
>(symbol: 'pty_spawn')
external int _ptySpawn(
  Pointer<Int32> masterFd,
  Pointer<Int32> childPid,
  int cols,
  int rows,
);

@Native<IntPtr Function(Int32 fd, Pointer<Uint8> buf, Size len)>(
  symbol: 'pty_read',
)
external int _ptyRead(int fd, Pointer<Uint8> buf, int len);

@Native<IntPtr Function(Int32 fd, Pointer<Uint8> buf, Size len)>(
  symbol: 'pty_write',
)
external int _ptyWrite(int fd, Pointer<Uint8> buf, int len);

@Native<Int32 Function(Int32 fd, Uint16 cols, Uint16 rows)>(
  symbol: 'pty_resize',
)
external int _ptyResize(int fd, int cols, int rows);

@Native<Void Function(Int32 fd, Int32 childPid)>(symbol: 'pty_close')
external void _ptyClose(int fd, int childPid);

class PtyFfi {
  (int masterFd, int childPid) spawn(int cols, int rows) {
    final pMasterFd = calloc<Int32>();
    final pChildPid = calloc<Int32>();
    try {
      final rc = _ptySpawn(pMasterFd, pChildPid, cols, rows);
      if (rc != 0) {
        throw StateError('pty_spawn failed with code $rc');
      }
      return (pMasterFd.value, pChildPid.value);
    } finally {
      calloc.free(pMasterFd);
      calloc.free(pChildPid);
    }
  }

  int read(int fd, Pointer<Uint8> buf, int len) => _ptyRead(fd, buf, len);

  int write(int fd, Pointer<Uint8> buf, int len) => _ptyWrite(fd, buf, len);

  int resize(int fd, int cols, int rows) => _ptyResize(fd, cols, rows);

  void close(int fd, int childPid) => _ptyClose(fd, childPid);
}
