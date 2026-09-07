import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/render/player_animation.dart';
import 'arena_config.dart';

/// Renders the arena: fighters, HP bars, attack cones, block shields, stun
/// stars, invincibility pulses, and the countdown overlay.
// Kept as reference, not used: the sim no longer tracks who has dropped out.
// See the commented presence block in `ArenaSim`.
//
// /// The same colour drained of it: kept dark enough to read against the
// /// floor, light enough to see the fighter is still standing there.
// Color _greyed(Color c) {
//   final grey = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 0.7;
//   return Color.from(alpha: c.a, red: grey, green: grey, blue: grey);
// }

class ArenaView extends GameView {
  ArenaView({
    required this.phoneId,
    this.characters = PlayerAnimations.none,
    this.roster = Roster.empty,
  });

  final String phoneId;

  /// Everyone's walking character, loaded and coloured by the platform.
  final PlayerAnimations characters;

  /// Everyone in the round, for their platform colour — the one they were
  /// shown in the lobby, rather than the sim's own palette.
  final Roster roster;

  static const _floorColor = Color(0xFF16213E);

  /// World units per second below which a fighter counts as standing still.
  ///
  /// Not zero: positions are interpolated, so a stationary fighter still
  /// jitters by a hair between frames and an exact test would flicker the walk
  /// on and off.
  static const _walkingSpeed = 0.5;

  // Reusable paint objects.
  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  /// Where each fighter was last frame, to tell walking from standing.
  final _lastSeen = <String, Offset>{};

  @override
  void render(Canvas canvas, Frame frame) {
    // Floor, over the whole panel.
    //
    // It used to be painted over `frame.board` alone, and on a table of
    // mismatched phones that rectangle stops short of the biggest screen — so
    // the rest of that screen was left showing through as a differently
    // coloured band nobody could walk into. The sim now keeps fighters inside
    // the screens themselves (see [PlayArea]), which means every point this
    // phone can draw is a point somebody can stand on, and the floor can
    // simply cover it.
    _fill.color = _floorColor;
    final view = frame.visible;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
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

      // Fighter body. `RenderEntity` carries no velocity, so movement is the
      // distance covered since the last frame; a stunned fighter is being
      // knocked about rather than walking, so they hold still.
      final here = Offset(e.x, e.y);
      final before = _lastSeen[e.id];
      _lastSeen[e.id] = here;
      final moving = !isStunned &&
          before != null &&
          frame.dt > 0 &&
          (here - before).distance / frame.dt > _walkingSpeed;

      // A fighter with no seat at the roster has no platform colour to ask a
      // character for, so they stay the sim's own circle.
      //
      // A player who had dropped out used to go grey here — still there, still
      // hittable, plainly nobody home. Kept as reference, not implemented:
      //
      // final away = frame.sharedState['away_p${e.propInt('index', 0)}'] == true;
      // final body = away ? _greyed(color) : color;
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

    // The player's own stick, drawn last so a fighter walking over their own
    // anchor does not cut a hole in it.
    //
    // Only this phone's: a joystick is a picture of what one pair of hands is
    // doing, and drawing everybody's would litter the table with rings nobody
    // can act on — and quietly leak which way each opponent is about to break.
    _drawJoystick(canvas, frame);

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

  /// The anchor the drag is measured from, under the finger that set it.
  ///
  /// Movement here is an angle from a point the player cannot see, which is a
  /// fine control and an invisible one — a finger drifting an inch during a
  /// scrap steers hard without ever feeling like it moved. The ring gives that
  /// point a body: where the stick is centred, how far in it counts as still
  /// (the dead zone), and which way it is currently pushed.
  void _drawJoystick(Canvas canvas, Frame frame) {
    final key = _myKey(frame.sharedState);
    if (key == null) return;

    final ax = (frame.sharedState['stickX_$key'] as num?)?.toDouble();
    final ay = (frame.sharedState['stickY_$key'] as num?)?.toDouble();
    // Absent means no finger is down. Nothing to draw, and nothing else in
    // here is worth reading.
    if (ax == null || ay == null) return;
    final tx = (frame.sharedState['stickToX_$key'] as num?)?.toDouble() ?? ax;
    final ty = (frame.sharedState['stickToY_$key'] as num?)?.toDouble() ?? ay;

    final anchor = Offset(ax, ay);
    final pushed = Offset(tx - ax, ty - ay);
    final reach = ArenaConfig.joystickRadius;
    // Past the ring the knob stops travelling but the drag keeps steering, so
    // full tilt looks like full tilt however far the hand has wandered.
    final tilt = pushed.distance > reach
        ? pushed * (reach / pushed.distance)
        : pushed;
    final knob = anchor + tilt;

    final blocking = frame.sharedState['blocking_$key'] == true;
    // Held still long enough to be blocking: the stick says so in the shield's
    // own colour, because a player holding a block is doing it by *not*
    // moving, and an unlit ring looks identical to a dead one.
    final ringColor =
        blocking ? const Color(0xFF4488FF) : const Color(0xFFFFFFFF);

    _fill.color = const Color(0xFFFFFFFF)
        .withAlpha(ArenaConfig.joystickWellAlpha);
    canvas.drawCircle(anchor, reach, _fill);

    _stroke
      ..color = ringColor.withAlpha(ArenaConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.04);
    canvas.drawCircle(anchor, reach, _stroke);

    // The dead zone, so a player can see the distance their finger has to
    // cover before the fighter starts walking.
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

    // The knob in the player's own colour — the one their fighter is wearing,
    // so at a glance the ring belongs to somebody.
    final me = roster.byPhone(phoneId);
    final knobColor = me?.color.value ?? const Color(0xFFFFFFFF);
    _fill.color = knobColor.withAlpha(ArenaConfig.joystickKnobAlpha);
    canvas.drawCircle(knob, ArenaConfig.joystickKnobRadius, _fill);
    _stroke
      ..color = const Color(0xFFFFFFFF)
          .withAlpha(ArenaConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(knob, ArenaConfig.joystickKnobRadius, _stroke);
  }

  /// Which fighter is this phone's, as `p0`..`p7`. Null before the sim has
  /// seated anybody, and on a phone that is watching rather than playing.
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

    final key = _myKey(frame.sharedState);
    if (key == null) return null;

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
