import 'dart:ffi';
import 'ghostty_bindings.g.dart';

class Ghostty {
  final GhosttyBindings bindings;

  Ghostty() : bindings = GhosttyBindings(DynamicLibrary.open('libghostty-vt.dylib'));
}
