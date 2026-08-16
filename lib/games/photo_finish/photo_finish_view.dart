import 'dart:ui';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// Photo Finish's look: the default circles for the runners, plus a dashed
/// finish line the width of the board — every phone the line only *passes
/// through* draws its own slice of the same dashes, at the same world x, so
/// the line reads as one continuous mark rather than one phone's decoration.
class PhotoFinishView extends ShapeView {
  PhotoFinishView() : super(playfield: const Color(0xFF141C33));

  final _line = Paint()..color = const Color(0xFFFFD166);

  @override
  void renderForeground(Canvas canvas, Frame frame) {
    final finishX = frame.sharedState['finishX'];
    if (finishX is! num) return;

    final x = finishX.toDouble();
    _line.strokeWidth = frame.onePixel * 4;
    const dash = 0.7;
    var y = frame.board.top;
    while (y < frame.board.bottom) {
      final end = (y + dash).clamp(frame.board.top, frame.board.bottom);
      canvas.drawLine(Offset(x, y), Offset(x, end), _line);
      y += dash * 2;
    }
  }
}
