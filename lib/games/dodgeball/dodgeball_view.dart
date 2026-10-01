import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/render/particle_burst.dart';
import '../../sdk/render/player_animation.dart';
import 'dodgeball_config.dart';

class DodgeballView extends GameView {
  DodgeballView({
    required this.phoneId,
    this.characters = PlayerAnimations.none,
    this.roster = Roster.empty,
  });

  final String phoneId;

  final PlayerAnimations characters;

  final Roster roster;

  static const _floorColor = Color(0xFFF3DDB0);
  static const _plankLine = Color(0xFFE2C48F);
  static const _courtLine = Color(0xFFF08A80);
  static const _ink = Color(0xFF191510);

  static const _plankWidth = 0.9;
  static const _plankLength = 7.0;
  static const _ballColor = Color(0xFFFF4444);
  static const _ballGlowColor = Color(0x44FF4444);

  static const _walkingSpeed = 0.5;

  static const _messageMargin = 0.06;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  final _lastSeen = <String, Offset>{};

  final _burstAt = <String, double>{};

  @override
  void render(Canvas canvas, Frame frame) {
    _drawFloor(canvas, frame);

    final demo = _demoFade(frame);
    for (final e in frame.ofKind('ball')) {
      final radius = e.propDouble('radius', DodgeballConfig.ballRadius);

      _fill.color = _ballGlowColor.withValues(alpha: _ballGlowColor.a * demo);
      canvas.drawCircle(Offset(e.x, e.y), radius * 2.0, _fill);

      _fill.color = _ballColor.withValues(alpha: _ballColor.a * demo);
      canvas.drawCircle(Offset(e.x, e.y), radius, _fill);

      _fill.color = Color.fromARGB((0x66 * demo).round(), 255, 255, 255);
      canvas.drawCircle(
        Offset(e.x - radius * 0.25, e.y - radius * 0.25),
        radius * 0.3,
        _fill,
      );
    }

    _drawDeaths(canvas, frame);

    for (final e in frame.ofKind('player')) {
      final idx = e.propInt('index');
      final key = 'p$idx';

      final phone = frame.sharedState['phoneId_$key'] as String?;
      final seated = phone == null ? null : roster.byPhone(phone);
      final color =
          seated?.color.value ?? Color(e.propInt('color', 0xFFFFFFFF));
      final radius = e.propDouble('radius', DodgeballConfig.characterRadius);
      final alive = frame.sharedState['alive_$key'] == true;
      if (!alive) continue;

      final isDashing = frame.sharedState['dashing_$key'] == true;
      final isInvincible = frame.sharedState['invincible_$key'] == true;

      final dashCd =
          (frame.sharedState['dashCd_$key'] as num?)?.toDouble() ?? 0;
      if (dashCd > 0) {
        final charge =
            1 - (dashCd / DodgeballConfig.dashCooldown).clamp(0.0, 1.0);
        _stroke
          ..color = color.withValues(alpha: 0.85)
          ..strokeWidth = radius * 0.16;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(e.x, e.y), radius: radius * 1.45),
          -math.pi / 2,
          2 * math.pi * charge,
          false,
          _stroke,
        );
      }

      if (isInvincible) {
        final pulse = 0.5 + 0.5 * math.sin(frame.timeMs / 60);
        _stroke
          ..color = _ink.withAlpha((pulse * 160).toInt())
          ..strokeWidth = radius * 0.18;
        canvas.drawCircle(Offset(e.x, e.y), radius * 1.4, _stroke);
      }

      if (isDashing) {
        _fill.color = color.withAlpha(60);
        final trailDx = -math.cos(e.angle) * radius * 1.5;
        final trailDy = -math.sin(e.angle) * radius * 1.5;
        canvas.drawCircle(
          Offset(e.x + trailDx, e.y + trailDy),
          radius * 0.7,
          _fill,
        );
        canvas.drawCircle(
          Offset(e.x + trailDx * 2, e.y + trailDy * 2),
          radius * 0.4,
          _fill,
        );
      }

      final here = Offset(e.x, e.y);
      final before = _lastSeen[e.id];
      _lastSeen[e.id] = here;
      final moving =
          before != null &&
          frame.dt > 0 &&
          (here - before).distance / frame.dt > _walkingSpeed;

      if (seated == null) {
        _fill.color = isDashing
            ? Color.lerp(color, const Color(0xFFFFFFFF), 0.4)!
            : color;
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
    }

    _drawJoystick(canvas, frame);

    final phase = frame.sharedState['phase'];
    if (phase == 'briefing') {
      final step = (frame.sharedState['step'] as num?)?.toInt() ?? 0;
      if (step >= 0 && step < DodgeballConfig.briefingLines.length) {
        _drawCentered(
          canvas,
          frame,
          DodgeballConfig.briefingLines[step],
          frame.me.halfWidth * 2 * 0.1,
        );
      }
    }

    if (frame.sharedState['phase'] == 'countdown') {
      final cd = (frame.sharedState['countdown'] as num?)?.toDouble() ?? 0;
      final go = cd <= DodgeballConfig.goSeconds;
      _drawCentered(
        canvas,
        frame,
        go ? 'GO' : (cd - DodgeballConfig.goSeconds).ceil().toString(),
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
      final t =
          (frame.timeMs - started) / 1000 / DodgeballConfig.deathBurstSeconds;
      if (t < 0 || t >= 1) continue;

      final x = (frame.sharedState['deadX_$key'] as num?)?.toDouble();
      final y = (frame.sharedState['deadY_$key'] as num?)?.toDouble();
      if (x == null || y == null) continue;

      drawParticleBurst(
        canvas,
        _fill,
        Offset(x, y),
        _colorOf(frame, key),
        t,
        count: DodgeballConfig.deathParticles,
        speed: DodgeballConfig.deathBurstSpeed,
        seconds: DodgeballConfig.deathBurstSeconds,
        particleRadius:
            DodgeballConfig.characterRadius *
            DodgeballConfig.deathParticleScale,
      );
    }
  }

  Color _colorOf(Frame frame, String key) {
    final phoneId = frame.sharedState['phoneId_$key'] as String? ?? '';
    final seated = roster.byPhone(phoneId);
    return seated?.color.value ??
        Color((frame.sharedState['color_$key'] as num?)?.toInt() ?? 0xFFFFFFFF);
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
    final reach = DodgeballConfig.joystickRadius;

    final tilt = pushed.distance > reach
        ? pushed * (reach / pushed.distance)
        : pushed;
    final knob = anchor + tilt;

    _fill.color = _ink.withAlpha(DodgeballConfig.joystickWellAlpha);
    canvas.drawCircle(anchor, reach, _fill);

    _stroke
      ..color = _ink.withAlpha(DodgeballConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.04);
    canvas.drawCircle(anchor, reach, _stroke);

    _stroke
      ..color = _ink.withAlpha(DodgeballConfig.joystickDeadZoneAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(anchor, DodgeballConfig.minMoveDistance, _stroke);

    if (tilt.distance > 0) {
      _stroke
        ..color = _ink.withAlpha(DodgeballConfig.joystickDeadZoneAlpha)
        ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.03);
      canvas.drawLine(anchor, knob, _stroke);
    }

    final me = roster.byPhone(phoneId);
    _fill.color = (me?.color.value ?? _ink).withAlpha(
      DodgeballConfig.joystickKnobAlpha,
    );
    canvas.drawCircle(knob, DodgeballConfig.joystickKnobRadius, _fill);
    _stroke
      ..color = _ink.withAlpha(DodgeballConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(knob, DodgeballConfig.joystickKnobRadius, _stroke);
  }

  String? _myKey(Map<String, Object?> sharedState) {
    for (var i = 0; i < 8; i++) {
      if (sharedState['phoneId_p$i'] == phoneId) return 'p$i';
    }
    return null;
  }

  double _demoFade(Frame frame) {
    if (frame.sharedState['phase'] != 'briefing') return 1;

    final left = (frame.sharedState['stepLeft'] as num?)?.toDouble();
    if (left == null) return 1;

    final age =
        DodgeballConfig.briefingStepSeconds -
        left -
        DodgeballConfig.briefingDemoAt;
    if (age <= 0) return 0;

    final fadingIn = (age / DodgeballConfig.demoFadeIn).clamp(0.0, 1.0);
    final fadingOut = (left / DodgeballConfig.demoFadeOut).clamp(0.0, 1.0);
    return fadingIn < fadingOut ? fadingIn : fadingOut;
  }

  void _drawFloor(Canvas canvas, Frame frame) {
    final view = frame.visible;
    _fill.color = _floorColor;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );

    _stroke
      ..color = _plankLine
      ..strokeWidth = 0.05;
    final firstRow = (view.top / _plankWidth).floor();
    final lastRow = (view.bottom / _plankWidth).ceil();
    for (var row = firstRow; row <= lastRow; row++) {
      final y = row * _plankWidth;
      canvas.drawLine(Offset(view.left, y), Offset(view.right, y), _stroke);
      final stagger = (row % 3) * _plankLength / 3;
      for (
        var x =
            ((view.left - stagger) / _plankLength).floorToDouble() *
                _plankLength +
            stagger;
        x <= view.right;
        x += _plankLength
      ) {
        canvas.drawLine(Offset(x, y), Offset(x, y + _plankWidth), _stroke);
      }
    }

    final board = frame.board;
    final centre = Offset(board.centerX, board.centerY);
    _stroke
      ..color = _courtLine
      ..strokeWidth = 0.2;
    if (board.width >= board.height) {
      canvas.drawLine(
        Offset(centre.dx, board.top),
        Offset(centre.dx, board.bottom),
        _stroke,
      );
    } else {
      canvas.drawLine(
        Offset(board.left, centre.dy),
        Offset(board.right, centre.dy),
        _stroke,
      );
    }
    canvas.drawCircle(
      centre,
      math.min(board.width, board.height) * 0.22,
      _stroke,
    );
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

    final bodyBottom = DodgeballConfig.characterRadius * 1.8;
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
