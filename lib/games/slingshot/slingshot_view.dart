import 'dart:ui';

import 'slingshot_config.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// The slingshot's look: [ShapeView] for the bird, ground and tower, plus the
/// rubber band on top.
///
/// A worked example of the cheap path — the shapes come for free, and the game
/// only writes the one thing the default renderer could not have guessed.
class SlingshotView extends ShapeView {
  SlingshotView();

  final _band = Paint()..style = PaintingStyle.stroke;

  @override
  void renderForeground(Canvas canvas, Frame frame) {
    final anchorX = frame.sharedState['anchorX'] as double?;
    final anchorY = frame.sharedState['anchorY'] as double?;
    if (anchorX == null || anchorY == null) return;

    final anchor = Offset(anchorX, anchorY);
    final px = frame.onePixel;

    // The pouch marker is always drawn, so you can see where to grab.
    _band
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.5 * px;
    canvas.drawCircle(anchor, SlingshotConfig.birdRadius * 1.5, _band);

    if (frame.sharedState['dragging'] == null) return;

    // The pouch rides the same interpolated timeline as the bird, so the band
    // and the thing it is flinging can never disagree.
    final pouch = frame.byId('pouch');
    if (pouch == null) return;

    final pull = Offset(pouch.x, pouch.y);
    final stretch = (pull - anchor).distance / SlingshotConfig.maxPull;
    _band
      ..color = Color.lerp(
        const Color(0xFF7FD1C4),
        const Color(0xFFFF4D4D),
        stretch.clamp(0.0, 1.0),
      )!
      ..strokeWidth = 3 * px;
    canvas.drawLine(anchor, pull, _band);
  }
}
