import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import 'dodgeball_config.dart';

/// Renders the dodgeball game: players, bouncing balls, dash effects, and
/// countdown/game-over overlays.
class DodgeballView extends GameView {
  DodgeballView({required this.phoneId});

  final String phoneId;

  static const _bgColor = Color(0xFF0D1117);
  static const _floorColor = Color(0xFF161B22);
  static const _ballColor = Color(0xFFFF4444);
  static const _ballGlowColor = Color(0x44FF4444);

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas, Frame frame) {
    // Background.
    _fill.color = _bgColor;
    canvas.drawRect(
      Rect.fromLTWH(
        frame.board.left,
        frame.board.top,
        frame.board.width,
        frame.board.height,
      ),
      _fill,
    );
    _fill.color = _floorColor;
    canvas.drawRect(
      Rect.fromLTWH(
        frame.board.left,
        frame.board.top,
        frame.board.width,
        frame.board.height,
      ),
      _fill,
    );

    // Draw balls.
    for (final e in frame.ofKind('ball')) {
      final radius = e.propDouble('radius', DodgeballConfig.ballRadius);

      // Glow.
      _fill.color = _ballGlowColor;
      canvas.drawCircle(Offset(e.x, e.y), radius * 2.0, _fill);

      // Ball body.
      _fill.color = _ballColor;
      canvas.drawCircle(Offset(e.x, e.y), radius, _fill);

      // Highlight.
      _fill.color = const Color(0x66FFFFFF);
      canvas.drawCircle(
        Offset(e.x - radius * 0.25, e.y - radius * 0.25),
        radius * 0.3,
        _fill,
      );
    }

    // Draw players.
    for (final e in frame.ofKind('player')) {
      final idx = e.propInt('index');
      final key = 'p$idx';
      final color = Color(e.propInt('color', 0xFFFFFFFF));
      final radius = e.propDouble('radius', DodgeballConfig.characterRadius);
      final alive = frame.sharedState['alive_$key'] == true;
      if (!alive) continue;

      final isDashing = frame.sharedState['dashing_$key'] == true;
      final isInvincible = frame.sharedState['invincible_$key'] == true;

      // Invincibility / dash shimmer.
      if (isInvincible) {
        final pulse = 0.5 + 0.5 * math.sin(frame.timeMs / 60);
        _stroke
          ..color = Color.fromARGB((pulse * 220).toInt(), 255, 255, 255)
          ..strokeWidth = radius * 0.18;
        canvas.drawCircle(Offset(e.x, e.y), radius * 1.4, _stroke);
      }

      // Dash trail.
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

      // Player body.
      _fill.color = isDashing ? Color.lerp(color, const Color(0xFFFFFFFF), 0.4)! : color;
      canvas.drawCircle(Offset(e.x, e.y), radius, _fill);

      // Direction indicator.
      _fill.color = const Color(0xDDFFFFFF);
      canvas.save();
      canvas.translate(e.x, e.y);
      canvas.rotate(e.angle);
      final tip = radius * 1.15;
      final base = radius * 0.3;
      final dirPath = ui.Path()
        ..moveTo(tip, 0)
        ..lineTo(radius * 0.7, -base)
        ..lineTo(radius * 0.7, base)
        ..close();
      canvas.drawPath(dirPath, _fill);
      canvas.restore();
    }

    // Countdown overlay.
    if (frame.sharedState['phase'] == 'countdown') {
      final cd = (frame.sharedState['countdown'] as num?)?.toDouble() ?? 0;
      final digit = cd.ceil().toString();
      _drawCenteredText(canvas, frame, digit, frame.board.height * 0.15);
    }

    // Finished overlay.
    if (frame.sharedState['phase'] == 'finished') {
      _drawCenteredText(canvas, frame, 'OUT!', frame.board.height * 0.12);
    }
  }

  void _drawCenteredText(
      Canvas canvas, Frame frame, String text, double fontSize) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
    ))
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontWeight: FontWeight.w900,
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: frame.visible.width));
    canvas.drawParagraph(
      paragraph,
      Offset(
        frame.visible.left,
        frame.visible.top + frame.visible.height / 2 - fontSize / 2,
      ),
    );
  }

  // -- HUD --------------------------------------------------------------------

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final phase = frame.sharedState['phase'] as String?;

    int? myIndex;
    for (var i = 0; i < 8; i++) {
      if (frame.sharedState['phoneId_p$i'] == phoneId) {
        myIndex = i;
        break;
      }
    }
    if (myIndex == null) return null;

    final key = 'p$myIndex';
    final alive = frame.sharedState['alive_$key'] == true;
    final dashCd =
        (frame.sharedState['dashCd_$key'] as num?)?.toDouble() ?? 0;
    final ballCount =
        (frame.sharedState['ballCount'] as num?)?.toInt() ?? 0;

    if (!alive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'ELIMINATED',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFF4444),
          ),
        ),
      );
    }

    if (phase == 'countdown') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Drag=Move  Tap=Dash',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFFCCCCCC),
          ),
        ),
      );
    }

    final parts = <Widget>[];

    // Ball count.
    parts.add(Text(
      'Balls: $ballCount',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFFFF6666),
      ),
    ));

    // Dash status.
    if (dashCd > 0) {
      parts.add(Text(
        '  DASH ${dashCd.toStringAsFixed(1)}',
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF999999),
        ),
      ));
    } else {
      parts.add(const Text(
        '  DASH READY',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF44FF44),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: parts),
    );
  }
}
