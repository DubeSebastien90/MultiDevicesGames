import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
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

  static const _floorColor = Color(0xFF161B22);
  static const _ballColor = Color(0xFFFF4444);
  static const _ballGlowColor = Color(0x44FF4444);

  /// World units per second below which a player counts as standing still.
  ///
  /// Not zero: positions are interpolated, so a stationary player still jitters
  /// by a hair between frames and an exact test would flicker the walk on and
  /// off.
  static const _walkingSpeed = 0.5;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  /// Where each player was last frame, to tell walking from standing.
  final _lastSeen = <String, Offset>{};

  @override
  void render(Canvas canvas, Frame frame) {
    // Floor, over the whole panel — see the note in `ArenaView`. Painting it
    // over `frame.board` left the far end of the biggest screen showing as a
    // differently coloured band that players were fenced out of; the sim keeps
    // them inside the screens themselves now, so every point this phone can
    // draw is playable.
    _fill.color = _floorColor;
    final view = frame.visible;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
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

    const white = Color(0xFFFFFFFF);

    _fill.color = white.withAlpha(DodgeballConfig.joystickWellAlpha);
    canvas.drawCircle(anchor, reach, _fill);

    _stroke
      ..color = white.withAlpha(DodgeballConfig.joystickRingAlpha)
      ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.04);
    canvas.drawCircle(anchor, reach, _stroke);

    // The dead zone: where the player stops, and the edge the speed ramps up
    // from — a knob sitting just outside this circle is a crawl, and out at
    // the ring it is a run.
    _stroke
      ..color = white.withAlpha(DodgeballConfig.joystickDeadZoneAlpha)
      ..strokeWidth = math.max(frame.onePixel, reach * 0.02);
    canvas.drawCircle(anchor, DodgeballConfig.minMoveDistance, _stroke);

    if (tilt.distance > 0) {
      _stroke
        ..color = white.withAlpha(DodgeballConfig.joystickDeadZoneAlpha)
        ..strokeWidth = math.max(frame.onePixel * 2, reach * 0.03);
      canvas.drawLine(anchor, knob, _stroke);
    }

    // The knob in the player's own colour — the one their body is wearing, so
    // at a glance the ring belongs to somebody.
    final me = roster.byPhone(phoneId);
    _fill.color = (me?.color.value ?? white).withAlpha(
      DodgeballConfig.joystickKnobAlpha,
    );
    canvas.drawCircle(knob, DodgeballConfig.joystickKnobRadius, _fill);
    _stroke
      ..color = white.withAlpha(DodgeballConfig.joystickRingAlpha)
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
    final dashCd = (frame.sharedState['dashCd_$key'] as num?)?.toDouble() ?? 0;
    final ballCount = (frame.sharedState['ballCount'] as num?)?.toInt() ?? 0;

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
    parts.add(
      Text(
        'Balls: $ballCount',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFF6666),
        ),
      ),
    );

    // Dash status.
    if (dashCd > 0) {
      parts.add(
        Text(
          '  DASH ${dashCd.toStringAsFixed(1)}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
        ),
      );
    } else {
      parts.add(
        const Text(
          '  DASH READY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF44FF44),
          ),
        ),
      );
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
