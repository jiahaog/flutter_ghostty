import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ghostty_bindings.g.dart';
import 'terminal_state.dart';
import 'terminal_painter.dart';
import 'key_map.dart';

class TerminalView extends StatefulWidget {
  final double fontSize;
  final String fontFamily;
  final double padding;

  const TerminalView({
    super.key,
    this.fontSize = 14.0,
    this.fontFamily = 'monospace',
    this.padding = 4.0,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  late final TerminalState _state;
  late Timer _frameTimer;

  double _cellWidth = 0;
  double _cellHeight = 0;
  int _cols = 80;
  int _rows = 24;
  bool _initialized = false;
  bool _firstFocusSent = false;

  @override
  void initState() {
    super.initState();
    _state = TerminalState();
    _measureCell();
  }

  void _measureCell() {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: widget.fontFamily,
              fontSize: widget.fontSize,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              fontFamily: widget.fontFamily,
              fontSize: widget.fontSize,
            ),
          )
          ..addText('M');

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    _cellWidth = paragraph.maxIntrinsicWidth;
    _cellHeight = paragraph.height;
  }

  void _initTerminal(BoxConstraints constraints) {
    if (_initialized) return;
    _initialized = true;

    _cols = ((constraints.maxWidth - 2 * widget.padding) / _cellWidth).floor();
    _rows = ((constraints.maxHeight - 2 * widget.padding) / _cellHeight)
        .floor();
    if (_cols < 1) _cols = 1;
    if (_rows < 1) _rows = 1;

    _state.init(_cols, _rows);

    _frameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _state.readPty();
      _state.updateRenderState();
      final dirty = _state.getDirty();
      if (dirty != GhosttyRenderStateDirty.GHOSTTY_RENDER_STATE_DIRTY_FALSE) {
        if (mounted) setState(() {});
      }
    });
  }

  void _handleResize(BoxConstraints constraints) {
    if (!_initialized) return;

    final newCols = ((constraints.maxWidth - 2 * widget.padding) / _cellWidth)
        .floor();
    final newRows = ((constraints.maxHeight - 2 * widget.padding) / _cellHeight)
        .floor();

    if (newCols > 0 && newRows > 0 && (newCols != _cols || newRows != _rows)) {
      _cols = newCols;
      _rows = newRows;
      _state.resize(_cols, _rows);
      _state.setMouseEncoderSize(
        constraints.maxWidth.toInt(),
        constraints.maxHeight.toInt(),
        _cellWidth.toInt(),
        _cellHeight.toInt(),
        widget.padding.toInt(),
        widget.padding.toInt(),
      );
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final ghosttyKey = mapFlutterKey(event.logicalKey);
    if (ghosttyKey == null) return KeyEventResult.ignored;

    GhosttyKeyAction action;
    if (event is KeyDownEvent) {
      action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_PRESS;
    } else if (event is KeyUpEvent) {
      action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_RELEASE;
    } else if (event is KeyRepeatEvent) {
      action = GhosttyKeyAction.GHOSTTY_KEY_ACTION_REPEAT;
    } else {
      return KeyEventResult.ignored;
    }

    int mods = 0;
    if (HardwareKeyboard.instance.isShiftPressed) mods |= 1; // SHIFT
    if (HardwareKeyboard.instance.isControlPressed) mods |= 2; // CTRL
    if (HardwareKeyboard.instance.isAltPressed) mods |= 4; // ALT
    if (HardwareKeyboard.instance.isMetaPressed) mods |= 8; // SUPER

    String? text;
    if (event.character != null && event.character!.isNotEmpty) {
      text = event.character;
    }

    _state.encodeKeyAndWrite(ghosttyKey, action, mods, text);
    return KeyEventResult.handled;
  }

  void _onPointerDown(PointerDownEvent event) {
    _state.encodeMouseAndWrite(
      GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_PRESS,
      _mapPointerButton(event.buttons),
      0,
      event.localPosition.dx,
      event.localPosition.dy,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    _state.encodeMouseAndWrite(
      GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_RELEASE,
      GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_LEFT,
      0,
      event.localPosition.dx,
      event.localPosition.dy,
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    _state.encodeMouseAndWrite(
      GhosttyMouseAction.GHOSTTY_MOUSE_ACTION_MOTION,
      GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_UNKNOWN,
      0,
      event.localPosition.dx,
      event.localPosition.dy,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy > 0 ? 3 : -3;
      _state.scroll(delta);
    }
  }

  GhosttyMouseButton _mapPointerButton(int buttons) {
    if (buttons & 0x01 != 0) {
      return GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_LEFT;
    }
    if (buttons & 0x02 != 0) {
      return GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_RIGHT;
    }
    if (buttons & 0x04 != 0) {
      return GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_MIDDLE;
    }
    return GhosttyMouseButton.GHOSTTY_MOUSE_BUTTON_UNKNOWN;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onFocusChange: (focused) {
        if (_initialized) {
          if (!_firstFocusSent) {
            _firstFocusSent = true;
            return;
          }
          _state.encodeFocusAndWrite(focused);
        }
      },
      onKeyEvent: _onKeyEvent,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerMove: _onPointerMove,
        onPointerSignal: _onPointerSignal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _initTerminal(constraints);
            _handleResize(constraints);

            return CustomPaint(
              painter: TerminalPainter(
                state: _state,
                cellWidth: _cellWidth,
                cellHeight: _cellHeight,
                padding: widget.padding,
                fontFamily: widget.fontFamily,
                fontSize: widget.fontSize,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_initialized) {
      _frameTimer.cancel();
      _state.dispose();
    }
    super.dispose();
  }
}
