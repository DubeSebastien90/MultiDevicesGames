import 'dart:ui';

import 'slingshot_config.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/world_rect.dart';
import '../../sdk/render/lottie_sprite.dart';
import '../../sdk/render/shape_view.dart';

class SlingshotView extends ShapeView {
  SlingshotView();

  final _band = Paint()..style = PaintingStyle.stroke;
  final _character = LottieSprite();

  @override
  Future<void> load() async {
    await _character.load(
      'assets/animations/character_test.json',
      width: 256,
      height: 256,
    );
  }

  @override
  void renderEntities(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2.0);

    for (final e in frame.entities.values) {
      if (e.kind == 'bird') {
        // Draw the Lottie character instead of the default circle.
        final size = SlingshotConfig.birdRadius * 2.5;
        if (_isOffScreen(e, size, view)) continue;
        _character.draw(
          canvas,
          Offset(e.x, e.y),
          frame.timeMs,
          worldSize: size,
          angle: e.angle,
        );
      } else {
        // Everything else uses the default shape renderer.
        _drawShape(canvas, e, view, frame.onePixel);
      }
    }
  }

  bool _isOffScreen(RenderEntity e, double reach, WorldRect view) {
    return e.x + reach < view.left ||
        e.x - reach > view.right ||
        e.y + reach < view.top ||
        e.y - reach > view.bottom;
  }

  /// Replicates ShapeView's per-entity drawing for non-bird entities.
  void _drawShape(Canvas canvas, RenderEntity e, WorldRect view, double onePixel) {
    final shape = e.props[ShapeProps.shape] as String?;
    if (shape == null) return;

    final fill = Paint();
    fill.color = Color(e.propInt(ShapeProps.color, 0xFFFFFFFF));

    switch (shape) {
      case ShapeKind.circle:
        final r = e.propDouble(ShapeProps.radius);
        if (_isOffScreen(e, r, view)) return;
        canvas.drawCircle(Offset(e.x, e.y), r, fill);
      case ShapeKind.box:
        final w = e.propDouble(ShapeProps.width);
        final h = e.propDouble(ShapeProps.height);
        if (_isOffScreen(e, w > h ? w : h, view)) return;
        canvas
          ..save()
          ..translate(e.x, e.y)
          ..rotate(e.angle);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
            Radius.circular((w < h ? w : h) * 0.12),
          ),
          fill,
        );
        canvas.restore();
    }
  }

  @override
  void renderForeground(Canvas canvas, Frame frame) {
    final anchorX = frame.sharedState['anchorX'] as double?;
    final anchorY = frame.sharedState['anchorY'] as double?;
    if (anchorX == null || anchorY == null) return;

    final anchor = Offset(anchorX, anchorY);
    final px = frame.onePixel;

    _band
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.5 * px;
    canvas.drawCircle(anchor, SlingshotConfig.birdRadius * 1.5, _band);

    if (frame.sharedState['dragging'] == null) return;

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

  @override
  void dispose() {
    _character.dispose();
    super.dispose();
  }
}
