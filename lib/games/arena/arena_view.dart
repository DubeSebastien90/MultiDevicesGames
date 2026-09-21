import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/render/player_animation.dart';
import 'arena_config.dart';

/// Renders the arena: fighters, their swords, lives, stun stars, invincibility
/// pulses, and the countdown overlay.
///
/// The cone the old attack drew and the arc the old block drew are both gone.
/// Neither was ever the thing that hit or stopped anybody — they were pictures
/// of a decision taken elsewhere — and the blade now does both jobs honestly:
/// where it is *is* what it can reach, and a blade held across the body is what
/// a raised guard looks like.
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

  /// When each fallen fighter's burst started, on the host's clock.
  ///
  /// The *instant* is local — it is whenever this phone was told the fighter
  /// was gone — while everything after it is phased off [Frame.timeMs] like
  /// every other animation here. That split is deliberate: a burst is a
  /// one-shot fired by an event that reaches every phone within a few
  /// milliseconds, so there is nothing for the phones to disagree about, and
  /// hanging it off a timestamp from the sim would mean lining up two clocks
  /// to no visible end.
  final _burstAt = <String, double>{};

  /// The last blow each fighter had counted against them, and when this phone
  /// saw it. A burst runs while the clock is inside its length.
  final _impactSeen = <String, int>{};
  final _impactAt = <String, double>{};

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
      final isInvincible = frame.sharedState['invincible_$key'] == true;
      final lives =
          (frame.sharedState['lives_$key'] as num?)?.toInt() ??
          ArenaConfig.maxLives;

      // Invincibility pulse.
      if (isInvincible) {
        final pulse = 0.5 + 0.5 * math.sin(frame.timeMs / 100);
        _stroke
          ..color = Color.fromARGB((pulse * 200).toInt(), 255, 255, 255)
          ..strokeWidth = radius * 0.15;
        canvas.drawCircle(Offset(e.x, e.y), radius * 1.3, _stroke);
      }

      // Fighter body. `RenderEntity` carries no velocity, so movement is the
      // distance covered since the last frame; a stunned fighter is being
      // knocked about rather than walking, so they hold still.
      final here = Offset(e.x, e.y);
      final before = _lastSeen[e.id];
      _lastSeen[e.id] = here;
      final moving =
          !isStunned &&
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

      // Lives, as dots over the head — one per hit left, and a dot simply
      // gone once it is spent. A bar had to be read: a fighter on a sliver of
      // red and one on a third of it look alike at arm's length across a
      // table, while two dots and three never do.
      _drawLives(canvas, Offset(e.x, e.y), radius, lives);

      // Stun stars, going round the fighter in a circle.
      //
      // A circle, and centred on the fighter's own origin — not an ellipse
      // over the head. This world is seen from above: a fighter *is* their
      // head, they spin on the spot constantly, and a ring drawn with a
      // squashed vertical axis is a ring that only looks right while they
      // happen to be facing along it. A true circle round the middle of them
      // reads the same from every angle, which is the only thing that works
      // when the thing it is drawn on turns.
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

    // Whoever has just come apart, over the floor and under the living: a
    // burst is something that happened *there*, and a fighter standing on the
    // spot is standing on it.
    _drawDeaths(canvas, frame);
    _drawImpacts(canvas, frame);

    // Blades over bodies, and over *all* the bodies: a sword swung across a
    // neighbour passes in front of them, which is also the truth — the sim
    // just cut them with it.
    for (final e in frame.ofKind('sword')) {
      final key = 'p${e.propInt('index')}';
      if (frame.sharedState['alive_$key'] != true) continue;
      _drawSword(canvas, e);
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

    // No finished overlay. The round now holds for a second after the last
    // fall so the burst can play, and a word stamped over the middle of the
    // table is exactly what nobody should be reading during it — the phones
    // move on to the score by themselves a moment later.
  }

  /// Everybody's burst, for as long as theirs lasts.
  ///
  /// Driven from `alive_pN` going false rather than from a death message,
  /// because the sim publishes no such message and does not need to: the
  /// roster of who is still standing is already on the wire, and the moment it
  /// changes is the moment somebody fell.
  void _drawDeaths(Canvas canvas, Frame frame) {
    for (var i = 0; i < 8; i++) {
      final key = 'p$i';
      if (frame.sharedState['phoneId_$key'] == null) break;

      if (frame.sharedState['alive_$key'] == true) {
        // Alive, so any burst of theirs belongs to a previous round. Cleared
        // rather than left: this view outlives a replay.
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

  /// The small bursts: a blow landing, and a blow turned away.
  ///
  /// Driven off a counter rather than a flag. Two blows in a row set the same
  /// flag to the same value, and a diffed broadcast would never mention the
  /// second — so the fighter would be hit twice and spark once.
  void _drawImpacts(Canvas canvas, Frame frame) {
    for (var i = 0; i < 8; i++) {
      final key = 'p$i';
      if (frame.sharedState['phoneId_$key'] == null) break;

      final count = (frame.sharedState['impacts_$key'] as num?)?.toInt() ?? 0;
      if (count == 0) {
        // A replay: nothing has struck anybody yet, so nothing is owed.
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

      // White for a guard that held — the sparks belong to neither fighter —
      // and the player's own colour for a life going.
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

  /// A fighter's colour: the platform one they have worn since the lobby where
  /// there is a seat for them, and the sim's palette otherwise — the same
  /// choice the body itself makes.
  Color _colorOf(Frame frame, String key) {
    final phoneId = frame.sharedState['phoneId_$key'] as String? ?? '';
    final seated = roster.byPhone(phoneId);
    return seated?.color.value ??
        Color((frame.sharedState['color_$key'] as num?)?.toInt() ?? 0xFFFFFFFF);
  }

  /// One burst: round bits of [color] thrown out of [at], slowing and fading.
  ///
  /// A pure function of [t], 0 to 1 — no particle list, no per-frame state.
  /// Every bit's direction and speed comes from its own index, so the burst is
  /// the same burst on every phone and costs nothing to keep between frames.
  void _drawBurst(
    Canvas canvas,
    Offset at,
    Color color,
    double t, {
    required int count,
    required double speed,
    required double seconds,
  }) {
    final n = count;
    final radius = ArenaConfig.characterRadius;

    // Slowing as they go, rather than flying at a constant rate: the give in
    // the first tenth of a second is most of what makes it read as a burst.
    final travel =
        speed * seconds * (1 - math.pow(1 - t, 2.4).toDouble()) * 0.45;

    final fade = math.pow(1 - t, 1.6).toDouble();
    final size = radius * ArenaConfig.deathParticleScale * (1 - 0.55 * t);

    for (var i = 0; i < n; i++) {
      // Spread evenly, then nudged off the ring by a number that depends only
      // on which bit this is — a tidy circle of dots looks like a diagram.
      final wobble = _scatter(i);
      final angle = i * 2 * math.pi / n + wobble * 0.4;
      final reach = travel * (0.55 + 0.45 * _scatter(i + 97).abs());

      _fill.color = color.withValues(alpha: color.a * fade);
      canvas.drawCircle(
        Offset(
          at.dx + math.cos(angle) * reach,
          at.dy + math.sin(angle) * reach,
        ),
        size * (0.7 + 0.5 * _scatter(i + 31).abs()),
        _fill,
      );
    }
  }

  /// A repeatable number in (-1, 1) for [i]. Not random — the same bit must
  /// fly the same way on every phone, and on this one every frame.
  static double _scatter(int i) {
    final v = math.sin(i * 12.9898) * 43758.5453;
    return (v - v.floorToDouble()) * 2 - 1;
  }

  /// The blade: a grey rectangle from the hilt outwards, at whatever angle the
  /// sim has it pointing this instant.
  ///
  /// Nothing here decides anything. The angle is interpolated between the
  /// host's snapshots like any other transform, so the swing a player sees is
  /// the swing that cut them, a frame or two of playback delay apart — the same
  /// delay every other moving thing on the table is drawn with.
  void _drawSword(Canvas canvas, RenderEntity e) {
    final length = e.propDouble('length', ArenaConfig.swordLength);
    final width = e.propDouble('width', ArenaConfig.swordWidth);

    // The entity *is* the hilt, so there is nothing to offset: translate,
    // turn, and lay the blade down the positive x axis.
    canvas.save();
    canvas.translate(e.x, e.y);
    canvas.rotate(e.angle);

    // A guard across the hilt, so the thing reads as a sword rather than a
    // stick, and so which end is the dangerous one is obvious.
    _fill.color = const Color(0xFF6B7280);
    canvas.drawRect(
      Rect.fromLTWH(-width * 0.6, -width * 1.8, width * 1.2, width * 3.6),
      _fill,
    );

    _fill.color = const Color(ArenaConfig.swordColor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -width / 2, length, width),
        Radius.circular(width / 2),
      ),
      _fill,
    );

    canvas.restore();
  }

  /// The three dots. Only the ones still in hand are drawn — a spent life is
  /// gone rather than greyed, which is what makes the row countable at a
  /// glance instead of read.
  void _drawLives(Canvas canvas, Offset at, double radius, int lives) {
    if (lives <= 0) return;

    final dot = radius * 0.22;
    final gap = dot * 3;
    // High enough to leave the head clear: the stun ring goes round just above
    // it, and two things in that band read as one mess.
    final top = at.dy - radius - dot * 5.5;
    final left = at.dx - gap * (lives - 1) / 2;

    _fill.color = const Color(0xFFFF4444);
    for (var i = 0; i < lives; i++) {
      canvas.drawCircle(Offset(left + gap * i, top), dot, _fill);
    }
  }

  /// The anchor the drag is measured from, under the finger that set it.
  ///
  /// Movement here is an angle from a point the player cannot see, which is a
  /// fine control and an invisible one — a finger drifting an inch during a
  /// scrap steers hard without ever feeling like it moved. The ring gives that
  /// point a body: where the stick is centred, which way it is pushed, and how
  /// far, now that how far is how fast.
  ///
  /// It appears only once the drag is actually steering. A finger sitting
  /// still is a tap or a block being held, and a ring under it would be the
  /// game saying "you are moving" to a player who is not.
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
    final ringColor = blocking
        ? const Color(0xFF4488FF)
        : const Color(0xFFFFFFFF);

    _fill.color = const Color(
      0xFFFFFFFF,
    ).withAlpha(ArenaConfig.joystickWellAlpha);
    canvas.drawCircle(anchor, reach, _fill);

    _stroke
      ..color = ringColor.withAlpha(ArenaConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.04);
    canvas.drawCircle(anchor, reach, _stroke);

    // The dead zone: where the fighter stops, and the edge the speed ramps up
    // from — a knob sitting just outside this circle is a crawl, and out at
    // the ring it is a run.
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
      ..color = const Color(0xFFFFFFFF).withAlpha(ArenaConfig.joystickRingAlpha)
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
    Canvas canvas,
    Frame frame,
    String text,
    double fontSize,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: fontSize),
          )
          ..pushStyle(
            ui.TextStyle(
              color: const Color(0xFFFFFFFF),
              fontWeight: FontWeight.w900,
            ),
          )
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

    // No lives here. They are already drawn over the fighter's own head, on
    // the floor where the player is looking, and a second copy in the corner
    // was the same fact twice — read from the further of the two places.
    final parts = <Widget>[];

    if (stunned) {
      parts.add(
        const Text(
          ' STUNNED',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFFDD44),
          ),
        ),
      );
    }

    if (atkCd > 0) {
      parts.add(
        Text(
          ' ATK ${atkCd.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
        ),
      );
    }

    if (blkCd > 0) {
      parts.add(
        Text(
          ' BLK ${blkCd.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
        ),
      );
    }

    // Nothing to say: no badge at all rather than an empty black pill in the
    // corner. Most of a round is spent in this state now that the lives have
    // gone back to the fighter.
    if (parts.isEmpty) return null;

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
