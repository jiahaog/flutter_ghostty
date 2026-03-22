import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'ghostty_bindings.g.dart';
import 'terminal_state.dart';

class TerminalPainter extends CustomPainter {
  final TerminalState state;
  final double cellWidth;
  final double cellHeight;
  final double padding;
  final String fontFamily;
  final double fontSize;

  TerminalPainter({
    required this.state,
    required this.cellWidth,
    required this.cellHeight,
    this.padding = 4.0,
    this.fontFamily = 'monospace',
    this.fontSize = 14.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final colors = state.colors;

    // Use sensible defaults when the terminal hasn't configured colors
    final bgColor = (colors.background.r == 0 &&
            colors.background.g == 0 &&
            colors.background.b == 0 &&
            colors.foreground.r == 0 &&
            colors.foreground.g == 0 &&
            colors.foreground.b == 0)
        ? const Color(0xFF1E1E2E)
        : Color.fromARGB(255, colors.background.r, colors.background.g,
            colors.background.b);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = bgColor);

    final fgDefault = (colors.foreground.r == 0 &&
            colors.foreground.g == 0 &&
            colors.foreground.b == 0)
        ? const Color(0xFFCDD6F4)
        : Color.fromARGB(255, colors.foreground.r, colors.foreground.g,
            colors.foreground.b);

    // Iterate rows
    state.populateRowIterator();
    int rowIdx = 0;

    while (state.rowIteratorNext()) {
      final y = padding + rowIdx * cellHeight;

      state.populateRowCells();
      int colIdx = 0;
      while (state.rowCellsNext()) {
        final x = padding + colIdx * cellWidth;
        final graphemeLen = state.getCellGraphemeLen();

        if (graphemeLen > 0) {
          final style = state.cellStyle;
          final grapheme = state.getCellGrapheme(graphemeLen);

          // Resolve colors
          var fg = _resolveColor(style.fg_color, fgDefault);
          var bg = _resolveColor(style.bg_color, bgColor);

          if (style.inverse) {
            final tmp = fg;
            fg = bg;
            bg = tmp;
          }

          if (style.faint) {
            fg = fg.withValues(alpha: 0.5);
          }

          // Draw background if non-default
          if (bg != bgColor) {
            canvas.drawRect(
              Rect.fromLTWH(x, y, cellWidth, cellHeight),
              Paint()..color = bg,
            );
          }

          // Draw text
          if (!style.invisible && grapheme.isNotEmpty) {
            _drawText(
              canvas,
              grapheme,
              x,
              y,
              fg,
              bold: style.bold,
              italic: style.italic,
            );
          }
        } else {
          // Empty cell — check for bg-only styling
          final style = state.cellStyle;
          final bg = _resolveColor(style.bg_color, bgColor);
          if (bg != bgColor) {
            canvas.drawRect(
              Rect.fromLTWH(x, y, cellWidth, cellHeight),
              Paint()..color = bg,
            );
          }
        }

        colIdx++;
      }

      state.setRowDirty(false);
      rowIdx++;
    }

    // Draw cursor
    if (state.cursorVisible && state.cursorInViewport) {
      final cx = padding + state.cursorX * cellWidth;
      final cy = padding + state.cursorY * cellHeight;
      final cursorColor =
          colors.cursor_has_value
              ? Color.fromARGB(
                  255, colors.cursor.r, colors.cursor.g, colors.cursor.b)
              : fgDefault;

      final cursorStyle = state.cursorStyle;
      switch (cursorStyle) {
        case GhosttyRenderStateCursorVisualStyle
              .GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK:
          canvas.drawRect(
            Rect.fromLTWH(cx, cy, cellWidth, cellHeight),
            Paint()..color = cursorColor.withValues(alpha: 0.7),
          );
        case GhosttyRenderStateCursorVisualStyle
              .GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR:
          canvas.drawRect(
            Rect.fromLTWH(cx, cy, 2, cellHeight),
            Paint()..color = cursorColor,
          );
        case GhosttyRenderStateCursorVisualStyle
              .GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE:
          canvas.drawRect(
            Rect.fromLTWH(cx, cy + cellHeight - 2, cellWidth, 2),
            Paint()..color = cursorColor,
          );
        case GhosttyRenderStateCursorVisualStyle
              .GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW:
          canvas.drawRect(
            Rect.fromLTWH(cx, cy, cellWidth, cellHeight),
            Paint()
              ..color = cursorColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
      }
    }

    // Reset dirty flag
    state.setDirty(
        GhosttyRenderStateDirty.GHOSTTY_RENDER_STATE_DIRTY_FALSE);
  }

  Color _resolveColor(
      GhosttyStyleColor styleColor, Color defaultColor) {
    switch (styleColor.tag) {
      case GhosttyStyleColorTag.GHOSTTY_STYLE_COLOR_NONE:
        return defaultColor;
      case GhosttyStyleColorTag.GHOSTTY_STYLE_COLOR_RGB:
        final rgb = styleColor.value.rgb;
        return Color.fromARGB(255, rgb.r, rgb.g, rgb.b);
      case GhosttyStyleColorTag.GHOSTTY_STYLE_COLOR_PALETTE:
        final idx = styleColor.value.palette;
        final (r, g, b) = state.paletteColor(idx);
        return Color.fromARGB(255, r, g, b);
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y, Color color,
      {bool bold = false, bool italic = false}) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
    ))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ))
      ..addText(text);

    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: cellWidth * 2));

    canvas.drawParagraph(paragraph, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant TerminalPainter oldDelegate) => true;
}
