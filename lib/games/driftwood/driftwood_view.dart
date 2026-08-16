import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// The shapes are enough to read the game — a log, some rocks, a current — so
/// this only adds what [ShapeView] cannot: a streaked background reading
/// "downstream", and a HUD showing how far along the log has got.
class DriftwoodView extends ShapeView {
  DriftwoodView() : super(background: _water, playfield: _lane, grid: false);

  static const _water = Color(0xFF0A1A22);
  static const _lane = Color(0xFF123244);
  static const _streak = Color(0x1F6FD3FF);

  final _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void renderBackground(Canvas canvas, Frame frame) {
    super.renderBackground(canvas, frame);

    // Streaks drifting at the current's own speed, phased on the shared
    // clock — every phone draws the same streak in the same place, so the
    // current reads as one continuous flow through every seam it crosses.
    const period = 3.4;
    const speed = 6.5; // DriftwoodConfig.currentSpeed, kept local to the view.
    final board = frame.board;
    final view = frame.visible;
    final top = board.top.clamp(view.top, view.bottom);
    final bottom = board.bottom.clamp(view.top, view.bottom);
    if (bottom <= top) return;

    _stroke
      ..color = _streak
      ..strokeWidth = frame.onePixel * 1.5;

    final phase = (frame.timeMs / 1000 * speed) % period;
    final lanes = 5;
    for (var lane = 0; lane < lanes; lane++) {
      final y = top + (bottom - top) * (lane + 0.5) / lanes;
      var x = (view.left / period).floorToDouble() * period + phase - period;
      while (x < view.right) {
        final a = x.clamp(view.left, view.right);
        final b = (x + 1.1).clamp(view.left, view.right);
        if (b > a) canvas.drawLine(Offset(a, y), Offset(b, y), _stroke);
        x += period;
      }
    }
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    if (frame.sharedState['crashed'] == true) {
      return const Text(
        'Aground',
        style: TextStyle(color: Color(0xFFFF8A65), fontWeight: FontWeight.w700),
      );
    }
    final progress = (frame.sharedState['progress'] as num?)?.toDouble() ?? 0;
    return Text(
      '${(progress * 100).round()}% downstream',
      style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
    );
  }
}
