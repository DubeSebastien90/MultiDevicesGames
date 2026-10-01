import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/render/particle_burst.dart';
import '../../sdk/render/player_animation.dart';
import 'arena_config.dart';
import 'lightsaber_art.dart';

class ArenaView extends GameView {
  ArenaView({
    required this.phoneId,
    this.characters = PlayerAnimations.none,
    this.roster = Roster.empty,
  }) {
    LightsaberArt.preload([
      const Color(ArenaConfig.swordColor),
      for (final p in roster.players) p.color.value,
    ]);
  }

  final String phoneId;

  final PlayerAnimations characters;

  final Roster roster;

  static const _floorColor = Color(0xFFEBD0A2);
  static const _rake = Color(0x33B98A4E);
  static const _ring = Color(0xFFD2A76C);
  static const _gritDark = Color(0x55976A36);
  static const _gritLight = Color(0x66FFF3DC);
  static const _ink = Color(0xFF191510);

  static const _rakeGap = 0.45;

  static const _gritCell = 0.7;

  static const _messageMargin = 0.06;

  static const _walkingSpeed = 0.5;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  final _lastSeen = <String, Offset>{};

  final _burstAt = <String, double>{};

  final _impactSeen = <String, int>{};
  final _impactAt = <String, double>{};

  @override
  void render(Canvas canvas, Frame frame) {
    _drawFloor(canvas, frame);

    for (final e in frame.ofKind('sword')) {
      if (frame.sharedState['alive_p${e.propInt('index')}'] != true) continue;
      _drawGrip(canvas, e);
    }

    final fighters = frame.ofKind('fighter').toList();

    for (final e in fighters) {
      final idx = e.propInt('index');
      final key = 'p$idx';
      final color = Color(e.propInt('color', 0xFFFFFFFF));
      final radius = e.propDouble('radius', ArenaConfig.characterRadius);
      final alive = frame.sharedState['alive_$key'] == true;
      if (!alive) continue;

      final isStunned = frame.sharedState['stunned_$key'] == true;
      final isInvincible = frame.sharedState['invincible_$key'] == true;
      final lives =
          (frame.sharedState['lives_$key'] as num?)?.toInt() ??
          ArenaConfig.maxLives;

      final guard = _guardCharge(frame, key);
      if (guard < 1 && frame.sharedState['blocking_$key'] != true) {
        _stroke
          ..color = _colorOf(frame, key).withValues(alpha: 0.85)
          ..strokeWidth = radius * ArenaConfig.guardRingWidth;
        canvas.drawArc(
          Rect.fromCircle(
            center: Offset(e.x, e.y),
            radius: radius * ArenaConfig.guardRingRadius,
          ),
          -math.pi / 2,
          2 * math.pi * guard,
          false,
          _stroke,
        );
      }

      if (isInvincible) {
        final pulse = 0.5 + 0.5 * math.sin(frame.timeMs / 100);
        _stroke
          ..color = Color.fromARGB((pulse * 200).toInt(), 255, 255, 255)
          ..strokeWidth = radius * 0.15;
        canvas.drawCircle(Offset(e.x, e.y), radius * 1.3, _stroke);
      }

      final here = Offset(e.x, e.y);
      final before = _lastSeen[e.id];
      _lastSeen[e.id] = here;
      final moving =
          !isStunned &&
          before != null &&
          frame.dt > 0 &&
          (here - before).distance / frame.dt > _walkingSpeed;

      final seated = roster.byPhone(e.props['phoneId'] as String? ?? '');
      if (seated == null) {
        _fill.color = isStunned ? color.withAlpha(140) : color;
        canvas.drawCircle(here, radius, _fill);
      } else {
        final character = characters.of(seated.color);
        moving ? character.start() : character.stop();
        character.draw(
          canvas,
          here,
          worldSize: radius * 3,
          dt: frame.dt,
          angle: e.angle,
        );
      }

      _drawLives(canvas, Offset(e.x, e.y), radius, lives);

      if (isStunned) {
        _fill.color = const Color(0xFFFFDD44);
        final spin = frame.timeMs / 320;
        for (var s = 0; s < 3; s++) {
          final a = spin + s * (2 * math.pi / 3);
          _drawStar(
            canvas,
            e.x + math.cos(a) * radius * 1.2,
            e.y + math.sin(a) * radius * 1.2,
            radius * 0.16,
            _fill,
          );
        }
      }
    }

    _drawDeaths(canvas, frame);
    _drawImpacts(canvas, frame);

    for (final e in frame.ofKind('sword')) {
      final key = 'p${e.propInt('index')}';
      if (frame.sharedState['alive_$key'] != true) continue;
      _drawSword(canvas, e, _colorOf(frame, key));
    }

    _drawJoystick(canvas, frame);

    final phase = frame.sharedState['phase'];
    if (phase == 'briefing') {
      final step = (frame.sharedState['step'] as num?)?.toInt() ?? 0;
      if (step >= 0 && step < ArenaConfig.briefingLines.length) {
        _drawCentered(
          canvas,
          frame,
          ArenaConfig.briefingLines[step],
          frame.me.halfWidth * 2 * 0.1,
        );
      }
    } else if (phase == 'countdown') {
      final cd = (frame.sharedState['countdown'] as num?)?.toDouble() ?? 0;
      final go = cd <= ArenaConfig.goSeconds;
      _drawCentered(
        canvas,
        frame,
        go ? 'GO' : (cd - ArenaConfig.goSeconds).ceil().toString(),
        frame.me.halfWidth * 2 * (go ? 0.22 : 0.3),
      );
    }
  }

  void _drawDeaths(Canvas canvas, Frame frame) {
    for (var i = 0; i < 8; i++) {
      final key = 'p$i';
      if (frame.sharedState['phoneId_$key'] == null) break;

      if (frame.sharedState['alive_$key'] == true) {
        _burstAt.remove(key);
        continue;
      }

      final started = _burstAt[key] ??= frame.timeMs;
      final t = (frame.timeMs - started) / 1000 / ArenaConfig.deathBurstSeconds;
      if (t < 0 || t >= 1) continue;

      final x = (frame.sharedState['deadX_$key'] as num?)?.toDouble();
      final y = (frame.sharedState['deadY_$key'] as num?)?.toDouble();
      if (x == null || y == null) continue;

      _drawBurst(
        canvas,
        Offset(x, y),
        _colorOf(frame, key),
        t,
        count: ArenaConfig.deathParticles,
        speed: ArenaConfig.deathBurstSpeed,
        seconds: ArenaConfig.deathBurstSeconds,
      );
    }
  }

  void _drawImpacts(Canvas canvas, Frame frame) {
    for (var i = 0; i < 8; i++) {
      final key = 'p$i';
      if (frame.sharedState['phoneId_$key'] == null) break;

      final count = (frame.sharedState['impacts_$key'] as num?)?.toInt() ?? 0;
      if (count == 0) {
        _impactSeen.remove(key);
        _impactAt.remove(key);
        continue;
      }

      if (_impactSeen[key] != count) {
        _impactSeen[key] = count;
        _impactAt[key] = frame.timeMs;
      }

      final started = _impactAt[key];
      if (started == null) continue;
      final t = (frame.timeMs - started) / 1000 / ArenaConfig.hitBurstSeconds;
      if (t < 0 || t >= 1) continue;

      final x = (frame.sharedState['impactX_$key'] as num?)?.toDouble();
      final y = (frame.sharedState['impactY_$key'] as num?)?.toDouble();
      if (x == null || y == null) continue;

      final parried = frame.sharedState['impactKind_$key'] == 'parry';
      final color = parried
          ? const Color(ArenaConfig.parryColor)
          : _colorOf(frame, key);

      _drawBurst(
        canvas,
        Offset(x, y),
        color,
        t,
        count: ArenaConfig.hitParticles,
        speed: ArenaConfig.hitBurstSpeed,
        seconds: ArenaConfig.hitBurstSeconds,
      );
    }
  }

  Color _colorOf(Frame frame, String key) {
    final phoneId = frame.sharedState['phoneId_$key'] as String? ?? '';
    final seated = roster.byPhone(phoneId);
    return seated?.color.value ??
        Color((frame.sharedState['color_$key'] as num?)?.toInt() ?? 0xFFFFFFFF);
  }

  void _drawBurst(
    Canvas canvas,
    Offset at,
    Color color,
    double t, {
    required int count,
    required double speed,
    required double seconds,
  }) => drawParticleBurst(
    canvas,
    _fill,
    at,
    color,
    t,
    count: count,
    speed: speed,
    seconds: seconds,
    particleRadius:
        ArenaConfig.characterRadius * ArenaConfig.deathParticleScale,
  );

  double _guardCharge(Frame frame, String key) {
    if (frame.sharedState['blocking_$key'] == true) return 0;
    final left = (frame.sharedState['blkCd_$key'] as num?)?.toDouble() ?? 0;
    if (left <= 0) return 1;
    final charge = 1 - left / ArenaConfig.blockCooldown;
    return charge < 0 ? 0 : (charge > 1 ? 1 : charge);
  }

  void _drawGrip(Canvas canvas, RenderEntity e) {
    canvas
      ..save()
      ..translate(e.x, e.y)
      ..rotate(e.angle);
    LightsaberArt.draw(
      canvas,
      const Color(ArenaConfig.swordColor),
      length: e.propDouble('length', ArenaConfig.swordLength),
      to: 0,
    );
    canvas.restore();
  }

  void _drawSword(Canvas canvas, RenderEntity e, Color color) {
    final length = e.propDouble('length', ArenaConfig.swordLength);
    final width = e.propDouble('width', ArenaConfig.swordWidth);

    canvas.save();
    canvas.translate(e.x, e.y);
    canvas.rotate(e.angle);

    final blade = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, -width / 2, length, width),
      Radius.circular(width / 2),
    );

    _fill
      ..color = color.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 1.6);
    canvas.drawRRect(blade, _fill);
    _fill.maskFilter = null;

    if (LightsaberArt.isLoaded(color)) {
      LightsaberArt.draw(canvas, color, length: length, from: 0, to: length);
      canvas.restore();
      return;
    }

    _fill.color = const Color(0xFF6B7280);
    canvas.drawRect(
      Rect.fromLTWH(-width * 0.6, -width * 1.8, width * 1.2, width * 3.6),
      _fill,
    );
    _fill.color = color;
    canvas.drawRRect(blade, _fill);

    canvas.restore();
  }

  void _drawLives(Canvas canvas, Offset at, double radius, int lives) {
    if (lives <= 0) return;

    final dot = radius * 0.22;
    final gap = dot * 3;

    final top = at.dy - radius - dot * 5.5;
    final left = at.dx - gap * (lives - 1) / 2;

    _fill.color = const Color(0xFFFF4444);
    for (var i = 0; i < lives; i++) {
      canvas.drawCircle(Offset(left + gap * i, top), dot, _fill);
    }
  }

  void _drawJoystick(Canvas canvas, Frame frame) {
    final key = _myKey(frame.sharedState);
    if (key == null) return;

    final ax = (frame.sharedState['stickX_$key'] as num?)?.toDouble();
    final ay = (frame.sharedState['stickY_$key'] as num?)?.toDouble();

    if (ax == null || ay == null) return;
    final tx = (frame.sharedState['stickToX_$key'] as num?)?.toDouble() ?? ax;
    final ty = (frame.sharedState['stickToY_$key'] as num?)?.toDouble() ?? ay;

    final anchor = Offset(ax, ay);
    final pushed = Offset(tx - ax, ty - ay);
    final reach = ArenaConfig.joystickRadius;

    final tilt = pushed.distance > reach
        ? pushed * (reach / pushed.distance)
        : pushed;
    final knob = anchor + tilt;

    final blocking = frame.sharedState['blocking_$key'] == true;

    final ringColor = blocking ? const Color(0xFF4488FF) : _ink;

    _fill.color = _ink.withAlpha(ArenaConfig.joystickWellAlpha);
    canvas.drawCircle(anchor, reach, _fill);

    _stroke
      ..color = ringColor.withAlpha(ArenaConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.04);
    canvas.drawCircle(anchor, reach, _stroke);

    _stroke
      ..color = ringColor.withAlpha(ArenaConfig.joystickDeadZoneAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(anchor, ArenaConfig.minMoveDistance, _stroke);

    if (tilt.distance > 0) {
      _stroke
        ..color = ringColor.withAlpha(ArenaConfig.joystickDeadZoneAlpha)
        ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.03);
      canvas.drawLine(anchor, knob, _stroke);
    }

    final me = roster.byPhone(phoneId);
    final knobColor = me?.color.value ?? const Color(0xFFFFFFFF);
    _fill.color = knobColor.withAlpha(ArenaConfig.joystickKnobAlpha);
    canvas.drawCircle(knob, ArenaConfig.joystickKnobRadius, _fill);
    _stroke
      ..color = _ink.withAlpha(ArenaConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(knob, ArenaConfig.joystickKnobRadius, _stroke);
  }

  void _drawFloor(Canvas canvas, Frame frame) {
    final view = frame.visible;
    final area = Rect.fromLTWH(view.left, view.top, view.width, view.height);
    _fill.color = _floorColor;
    canvas.drawRect(area, _fill);

    final board = frame.board;
    final centre = Offset(board.centerX, board.centerY);

    final near =
        (Offset(
                  centre.dx.clamp(area.left, area.right),
                  centre.dy.clamp(area.top, area.bottom),
                ) -
                centre)
            .distance;
    var far = 0.0;
    for (final corner in [
      area.topLeft,
      area.topRight,
      area.bottomLeft,
      area.bottomRight,
    ]) {
      far = math.max(far, (corner - centre).distance);
    }
    _stroke
      ..color = _rake
      ..strokeWidth = 0.05;
    for (
      var r = math.max(_rakeGap, (near / _rakeGap).floorToDouble() * _rakeGap);
      r <= far;
      r += _rakeGap
    ) {
      canvas.drawCircle(centre, r, _stroke);
    }

    final ring = math.min(board.width, board.height) * 0.42;
    _stroke
      ..color = _ring
      ..strokeWidth = 0.3;
    canvas.drawCircle(centre, ring, _stroke);

    _drawGrit(canvas, area);
  }

  void _drawGrit(Canvas canvas, Rect area) {
    final x0 = (area.left / _gritCell).floor();
    final x1 = (area.right / _gritCell).ceil();
    final y0 = (area.top / _gritCell).floor();
    final y1 = (area.bottom / _gritCell).ceil();
    for (var ix = x0; ix <= x1; ix++) {
      for (var iy = y0; iy <= y1; iy++) {
        final h = _hash(ix, iy);
        final dx = (h % 97) / 97;
        final dy = (h ~/ 97 % 89) / 89;
        final size = 0.03 + (h ~/ 8633 % 5) * 0.012;
        _fill.color = h % 3 == 0 ? _gritLight : _gritDark;
        canvas.drawCircle(
          Offset((ix + dx) * _gritCell, (iy + dy) * _gritCell),
          size,
          _fill,
        );
      }
    }
  }

  static int _hash(int x, int y) {
    const m = 1000003;
    var h = ((x * 7919 + y * 104729) % m + m) % m;
    h = (h * h + 12345) % m;
    return (h * 31 + x % 17) % m;
  }

  String? _myKey(Map<String, Object?> sharedState) {
    for (var i = 0; i < 8; i++) {
      if (sharedState['phoneId_p$i'] == phoneId) return 'p$i';
    }
    return null;
  }

  void _drawStar(Canvas canvas, double cx, double cy, double r, Paint paint) {
    final path = ui.Path();
    for (var i = 0; i < 5; i++) {
      final outerAngle = -math.pi / 2 + i * 2 * math.pi / 5;
      final innerAngle = outerAngle + math.pi / 5;
      final ox = cx + r * math.cos(outerAngle);
      final oy = cy + r * math.sin(outerAngle);
      final ix = cx + r * 0.4 * math.cos(innerAngle);
      final iy = cy + r * 0.4 * math.sin(innerAngle);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawCentered(Canvas canvas, Frame frame, String text, double size) {
    final me = frame.me;
    final width = me.halfWidth * 2;

    final px = me.logicalPxPerWorldUnit;

    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: size * px),
          )
          ..pushStyle(ui.TextStyle(color: _ink, fontWeight: FontWeight.w900))
          ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width * px));

    final half = paragraph.height / px / 2;
    final margin = me.halfHeight * _messageMargin;

    final bodyBottom = ArenaConfig.characterRadius * 1.8;
    final glassBottom = me.halfHeight - margin;
    var centre = (bodyBottom + glassBottom) / 2;

    final lowest = glassBottom - half;
    final highest = -me.halfHeight + margin + half;
    if (centre > lowest) centre = lowest;
    if (centre < highest) centre = highest;

    canvas.save();
    canvas.translate(me.worldCenterX, me.worldCenterY);
    canvas.rotate(me.turnRadians);
    canvas.scale(1 / px);
    canvas.drawParagraph(
      paragraph,
      Offset(-width / 2 * px, (centre - half) * px),
    );
    canvas.restore();
  }
}
