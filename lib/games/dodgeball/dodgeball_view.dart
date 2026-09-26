import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/render/particle_burst.dart';
import '../../sdk/render/player_animation.dart';
import 'dodgeball_config.dart';

/// Renders the dodgeball game: players, bouncing balls, dash effects, and
/// countdown/game-over overlays.
class DodgeballView extends GameView {
  DodgeballView({
    required this.phoneId,
    this.characters = PlayerAnimations.none,
    this.roster = Roster.empty,
  });

  final String phoneId;

  /// Everyone's walking character, loaded and coloured by the platform.
  final PlayerAnimations characters;

  /// Everyone in the round, for their platform colour. The sim ships a colour
  /// of its own on the entity, but the one a player recognises across the table
  /// is the one the lobby gave them.
  final Roster roster;

  /// A gym floor: light wood, so every player's colour and the red ball stand
  /// out against it — and the controls and words drawn over it are in [_ink],
  /// the lobby's own dark, rather than white.
  static const _floorColor = Color(0xFFF3DDB0);
  static const _plankLine = Color(0xFFE2C48F);
  static const _courtLine = Color(0xFFF08A80);
  static const _ink = Color(0xFF191510);

  /// One floorboard's width, and how long a board runs before its joint.
  static const _plankWidth = 0.9;
  static const _plankLength = 7.0;
  static const _ballColor = Color(0xFFFF4444);
  static const _ballGlowColor = Color(0x44FF4444);

  /// World units per second below which a player counts as standing still.
  ///
  /// Not zero: positions are interpolated, so a stationary player still jitters
  /// by a hair between frames and an exact test would flicker the walk on and
  /// off.
  static const _walkingSpeed = 0.5;

  /// The air kept between a message and the bottom edge of the glass, as a
  /// fraction of the screen's half-height.
  static const _messageMargin = 0.06;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  /// Where each player was last frame, to tell walking from standing.
  final _lastSeen = <String, Offset>{};

  /// When each player's burst started, on this phone's clock — the moment it
  /// was told they were out. See the same map in `ArenaView` for why the
  /// instant is local and everything after it runs off [Frame.timeMs].
  final _burstAt = <String, double>{};

  @override
  void render(Canvas canvas, Frame frame) {
    // Floor, over the whole panel — see the note in `ArenaView`. Painting it
    // over `frame.board` left the far end of the biggest screen showing as a
    // differently coloured band that players were fenced out of; the sim keeps
    // them inside the screens themselves now, so every point this phone can
    // draw is playable.
    _drawFloor(canvas, frame);

    // Draw balls. During the briefing the only ball on the board is the one
    // being thrown to explain the dash, and it fades at both ends — it has to
    // arrive from nowhere and leave without anybody waiting for it to bounce
    // off something.
    final demo = _demoFade(frame);
    for (final e in frame.ofKind('ball')) {
      final radius = e.propDouble('radius', DodgeballConfig.ballRadius);

      // Glow.
      _fill.color = _ballGlowColor.withValues(alpha: _ballGlowColor.a * demo);
      canvas.drawCircle(Offset(e.x, e.y), radius * 2.0, _fill);

      // Ball body.
      _fill.color = _ballColor.withValues(alpha: _ballColor.a * demo);
      canvas.drawCircle(Offset(e.x, e.y), radius, _fill);

      // Highlight.
      _fill.color = Color.fromARGB((0x66 * demo).round(), 255, 255, 255);
      canvas.drawCircle(
        Offset(e.x - radius * 0.25, e.y - radius * 0.25),
        radius * 0.3,
        _fill,
      );
    }

    // Whoever has just gone out, over the balls and under the living: the
    // burst happened *there*, and a player standing on the spot is standing
    // on it.
    _drawDeaths(canvas, frame);

    // Draw players.
    for (final e in frame.ofKind('player')) {
      final idx = e.propInt('index');
      final key = 'p$idx';
      // The platform's colour for whoever is in this seat, which is the one
      // they were shown in the lobby. The sim's own palette is the fallback,
      // for a seat nobody is sitting in yet.
      final phone = frame.sharedState['phoneId_$key'] as String?;
      final seated = phone == null ? null : roster.byPhone(phone);
      final color =
          seated?.color.value ?? Color(e.propInt('color', 0xFFFFFFFF));
      final radius = e.propDouble('radius', DodgeballConfig.characterRadius);
      final alive = frame.sharedState['alive_$key'] == true;
      if (!alive) continue;

      final isDashing = frame.sharedState['dashing_$key'] == true;
      final isInvincible = frame.sharedState['invincible_$key'] == true;

      // The dash, as a ring closing round the player.
      //
      // This is the whole of the old DASH readout, moved onto the thing it is
      // about. A number in the corner had to be found and read; a ring that
      // fills where the player is already looking is seen without either. Full
      // circle means ready — which is why it is drawn *only* while it is
      // filling, so a ready player has nothing extra round their feet.
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

      // Invincibility / dash shimmer.
      if (isInvincible) {
        final pulse = 0.5 + 0.5 * math.sin(frame.timeMs / 60);
        _stroke
          ..color = _ink.withAlpha((pulse * 160).toInt())
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

      // Player body. The character walks only while the player is actually
      // moving; `RenderEntity` carries no velocity, so movement is the distance
      // covered since the last frame.
      final here = Offset(e.x, e.y);
      final before = _lastSeen[e.id];
      _lastSeen[e.id] = here;
      final moving =
          before != null &&
          frame.dt > 0 &&
          (here - before).distance / frame.dt > _walkingSpeed;

      // A seat nobody is sitting in yet has no platform colour to ask for a
      // character with, so it stays the sim's own circle.
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

    // The player's own stick, drawn last so a body walking over their own
    // anchor does not cut a hole in it.
    //
    // Only this phone's: a joystick is a picture of what one pair of hands is
    // doing, and drawing everybody's would litter a floor that already has
    // balls crossing it.
    _drawJoystick(canvas, frame);

    // Countdown overlay.
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
        // GO for the last stretch, and the digits before it — never a nought,
        // which is what the clock actually says for the few frames between
        // running out and the round starting.
        go ? 'GO' : (cd - DodgeballConfig.goSeconds).ceil().toString(),
        frame.me.halfWidth * 2 * (go ? 0.22 : 0.3),
      );
    }

    // No finished overlay, as in Arena: the round holds for a second after the
    // last player goes out so the burst can play, and the phones move on to
    // the score by themselves a moment later.
  }

  /// Everybody's burst, for as long as theirs lasts.
  ///
  /// Driven from `alive_pN` going false: the roster of who is still standing
  /// is already on the wire, and the moment it changes is the moment somebody
  /// went out.
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
        particleRadius: DodgeballConfig.characterRadius *
            DodgeballConfig.deathParticleScale,
      );
    }
  }

  /// A player's colour: the platform one they have worn since the lobby where
  /// there is a seat for them, and the sim's palette otherwise — the same
  /// choice the body itself makes.
  Color _colorOf(Frame frame, String key) {
    final phoneId = frame.sharedState['phoneId_$key'] as String? ?? '';
    final seated = roster.byPhone(phoneId);
    return seated?.color.value ??
        Color((frame.sharedState['color_$key'] as num?)?.toInt() ?? 0xFFFFFFFF);
  }

  /// The anchor the drag is measured from, under the finger that set it.
  ///
  /// Movement here is an angle from a point the player cannot see, which is a
  /// fine control and an invisible one — a finger drifting an inch while
  /// threading between two balls steers hard without ever feeling like it
  /// moved. The ring gives that point a body: where the stick is centred,
  /// which way it is pushed, and how far, now that how far is how fast.
  ///
  /// It appears only once the drag is actually steering. A finger sitting
  /// still is a dash being aimed, and a ring under it would be the game saying
  /// "you are moving" to a player who is not.
  void _drawJoystick(Canvas canvas, Frame frame) {
    final key = _myKey(frame.sharedState);
    if (key == null) return;

    final ax = (frame.sharedState['stickX_$key'] as num?)?.toDouble();
    final ay = (frame.sharedState['stickY_$key'] as num?)?.toDouble();
    // Absent means no finger is steering. Nothing to draw, and nothing else in
    // here is worth reading.
    if (ax == null || ay == null) return;
    final tx = (frame.sharedState['stickToX_$key'] as num?)?.toDouble() ?? ax;
    final ty = (frame.sharedState['stickToY_$key'] as num?)?.toDouble() ?? ay;

    final anchor = Offset(ax, ay);
    final pushed = Offset(tx - ax, ty - ay);
    final reach = DodgeballConfig.joystickRadius;
    // Past the ring the knob stops travelling but the drag keeps steering, so
    // full tilt looks like full tilt however far the hand has wandered.
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

    // The dead zone: where the player stops, and the edge the speed ramps up
    // from — a knob sitting just outside this circle is a crawl, and out at
    // the ring it is a run.
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

    // The knob in the player's own colour — the one their body is wearing, so
    // at a glance the ring belongs to somebody.
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

  /// Which player is this phone's, as `p0`..`p7`. Null before the sim has
  /// seated anybody, and on a phone that is watching rather than playing.
  String? _myKey(Map<String, Object?> sharedState) {
    for (var i = 0; i < 8; i++) {
      if (sharedState['phoneId_p$i'] == phoneId) return 'p$i';
    }
    return null;
  }

  /// How solid the demonstration ball is right now, 0 to 1.
  ///
  /// One outside the briefing, where every ball on the board is a real one.
  /// Inside it, a fade in as it arrives and a fade out as it leaves: the ball
  /// exists to be dodged once, and one that simply vanished — or that hung
  /// about afterwards — would read as a ball still in play.
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

  /// Floorboards, and the court painted on them.
  ///
  /// Laid from the world origin rather than from this screen's edge, so the
  /// boards and the lines run unbroken from one phone to the next. The joints
  /// are staggered row by row, the way boards are actually laid.
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

    // Halfway line and centre circle, across the long side of the table.
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

  /// One line across this phone's own glass, under the player standing on it.
  ///
  /// [Frame.me] rather than [Frame.visible]: a phone laid at an angle has a
  /// bounding box wider than its screen, so world x and y run diagonally
  /// across its glass — text placed by them comes out crooked, and "half a
  /// screen down" in world y can be most of the way off a screen whose height
  /// points sideways. Turning the canvas to match the slot makes the
  /// arithmetic plain and has the words arrive upright for whoever is holding
  /// the phone.
  ///
  /// *Below* the player, because a player stands in the middle of their own
  /// screen and the briefing is about watching them move.
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

    final bodyBottom = DodgeballConfig.characterRadius * 1.8;
    final glassBottom = me.halfHeight - margin;
    var centre = (bodyBottom + glassBottom) / 2;

    // Pinned to the glass. On a screen too short for the band to hold the
    // line, this is what decides which of the two it gives up: staying on
    // screen wins, and the words may lie across the player's feet.
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
  // controls into the briefing that opens the round, the dash cooldown into a
  // ring round the player, the ball count nowhere — the balls are on the table
  // and counting them in a corner was the same fact written twice.
}
