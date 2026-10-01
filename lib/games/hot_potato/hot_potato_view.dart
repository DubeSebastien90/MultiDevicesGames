import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/model/player_color.dart';
import '../../sdk/render/player_hand.dart';
import '../../sdk/render/shape_view.dart';
import 'hot_potato_art.dart';
import 'hot_potato_config.dart';

class HotPotatoView extends ShapeView {
  HotPotatoView({this.phoneId = '', super.roster = Roster.empty})
    : super(grid: false, playfield: const Color(_cloth)) {
    PlayerHand.preload([for (final p in roster.players) p.color]);
    HotPotatoArt.preload();
  }

  static const _cloth = 0xFFF2F9FF;
  static const _gingham = Color(0x66A9D6F2);

  static const _check = 1.4;

  final String phoneId;

  final _fill = Paint();

  final _smoke = <_Puff>[];
  final _random = math.Random();
  double _smokeOwed = 0;

  final _chunks = <_Chunk>[];

  double _blastAge = -1;

  @override
  void render(Canvas canvas, Frame frame) {
    renderBackground(canvas, frame);

    final heat = _heatOf(frame);
    final dt = frame.dt.clamp(0.0, 0.1);

    final calmDown = frame.sharedState['exploded'] == true
        ? 1 - (math.max(_blastAge, 0.0) / 0.4).clamp(0.0, 1.0)
        : 1.0;
    if (frame.sharedState['holder'] == phoneId && calmDown > 0) {
      _drawVignette(canvas, frame, heat * calmDown);
    }

    for (final arm in frame.ofKind('arm')) {
      _drawArm(canvas, arm);
    }

    final potato = frame.byId('potato');
    final shadow = frame.byId('potato-shadow');
    final blast = frame.byId('blast');

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
    _stepChunks(dt);

    if (shadow != null) _drawShadow(canvas, shadow, heat, height);
    _drawSmoke(canvas);
    if (potato != null) _drawPotato(canvas, frame, potato, heat, height);
    if (blast != null) _drawBlast(canvas, blast);
    _drawChunks(canvas);
  }

  @override
  void renderBackground(Canvas canvas, Frame frame) {
    final view = frame.visible;
    _fill.color = const Color(_cloth);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );

    _fill.color = _gingham;
    const period = _check * 2;
    for (
      var x = (view.left / period).floorToDouble() * period;
      x < view.right;
      x += period
    ) {
      canvas.drawRect(
        Rect.fromLTRB(x, view.top, x + _check, view.bottom),
        _fill,
      );
    }
    for (
      var y = (view.top / period).floorToDouble() * period;
      y < view.bottom;
      y += period
    ) {
      canvas.drawRect(
        Rect.fromLTRB(view.left, y, view.right, y + _check),
        _fill,
      );
    }
  }

  void _shade(ui.Shader shader) {
    _fill
      ..color = const Color(0xFFFFFFFF)
      ..shader = shader;
  }

  double _heatOf(Frame frame) {
    final left = (frame.sharedState['secondsLeft'] as num?)?.toDouble();
    final fuse =
        (frame.sharedState['fuse'] as num?)?.toDouble() ??
        HotPotatoConfig.fuseSeconds;
    if (left == null || fuse <= 0) return 0;
    return (1 - left / fuse).clamp(0.0, 1.0);
  }

  void _drawVignette(Canvas canvas, Frame frame, double heat) {
    if (heat <= 0) return;
    final view = frame.visible;
    final centre = Offset(frame.me.worldCenterX, frame.me.worldCenterY);
    final radius =
        math.sqrt(view.width * view.width + view.height * view.height) / 2;

    final beat = 1.5 + heat * 6;
    final pulse =
        0.8 + 0.2 * math.sin(frame.timeMs / 1000 * beat * 2 * math.pi);
    final strength = math.pow(heat, 1.4) * 0.7 * pulse;

    _shade(
      ui.Gradient.radial(
        centre,
        radius,
        [
          const Color(0x00FF2A12),
          Color(HotPotatoConfig.colorHot).withValues(alpha: strength * 0.35),
          Color(HotPotatoConfig.colorHot).withValues(alpha: strength),
        ],
        [0.25 - 0.2 * heat, 0.65, 1],
      ),
    );
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
    _fill.shader = null;
  }

  void _drawArm(Canvas canvas, RenderEntity arm) {
    final length = arm.propDouble(ShapeProps.width);
    final seat = arm.props[HotPotatoConfig.propSeat] as String?;
    final color = roster.byPhone(seat ?? '')?.color ?? PlayerPalette.away;
    PlayerHand.of(color).draw(
      canvas,
      Offset(
        arm.x + math.cos(arm.angle) * length / 2,
        arm.y + math.sin(arm.angle) * length / 2,
      ),
      angle: arm.angle,
      length: length,
      left: arm.props[HotPotatoConfig.propLeft] == true,
    );
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

    if (heat > 0.05) {
      _shade(
        ui.Gradient.radial(centre, r * (1.4 + 1.6 * heat), [
          Color(HotPotatoConfig.colorHot).withValues(alpha: 0.75 * heat),
          const Color(0x00FF2A12),
        ]),
      );
      canvas.drawCircle(centre, r * (1.4 + 1.6 * heat), _fill);
      _fill.shader = null;
    }

    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(potato.angle);

    final art = HotPotatoArt.of(excited: heat >= HotPotatoConfig.excitedFrom);
    if (art != null) {
      _drawPotatoArt(canvas, art, r, heat);
      canvas.restore();
      return;
    }

    final shape = Rect.fromCenter(
      center: Offset.zero,
      width: r * 2.4,
      height: r * 1.8,
    );
    _shade(
      ui.Gradient.radial(
        Offset(-r * 0.35, -r * 0.3),
        r * 1.4,
        [
          Color.lerp(body, const Color(0xFFFFF0C8), 0.35)!,
          body,
          Color.lerp(body, const Color(0xFF000000), 0.35)!,
        ],
        [0, 0.55, 1],
      ),
    );
    canvas.drawOval(shape, _fill);
    _fill.shader = null;

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

  void _drawPotatoArt(Canvas canvas, PictureInfo art, double r, double heat) {
    final scale = r * 2.4 / HotPotatoArt.length;
    final tint = Color.lerp(
      const Color(0xFFFFFFFF),
      Color(HotPotatoConfig.colorHot),
      0.85 * math.pow(heat, 1.2),
    )!;
    final tinted = heat > 0;
    if (tinted) {
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: r * 2),
        Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.modulate),
      );
    }
    canvas
      ..save()
      ..scale(scale)
      ..translate(-HotPotatoArt.centre.dx, -HotPotatoArt.centre.dy)
      ..drawPicture(art.picture)
      ..restore();
    if (tinted) canvas.restore();
  }

  double _radius(double heat) =>
      HotPotatoConfig.potatoRadius * (1 + heat * HotPotatoConfig.swellAtZero);

  void _emitSmoke(Frame frame, RenderEntity potato, double heat, double dt) {
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

    _smokeOwed += dt * HotPotatoConfig.smokeMaxPerSecond * math.pow(power, 1.5);
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

  void _blast(Frame frame, RenderEntity blast, double dt) {
    if (_blastAge >= 0) {
      _blastAge += dt;
      return;
    }
    _blastAge = 0;
    _burst(blast);
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

  void _burst(RenderEntity blast) {
    final r = HotPotatoConfig.potatoRadius;
    for (var i = 0; i < HotPotatoConfig.blastChunks; i++) {
      final a = _random.nextDouble() * 2 * math.pi;
      final speed = 10 + _random.nextDouble() * 22;
      final flesh = _random.nextDouble() < 0.3;
      _chunks.add(
        _Chunk(
          x: blast.x,
          y: blast.y,
          vx: math.cos(a) * speed,
          vy: math.sin(a) * speed,
          angle: _random.nextDouble() * 2 * math.pi,
          spin: (_random.nextDouble() - 0.5) * 20,
          size: r * (0.18 + _random.nextDouble() * 0.3),
          life: 1.2 + _random.nextDouble() * 0.7,
          colour: flesh
              ? Color.lerp(
                  const Color(0xFFF7E3A1),
                  const Color(0xFFE8B45A),
                  _random.nextDouble(),
                )!
              : Color.lerp(
                  Color(HotPotatoConfig.colorPotato),
                  Color(HotPotatoConfig.colorHot),
                  0.5 + _random.nextDouble() * 0.5,
                )!,
        ),
      );
    }
  }

  void _stepChunks(double dt) {
    final drag = math.exp(-3.2 * dt);
    for (final c in _chunks) {
      c.age += dt;
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      c.vx *= drag;
      c.vy *= drag;
      c.angle += c.spin * dt;
      c.spin *= drag;
    }
    _chunks.removeWhere((c) => c.age >= c.life);
  }

  void _drawChunks(Canvas canvas) {
    for (final c in _chunks) {
      final t = c.age / c.life;
      final alpha = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
      canvas
        ..save()
        ..translate(c.x, c.y)
        ..rotate(c.angle);
      _fill.color = Color.lerp(
        c.colour,
        const Color(0xFF000000),
        0.35,
      )!.withValues(alpha: alpha);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: c.size * 2.3,
          height: c.size * 1.6,
        ),
        _fill,
      );
      _fill.color = c.colour.withValues(alpha: alpha);
      canvas
        ..drawOval(
          Rect.fromCenter(
            center: Offset(-c.size * 0.1, -c.size * 0.1),
            width: c.size * 1.9,
            height: c.size * 1.25,
          ),
          _fill,
        )
        ..restore();
    }
  }

  void _stepSmoke(double dt) {
    for (final p in _smoke) {
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;

      final drag = math.exp(-1.8 * dt);
      p.vx *= drag;
      p.vy *= drag;
    }
    _smoke.removeWhere((p) => p.age >= p.life);
  }

  void _drawSmoke(Canvas canvas) {
    for (final p in _smoke) {
      final t = p.age / p.life;

      final smoke = Color.lerp(
        const Color(0xFF9C9C9C),
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

  void _drawBlast(Canvas canvas, RenderEntity blast) {
    final full = blast.propDouble(ShapeProps.radius);
    final t = math.max(_blastAge, 0.0);
    final bloom = 1 - math.pow(1 - math.min(t / 0.35, 1), 3);
    final r = full * (0.3 + 0.7 * bloom);

    final fade = 1 - ((t - 0.3) / 0.8).clamp(0.0, 1.0);
    if (fade <= 0) return;

    _shade(
      ui.Gradient.radial(
        Offset(blast.x, blast.y),
        r,
        [
          const Color(0xFFFFFBE6).withValues(alpha: fade),
          const Color(0xFFFFB02E).withValues(alpha: fade),
          Color(HotPotatoConfig.colorBlast).withValues(alpha: 0.85 * fade),
          const Color(0x00FF2A12),
        ],
        [0, 0.3, 0.7, 1],
      ),
    );
    canvas.drawCircle(Offset(blast.x, blast.y), r, _fill);
    _fill.shader = null;
  }

  Offset _towardMiddle(Frame frame, double x, double y) {
    final dx = frame.board.centerX - x;
    final dy = frame.board.centerY - y;
    final len = math.sqrt(dx * dx + dy * dy);
    return len < 1e-9 ? const Offset(0, -1) : Offset(dx / len, dy / len);
  }

  @override
  void dispose() {
    _smoke.clear();
    _chunks.clear();
  }
}

class _Chunk {
  _Chunk({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.size,
    required this.life,
    required this.colour,
  });

  double x;
  double y;
  double vx;
  double vy;
  double angle;
  double spin;
  double age = 0;
  final double size;
  final double life;
  final Color colour;
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

  final double power;
}
