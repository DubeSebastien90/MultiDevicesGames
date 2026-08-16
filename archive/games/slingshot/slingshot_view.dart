import 'dart:ui';

import 'slingshot_config.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/world_rect.dart';
import '../../sdk/render/player_art.dart';
import '../../sdk/render/shape_view.dart';

/// Slingshot's pixels: a band, a tower, and the host being fired at it.
///
/// The ammunition is the **host's own face**, which is the joke and also the
/// clearest possible answer to "whose game is this". It comes from the SDK, so
/// this game ships no artwork of its own and gains a real character the day one
/// is drawn.
class SlingshotView extends ShapeView {
  SlingshotView(this.context);

  final ViewContext context;

  final _band = Paint()..style = PaintingStyle.stroke;

  /// The host's portrait, or null at a table where nobody is seated yet — in
  /// which case the bird is the plain circle [ShapeView] would have drawn.
  PlayerArt? get _ammo => context.roster.host?.face;

  @override
  Future<void> load() async {
    // Started, not awaited. A round begins on time and the bird is a circle
    // until the picture has decoded — a second of plain artwork beats a screen
    // that never arrives, which is what awaiting artwork here once caused.
    PlayerArt.preload([
      if (context.roster.host != null) context.roster.host!.color,
    ]);
  }

  @override
  void renderEntities(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2.0);

    for (final e in frame.entities.values) {
      if (e.kind == 'bird') {
        final size = SlingshotConfig.birdRadius * 2.5;
        if (_isOffScreen(e, size, view)) continue;
        final ammo = _ammo;
        if (ammo != null) {
          // Always paints: the portrait if it has decoded, the placeholder
          // square in the host's colour until then. No fallback to write.
          ammo.draw(canvas, Offset(e.x, e.y), worldSize: size, angle: e.angle);
        } else {
          _drawShape(canvas, e, view, frame.onePixel);
        }
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

}
