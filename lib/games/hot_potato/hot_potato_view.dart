import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'hot_potato_config.dart';

/// Hot Potato's look: grey arms juggling a potato that gets redder, spins
/// faster and smokes harder as the fuse burns down.
///
/// Where the potato is, how high, how fast it spins — all of that arrives as
/// transforms from the sim, identical on every screen. The *heat* does not: an
/// entity's props are sent once, so the colour, the swell, the glow and the
/// smoke are all read here off the fuse in `sharedState`.
class HotPotatoView extends ShapeView {
  HotPotatoView({this.phoneId = ''})
    : super(grid: false, playfield: const Color(0xFF141C33));

  /// This screen's phone, so the holder's screen can be the one that burns.
  final String phoneId;

  // No HUD. The fuse belongs on the potato — how long is left is a thing to
  // read off the object being passed around, not off a corner of the screen —
  // and a phone that has it does not need telling: it is the one with the
  // potato drawn on it.

  final _fill = Paint();

  /// Smoke is local: it drifts on this phone's own clock and nobody else needs
  /// to agree on where a wisp went. The phones sit apart, so there is no seam
  /// for two screens' smoke to disagree across.
  final _smoke = <_Puff>[];
  final _random = math.Random();
  double _smokeOwed = 0;

  /// How long the blast has been on screen here, for its bloom.
  double _blastAge = -1;

  @override
  void render(Canvas canvas, Frame frame) {
    renderBackground(canvas, frame);

    final heat = _heatOf(frame);
    final dt = frame.dt.clamp(0.0, 0.1);

    if (frame.sharedState['holder'] == phoneId) {
      _drawVignette(canvas, frame, heat);
    }

    for (final arm in frame.ofKind('arm')) {
      _drawArm(canvas, arm);
    }

    final potato = frame.byId('potato');
    final shadow = frame.byId('potato-shadow');
    final blast = frame.byId('blast');

    // How high it is, recovered from how far it has been nudged off its
    // shadow — the sim draws height as a shift toward the middle of the table.
    final height = potato == null || shadow == null
        ? 0.0
        : math.sqrt(
                math.pow(potato.x - shadow.x, 2) +
                    math.pow(potato.y - shadow.y, 2),
              ) /
              HotPotatoConfig.heightShown;

    if (potato != null) _emitSmoke(frame, potato, heat, dt);
    if (blast != null) _blast(frame, blast, dt);
    if (blast == null) _blastAge = -1;
    _stepSmoke(dt);

    if (shadow != null) _drawShadow(canvas, shadow, heat, height);
    _drawSmoke(canvas);
    if (potato != null) _drawPotato(canvas, frame, potato, heat, height);
    if (blast != null) _drawBlast(canvas, blast);
  }

  /// 0 when the fuse is lit, 1 when it goes off.
  double _heatOf(Frame frame) {
    final left = (frame.sharedState['secondsLeft'] as num?)?.toDouble();
    final fuse =
        (frame.sharedState['fuse'] as num?)?.toDouble() ??
        HotPotatoConfig.fuseSeconds;
    if (left == null || fuse <= 0) return 0;
    return (1 - left / fuse).clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------- layers

  /// The holder's screen reddens from the edges in, harder and faster-pulsing
  /// as the end comes.
  void _drawVignette(Canvas canvas, Frame frame, double heat) {
    if (heat <= 0) return;
    final view = frame.visible;
    final centre = Offset(frame.me.worldCenterX, frame.me.worldCenterY);
    final radius = math.sqrt(
          view.width * view.width + view.height * view.height,
        ) /
        2;

    final beat = 1.5 + heat * 6; // Beats per second.
    final pulse = 0.8 + 0.2 * math.sin(frame.timeMs / 1000 * beat * 2 * math.pi);
    final strength = math.pow(heat, 1.4) * 0.7 * pulse;

    _fill.shader = ui.Gradient.radial(
      centre,
      radius,
      [
        const Color(0x00FF2A12),
        Color(HotPotatoConfig.colorHot).withValues(alpha: strength * 0.35),
        Color(HotPotatoConfig.colorHot).withValues(alpha: strength),
      ],
      [0.25 - 0.2 * heat, 0.65, 1],
    );
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
    _fill.shader = null;
  }

  /// Placeholder arms: grey bars, until the art arrives.
  void _drawArm(Canvas canvas, RenderEntity arm) {
    final w = arm.propDouble(ShapeProps.width);
    final h = arm.propDouble(ShapeProps.height);
    _fill.color = Color(arm.propInt(ShapeProps.color, HotPotatoConfig.colorArm));
    canvas
      ..save()
      ..translate(arm.x, arm.y)
      ..rotate(arm.angle)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          Radius.circular(h * 0.35),
        ),
        _fill,
      )
      ..restore();
  }

  void _drawShadow(
    Canvas canvas,
    RenderEntity shadow,
    double heat,
    double height,
  ) {
    final r = _radius(heat) * (1 - math.min(height * 0.05, 0.4));
    final alpha = (0.35 - height * 0.03).clamp(0.1, 0.35);
    _fill.color = Color.fromRGBO(0, 0, 0, alpha);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(shadow.x, shadow.y),
        width: r * 2.3,
        height: r * 1.8,
      ),
      _fill,
    );
  }

  void _drawPotato(
    Canvas canvas,
    Frame frame,
    RenderEntity potato,
    double heat,
    double height,
  ) {
    final centre = Offset(potato.x, potato.y);
    // Near the end it throbs, as if it were about to split.
    final throb =
        1 +
        0.07 *
            math.pow(heat, 3) *
            math.sin(frame.timeMs / 1000 * (4 + heat * 10) * 2 * math.pi);
    final r =
        _radius(heat) * (1 + height * HotPotatoConfig.heightGrowth) * throb;

    final body = Color.lerp(
      Color(HotPotatoConfig.colorPotato),
      Color(HotPotatoConfig.colorHot),
      math.pow(heat, 1.2).toDouble(),
    )!;

    // The glow: nothing when it is fresh, a red halo by the end.
    if (heat > 0.05) {
      _fill.shader = ui.Gradient.radial(
        centre,
        r * (1.4 + 1.6 * heat),
        [
          Color(HotPotatoConfig.colorHot).withValues(alpha: 0.75 * heat),
          const Color(0x00FF2A12),
        ],
      );
      canvas.drawCircle(centre, r * (1.4 + 1.6 * heat), _fill);
      _fill.shader = null;
    }

    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(potato.angle);

    // Lumpy, not round — a circle spinning looks like it is standing still.
    final shape = Rect.fromCenter(
      center: Offset.zero,
      width: r * 2.4,
      height: r * 1.8,
    );
    _fill.shader = ui.Gradient.radial(
      Offset(-r * 0.35, -r * 0.3),
      r * 1.4,
      [
        Color.lerp(body, const Color(0xFFFFF0C8), 0.35)!,
        body,
        Color.lerp(body, const Color(0xFF000000), 0.35)!,
      ],
      [0, 0.55, 1],
    );
    canvas.drawOval(shape, _fill);
    _fill.shader = null;

    // Eyes of the potato — the marks that make the spin readable.
    _fill.color = Color.lerp(body, const Color(0xFF3A1A08), 0.55)!;
    for (final (x, y, s) in const [
      (0.55, -0.2, 0.13),
      (-0.3, 0.35, 0.11),
      (-0.65, -0.25, 0.09),
      (0.15, 0.45, 0.08),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x * r, y * r),
          width: s * r * 2.2,
          height: s * r * 1.6,
        ),
        _fill,
      );
    }
    canvas.restore();
  }

  double _radius(double heat) =>
      HotPotatoConfig.potatoRadius * (1 + heat * HotPotatoConfig.swellAtZero);

  // ----------------------------------------------------------------- smoke

  void _emitSmoke(Frame frame, RenderEntity potato, double heat, double dt) {
    // Only the screens that can see it bother.
    final view = frame.visible.inflate(6);
    if (potato.x < view.left ||
        potato.x > view.right ||
        potato.y < view.top ||
        potato.y > view.bottom) {
      _smokeOwed = 0;
      return;
    }

    final power =
        ((heat - HotPotatoConfig.smokeFrom) / (1 - HotPotatoConfig.smokeFrom))
            .clamp(0.0, 1.0);
    if (power <= 0) return;

    _smokeOwed +=
        dt * HotPotatoConfig.smokeMaxPerSecond * math.pow(power, 1.5);
    final r = _radius(heat);
    final up = _towardMiddle(frame, potato.x, potato.y);
    while (_smokeOwed >= 1) {
      _smokeOwed -= 1;
      final a = _random.nextDouble() * 2 * math.pi;
      final drift = 0.6 + _random.nextDouble() * 1.2;
      final rise = 1.5 + power * 4 + _random.nextDouble() * 1.5;
      _smoke.add(
        _Puff(
          x: potato.x + math.cos(a) * r * 0.6,
          y: potato.y + math.sin(a) * r * 0.6,
          vx: up.dx * rise + math.cos(a) * drift,
          vy: up.dy * rise + math.sin(a) * drift,
          life: 0.6 + power * 0.9 + _random.nextDouble() * 0.3,
          size: r * (0.35 + 0.35 * power),
          grow: r * (0.8 + 1.4 * power),
          power: power,
        ),
      );
    }
  }

  /// The bang: one thick burst of smoke, once, on this screen.
  void _blast(Frame frame, RenderEntity blast, double dt) {
    if (_blastAge >= 0) {
      _blastAge += dt;
      return;
    }
    _blastAge = 0;
    final r = blast.propDouble(ShapeProps.radius);
    for (var i = 0; i < 40; i++) {
      final a = _random.nextDouble() * 2 * math.pi;
      final speed = 4 + _random.nextDouble() * 10;
      _smoke.add(
        _Puff(
          x: blast.x,
          y: blast.y,
          vx: math.cos(a) * speed,
          vy: math.sin(a) * speed,
          life: 0.9 + _random.nextDouble() * 0.8,
          size: r * 0.25,
          grow: r * 0.6,
          power: 1,
        ),
      );
    }
  }

  void _stepSmoke(double dt) {
    for (final p in _smoke) {
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      // Smoke slows as it spreads.
      final drag = math.exp(-1.8 * dt);
      p.vx *= drag;
      p.vy *= drag;
    }
    _smoke.removeWhere((p) => p.age >= p.life);
  }

  void _drawSmoke(Canvas canvas) {
    for (final p in _smoke) {
      final t = p.age / p.life;
      // Hotter smoke is thicker and darker, and starts as a glowing ember.
      final smoke = Color.lerp(
        const Color(0xFFD9D9D9),
        const Color(0xFF2E2A28),
        p.power,
      )!;
      final ember = Color.lerp(
        const Color(0xFFFFB347),
        Color(HotPotatoConfig.colorHot),
        p.power,
      )!;
      final colour = p.power > 0.5
          ? Color.lerp(ember, smoke, math.min(t * 3, 1))!
          : smoke;
      final alpha = (0.25 + 0.45 * p.power) * (1 - t) * (1 - t);
      _fill.color = colour.withValues(alpha: alpha);
      canvas.drawCircle(Offset(p.x, p.y), p.size + p.grow * t, _fill);
    }
  }

  // ----------------------------------------------------------------- blast

  void _drawBlast(Canvas canvas, RenderEntity blast) {
    final full = blast.propDouble(ShapeProps.radius);
    final t = math.max(_blastAge, 0.0);
    final bloom = 1 - math.pow(1 - math.min(t / 0.35, 1), 3);
    final r = full * (0.3 + 0.7 * bloom);
    // Bright, then settling into an ember that stays for the results.
    final fade = 1 - 0.5 * math.min(math.max(t - 0.4, 0) / 0.8, 1);

    _fill.shader = ui.Gradient.radial(
      Offset(blast.x, blast.y),
      r,
      [
        const Color(0xFFFFFBE6).withValues(alpha: fade),
        const Color(0xFFFFB02E).withValues(alpha: fade),
        Color(HotPotatoConfig.colorBlast).withValues(alpha: 0.85 * fade),
        const Color(0x00FF2A12),
      ],
      [0, 0.3, 0.7, 1],
    );
    canvas.drawCircle(Offset(blast.x, blast.y), r, _fill);
    _fill.shader = null;
  }

  // ----------------------------------------------------------------- misc

  /// "Up" from a seat is toward the middle of the table.
  Offset _towardMiddle(Frame frame, double x, double y) {
    final dx = frame.board.centerX - x;
    final dy = frame.board.centerY - y;
    final len = math.sqrt(dx * dx + dy * dy);
    return len < 1e-9 ? const Offset(0, -1) : Offset(dx / len, dy / len);
  }

  @override
  void dispose() {
    _smoke.clear();
  }
}

class _Puff {
  _Puff({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.grow,
    required this.power,
  });

  double x;
  double y;
  double vx;
  double vy;
  double age = 0;
  final double life;
  final double size;
  final double grow;

  /// How hot the potato was when this left it, 0 to 1.
  final double power;
}
