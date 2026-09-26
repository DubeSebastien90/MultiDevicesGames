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
  }) {
    LightsaberArt.preload([
      const Color(ArenaConfig.swordColor),
      for (final p in roster.players) p.color.value,
    ]);
  }

  final String phoneId;

  /// Everyone's walking character, loaded and coloured by the platform.
  final PlayerAnimations characters;

  /// Everyone in the round, for their platform colour — the one they were
  /// shown in the lobby, rather than the sim's own palette.
  final Roster roster;

  /// Packed earth, as in a real arena: warm sand, raked round the middle and
  /// scattered with grit. Light, so every fighter's colour and every blade's
  /// glow stands out against it — and the controls and words drawn over it
  /// are in [_ink], the lobby's own dark, rather than white.
  static const _floorColor = Color(0xFFEBD0A2);
  static const _rake = Color(0x33B98A4E);
  static const _ring = Color(0xFFD2A76C);
  static const _gritDark = Color(0x55976A36);
  static const _gritLight = Color(0x66FFF3DC);
  static const _ink = Color(0xFF191510);

  /// How far apart the rake's lines are, in world units.
  static const _rakeGap = 0.45;

  /// The grit is laid one speck per cell of this size, each nudged about
  /// inside its own cell so the floor does not read as a grid.
  static const _gritCell = 0.7;

  /// The air kept between the message and the bottom edge of the glass, as a
  /// fraction of the screen's half-height.
  static const _messageMargin = 0.06;

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
    _drawFloor(canvas, frame);

    // Grips under the bodies, blades over them: the hilt sits in the hand
    // that holds it, and whatever of it would show through the body is the
    // part the fist is closed round.
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

      // The guard coming back, as a ring closing round the fighter — drawn
      // only while it fills, so a fighter who can block has nothing extra
      // round their feet. Full circle is the moment the blade hums back on.
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
      _drawSword(canvas, e, _colorOf(frame, key));
    }

    // The player's own stick, drawn last so a fighter walking over their own
    // anchor does not cut a hole in it.
    //
    // Only this phone's: a joystick is a picture of what one pair of hands is
    // doing, and drawing everybody's would litter the table with rings nobody
    // can act on — and quietly leak which way each opponent is about to break.
    _drawJoystick(canvas, frame);

    // What to do, then when it starts. Both in the middle of this phone's own
    // screen rather than in the corner badge the platform collects HUDs into:
    // during the one moment there is nothing else to look at, the thing to
    // look at should not be in a corner.
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
        // GO for the last stretch, and the digits before it — never a nought,
        // which is what the clock actually says for the few frames between
        // running out and the round starting.
        go ? 'GO' : (cd - ArenaConfig.goSeconds).ceil().toString(),
        frame.me.halfWidth * 2 * (go ? 0.22 : 0.3),
      );
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

  /// One burst — see [drawParticleBurst] — sized to a fighter.
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
    particleRadius: ArenaConfig.characterRadius * ArenaConfig.deathParticleScale,
  );

  /// The blade: a grey rectangle from the hilt outwards, at whatever angle the
  /// sim has it pointing this instant.
  ///
  /// Nothing here decides anything. The angle is interpolated between the
  /// host's snapshots like any other transform, so the swing a player sees is
  /// the swing that cut them, a frame or two of playback delay apart — the same
  /// delay every other moving thing on the table is drawn with.
  /// How ready this fighter's guard is, 0 to 1.
  ///
  /// Spent while they are actually blocking, then climbing back over
  /// [ArenaConfig.blockCooldown]. Drawn as the ring round the fighter.
  double _guardCharge(Frame frame, String key) {
    if (frame.sharedState['blocking_$key'] == true) return 0;
    final left = (frame.sharedState['blkCd_$key'] as num?)?.toDouble() ?? 0;
    if (left <= 0) return 1;
    final charge = 1 - left / ArenaConfig.blockCooldown;
    return charge < 0 ? 0 : (charge > 1 ? 1 : charge);
  }

  /// The saber's grip, behind the blade. Nothing to draw without the art:
  /// the plain sword's guard goes over the body with its blade.
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

  /// Always fully lit, in the owner's colour: the guard's recharge is the
  /// ring round the fighter, and the blade only has to say *whose*.
  void _drawSword(Canvas canvas, RenderEntity e, Color color) {
    final length = e.propDouble('length', ArenaConfig.swordLength);
    final width = e.propDouble('width', ArenaConfig.swordWidth);

    // The entity *is* the hilt, so there is nothing to offset: translate,
    // turn, and lay the blade down the positive x axis.
    canvas.save();
    canvas.translate(e.x, e.y);
    canvas.rotate(e.angle);

    final blade = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, -width / 2, length, width),
      Radius.circular(width / 2),
    );

    // The glow, under whichever blade is drawn over it.
    _fill
      ..color = color.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 1.6);
    canvas.drawRRect(blade, _fill);
    _fill.maskFilter = null;

    // The lightsaber when it has loaded. The grip is drawn on its own, under
    // the body.
    if (LightsaberArt.isLoaded(color)) {
      LightsaberArt.draw(canvas, color, length: length, from: 0, to: length);
      canvas.restore();
      return;
    }

    // Until then, a plain sword: a guard across the hilt, so the thing reads
    // as a sword rather than a stick, and which end is dangerous is obvious.
    _fill.color = const Color(0xFF6B7280);
    canvas.drawRect(
      Rect.fromLTWH(-width * 0.6, -width * 1.8, width * 1.2, width * 3.6),
      _fill,
    );
    _fill.color = color;
    canvas.drawRRect(blade, _fill);

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
    final ringColor = blocking ? const Color(0xFF4488FF) : _ink;

    _fill.color = _ink.withAlpha(ArenaConfig.joystickWellAlpha);
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
      ..color = _ink.withAlpha(ArenaConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(knob, ArenaConfig.joystickKnobRadius, _stroke);
  }

  /// The arena floor: sand, the rake's rings round the middle of the table,
  /// the fighting circle trodden into it, and grit.
  ///
  /// All of it laid from the world, never from this screen's edge — the rings
  /// share the board's centre, and each speck of grit is placed by its cell's
  /// own coordinates — so the floor runs unbroken from one phone to the next.
  void _drawFloor(Canvas canvas, Frame frame) {
    final view = frame.visible;
    final area = Rect.fromLTWH(view.left, view.top, view.width, view.height);
    _fill.color = _floorColor;
    canvas.drawRect(area, _fill);

    final board = frame.board;
    final centre = Offset(board.centerX, board.centerY);

    // The rake, in rings round the middle. Only the rings this screen reaches.
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

    // The fighting circle, trodden darker into the sand.
    final ring = math.min(board.width, board.height) * 0.42;
    _stroke
      ..color = _ring
      ..strokeWidth = 0.3;
    canvas.drawCircle(centre, ring, _stroke);

    _drawGrit(canvas, area);
  }

  /// A speck of grit in every cell, dark or light, placed and sized by the
  /// cell's own coordinates — the same speck on every phone that can see it.
  ///
  /// Hashed with small integer arithmetic on purpose: it has to come out the
  /// same on a phone running compiled Dart and one running it as JavaScript,
  /// where big products lose their low bits.
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

  /// One line across this phone's own glass, under the fighter standing on it.
  ///
  /// Drawn in the phone's **own frame**, not the world's. A phone laid at an
  /// angle sits in an angled slot in the world, so world x and y run diagonally
  /// across its glass: text placed by world coordinates comes out crooked, and
  /// "half a screen down" in world y can be most of the way off a screen whose
  /// height points sideways. Turning the canvas to match the slot makes the
  /// arithmetic below plain again — x across the glass, y down it — and has
  /// the words arrive upright for whoever is holding it.
  ///
  /// *Below* the fighter, because above them is taken: the lives sit over their
  /// head and the stun ring goes round them. The line is centred in what is
  /// left — the band between the bottom of the body and the bottom of the
  /// screen — and then pinned inside the glass, because that band is a
  /// different size on every phone at the table and a message that is
  /// comfortable on a tall one must not fall off a short one.
  void _drawCentered(Canvas canvas, Frame frame, String text, double size) {
    final me = frame.me;
    final width = me.halfWidth * 2;

    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: size),
          )
          ..pushStyle(ui.TextStyle(color: _ink, fontWeight: FontWeight.w900))
          ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width));

    final half = paragraph.height / 2;
    final margin = me.halfHeight * _messageMargin;

    // All of this is now measured from the middle of the glass, down it.
    final bodyBottom = ArenaConfig.characterRadius * 1.8;
    final glassBottom = me.halfHeight - margin;
    var centre = (bodyBottom + glassBottom) / 2;

    // Pinned to the glass. On a screen too short for the band to hold the
    // line, this is what decides which of the two it gives up: staying on
    // screen wins, and the words may lie across the fighter's feet.
    final lowest = glassBottom - half;
    final highest = -me.halfHeight + margin + half;
    if (centre > lowest) centre = lowest;
    if (centre < highest) centre = highest;

    canvas.save();
    canvas.translate(me.worldCenterX, me.worldCenterY);
    canvas.rotate(me.turnRadians);
    canvas.drawParagraph(paragraph, Offset(-width / 2, centre - half));
    canvas.restore();
  }

  // No HUD. Everything it used to carry has gone where it belongs: the
  // controls into the briefing that opens the round, the lives onto the
  // fighter's own head, the block cooldown onto the blade, and the attack
  // cooldown nowhere — at half a second it is over before anybody could look
  // it up.
}
