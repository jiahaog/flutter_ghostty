import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'ghostty_bindings.g.dart';
import 'pty_ffi.dart';

class TerminalState {
  final PtyFfi _pty;

  late GhosttyTerminal _terminal;
  late GhosttyRenderState _renderState;
  late final Pointer<GhosttyRenderStateRowIterator> _rowIteratorPtr;
  late final Pointer<GhosttyRenderStateRowCells> _rowCellsPtr;
  late GhosttyKeyEncoder _keyEncoder;
  late GhosttyKeyEvent _keyEvent;
  late GhosttyMouseEncoder _mouseEncoder;
  late GhosttyMouseEvent _mouseEvent;

  late int _ptyFd;
  late int _childPid;

  int cols = 0;
  int rows = 0;

  final Pointer<Uint8> _readBuf = calloc<Uint8>(65536);
  final Pointer<Uint8> _keyBuf = calloc.allocate<Uint8>(256);
  final Pointer<Size> _keyLen = calloc<Size>();
  final Pointer<Uint32> _graphemeBuf = calloc<Uint32>(32);
  final Pointer<Uint32> _graphemeLen = calloc<Uint32>();

  TerminalState() : _pty = PtyFfi();

  void init(int cols, int rows) {
    this.cols = cols;
    this.rows = rows;

    // Create terminal
    final termPtr = calloc<GhosttyTerminal>();
    final opts = calloc<GhosttyTerminalOptions>();
    opts.ref.cols = cols;
    opts.ref.rows = rows;
    opts.ref.max_scrollback = 10000;
    ghostty_terminal_new(nullptr, termPtr, opts.ref);
    _terminal = termPtr.value;
    calloc.free(opts);
    calloc.free(termPtr);

    // Create render state
    final rsPtr = calloc<GhosttyRenderState>();
    ghostty_render_state_new(nullptr, rsPtr);
    _renderState = rsPtr.value;
    calloc.free(rsPtr);

    // Create row iterator
    _rowIteratorPtr = calloc<GhosttyRenderStateRowIterator>();
    ghostty_render_state_row_iterator_new(nullptr, _rowIteratorPtr);

    // Create row cells
    _rowCellsPtr = calloc<GhosttyRenderStateRowCells>();
    ghostty_render_state_row_cells_new(nullptr, _rowCellsPtr);

    // Create key encoder + event
    final kePtr = calloc<Pointer<GhosttyKeyEncoder$1>>();
    ghostty_key_encoder_new(nullptr, kePtr);
    _keyEncoder = kePtr.value;
    calloc.free(kePtr);

    final kevtPtr = calloc<Pointer<GhosttyKeyEvent$1>>();
    ghostty_key_event_new(nullptr, kevtPtr);
    _keyEvent = kevtPtr.value;
    calloc.free(kevtPtr);

    // Create mouse encoder + event
    final mePtr = calloc<Pointer<GhosttyMouseEncoder$1>>();
    ghostty_mouse_encoder_new(nullptr, mePtr);
    _mouseEncoder = mePtr.value;
    calloc.free(mePtr);

    final mevtPtr = calloc<Pointer<GhosttyMouseEvent$1>>();
    ghostty_mouse_event_new(nullptr, mevtPtr);
    _mouseEvent = mevtPtr.value;
    calloc.free(mevtPtr);

    // Spawn PTY
    final (fd, pid) = _pty.spawn(cols, rows);
    _ptyFd = fd;
    _childPid = pid;
  }

  void dispose() {
    _pty.close(_ptyFd, _childPid);
    ghostty_mouse_event_free(_mouseEvent);
    ghostty_mouse_encoder_free(_mouseEncoder);
    ghostty_key_event_free(_keyEvent);
    ghostty_key_encoder_free(_keyEncoder);
    ghostty_render_state_row_cells_free(_rowCellsPtr.value);
    ghostty_render_state_row_iterator_free(_rowIteratorPtr.value);
    ghostty_render_state_free(_renderState);
    ghostty_terminal_free(_terminal);
    calloc.free(_readBuf);
    calloc.free(_keyBuf);
    calloc.free(_keyLen);
    calloc.free(_graphemeBuf);
    calloc.free(_graphemeLen);
    calloc.free(_colorsPtr);
    calloc.free(_stylePtr);
    calloc.free(_palettePtr);
    calloc.free(_rowIteratorPtr);
    calloc.free(_rowCellsPtr);
  }

  void readPty() {
    while (true) {
      final n = _pty.read(_ptyFd, _readBuf, 65536);
      if (n <= 0) break;
      ghostty_terminal_vt_write(_terminal, _readBuf, n);
    }
  }

  void updateRenderState() {
    ghostty_render_state_update(_renderState, _terminal);
    _paletteDirty = true;
  }

  GhosttyRenderStateDirty getDirty() {
    final out = calloc<Int32>();
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData.GHOSTTY_RENDER_STATE_DATA_DIRTY,
      out.cast(),
    );
    final val = GhosttyRenderStateDirty.fromValue(out.value);
    calloc.free(out);
    return val;
  }

  void setDirty(GhosttyRenderStateDirty dirty) {
    final val = calloc<Int32>();
    val.value = dirty.value;
    ghostty_render_state_set(
      _renderState,
      GhosttyRenderStateOption.GHOSTTY_RENDER_STATE_OPTION_DIRTY,
      val.cast(),
    );
    calloc.free(val);
  }

  GhosttyRenderStateColors getColors() {
    final colors = calloc<GhosttyRenderStateColors>();
    colors.ref.size = sizeOf<GhosttyRenderStateColors>();
    ghostty_render_state_colors_get(_renderState, colors);
    final result = colors.ref;
    // Copy values before freeing - we need to return the struct by value
    // Actually GhosttyRenderStateColors is a Struct, return the pointer
    // and let caller free it. But that's error-prone. Instead, let's
    // keep a pre-allocated one.
    return result;
  }

  // Pre-allocated colors struct for reuse
  late final Pointer<GhosttyRenderStateColors> _colorsPtr = () {
    final p = calloc<GhosttyRenderStateColors>();
    p.ref.size = sizeOf<GhosttyRenderStateColors>();
    return p;
  }();

  GhosttyRenderStateColors get colors {
    ghostty_render_state_colors_get(_renderState, _colorsPtr);
    return _colorsPtr.ref;
  }

  void populateRowIterator() {
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData.GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR,
      _rowIteratorPtr.cast(),
    );
  }

  bool rowIteratorNext() {
    return ghostty_render_state_row_iterator_next(_rowIteratorPtr.value);
  }

  bool isRowDirty() {
    final out = calloc<Bool>();
    ghostty_render_state_row_get(
      _rowIteratorPtr.value,
      GhosttyRenderStateRowData.GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY,
      out.cast(),
    );
    final val = out.value;
    calloc.free(out);
    return val;
  }

  void setRowDirty(bool dirty) {
    final val = calloc<Bool>();
    val.value = dirty;
    ghostty_render_state_row_set(
      _rowIteratorPtr.value,
      GhosttyRenderStateRowOption.GHOSTTY_RENDER_STATE_ROW_OPTION_DIRTY,
      val.cast(),
    );
    calloc.free(val);
  }

  void populateRowCells() {
    ghostty_render_state_row_get(
      _rowIteratorPtr.value,
      GhosttyRenderStateRowData.GHOSTTY_RENDER_STATE_ROW_DATA_CELLS,
      _rowCellsPtr.cast(),
    );
  }

  bool rowCellsNext() {
    return ghostty_render_state_row_cells_next(_rowCellsPtr.value);
  }

  GhosttyStyle getCellStyle() {
    final style = calloc<GhosttyStyle>();
    style.ref.size = sizeOf<GhosttyStyle>();
    ghostty_render_state_row_cells_get(
      _rowCellsPtr.value,
      GhosttyRenderStateRowCellsData.GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
      style.cast(),
    );
    final result = style.ref;
    calloc.free(style);
    return result;
  }

  // Pre-allocated style for reuse
  late final Pointer<GhosttyStyle> _stylePtr = () {
    final p = calloc<GhosttyStyle>();
    p.ref.size = sizeOf<GhosttyStyle>();
    return p;
  }();

  GhosttyStyle get cellStyle {
    ghostty_render_state_row_cells_get(
      _rowCellsPtr.value,
      GhosttyRenderStateRowCellsData.GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE,
      _stylePtr.cast(),
    );
    return _stylePtr.ref;
  }

  int getCellGraphemeLen() {
    ghostty_render_state_row_cells_get(
      _rowCellsPtr.value,
      GhosttyRenderStateRowCellsData
          .GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN,
      _graphemeLen.cast(),
    );
    return _graphemeLen.value;
  }

  String getCellGrapheme(int len) {
    if (len == 0) return '';
    ghostty_render_state_row_cells_get(
      _rowCellsPtr.value,
      GhosttyRenderStateRowCellsData
          .GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF,
      _graphemeBuf.cast(),
    );
    final codepoints = <int>[];
    for (var i = 0; i < len; i++) {
      codepoints.add(_graphemeBuf[i]);
    }
    return String.fromCharCodes(codepoints);
  }

  void resize(int newCols, int newRows) {
    if (newCols == cols && newRows == rows) return;
    cols = newCols;
    rows = newRows;
    ghostty_terminal_resize(_terminal, newCols, newRows);
    _pty.resize(_ptyFd, newCols, newRows);
  }

  // Cursor info
  bool get cursorVisible {
    final out = calloc<Bool>();
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData.GHOSTTY_RENDER_STATE_DATA_CURSOR_VISIBLE,
      out.cast(),
    );
    final val = out.value;
    calloc.free(out);
    return val;
  }

  bool get cursorInViewport {
    final out = calloc<Bool>();
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData
          .GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE,
      out.cast(),
    );
    final val = out.value;
    calloc.free(out);
    return val;
  }

  int get cursorX {
    final out = calloc<Uint16>();
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData.GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_X,
      out.cast(),
    );
    final val = out.value;
    calloc.free(out);
    return val;
  }

  int get cursorY {
    final out = calloc<Uint16>();
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData.GHOSTTY_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y,
      out.cast(),
    );
    final val = out.value;
    calloc.free(out);
    return val;
  }

  GhosttyRenderStateCursorVisualStyle get cursorStyle {
    final out = calloc<Int32>();
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData.GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE,
      out.cast(),
    );
    final val = GhosttyRenderStateCursorVisualStyle.fromValue(out.value);
    calloc.free(out);
    return val;
  }

  // Key encoding
  void encodeKeyAndWrite(
    GhosttyKey key,
    GhosttyKeyAction action,
    int mods,
    String? text,
  ) {
    ghostty_key_encoder_setopt_from_terminal(_keyEncoder, _terminal);
    ghostty_key_event_set_key(_keyEvent, key);
    ghostty_key_event_set_action(_keyEvent, action);
    ghostty_key_event_set_mods(_keyEvent, mods);

    if (text != null && text.isNotEmpty) {
      final utf8 = text.toNativeUtf8();
      ghostty_key_event_set_utf8(_keyEvent, utf8.cast(), text.length);
      final result = ghostty_key_encoder_encode(
        _keyEncoder,
        _keyEvent,
        _keyBuf.cast(),
        256,
        _keyLen,
      );
      calloc.free(utf8);
      if (result == GhosttyResult.GHOSTTY_SUCCESS && _keyLen.value > 0) {
        _pty.write(_ptyFd, _keyBuf, _keyLen.value);
      }
    } else {
      ghostty_key_event_set_utf8(_keyEvent, nullptr, 0);
      final result = ghostty_key_encoder_encode(
        _keyEncoder,
        _keyEvent,
        _keyBuf.cast(),
        256,
        _keyLen,
      );
      if (result == GhosttyResult.GHOSTTY_SUCCESS && _keyLen.value > 0) {
        _pty.write(_ptyFd, _keyBuf, _keyLen.value);
      }
    }
  }

  // Mouse encoding
  void encodeMouseAndWrite(
    GhosttyMouseAction action,
    GhosttyMouseButton button,
    int mods,
    double x,
    double y,
  ) {
    ghostty_mouse_encoder_setopt_from_terminal(_mouseEncoder, _terminal);
    ghostty_mouse_event_set_action(_mouseEvent, action);
    if (button == GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_UNKNOWN) {
      ghostty_mouse_event_clear_button(_mouseEvent);
    } else {
      ghostty_mouse_event_set_button(_mouseEvent, button);
    }
    ghostty_mouse_event_set_mods(_mouseEvent, mods);

    final pos = calloc<GhosttyMousePosition>();
    pos.ref.x = x;
    pos.ref.y = y;
    ghostty_mouse_event_set_position(_mouseEvent, pos.ref);
    calloc.free(pos);

    final result = ghostty_mouse_encoder_encode(
      _mouseEncoder,
      _mouseEvent,
      _keyBuf.cast(),
      256,
      _keyLen,
    );
    if (result == GhosttyResult.GHOSTTY_SUCCESS && _keyLen.value > 0) {
      _pty.write(_ptyFd, _keyBuf, _keyLen.value);
    }
  }

  // Focus encoding
  void encodeFocusAndWrite(bool gained) {
    final event = gained
        ? GhosttyFocusEvent.GHOSTTY_FOCUS_GAINED
        : GhosttyFocusEvent.GHOSTTY_FOCUS_LOST;
    final result = ghostty_focus_encode(event, _keyBuf.cast(), 256, _keyLen);
    if (result == GhosttyResult.GHOSTTY_SUCCESS && _keyLen.value > 0) {
      _pty.write(_ptyFd, _keyBuf, _keyLen.value);
    }
  }

  // Scroll
  void scroll(int delta) {
    final sv = calloc<GhosttyTerminalScrollViewport>();
    sv.ref.tagAsInt =
        GhosttyTerminalScrollViewportTag.GHOSTTY_SCROLL_VIEWPORT_DELTA.value;
    sv.ref.value.delta = delta;
    ghostty_terminal_scroll_viewport(_terminal, sv.ref);
    calloc.free(sv);
  }

  // Update mouse encoder size
  void setMouseEncoderSize(
    int screenWidth,
    int screenHeight,
    int cellWidth,
    int cellHeight,
    int paddingLeft,
    int paddingTop,
  ) {
    final size = calloc<GhosttyMouseEncoderSize>();
    size.ref.size = sizeOf<GhosttyMouseEncoderSize>();
    size.ref.screen_width = screenWidth;
    size.ref.screen_height = screenHeight;
    size.ref.cell_width = cellWidth;
    size.ref.cell_height = cellHeight;
    size.ref.padding_left = paddingLeft;
    size.ref.padding_top = paddingTop;
    size.ref.padding_right = 0;
    size.ref.padding_bottom = 0;
    ghostty_mouse_encoder_setopt(
      _mouseEncoder,
      GhosttyMouseEncoderOption.GHOSTTY_MOUSE_ENCODER_OPT_SIZE,
      size.cast(),
    );
    calloc.free(size);
  }

  // Cache palette
  late final Pointer<GhosttyColorRgb> _palettePtr = calloc<GhosttyColorRgb>(
    256,
  );
  bool _paletteDirty = true;

  void _refreshPalette() {
    ghostty_render_state_get(
      _renderState,
      GhosttyRenderStateData.GHOSTTY_RENDER_STATE_DATA_COLOR_PALETTE,
      _palettePtr.cast(),
    );
    _paletteDirty = false;
  }

  (int r, int g, int b) paletteColor(int index) {
    if (_paletteDirty) _refreshPalette();
    final c = (_palettePtr + index).ref;
    return (c.r, c.g, c.b);
  }

  void markPaletteDirty() {
    _paletteDirty = true;
  }

  // Write raw bytes to PTY
  void writeToPty(Uint8List data) {
    final ptr = calloc<Uint8>(data.length);
    for (var i = 0; i < data.length; i++) {
      ptr[i] = data[i];
    }
    _pty.write(_ptyFd, ptr, data.length);
    calloc.free(ptr);
  }
}
