import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player_color.dart';
import 'guacamole_config.dart';

class GuacamoleView extends GameView {
  GuacamoleView(this.context);

  final ViewContext context;

  final _fill = Paint()..isAntiAlias = true;
  final _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  PlayerColor? get _myColor => context.me?.color;

  @override
  void render(Canvas canvas, Frame frame) {
    _drawBackground(canvas, frame);

    final moleStates = _moleStates(frame);

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

    var out = 1.0;
    var squish = 0.0;
    var fade = 1.0;

    switch (phase) {
      case 'rising':
        out = (t / GuacamoleConfig.riseSeconds).clamp(0.0, 1.0);
        out = _easeOutBack(out);
      case 'up':
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

    if (squish == 0) {
      canvas.clipRect(
        Rect.fromLTWH(e.x - r * 1.6, e.y - r * 2.4, r * 3.2, r * 3.02),
      );
    }

    final lift = r * 1.15 * out - _buried * r * (1 - out);
    final cx = e.x;
    final cy = e.y + r * 0.62 - lift;

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

  static const double _buried = 1.08;

  void _drawAvocado(Canvas canvas, double r, Color skin, double fade) {
    final a = (255 * fade).round().clamp(0, 255);

    final body = Rect.fromCenter(
      center: Offset.zero,
      width: r * 1.62,
      height: r * 2.05,
    );

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

    _fill.color = const Color(
      GuacamoleConfig.colorFlesh,
    ).withValues(alpha: 0.92 * fade);
    canvas.drawPath(_avocadoPath(body.deflate(r * 0.19)), _fill);

    _fill.color = const Color(GuacamoleConfig.colorPit).withValues(alpha: fade);
    canvas.drawCircle(Offset(0, r * 0.26), r * 0.42, _fill);

    _fill.color = const Color(
      GuacamoleConfig.colorPitHighlight,
    ).withValues(alpha: 0.75 * fade);
    canvas.drawCircle(Offset(-r * 0.13, r * 0.13), r * 0.15, _fill);

    _drawFace(canvas, r, fade);
  }

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

  void _drawSplat(
    Canvas canvas,
    double r,
    Color skin,
    double squish,
    double fade,
  ) {
    _fill.color = skin.withValues(alpha: 0.55 * fade);

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
}
