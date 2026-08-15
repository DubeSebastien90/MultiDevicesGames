import 'dart:ui';

import 'rally_config.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// Shapes for free, plus the two baselines and the centre line — drawn from
/// the board every phone already has, never sent across the wire as an
/// entity.
class RallyView extends ShapeView {
  final _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void renderForeground(Canvas canvas, Frame frame) {
    final board = frame.board;
    final lineWidth = frame.onePixel * 3;

    _stroke
      ..color = const Color(RallyConfig.colorTeamA).withValues(alpha: 0.8)
      ..strokeWidth = lineWidth;
    canvas.drawLine(
      Offset(board.left, board.top),
      Offset(board.left, board.bottom),
      _stroke,
    );

    _stroke.color = const Color(RallyConfig.colorTeamB).withValues(alpha: 0.8);
    canvas.drawLine(
      Offset(board.right, board.top),
      Offset(board.right, board.bottom),
      _stroke,
    );

    final mid = (board.left + board.right) / 2;
    _stroke
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = frame.onePixel;
    canvas.drawLine(
      Offset(mid, board.top),
      Offset(mid, board.bottom),
      _stroke,
    );
  }
}
