import 'dart:ui';

import 'push_of_war_config.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// Shapes for free, plus the two goal lines — the one thing a game may draw
/// that isn't an entity, since where they sit is derived from the board every
/// phone already has rather than sent across the wire.
class PushOfWarView extends ShapeView {
  final _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void renderForeground(Canvas canvas, Frame frame) {
    final board = frame.board;
    final margin = board.width * PushOfWarConfig.goalMarginFraction;
    final leftGoalX = board.left + margin;
    final rightGoalX = board.right - margin;
    final width = frame.onePixel * 3;

    _stroke
      ..color =
          const Color(PushOfWarConfig.colorTeamA).withValues(alpha: 0.75)
      ..strokeWidth = width;
    canvas.drawLine(
      Offset(leftGoalX, board.top),
      Offset(leftGoalX, board.bottom),
      _stroke,
    );

    _stroke.color =
        const Color(PushOfWarConfig.colorTeamB).withValues(alpha: 0.75);
    canvas.drawLine(
      Offset(rightGoalX, board.top),
      Offset(rightGoalX, board.bottom),
      _stroke,
    );
  }
}
