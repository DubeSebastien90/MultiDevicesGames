import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import 'arena_config.dart';

/// Renders the arena: fighters, HP bars, attack cones, block shields, stun
/// stars, invincibility pulses, and the countdown overlay.
class ArenaView extends GameView {
  ArenaView({required this.phoneId});

  final String phoneId;

  static const _bgColor = Color(0xFF1A1A2E);
  static const _floorColor = Color(0xFF16213E);

  // Reusable paint objects.
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

    final fighters = frame.ofKind('fighter').toList();

    for (final e in fighters) {
      final idx = e.propInt('index');
      final key = 'p$idx';
      final color = Color(e.propInt('color', 0xFFFFFFFF));
      final radius = e.propDouble('radius', ArenaConfig.characterRadius);
      final alive = frame.sharedState['alive_$key'] == true;
      if (!alive) continue;

      final isStunned = frame.sharedState['stunned_$key'] == true;
      final isBlocking = frame.sharedState['blocking_$key'] == true;
      final isAttacking = frame.sharedState['attacking_$key'] == true;
      final isInvincible = frame.sharedState['invincible_$key'] == true;
      final hp = (frame.sharedState['hp_$key'] as num?)?.toInt() ?? 0;

      // Invincibility pulse.
      if (isInvincible) {
        final pulse = 0.5 + 0.5 * math.sin(frame.timeMs / 100);
        _stroke
          ..color = Color.fromARGB((pulse * 200).toInt(), 255, 255, 255)
          ..strokeWidth = radius * 0.15;
        canvas.drawCircle(Offset(e.x, e.y), radius * 1.3, _stroke);
      }

      // Block shield (arc behind and around).
      if (isBlocking) {
        _fill.color = const Color(0x554488FF);
        canvas.save();
        canvas.translate(e.x, e.y);
        canvas.rotate(e.angle);
        final shieldRect =
            Rect.fromCircle(center: Offset.zero, radius: radius * 1.4);
        canvas.drawArc(
            shieldRect, -math.pi / 2, math.pi, false, _fill);
        canvas.restore();
      }

      // Attack flash cone.
      if (isAttacking) {
        _fill.color = const Color(0x88FF8800);
        canvas.save();
        canvas.translate(e.x, e.y);
        canvas.rotate(e.angle);
        final path = ui.Path()
          ..moveTo(0, 0)
          ..lineTo(
            ArenaConfig.attackRange * math.cos(-ArenaConfig.attackArc),
            ArenaConfig.attackRange * math.sin(-ArenaConfig.attackArc),
          )
          ..arcTo(
            Rect.fromCircle(
                center: Offset.zero, radius: ArenaConfig.attackRange),
            -ArenaConfig.attackArc,
            2 * ArenaConfig.attackArc,
            false,
          )
          ..close();
        canvas.drawPath(path, _fill);
        canvas.restore();
      }

      // Fighter body.
      _fill.color = isStunned ? color.withAlpha(140) : color;
      canvas.drawCircle(Offset(e.x, e.y), radius, _fill);

      // Direction indicator (small triangle).
      if (!isStunned) {
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

      // HP bar.
      final barWidth = radius * 2;
      final barHeight = radius * 0.2;
      final barX = e.x - barWidth / 2;
      final barY = e.y - radius - barHeight * 2.5;
      final hpFrac = hp / ArenaConfig.maxHp;

      _fill.color = const Color(0xFF333333);
      canvas.drawRect(
          Rect.fromLTWH(barX, barY, barWidth, barHeight), _fill);

      final hpColor = Color.lerp(
              const Color(0xFFFF4444), const Color(0xFF44FF44), hpFrac) ??
          const Color(0xFF44FF44);
      _fill.color = hpColor;
      canvas.drawRect(
          Rect.fromLTWH(barX, barY, barWidth * hpFrac, barHeight), _fill);

      // Stun stars.
      if (isStunned) {
        _fill.color = const Color(0xFFFFDD44);
        final starAngle = frame.timeMs / 200;
        for (var s = 0; s < 3; s++) {
          final a = starAngle + s * (2 * math.pi / 3);
          final sx = e.x + math.cos(a) * radius * 0.8;
          final sy = e.y - radius * 0.6 + math.sin(a) * radius * 0.3;
          _drawStar(canvas, sx, sy, radius * 0.12, _fill);
        }
      }
    }

    // Countdown overlay.
    if (frame.sharedState['phase'] == 'countdown') {
      final cd = (frame.sharedState['countdown'] as num?)?.toDouble() ?? 0;
      final digit = cd.ceil().toString();
      _drawCenteredText(canvas, frame, digit, frame.board.height * 0.15);
    }

    // Finished overlay.
    if (frame.sharedState['phase'] == 'finished') {
      _drawCenteredText(canvas, frame, 'K.O.', frame.board.height * 0.12);
    }
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

    // Find our fighter index via phoneId mapping in sharedState.
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
    final hp = (frame.sharedState['hp_$key'] as num?)?.toInt() ?? 0;
    final stunned = frame.sharedState['stunned_$key'] == true;
    final atkCd = (frame.sharedState['atkCd_$key'] as num?)?.toDouble() ?? 0;
    final blkCd = (frame.sharedState['blkCd_$key'] as num?)?.toDouble() ?? 0;

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
          'Drag=Move  Tap=Attack  Hold=Block',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFFCCCCCC),
          ),
        ),
      );
    }

    final parts = <Widget>[];

    // HP badge.
    parts.add(Text(
      'HP $hp',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: hp > 50
            ? const Color(0xFF44FF44)
            : hp > 25
                ? const Color(0xFFFFDD44)
                : const Color(0xFFFF4444),
      ),
    ));

    if (stunned) {
      parts.add(const Text(
        ' STUNNED',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFFDD44),
        ),
      ));
    }

    if (atkCd > 0) {
      parts.add(Text(
        ' ATK ${atkCd.toStringAsFixed(1)}',
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF999999),
        ),
      ));
    }

    if (blkCd > 0) {
      parts.add(Text(
        ' BLK ${blkCd.toStringAsFixed(1)}',
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF999999),
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
