import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player_color.dart';
import 'guacamole_config.dart';

/// Guac-a-Mole's pixels: holes, avocados, and a border in your own colour.
///
/// Everything animated here is driven from `frame.sharedState` and
/// `frame.timeMs` — the host's clock — never a local one. Two phones showing
/// the same mole at different heights would look like two different moles, and
/// on a board where people reach across screens that is not a cosmetic problem.
///
/// The avocado is drawn rather than loaded. It is a handful of ovals, it tints
/// to any player colour for free, and it stays sharp at every density on the
/// table — which a sprite sized for one phone would not.
class GuacamoleView extends GameView {
  GuacamoleView(this.context);

  final ViewContext context;

  final _fill = Paint()..isAntiAlias = true;
  final _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  /// This phone's own player, and so its own colour.
  ///
  /// Known at build time now that the roster comes with the [ViewContext]: it
  /// is assembled from the slices the host already sends, which arrive with the
  /// layout. This used to be learned from the first HUD build, via a map the
  /// sim published into `sharedState` — a round trip through the wire for a
  /// fact the platform had all along.
  PlayerColor? get _myColor => context.me?.color;

  @override
  void render(Canvas canvas, Frame frame) {
    _drawBackground(canvas, frame);

    final moleStates = _moleStates(frame);

    // Holes first, so a mole always sits over its own hole rather than under
    // its neighbour's.
    for (final e in frame.ofKind('hole')) {
      _drawHole(canvas, e);
    }
    for (final e in frame.ofKind('mole')) {
      _drawMole(canvas, e, moleStates[e.id]);
    }

    _drawBorder(canvas, frame);
  }

  Map<String, Map<String, Object?>> _moleStates(Frame frame) {
    final raw = frame.sharedState['moles'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is Map)
          '${entry.key}': (entry.value as Map).cast<String, Object?>(),
    };
  }

  void _drawBackground(Canvas canvas, Frame frame) {
    final view = frame.visible;
    final board = frame.board;

    _fill.color = const Color(GuacamoleConfig.colorBackground);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
    final lawn = Rect.fromLTWH(
      board.left,
      board.top,
      board.width,
      board.height,
    );
    _fill.color = const Color(GuacamoleConfig.colorPlayfield);
    canvas.drawRect(lawn, _fill);

    // Mown in stripes, laid from the world origin rather than from this
    // screen's edge so they run unbroken from one phone to the next.
    const stripe = 2.5;
    final left = math.max(view.left, board.left);
    final right = math.min(view.right, board.right);
    canvas
      ..save()
      ..clipRect(lawn);
    _fill.color = const Color(GuacamoleConfig.colorLawnStripe);
    for (
      var x = (left / (stripe * 2)).floorToDouble() * stripe * 2;
      x < right;
      x += stripe * 2
    ) {
      canvas.drawRect(
        Rect.fromLTRB(x, board.top, x + stripe, board.bottom),
        _fill,
      );
    }
    canvas.restore();
  }

  void _drawHole(Canvas canvas, RenderEntity e) {
    final r = e.propDouble('r');
    final center = Offset(e.x, e.y + r * 0.62);

    // A squashed ellipse, not a circle: the board reads as a surface seen at an
    // angle, which is what makes a mole look like it is coming *out* of it.
    final rect = Rect.fromCenter(
      center: center,
      width: r * 2.15,
      height: r * 1.05,
    );

    _fill.color = const Color(GuacamoleConfig.colorHole);
    canvas.drawOval(rect, _fill);

    _stroke
      ..color = const Color(GuacamoleConfig.colorHoleRim)
      ..strokeWidth = r * 0.09;
    canvas.drawOval(rect, _stroke);
  }

  void _drawMole(Canvas canvas, RenderEntity e, Map<String, Object?>? state) {
    if (state == null) return;

    final phase = state['p'] as String?;
    final t = ((state['t'] as num?) ?? 0).toDouble() / 1000;
    final upSeconds = ((state['up'] as num?) ?? 1000).toDouble() / 1000;

    final r = e.propDouble('r');
    final skin = Color(e.propInt('color', 0xFFFFFFFF));

    // How far out of the hole, 0 to 1, and how squished, 0 to 1.
    var out = 1.0;
    var squish = 0.0;
    var fade = 1.0;

    switch (phase) {
      case 'rising':
        out = (t / GuacamoleConfig.riseSeconds).clamp(0.0, 1.0);
        out = _easeOutBack(out);
      case 'up':
        // A slow breath while it waits, so a still mole is not a dead one.
        final wobble =
            math.sin(t / math.max(upSeconds, 0.001) * math.pi) * 0.03;
        out = 1 + wobble;
      case 'sinking':
        out = 1 - (t / GuacamoleConfig.sinkSeconds).clamp(0.0, 1.0);
      case 'squished':
        final k = (t / GuacamoleConfig.squishSeconds).clamp(0.0, 1.0);
        squish = _easeOutCubic(k);
        fade = 1 - k;
      default:
        return;
    }

    if (out <= 0 || fade <= 0) return;

    canvas.save();
    // Clip to the hole so a rising mole emerges from it rather than sliding
    // across the board. Squished ones are splatted on the surface and want no
    // clip at all.
    if (squish == 0) {
      canvas.clipRect(
        Rect.fromLTWH(e.x - r * 1.6, e.y - r * 2.4, r * 3.2, r * 3.02),
      );
    }

    // Ride up out of the hole. The rest position sits a little above the
    // ellipse's centre so the body overlaps its own rim.
    final lift = r * 1.15 * out;
    final cx = e.x;
    final cy = e.y + r * 0.62 - lift;

    // Squishing: flatten vertically, bulge horizontally, and sink to the floor.
    final sx = 1 + squish * 0.55;
    final sy = 1 - squish * 0.72;
    final drop = squish * r * 0.5;

    canvas
      ..translate(cx, cy + drop)
      ..scale(sx, sy);

    _drawAvocado(canvas, r, skin, fade);

    if (squish > 0) _drawSplat(canvas, r, skin, squish, fade);

    canvas.restore();
  }

  /// The avocado itself, centred on the origin.
  ///
  /// Skin in the owner's colour is the load-bearing part: it is the one thing a
  /// player has to read correctly from across a table, so it gets the whole
  /// silhouette. The flesh and pit only ever appear *inside* it, and never grow
  /// large enough to compete.
  void _drawAvocado(Canvas canvas, double r, Color skin, double fade) {
    final a = (255 * fade).round().clamp(0, 255);

    // Body: an oval narrower at the top, like the fruit.
    final body = Rect.fromCenter(
      center: Offset.zero,
      width: r * 1.62,
      height: r * 2.05,
    );

    // A soft shadow under it, so it sits in the hole instead of floating.
    _fill.color = const Color(0x33000000).withValues(alpha: 0.18 * fade);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, r * 0.92),
        width: r * 1.5,
        height: r * 0.42,
      ),
      _fill,
    );

    _fill.color = skin.withAlpha(a);
    canvas.drawPath(_avocadoPath(body), _fill);

    // Flesh: the same silhouette, inset. Reads as the cut face of the fruit.
    _fill.color = const Color(
      GuacamoleConfig.colorFlesh,
    ).withValues(alpha: 0.92 * fade);
    canvas.drawPath(_avocadoPath(body.deflate(r * 0.19)), _fill);

    // Pit.
    _fill.color = const Color(GuacamoleConfig.colorPit).withValues(alpha: fade);
    canvas.drawCircle(Offset(0, r * 0.26), r * 0.42, _fill);

    _fill.color = const Color(
      GuacamoleConfig.colorPitHighlight,
    ).withValues(alpha: 0.75 * fade);
    canvas.drawCircle(Offset(-r * 0.13, r * 0.13), r * 0.15, _fill);

    _drawFace(canvas, r, fade);
  }

  /// A pear silhouette: narrow shoulders, round belly.
  Path _avocadoPath(Rect r) {
    final w = r.width;
    final h = r.height;
    final cx = r.center.dx;
    final top = r.top;
    final bottom = r.bottom;

    return Path()
      ..moveTo(cx, top)
      ..cubicTo(
        cx + w * 0.30,
        top + h * 0.04,
        cx + w * 0.40,
        top + h * 0.30,
        cx + w * 0.38,
        top + h * 0.52,
      )
      ..cubicTo(
        cx + w * 0.36,
        bottom - h * 0.10,
        cx + w * 0.22,
        bottom,
        cx,
        bottom,
      )
      ..cubicTo(
        cx - w * 0.22,
        bottom,
        cx - w * 0.36,
        bottom - h * 0.10,
        cx - w * 0.38,
        top + h * 0.52,
      )
      ..cubicTo(
        cx - w * 0.40,
        top + h * 0.30,
        cx - w * 0.30,
        top + h * 0.04,
        cx,
        top,
      )
      ..close();
  }

  /// Two eyes. Cheap, and it turns a shape into a creature worth hitting.
  void _drawFace(Canvas canvas, double r, double fade) {
    _fill.color = const Color(0xFF221100).withValues(alpha: 0.85 * fade);
    for (final dx in [-0.20, 0.20]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(r * dx, -r * 0.42),
          width: r * 0.17,
          height: r * 0.23,
        ),
        _fill,
      );
    }
  }

  /// Guacamole, briefly.
  void _drawSplat(
    Canvas canvas,
    double r,
    Color skin,
    double squish,
    double fade,
  ) {
    _fill.color = skin.withValues(alpha: 0.55 * fade);
    // Blobs flung outward, further as the squish develops.
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + 0.4;
      final reach = r * (0.95 + squish * 0.75);
      canvas.drawCircle(
        Offset(math.cos(angle) * reach, math.sin(angle) * reach * 0.45),
        r * 0.17 * (1 - squish * 0.4),
        _fill,
      );
    }
  }

  /// A frame in your own colour, so you never have to remember which you are.
  ///
  /// Drawn at the very edge of *this* screen rather than of the board, because
  /// it is a fact about the phone in front of you, not about the world.
  void _drawBorder(Canvas canvas, Frame frame) {
    final color = _myColor;
    if (color == null) return;

    final v = frame.visible;
    final w = math.min(v.width, v.height) * 0.022;

    _stroke
      ..color = color.value.withValues(alpha: 0.9)
      ..strokeWidth = w;
    canvas.drawRect(
      Rect.fromLTWH(v.left + w / 2, v.top + w / 2, v.width - w, v.height - w),
      _stroke,
    );
  }

  static double _easeOutBack(double t) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    final p = t - 1;
    return 1 + c3 * p * p * p + c1 * p * p;
  }

  static double _easeOutCubic(double t) {
    final p = 1 - t;
    return 1 - p * p * p;
  }

  // No HUD. The score is worth more as a surprise on the results screen than
  // as a number ticking in the corner while somebody is trying to hit moles,
  // and the clock is getting a home of its own.
}
