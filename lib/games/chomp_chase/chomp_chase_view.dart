import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/render/particle_burst.dart';
import 'chomp_chase_config.dart';
import 'chomp_chase_maze.dart';

/// The maze, the dots, the chompers and the ghosts.
///
/// Everything off the maze is wall: a bigger phone's spare glass is painted in
/// the wall colour, so the maze is exactly the rectangle every screen shows.
class ChompChaseView extends GameView {
  ChompChaseView({required this.phoneId, this.roster = Roster.empty});

  final String phoneId;
  final Roster roster;

  static const _messageMargin = 0.06;

  final _fill = Paint();
  final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// The maze as last decoded, and its walls as one path.
  String? _mazeRaw;
  ChompMaze? _maze;
  Path _walls = Path();

  final _burstAt = <String, double>{};

  @override
  void render(Canvas canvas, Frame frame) {
    final state = frame.sharedState;
    final view = frame.visible;

    _fill.color = const Color(ChompChaseConfig.colorWall);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );

    final ox = (state['ox'] as num?)?.toDouble() ?? 0;
    final oy = (state['oy'] as num?)?.toDouble() ?? 0;
    final tw = (state['tw'] as num?)?.toDouble() ?? 1;
    final th = (state['th'] as num?)?.toDouble() ?? 1;
    final raw = state['maze'] as String?;
    if (raw == null) return;
    if (raw != _mazeRaw) {
      _mazeRaw = raw;
      _maze = ChompMaze.decode(raw);
      _walls = _wallPath(_maze!, ox, oy, tw, th);
    }
    final maze = _maze!;
    final tile = math.min(tw, th);

    // The floor: the whole maze, and nothing past it.
    _fill.color = const Color(ChompChaseConfig.colorFloor);
    canvas.drawRect(
      Rect.fromLTWH(ox, oy, maze.cols * tw, maze.rows * th),
      _fill,
    );

    // Walls, with a soft glow under a crisp line.
    _line
      ..color = const Color(ChompChaseConfig.colorWallGlow).withAlpha(90)
      ..strokeWidth = tile * 0.34;
    canvas.drawPath(_walls, _line);
    _line
      ..color = const Color(ChompChaseConfig.colorWallGlow)
      ..strokeWidth = tile * 0.14;
    canvas.drawPath(_walls, _line);

    _drawDots(canvas, state['dots'] as String?, maze, ox, oy, tw, th, tile);
    _drawDeaths(canvas, frame, tile);

    for (final e in frame.ofKind('chomper')) {
      _drawChomper(canvas, frame, e, tile);
    }
    for (final e in frame.ofKind('ghost')) {
      _drawGhost(canvas, frame, e, tile);
    }

    _drawWords(canvas, frame);
  }

  /// Every closed side between two tiles, and the maze's outer edge.
  static Path _wallPath(
    ChompMaze maze,
    double ox,
    double oy,
    double tw,
    double th,
  ) {
    final path = Path();
    for (var r = 0; r < maze.rows; r++) {
      for (var c = 0; c < maze.cols; c++) {
        final x = ox + c * tw;
        final y = oy + r * th;
        if (!maze.open(c, r, 1, 0)) {
          path
            ..moveTo(x + tw, y)
            ..lineTo(x + tw, y + th);
        }
        if (!maze.open(c, r, 0, 1)) {
          path
            ..moveTo(x, y + th)
            ..lineTo(x + tw, y + th);
        }
        if (c == 0) {
          path
            ..moveTo(x, y)
            ..lineTo(x, y + th);
        }
        if (r == 0) {
          path
            ..moveTo(x, y)
            ..lineTo(x + tw, y);
        }
      }
    }
    return path;
  }

  void _drawDots(
    Canvas canvas,
    String? hex,
    ChompMaze maze,
    double ox,
    double oy,
    double tw,
    double th,
    double tile,
  ) {
    if (hex == null) return;
    _fill.color = const Color(ChompChaseConfig.colorDot);
    for (var d = 0; d < hex.length; d++) {
      final v = int.parse(hex[d], radix: 16);
      if (v == 0) continue;
      for (var b = 0; b < 4; b++) {
        if (v & (1 << b) == 0) continue;
        final k = d * 4 + b;
        if (k >= maze.tiles) break;
        canvas.drawCircle(
          Offset(ox + (k % maze.cols + 0.5) * tw, oy + (k ~/ maze.cols + 0.5) * th),
          tile * 0.09,
          _fill,
        );
      }
    }
  }

  // -- the runners ------------------------------------------------------------

  Color _colourOf(Frame frame, String key) {
    final phone = frame.sharedState['phoneId_$key'] as String? ?? '';
    return roster.byPhone(phone)?.color.value ??
        Color((frame.sharedState['color_$key'] as num?)?.toInt() ?? 0xFFFFFFFF);
  }

  /// A disc with a wedge for a mouth, opening and closing as it goes.
  void _drawChomper(Canvas canvas, Frame frame, RenderEntity e, double tile) {
    final key = 'p${e.propInt('index')}';
    final r = tile * 0.42;
    final open = 0.08 + 0.32 * (0.5 + 0.5 * math.sin(frame.timeMs / 55));
    final mouth = open * math.pi / 2;
    _fill.color = _colourOf(frame, key);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(e.x, e.y), radius: r),
      e.angle + mouth,
      2 * math.pi - 2 * mouth,
      true,
      _fill,
    );
  }

  /// A dome with a wavy hem, and eyes looking the way it is going.
  void _drawGhost(Canvas canvas, Frame frame, RenderEntity e, double tile) {
    final key = 'p${e.propInt('index')}';
    final w = tile * 0.84;
    final h = tile * 0.84;
    final left = e.x - w / 2;
    final top = e.y - h / 2;
    final wave = math.sin(frame.timeMs / 90) * h * 0.04;

    final body = Path()
      ..moveTo(left, top + h * 0.5)
      ..arcTo(Rect.fromLTWH(left, top, w, w), math.pi, math.pi, false)
      ..lineTo(left + w, top + h);
    const scallops = 3;
    for (var s = scallops; s > 0; s--) {
      final x1 = left + w * (s - 0.5) / scallops;
      final x0 = left + w * (s - 1) / scallops;
      body.quadraticBezierTo(x1, top + h * 0.82 + wave, x0, top + h);
    }
    body.close();
    _fill.color = _colourOf(frame, key);
    canvas.drawPath(body, _fill);

    final lookX = math.cos(e.angle) * w * 0.07;
    final lookY = math.sin(e.angle) * w * 0.07;
    for (final side in [-1, 1]) {
      final eye = Offset(e.x + side * w * 0.2, top + h * 0.42);
      _fill.color = const Color(0xFFFFFFFF);
      canvas.drawOval(
        Rect.fromCenter(center: eye, width: w * 0.26, height: w * 0.32),
        _fill,
      );
      _fill.color = const Color(0xFF1B2A8A);
      canvas.drawCircle(eye + Offset(lookX, lookY), w * 0.08, _fill);
    }
  }


  void _drawDeaths(Canvas canvas, Frame frame, double tile) {
    for (var i = 0; i < 8; i++) {
      final key = 'p$i';
      if (frame.sharedState['phoneId_$key'] == null) break;
      if (frame.sharedState['caught_$key'] != true) {
        _burstAt.remove(key);
        continue;
      }
      final started = _burstAt[key] ??= frame.timeMs;
      final t =
          (frame.timeMs - started) / 1000 / ChompChaseConfig.deathBurstSeconds;
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
        count: ChompChaseConfig.deathParticles,
        speed: ChompChaseConfig.deathBurstSpeed,
        seconds: ChompChaseConfig.deathBurstSeconds,
        particleRadius: tile * ChompChaseConfig.deathParticleScale,
      );
    }
  }

  // -- words ------------------------------------------------------------------

  /// This phone's team, or null on a phone nobody is playing at.
  int? _myTeam(Map<String, Object?> state) {
    for (var i = 0; i < 8; i++) {
      if (state['phoneId_p$i'] == phoneId) {
        return (state['team_p$i'] as num?)?.toInt();
      }
    }
    return null;
  }

  void _drawWords(Canvas canvas, Frame frame) {
    final state = frame.sharedState;
    final size = frame.me.halfWidth * 2;
    final team = _myTeam(state);
    final chomping = (state['chomping'] as num?)?.toInt() ?? 0;
    final eaten0 = (state['eaten0'] as num?)?.toInt() ?? 0;
    final eaten1 = (state['eaten1'] as num?)?.toInt() ?? 0;
    final mine = team == 1 ? eaten1 : eaten0;
    final theirs = team == 1 ? eaten0 : eaten1;

    switch (state['phase']) {
      case 'role':
        final text = team == null
            ? ''
            : team == chomping
            ? 'CHOMP! Eat the dots'
            : 'GHOST! Catch them';
        _drawCentered(canvas, frame, text, size * 0.08);
      case 'playing':
        final left = (state['left'] as num?)?.toInt() ?? 0;
        if (left > 0 && left <= ChompChaseConfig.finalCountdown) {
          _drawCentered(canvas, frame, '$left', size * 0.26);
        }
      case _ when state['timeUp'] == true:
        _drawCentered(canvas, frame, 'ROUND OVER', size * 0.12);
      case 'countdown':
        final cd = (state['countdown'] as num?)?.toDouble() ?? 0;
        final go = cd <= ChompChaseConfig.goSeconds;
        _drawCentered(
          canvas,
          frame,
          go ? 'GO' : (cd - ChompChaseConfig.goSeconds).ceil().toString(),
          size * (go ? 0.2 : 0.26),
        );
      case 'switch':
        _drawCentered(
          canvas,
          frame,
          'SWITCH! You ate $mine',
          size * 0.08,
        );
      case 'over' || 'finished':
        _drawCentered(canvas, frame, '$mine — $theirs', size * 0.14);
    }
  }

  /// One line across this phone's own glass, turned to its slot so it reads
  /// upright for whoever is holding it.
  void _drawCentered(Canvas canvas, Frame frame, String text, double size) {
    if (text.isEmpty) return;
    final me = frame.me;
    final width = me.halfWidth * 2;
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: size),
          )
          ..pushStyle(
            ui.TextStyle(
              color: const Color(ChompChaseConfig.colorText),
              fontWeight: FontWeight.w900,
              shadows: const [
                Shadow(color: Color(0xFF000000), blurRadius: 6),
              ],
            ),
          )
          ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));
    final half = paragraph.height / 2;
    final margin = me.halfHeight * _messageMargin;
    var centre = 0.0;
    final lowest = me.halfHeight - margin - half;
    final highest = -me.halfHeight + margin + half;
    if (centre > lowest) centre = lowest;
    if (centre < highest) centre = highest;

    canvas.save();
    canvas.translate(me.worldCenterX, me.worldCenterY);
    canvas.rotate(me.turnRadians);
    canvas.drawParagraph(paragraph, Offset(-width / 2, centre - half));
    canvas.restore();
  }
}
