import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/render/particle_burst.dart';
import '../../sdk/render/player_animation.dart';
import 'paint_war_config.dart';
import 'paint_war_contours.dart';

class PaintWarView extends GameView {
  PaintWarView({
    required this.phoneId,
    this.characters = PlayerAnimations.none,
    this.roster = Roster.empty,
  });

  final String phoneId;
  final PlayerAnimations characters;
  final Roster roster;

  static const _paper = Color(0xFFF7F4EC);
  static const _ink = Color(0xFF191510);

  static const _walkingSpeed = 0.5;

  static const _messageMargin = 0.06;

  final _fill = Paint();
  final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  final _stick = Paint()..style = PaintingStyle.stroke;

  final _lastSeen = <String, Offset>{};
  final _burstAt = <String, double>{};

  String? _paintRaw;
  Map<int, Path> _paintPaths = const {};

  @override
  void render(Canvas canvas, Frame frame) {
    final state = frame.sharedState;
    final view = frame.visible;

    _fill.color = _paper;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );

    _drawPaint(canvas, frame);
    _drawTrails(canvas, frame);
    _drawDeaths(canvas, frame);
    _drawPainters(canvas, frame);

    _drawJoystick(canvas, frame);

    final phase = state['phase'];
    final size = frame.me.halfWidth * 2;
    if (phase == 'briefing') {
      final step = (state['step'] as num?)?.toInt() ?? 0;
      if (step >= 0 && step < PaintWarConfig.briefingLines.length) {
        _drawCentered(
          canvas,
          frame,
          PaintWarConfig.briefingLines[step],
          size * 0.1,
        );
      }
    } else if (phase == 'countdown') {
      final cd = (state['countdown'] as num?)?.toDouble() ?? 0;
      final go = cd <= PaintWarConfig.goSeconds;
      _drawCentered(
        canvas,
        frame,
        go ? 'GO' : (cd - PaintWarConfig.goSeconds).ceil().toString(),
        size * (go ? 0.22 : 0.3),
      );
    } else if (phase == 'playing') {
      final left = (state['left'] as num?)?.toInt() ?? 0;
      if (left > 0 && left <= PaintWarConfig.finalCountdown) {
        _drawCentered(canvas, frame, '$left', size * 0.3);
      }
    } else if (phase == 'over' || phase == 'finished') {
      _drawCentered(canvas, frame, 'OVER', size * 0.22);
    }
  }

  void _drawPaint(Canvas canvas, Frame frame) {
    final state = frame.sharedState;
    final raw = state['paint'] as String?;
    if (raw == null) return;
    if (raw != _paintRaw) {
      _paintRaw = raw;
      _paintPaths = _decode(
        raw,
        gx: (state['gx'] as num?)?.toDouble() ?? 0,
        gy: (state['gy'] as num?)?.toDouble() ?? 0,
        gw: (state['gw'] as num?)?.toInt() ?? 1,
        cell: (state['gc'] as num?)?.toDouble() ?? PaintWarConfig.cellSize,
      );
    }
    final cell = (state['gc'] as num?)?.toDouble() ?? PaintWarConfig.cellSize;
    for (final e in _paintPaths.entries) {
      final colour = _paintColour(frame, 'p${e.key}');
      _fill.color = colour;
      canvas.drawPath(e.value, _fill);

      _edge
        ..color = colour
        ..strokeWidth = cell;
      canvas.drawPath(e.value, _edge);
    }
  }

  static Map<int, Path> _decode(
    String raw, {
    required double gx,
    required double gy,
    required int gw,
    required double cell,
  }) {
    final owners = PaintContours.decode(raw);
    final present = <int>{
      for (final o in owners)
        if (o >= 0) o,
    };
    return {
      for (final owner in present)
        owner: _pathOf(
          PaintContours.outlines(
            owners,
            owner: owner,
            gw: gw,
            gx: gx,
            gy: gy,
            cell: cell,
          ),
        ),
    };
  }

  static Path _pathOf(List<List<(double, double)>> loops) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final loop in loops) {
      final (x0, y0) = loop.first;
      path.moveTo(x0, y0);
      for (var k = 1; k < loop.length; k++) {
        final (x, y) = loop[k];
        path.lineTo(x, y);
      }
      path.close();
    }
    return path;
  }

  void _drawTrails(Canvas canvas, Frame frame) {
    final state = frame.sharedState;
    for (var i = 0; i < 8; i++) {
      final key = 'p$i';
      if (state['phoneId_$key'] == null) break;
      final raw = state['trail_$key'] as String?;
      if (raw == null || raw.isEmpty) continue;

      final path = Path();
      var first = true;
      for (final point in raw.split(';')) {
        final xy = point.split(',');
        if (xy.length != 2) continue;
        final x = double.tryParse(xy[0]);
        final y = double.tryParse(xy[1]);
        if (x == null || y == null) continue;
        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }
      if (first) continue;

      final body = frame.byId('player_$i');
      if (body != null) path.lineTo(body.x, body.y);

      final colour = _colourOf(frame, key);
      _stroke
        ..color = colour.withValues(alpha: PaintWarConfig.trailOpacity)
        ..strokeWidth = PaintWarConfig.trailRadius * 2;
      canvas.drawPath(path, _stroke);
    }
  }

  void _drawPainters(Canvas canvas, Frame frame) {
    for (final e in frame.ofKind('player')) {
      final key = 'p${e.propInt('index')}';
      if (frame.sharedState['alive_$key'] != true) continue;
      final radius = e.propDouble('radius', PaintWarConfig.characterRadius);

      final here = Offset(e.x, e.y);
      final before = _lastSeen[e.id];
      _lastSeen[e.id] = here;
      final moving =
          before != null &&
          frame.dt > 0 &&
          (here - before).distance / frame.dt > _walkingSpeed;

      final phone = frame.sharedState['phoneId_$key'] as String?;
      final seated = phone == null ? null : roster.byPhone(phone);
      if (seated == null) {
        _fill.color = _colourOf(frame, key);
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
          (frame.timeMs - started) / 1000 / PaintWarConfig.deathBurstSeconds;
      if (t < 0 || t >= 1) continue;
      final x = double.tryParse('${frame.sharedState['deadX_$key']}');
      final y = double.tryParse('${frame.sharedState['deadY_$key']}');
      if (x == null || y == null) continue;
      drawParticleBurst(
        canvas,
        _fill,
        Offset(x, y),
        _colourOf(frame, key),
        t,
        count: PaintWarConfig.deathParticles,
        speed: PaintWarConfig.deathBurstSpeed,
        seconds: PaintWarConfig.deathBurstSeconds,
        particleRadius:
            PaintWarConfig.characterRadius * PaintWarConfig.deathParticleScale,
      );
    }
  }

  void _drawJoystick(Canvas canvas, Frame frame) {
    RenderEntity? anchorE;
    RenderEntity? knobE;
    for (final e in frame.ofKind('stick')) {
      if (e.props['phoneId'] == phoneId) anchorE = e;
    }
    for (final e in frame.ofKind('knob')) {
      if (e.props['phoneId'] == phoneId) knobE = e;
    }
    if (anchorE == null || knobE == null) return;

    final anchor = Offset(anchorE.x, anchorE.y);
    final pushed = Offset(knobE.x, knobE.y) - anchor;
    const reach = PaintWarConfig.joystickRadius;

    final tilt = pushed.distance > reach
        ? pushed * (reach / pushed.distance)
        : pushed;
    final knob = anchor + tilt;

    _fill.color = _ink.withAlpha(PaintWarConfig.joystickWellAlpha);
    canvas.drawCircle(anchor, reach, _fill);

    _stick
      ..color = _ink.withAlpha(PaintWarConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.04);
    canvas.drawCircle(anchor, reach, _stick);

    _stick
      ..color = _ink.withAlpha(PaintWarConfig.joystickDeadZoneAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(anchor, PaintWarConfig.minMoveDistance, _stick);

    if (tilt.distance > 0) {
      _stick
        ..color = _ink.withAlpha(PaintWarConfig.joystickDeadZoneAlpha)
        ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.03);
      canvas.drawLine(anchor, knob, _stick);
    }

    final me = roster.byPhone(phoneId);
    _fill.color = (me?.color.value ?? _ink).withAlpha(
      PaintWarConfig.joystickKnobAlpha,
    );
    canvas.drawCircle(knob, PaintWarConfig.joystickKnobRadius, _fill);
    _stick
      ..color = _ink.withAlpha(PaintWarConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(knob, PaintWarConfig.joystickKnobRadius, _stick);
  }

  Color _colourOf(Frame frame, String key) {
    final phone = frame.sharedState['phoneId_$key'] as String? ?? '';
    return roster.byPhone(phone)?.color.value ??
        Color((frame.sharedState['color_$key'] as num?)?.toInt() ?? 0xFF888888);
  }

  Color _paintColour(Frame frame, String key) {
    final phone = frame.sharedState['phoneId_$key'] as String? ?? '';
    final seated = roster.byPhone(phone);
    if (seated != null) return seated.color.skinDark;
    return Color.lerp(_colourOf(frame, key), const Color(0xFF000000), 0.25)!;
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
    final bodyBottom = PaintWarConfig.characterRadius * 1.8;
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
