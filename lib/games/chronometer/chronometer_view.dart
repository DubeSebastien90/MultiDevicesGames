import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/player_color.dart';
import 'chronometer_config.dart';
import 'chronometer_sim.dart';

/// A number, a countdown, then nothing at all — and a dial that fills with
/// everyone's guesses.
///
/// **Your phone is your colour.** The whole screen is washed in the player's own
/// swatch, dark at the corners and bright behind the middle, so a table of
/// phones reads as a row of different-coloured toys rather than a row of black
/// rectangles. It also makes the colour mean something before a single pip has
/// landed: you learn you are Green by looking down, not by hunting for a dot.
/// Pips stay in the palette's own colours, so the dial still shows everybody.
///
/// The look is chunky on purpose — fat rings, hard shadows, a wobble on the big
/// numbers. Board-game plastic, not a dashboard.
///
/// One rule survives all of that: **during the running phase nothing on screen
/// ticks.** No sweep hand, no numerals, no progress arc. Anything moving at a
/// steady rate is something a player can count instead of estimating, and the
/// game would be measuring eyesight rather than timekeeping. The background
/// still breathes, on a period that is deliberately not a round number of
/// seconds and is slowed and flattened while the clock runs — alive enough that
/// the phone does not look switched off, useless as a metronome.
///
/// Each phone draws its own dial, centred on itself, because there is no seam
/// here: nothing crosses between screens, so a shared board-space dial would
/// only mean most players squinting at an arc off the side of their phone.
class ChronometerView extends GameView {
  ChronometerView(this.context);

  final ViewContext context;

  /// The dark the colour is bedded into. Warm rather than pure black, so a
  /// saturated wash on top reads as lit rather than as a screen turned down.
  static const _pit = Color(0xFF13111C);
  static const _chalk = Color(0xFFFFF8E7);
  static const _shadow = Color(0x55000000);

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  /// Text is laid out once per distinct string and kept. A `TextPainter` per
  /// frame is a whole shaping pass sixty times a second for a digit that
  /// changes once a second.
  final _text = <String, TextPainter>{};

  /// Guesses this phone has already seen land, so a new one can flare exactly
  /// once. Keyed by the encoded row, which is unique per press.
  final _seen = <String>{};

  /// Pips still flaring, and how much of the flare is left. Counted down from
  /// the local frame delta rather than stored as a timestamp: `frame.timeMs` is
  /// the *round's* clock and goes back to zero at every new one, so a stored
  /// instant comes round again later and lights up pips nobody touched.
  final _flares = <String, double>{};

  /// This phone's own press, confirmed under the finger.
  double _pulseLeftMs = 0;

  /// How long the results have been up, locally, for the winner's pip to swell
  /// out of the rim and settle in the middle.
  double _resultsMs = 0;

  /// Whether this phone has committed, for the HUD and for tests.
  bool _committed = false;

  bool get isPulsing => _pulseLeftMs > 0;
  bool get hasCommitted => _committed;

  // ----------------------------------------------------------------- render

  @override
  void render(Canvas canvas, Frame frame) {
    final phase = frame.sharedState['phase'] as String? ?? ChronoPhase.reveal;
    final mine = _myColor(frame);

    // The backdrop is a plain wash over the whole visible rect, so it neither
    // needs nor wants un-turning — rotating a full-bleed gradient only risks
    // leaving a corner unpainted.
    _paintBackdrop(canvas, frame, phase, mine);
    _advanceEffects(frame, phase);

    // Everything else is drawn upright to the person holding the phone.
    //
    // A phone in this game's ring lies at whatever angle its seat demands — a
    // three-armed star turns two of the three phones by 120° and 240° — and the
    // platform camera rotates the world by that angle so a *shared* board
    // arrives the right way round on every screen. That is exactly right for a
    // game with a seam and exactly wrong here: there is no shared board, each
    // phone draws its own dial, and the camera's turn was landing on the dial
    // as a tilt with nothing to justify it. The host sits at zero degrees, so
    // it looked perfect on the one screen anybody was watching.
    //
    // Undoing the camera's angle here, rather than flattening the turns in
    // `planBoard`, keeps the two facts in the places they belong: the layout
    // still says how the phones are *put on the table*, which is what the
    // placement screen draws and what people follow; the view says which way
    // its own pixels read. Fixing it in the layout threw away the star.
    final turn = frame.me.turnRadians;
    if (turn.abs() < 1e-9) {
      _drawPhase(canvas, frame, phase, mine);
      _drawPressPulse(canvas, frame, mine);
      return;
    }

    final pivot = _dialOf(frame).centre;
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(-turn);
    canvas.translate(-pivot.dx, -pivot.dy);

    _drawPhase(canvas, frame, phase, mine);
    _drawPressPulse(canvas, frame, mine);

    canvas.restore();
  }

  void _drawPhase(Canvas canvas, Frame frame, String phase, Color mine) {
    switch (phase) {
      case ChronoPhase.reveal:
        _drawTarget(canvas, frame, mine);
      case ChronoPhase.countdown:
        _drawCountdown(canvas, frame, mine);
      case ChronoPhase.running:
        _drawDial(canvas, frame, mine);
      default:
        _drawResults(canvas, frame, mine);
    }
  }

  /// This phone's own player colour, from the seating the sim publishes.
  ///
  /// Falls back to a warm neutral rather than to nothing: a phone the host
  /// never seated still has to look like a game, not like a crash.
  Color _myColor(Frame frame) {
    final seating = frame.sharedState['seating'];
    if (seating is List) {
      for (final row in seating) {
        final parts = (row as String).split(':');
        if (parts.first == frame.me.phoneId) {
          return PlayerPalette.byId(parts.length > 1 ? parts[1] : null)?.value ??
              _chalk;
        }
      }
    }
    return _chalk;
  }

  /// The centre of *this* screen, and how big a dial fits on it.
  ///
  /// Both in world units and both derived from this phone's own viewport, which
  /// is what lets a small phone and a large one show the same picture at the
  /// size each can actually hold.
  /// Sized from the screen's **own** extent, not from [PhoneLayout.viewport].
  ///
  /// `viewport` is the axis-aligned box a turned screen occupies, which is
  /// bigger than the screen itself — a phone at 45° reports a box about 1.4×
  /// its own width. Sizing a dial off that drew it larger than the glass it had
  /// to fit on, and the further round the ring a player sat the worse it got.
  /// `halfWidth`/`halfHeight` are the real thing, turn excluded, which is what
  /// the counter-rotated canvas is drawing into.
  ({Offset centre, double radius}) _dialOf(Frame frame) {
    final me = frame.me;
    final centre = Offset(me.worldCenterX, me.worldCenterY);
    final radius = math.min(me.halfWidth, me.halfHeight) *
        2 *
        ChronometerConfig.dialFraction;
    return (centre: centre, radius: radius);
  }

  // -------------------------------------------------------------- backdrop

  /// The player's colour, bloomed out of the middle over a dark bed.
  void _paintBackdrop(Canvas canvas, Frame frame, String phase, Color mine) {
    final area = frame.visible.inflate(2);
    final rect = Rect.fromLTWH(area.left, area.top, area.width, area.height);

    _fill.shader = null;
    _fill.color = _pit;
    canvas.drawRect(rect, _fill);

    final running = phase == ChronoPhase.running;
    final period = running ? 7300.0 : 4100.0;
    final swing = running ? 0.05 : 0.16;
    final breath = 0.5 + 0.5 * math.sin(frame.timeMs / period * 2 * math.pi);

    final dial = _dialOf(frame);

    // Pulled right down on the results screen, so the winner's disc has
    // something to stand against.
    //
    // The wash is this phone's own colour and the disc is the winner's, so when
    // you win they are the same colour and the hero of the screen disappears
    // into its own background — which is precisely the moment it must not. The
    // colour has done its job by then: everyone knows whose phone this is, and
    // the disc needs the contrast more than the room needs the glow.
    final lift = phase == ChronoPhase.results ? 0.34 : 1.0;

    // Two stops rather than one: a hot core that keeps the middle readable and
    // a long falloff that reaches the corners, so the phone looks lit rather
    // than spotlit.
    _fill.shader = ui.Gradient.radial(
      dial.centre,
      math.max(frame.me.viewport.width, frame.me.viewport.height) * 0.95,
      [
        mine.withValues(alpha: (0.62 + swing * breath) * lift),
        mine.withValues(alpha: 0.34 * lift),
        mine.withValues(alpha: 0.10 * lift),
      ],
      const [0.0, 0.45, 1.0],
    );
    canvas.drawRect(rect, _fill);
    _fill.shader = null;

    if (phase == ChronoPhase.results) _drawConfetti(canvas, frame, mine);
  }

  /// Slow drifting flecks once the round is done. Purely decorative, and only
  /// ever on the results screen — during the guess a moving speck is something
  /// to count.
  void _drawConfetti(Canvas canvas, Frame frame, Color mine) {
    final v = frame.me.viewport;
    final t = _resultsMs / 1000;

    for (var i = 0; i < 14; i++) {
      // A fixed pseudo-random scatter: the same flecks every round, which
      // nobody notices, and no allocation per frame.
      final seed = i * 47.13;
      final x = v.left + v.width * ((math.sin(seed) + 1) / 2);
      final drift = (t * (0.35 + (i % 5) * 0.11)) % 1.0;
      final y = v.bottom - v.height * drift;
      final r = v.width * (0.006 + (i % 3) * 0.004);

      _fill
        ..shader = null
        ..color = _chalk.withValues(alpha: 0.22 * (1 - drift));
      canvas.drawCircle(Offset(x, y), r, _fill);
    }
  }

  void _advanceEffects(Frame frame, String phase) {
    final ms = frame.dt * 1000;
    _pulseLeftMs = math.max(0, _pulseLeftMs - ms);

    if (phase == ChronoPhase.results) {
      _resultsMs += ms;
    } else {
      _resultsMs = 0;
    }

    for (final key in _flares.keys.toList()) {
      final left = _flares[key]! - ms;
      if (left <= 0) {
        _flares.remove(key);
      } else {
        _flares[key] = left;
      }
    }

    // A new round: forget everything the last one left lying about.
    if (phase == ChronoPhase.reveal && (_seen.isNotEmpty || _committed)) {
      _seen.clear();
      _flares.clear();
      _committed = false;
      _pulseLeftMs = 0;
    }

    _noticeGuesses(frame);
  }

  /// Flare each newly-landed pip, and buzz only for this phone's own.
  ///
  /// The buzz is the confirmation that a press was *registered by the host* —
  /// which is the only registration that counts — so it is fired here off the
  /// shared state rather than in the touch handler, where it would be a
  /// comforting lie about a packet that had not arrived yet.
  void _noticeGuesses(Frame frame) {
    final rows = frame.sharedState['guesses'];
    if (rows is! List) return;

    for (final row in rows) {
      final key = row as String;
      if (!_seen.add(key)) continue;

      _flares[key] = ChronometerConfig.pipFlashMs;
      if (_phoneOf(key) != frame.me.phoneId) continue;

      _committed = true;
      _pulseLeftMs = ChronometerConfig.pressPulseMs;
      // The long buzz, not a light impact: this has to be felt by somebody
      // whose eyes are on the table, through a phone lying flat on it.
      HapticFeedback.vibrate();
    }
  }

  static String _phoneOf(String row) => row.split(':').first;

  // ------------------------------------------------------------ the phases

  /// The number, huge, sitting on a fat disc.
  void _drawTarget(Canvas canvas, Frame frame, Color mine) {
    final dial = _dialOf(frame);

    // A slow wobble, so the reveal has some life in it. Big and lazy — this is
    // the one screen where a player is only reading a number.
    final wobble = 1 + 0.035 * math.sin(frame.timeMs / 620 * 2 * math.pi);
    final r = dial.radius * wobble;

    _disc(canvas, dial.centre, r, mine);

    final target = (frame.sharedState['target'] as num?)?.toDouble() ?? 0;
    final label = target == target.roundToDouble()
        ? '${target.round()}'
        : target.toStringAsFixed(1);

    _paintText(
      canvas,
      label,
      dial.centre - Offset(0, r * 0.06),
      size: r * 1.0,
      color: _chalk,
      weight: FontWeight.w900,
    );
    _paintText(
      canvas,
      'SECONDS',
      dial.centre + Offset(0, r * 1.34),
      size: r * 0.17,
      color: _chalk,
      weight: FontWeight.w800,
      letterSpacing: r * 0.09,
    );
  }

  /// 3, 2, 1 — each digit punching in and easing out.
  void _drawCountdown(Canvas canvas, Frame frame, Color mine) {
    final n = (frame.sharedState['countIn'] as num?)?.toInt() ?? 0;
    if (n <= 0) return;

    final dial = _dialOf(frame);

    // Where inside this digit's own second we are. Derived from the shared
    // clock so every phone punches in step — a countdown a beat apart across
    // the table is worse than none at all.
    final t = 1 - (frame.timeMs / 1000) % 1.0;

    // Overshoot and settle, rather than a linear swell: the digit arrives with
    // a bounce, which is most of what makes it feel like a game.
    final pop = t > 0.75 ? (1 - t) / 0.25 : 1.0;
    final scale = 0.72 + 0.5 * _overshoot(pop);

    // A shockwave ring left behind by the digit that just landed.
    final ring = 1 - t;
    if (ring < 0.55) {
      _stroke
        ..color = _chalk.withValues(alpha: 0.30 * (1 - ring / 0.55))
        ..strokeWidth = frame.onePixel * 5;
      canvas.drawCircle(dial.centre, dial.radius * (0.7 + ring * 2.4), _stroke);
    }

    _disc(canvas, dial.centre, dial.radius * 0.86, mine);
    _paintText(
      canvas,
      '$n',
      dial.centre,
      size: dial.radius * scale * 1.25,
      color: _chalk,
      weight: FontWeight.w900,
    );
  }

  /// Nothing to full and a little past it, then back. The bounce.
  static double _overshoot(double t) {
    if (t >= 1) return 1;
    const c = 1.9;
    final x = t - 1;
    return 1 + x * x * ((c + 1) * x + c);
  }

  // -------------------------------------------------------------- the dial

  /// The rim, the twelve-o'clock notch, and every guess that has landed.
  void _drawDial(Canvas canvas, Frame frame, Color mine) {
    final dial = _dialOf(frame);
    final px = frame.onePixel;

    // A fat, soft track rather than a hairline: this is the thing pips sit on,
    // and it should look like a moulded groove.
    _stroke
      ..color = _shadow
      ..strokeWidth = px * 13;
    canvas.drawCircle(dial.centre, dial.radius, _stroke);
    _stroke
      ..color = _chalk.withValues(alpha: 0.30)
      ..strokeWidth = px * 9;
    canvas.drawCircle(dial.centre, dial.radius, _stroke);

    _drawNotch(canvas, dial, px);

    final sweep = (frame.sharedState['sweep'] as num?)?.toDouble() ?? 1;
    final target = (frame.sharedState['target'] as num?)?.toDouble() ?? 0;

    // The number, faint, in the middle of the ring. A full turn of the dial is
    // this many seconds, so saying which number the circle stands for is what
    // makes the pips mean anything — and forgetting the target mid-round is a
    // way to lose that has nothing to do with timekeeping.
    //
    // Static: it is the target, not a clock, and nothing here counts.
    _paintText(
      canvas,
      target == target.roundToDouble()
          ? '${target.round()}'
          : target.toStringAsFixed(1),
      dial.centre,
      size: dial.radius * 0.52,
      color: _chalk.withValues(alpha: 0.30),
      weight: FontWeight.w900,
    );
    final rows = frame.sharedState['guesses'];
    if (rows is List) {
      for (final row in rows) {
        _drawPip(canvas, frame, dial, row as String, sweep, target);
      }
    }

    if (!_committed) {
      // The only instruction, and it breathes so the screen is never wholly
      // still. Slow enough not to be countable.
      final pulse = 0.62 +
          0.38 * (0.5 + 0.5 * math.sin(frame.timeMs / 1450 * 2 * math.pi));
      _paintText(
        canvas,
        'TAP WHEN IT LANDS',
        dial.centre + Offset(0, dial.radius * 1.62),
        size: dial.radius * 0.15,
        color: _chalk.withValues(alpha: pulse),
        weight: FontWeight.w800,
        letterSpacing: dial.radius * 0.055,
      );
    } else {
      // Chalk, not the player's own colour: the background is already that
      // colour, and colour-on-colour was all but invisible.
      _paintText(
        canvas,
        'LOCKED IN',
        dial.centre + Offset(0, dial.radius * 1.62),
        size: dial.radius * 0.15,
        color: _chalk,
        weight: FontWeight.w900,
        letterSpacing: dial.radius * 0.055,
      );
    }
  }

  /// Twelve o'clock is *exactly right*, and marked as such.
  ///
  /// The whole dial is read as "how far from that notch", so leaving it
  /// unmarked would make it read as "somewhere near the top".
  void _drawNotch(Canvas canvas, ({Offset centre, double radius}) dial,
      double px) {
    final top = dial.centre + Offset(0, -dial.radius);

    // Sized against the *track*, which is stroked in pixels, not against the
    // dial's radius in world units. Mixing the two is why the notch was
    // invisible: a world-unit sliver 5% of the radius wide came out thinner
    // than the 9-pixel groove it was supposed to interrupt, so the ring simply
    // swallowed it. The mark that defines "bang on" has to be the boldest thing
    // on the rim.
    _fill
      ..shader = null
      ..color = _chalk;
    final w = math.max(px * 5, dial.radius * 0.045);
    final h = math.max(px * 26, dial.radius * 0.26);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: top, width: w * 2, height: h),
        Radius.circular(w),
      ),
      _fill,
    );
  }

  /// One guess, as a fat pip on the rim in that player's colour.
  ///
  /// The angle is the guess as a fraction of the whole window, offset so that a
  /// *perfect* guess sits at twelve o'clock rather than wherever the arithmetic
  /// happened to put it. Early guesses fall to the left of the notch, late ones
  /// to the right, and how far round tells you how badly — which is the reading
  /// the dial exists to give at a glance, before any number is shown.
  void _drawPip(
    Canvas canvas,
    Frame frame,
    ({Offset centre, double radius}) dial,
    String row,
    double sweep,
    double target,
  ) {
    final at = _guessIn(row);
    if (at == null || sweep <= 0) return;

    final centre = _pipCentre(dial, at, sweep, target);
    final color = _colorIn(row);
    final flare = (_flares[row] ?? 0) / ChronometerConfig.pipFlashMs;
    final r = dial.radius * ChronometerConfig.pipFraction;

    // The flare: a halo swelling out and fading, so a pip landing is caught in
    // the corner of the eye by everybody at the table.
    if (flare > 0) {
      _fill
        ..shader = null
        ..color = color.withValues(alpha: 0.34 * flare);
      canvas.drawCircle(centre, r * (1 + 2.4 * (1 - flare)), _fill);
    }

    _blob(canvas, centre, r * (1 + 0.38 * flare), color, frame.onePixel);
  }

  /// Where on the rim a guess of [at] seconds belongs.
  ///
  /// One full turn is the *target*, clockwise from twelve o'clock, so the dial
  /// is a clock face: pressing at half the target puts you at six, and a
  /// perfect guess comes right back round to the notch at the top. A player
  /// reads their own pip as "how far round the circle I got", which is the
  /// thing they were actually estimating.
  ///
  /// [sweep] is no longer part of the angle. It stays in the signature because
  /// the results rows still carry it and a guard below needs the round's own
  /// scale, but the arithmetic is deliberately anchored to the target alone.
  /// [_pipCentre], for the tests that pin the dial's geometry.
  ///
  /// The angle a guess maps to is the one claim this view makes that is worth
  /// asserting directly — "half the target is at six o'clock" is a fact, not a
  /// look — and reading it back out of pixels would test the rasteriser.
  @visibleForTesting
  static Offset debugPipCentre(
    ({Offset centre, double radius}) dial,
    double at,
    double sweep,
    double target,
  ) =>
      _pipCentre(dial, at, sweep, target);

  static Offset _pipCentre(({Offset centre, double radius}) dial, double at,
      double sweep, double target) {
    // A target of zero cannot happen — the sim draws from three seconds up —
    // but dividing by it would put every pip in the same place if it ever did.
    final turns = target <= 0
        ? 0.0
        : (at / target * ChronometerConfig.sweepTurns)
            .clamp(0.0, ChronometerConfig.maxLapTurns);
    final angle = -math.pi / 2 + turns * 2 * math.pi;
    return dial.centre +
        Offset(math.cos(angle), math.sin(angle)) * dial.radius;
  }

  static double? _guessIn(String row) {
    final parts = row.split(':');
    return parts.length < 3 ? null : double.tryParse(parts[2]);
  }

  static Color _colorIn(String row) {
    final parts = row.split(':');
    return PlayerPalette.byId(parts.length > 1 ? parts[1] : null)?.value ??
        _chalk;
  }

  // ----------------------------------------------------------- the results

  /// **Your own result in the middle, on every phone.**
  ///
  /// The winner used to fly into the centre of every screen, which meant four
  /// phones all showing the same person's time and three players hunting a list
  /// for their own. A phone belongs to the person holding it: the number in the
  /// middle of yours is yours, and the winner — when it is not you — is a small
  /// bubble off to the side, which is exactly the weight "somebody else won"
  /// deserves on your screen.
  ///
  /// Your pip still *flies* there from its place on the rim, growing as it
  /// goes. That journey is what explains the result: the eye follows the mark
  /// from where it sat relative to the notch into the spotlight, so you see how
  /// close you were before you read a single digit.
  void _drawResults(Canvas canvas, Frame frame, Color mine) {
    final rows = frame.sharedState['results'];
    if (rows is! List || rows.isEmpty) {
      _drawDial(canvas, frame, mine);
      return;
    }

    final sweep = (frame.sharedState['sweep'] as num?)?.toDouble() ?? 1;
    final target = (frame.sharedState['target'] as num?)?.toDouble() ?? 0;
    final dial = _dialOf(frame);

    final winner = rows.first as String;
    final iWon = winner.split(':').first == frame.me.phoneId;

    String? me;
    for (final row in rows) {
      if ((row as String).split(':').first == frame.me.phoneId) me = row;
    }

    final t = (_resultsMs / ChronometerConfig.winnerFlightMs).clamp(0.0, 1.0);
    final ease = _easeOutBack(t);

    // Everything except the hero, dimming as it comes forward.
    _drawFadingDial(canvas, frame, dial, rows, sweep, target, 1 - t,
        skip: me ?? winner);

    // This phone never pressed: there is no pip of its own to fly, so the
    // winner's takes the middle instead. Saying nothing at all would leave the
    // one player who most needs telling staring at an empty dial.
    final heroRow = (me != null && _guessIn(me) != null) ? me : winner;
    final heroAt = _guessIn(heroRow);
    if (heroAt == null || sweep <= 0) {
      _drawDial(canvas, frame, mine);
      _drawNoPress(canvas, frame, dial, rows, target);
      return;
    }

    final from = _pipCentre(dial, heroAt, sweep, target);
    final centre = Offset.lerp(from, dial.centre, ease)!;
    final r = ui.lerpDouble(
      dial.radius * ChronometerConfig.pipFraction,
      dial.radius * ChronometerConfig.winnerFraction,
      ease,
    )!;
    final color = _colorIn(heroRow);

    // A halo that keeps breathing once it has arrived, so the disc is never a
    // static sticker.
    final settle = t >= 1
        ? 0.5 + 0.5 * math.sin(frame.timeMs / 780 * 2 * math.pi)
        : 0.0;
    _fill
      ..shader = null
      ..color = color.withValues(alpha: 0.18 + 0.10 * settle);
    canvas.drawCircle(centre, r * (1.16 + 0.06 * settle), _fill);

    _blob(canvas, centre, r, color, frame.onePixel);

    if (t <= 0.55) return;

    // Written in the colour's own ink, so it is legible on yellow as well as
    // on purple.
    final ink = PlayerPalette.byId(heroRow.split(':')[1])?.onColor ?? _pit;
    final fade = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
    final guess = heroRow.split(':')[2];
    final mineIsHero = heroRow == me;

    // Four lines stacked inside one disc, so the spacing is set from each
    // line's own height rather than by eye: the time is nearly three times the
    // size of the labels, and gaps guessed as fractions of the radius had the
    // caption sitting on the digits' baseline.
    _paintText(
      canvas,
      iWon ? 'YOU WIN' : (mineIsHero ? 'YOU' : 'WINNER'),
      centre - Offset(0, r * 0.56),
      size: r * 0.145,
      color: ink.withValues(alpha: 0.85 * fade),
      weight: FontWeight.w900,
      letterSpacing: r * 0.05,
    );
    _paintText(
      canvas,
      '${guess}s',
      centre - Offset(0, r * 0.16),
      size: r * 0.36,
      color: ink.withValues(alpha: fade),
      weight: FontWeight.w900,
    );
    _paintText(
      canvas,
      _winnerCaption(heroRow, target),
      centre + Offset(0, r * 0.26),
      size: r * 0.125,
      color: ink.withValues(alpha: 0.72 * fade),
      weight: FontWeight.w800,
      letterSpacing: r * 0.025,
    );

    // Where that put you, in words, inside the disc: '2ND OF 4'.
    final place = rows.indexOf(heroRow) + 1;
    _paintText(
      canvas,
      '${_ordinal(place)} OF ${rows.length}',
      centre + Offset(0, r * 0.52),
      size: r * 0.105,
      color: ink.withValues(alpha: 0.55 * fade),
      weight: FontWeight.w800,
      letterSpacing: r * 0.03,
    );

    if (!iWon && mineIsHero) {
      _drawWinnerBubble(canvas, frame, dial, winner, target, fade);
    }
  }

  /// The winner, small, off to the side — for the phones that did not win.
  ///
  /// Deliberately a fraction of the size of your own disc and pushed out of the
  /// middle. You still need to know who took it and by how much, but on your
  /// phone that is a footnote to your own result rather than the headline.
  void _drawWinnerBubble(
    Canvas canvas,
    Frame frame,
    ({Offset centre, double radius}) dial,
    String winner,
    double target,
    double fade,
  ) {
    final guess = winner.split(':')[2];
    if (guess.isEmpty) return;

    final color = _colorIn(winner);
    final r = dial.radius * ChronometerConfig.sideBubbleFraction;

    // Up and to the right of the big disc, clear of it and of the strip along
    // the bottom.
    final centre = dial.centre +
        Offset(
          dial.radius * 0.92,
          -dial.radius * ChronometerConfig.winnerFraction * 1.12,
        );

    _fill
      ..shader = null
      ..color = color.withValues(alpha: 0.16 * fade);
    canvas.drawCircle(centre, r * 1.3, _fill);

    _blob(canvas, centre, r, color.withValues(alpha: fade), frame.onePixel);

    final ink = PlayerPalette.byId(winner.split(':')[1])?.onColor ?? _pit;
    _paintText(
      canvas,
      'WON',
      centre - Offset(0, r * 0.36),
      size: r * 0.24,
      color: ink.withValues(alpha: 0.8 * fade),
      weight: FontWeight.w900,
      letterSpacing: r * 0.06,
    );
    _paintText(
      canvas,
      '${guess}s',
      centre + Offset(0, r * 0.16),
      size: r * 0.36,
      color: ink.withValues(alpha: fade),
      weight: FontWeight.w900,
    );
  }

  /// For a phone that never pressed: say so, rather than leaving it blank.
  void _drawNoPress(
    Canvas canvas,
    Frame frame,
    ({Offset centre, double radius}) dial,
    List<Object?> rows,
    double target,
  ) {
    _paintText(
      canvas,
      'YOU NEVER PRESSED',
      dial.centre,
      size: dial.radius * 0.19,
      color: _chalk.withValues(alpha: 0.85),
      weight: FontWeight.w900,
      letterSpacing: dial.radius * 0.03,
    );

    final winner = rows.first as String;
    final guess = winner.split(':')[2];
    if (guess.isEmpty) return;

    _paintText(
      canvas,
      'WINNER  ${guess}s',
      dial.centre + Offset(0, dial.radius * 0.42),
      size: dial.radius * 0.15,
      color: _colorIn(winner),
      weight: FontWeight.w900,
      letterSpacing: dial.radius * 0.03,
    );
  }

  static String _ordinal(int n) => switch (n) {
        1 => '1ST',
        2 => '2ND',
        3 => '3RD',
        _ => '${n}TH',
      };

  /// What to write under the winner's time: how they did, not who they are.
  /// The colour of the disc already says who.
  static String _winnerCaption(String row, double target) {
    final parts = row.split(':');
    final error = double.tryParse(parts.length > 3 ? parts[3] : '') ?? 0;
    if (error <= ChronometerConfig.bullseyeSeconds) return 'BANG ON';
    final guess = double.tryParse(parts[2]) ?? target;
    return guess < target ? '${parts[3]}s EARLY' : '${parts[3]}s LATE';
  }

  /// The dial and the losing pips, dimming out as the winner takes the middle.
  void _drawFadingDial(
    Canvas canvas,
    Frame frame,
    ({Offset centre, double radius}) dial,
    List<Object?> rows,
    double sweep,
    double target,
    double alpha, {
    required String skip,
  }) {
    if (alpha <= 0.01) return;
    final px = frame.onePixel;

    _stroke
      ..color = _chalk.withValues(alpha: 0.30 * alpha)
      ..strokeWidth = px * 9;
    canvas.drawCircle(dial.centre, dial.radius, _stroke);

    // Everyone except whoever is in flight, who is drawn by the caller. Named
    // rather than assumed to be first: the hero is this phone's own pip now,
    // and which row that is differs on every screen.
    for (final entry in rows) {
      final row = entry as String;
      if (row == skip) continue;
      final at = _guessIn(row);
      if (at == null) continue;

      final centre = _pipCentre(dial, at, sweep, target);
      _fill
        ..shader = null
        ..color = _colorIn(row).withValues(alpha: alpha);
      canvas.drawCircle(
        centre,
        dial.radius * ChronometerConfig.pipFraction,
        _fill,
      );
    }
  }

  /// Overshoot and settle. The winner's disc arrives a touch too big and eases
  /// back, which is what stops it feeling like a slide transition.
  static double _easeOutBack(double t) {
    const c = 1.34;
    final x = t - 1;
    return 1 + x * x * ((c + 1) * x + c);
  }

  /// A ring washing out from the middle when this phone's own guess registers.
  ///
  /// Local, and deliberately so: everything the platform insists be driven by
  /// the shared clock is something two screens must agree about, and this is one
  /// phone's receipt to the person holding it. No other screen shows it at all.
  void _drawPressPulse(Canvas canvas, Frame frame, Color mine) {
    if (_pulseLeftMs <= 0) return;
    final t = 1 - _pulseLeftMs / ChronometerConfig.pressPulseMs;

    final dial = _dialOf(frame);
    _stroke
      ..color = _chalk.withValues(alpha: 0.55 * (1 - t) * (1 - t))
      ..strokeWidth = frame.onePixel * 6;
    canvas.drawCircle(dial.centre, dial.radius * (0.2 + 1.6 * t), _stroke);
  }

  // -------------------------------------------------------------- the parts

  /// A soft disc of colour with a dark bed under it, for the big numbers to
  /// sit on.
  void _disc(Canvas canvas, Offset centre, double r, Color color) {
    _fill
      ..shader = null
      ..color = _shadow;
    canvas.drawCircle(centre + Offset(0, r * 0.05), r * 1.02, _fill);

    _fill.shader = ui.Gradient.radial(
      centre - Offset(0, r * 0.35),
      r * 1.5,
      [
        Color.lerp(color, _chalk, 0.22)!.withValues(alpha: 0.55),
        color.withValues(alpha: 0.20),
      ],
    );
    canvas.drawCircle(centre, r, _fill);
    _fill.shader = null;
  }

  /// A solid pip: dark rim, colour body, and a highlight up top so it reads as
  /// a physical counter rather than a flat circle.
  void _blob(Canvas canvas, Offset centre, double r, Color color, double px) {
    _fill
      ..shader = null
      ..color = _shadow;
    canvas.drawCircle(centre + Offset(0, r * 0.10), r, _fill);

    _fill.color = color;
    canvas.drawCircle(centre, r, _fill);

    // The highlight, a slim crescent near the top.
    _fill.shader = ui.Gradient.radial(
      centre - Offset(0, r * 0.42),
      r * 1.1,
      [
        _chalk.withValues(alpha: 0.42),
        _chalk.withValues(alpha: 0),
      ],
    );
    canvas.drawCircle(centre, r, _fill);
    _fill.shader = null;

    // A dark rim, so two pips that land almost together stay two pips.
    _stroke
      ..color = _pit.withValues(alpha: 0.75)
      ..strokeWidth = math.max(px * 2, r * 0.07);
    canvas.drawCircle(centre, r, _stroke);
  }

  // ------------------------------------------------------------------ text

  /// Centred on [at], cached by everything that affects the glyphs.
  void _paintText(
    Canvas canvas,
    String value,
    Offset at, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
  }) {
    if (size <= 0) return;

    // The colour is part of the key and baked into the span.
    //
    // It was applied at paint time, through a `saveLayer`, so that one cached
    // painter could be reused at any tint — and that is what turned every
    // string on screen into a solid block: a layer composited with a plain
    // `Paint.color` fills the layer's bounds rather than tinting the glyphs
    // inside it. Alpha is quantised to sixteen steps so a fade still reuses
    // entries instead of laying out afresh on every frame, which is the only
    // reason the layer trick was worth attempting in the first place.
    final quantised = color.withValues(alpha: (color.a * 16).round() / 16);
    final key = '$value|${size.toStringAsFixed(2)}|$weight|$letterSpacing'
        '|${quantised.toARGB32()}';

    final painter = _text.putIfAbsent(
      key,
      () => _painterFor(value, size, weight, letterSpacing, quantised),
    );

    // Letter spacing is added *after* the last glyph too, so a tracked-out word
    // measures wider than it looks and centring on the raw width leaves it
    // sitting visibly to the left. Half the trailing gap comes back off.
    final offset = at -
        Offset((painter.width - letterSpacing) / 2, painter.height / 2);

    // A hard drop shadow, so bright text stays legible over a wash of any hue.
    // Its own cached painter rather than a layer, for the same reason.
    if (quantised.a > 0.5) {
      final shadow = _text.putIfAbsent(
        '$key|shadow',
        () => _painterFor(
          value,
          size,
          weight,
          letterSpacing,
          _shadow.withValues(alpha: _shadow.a * quantised.a),
        ),
      );
      shadow.paint(canvas, offset + Offset(0, size * 0.045));
    }

    painter.paint(canvas, offset);
  }

  /// Set only when rendering screenshots by hand, to name a font the test
  /// engine has actually been given.
  ///
  /// Null in the app, where the platform font is the right one. It exists
  /// because the test engine ships **no fonts at all**: text painted under
  /// `flutter test` comes out as `.notdef` boxes, which looks exactly like a
  /// paint bug and is not one. Anyone eyeballing this view's output should load
  /// a real font with `FontLoader` and point this at it before believing that
  /// the words are broken.
  static String? debugFontFamily;

  static TextPainter _painterFor(
    String value,
    double size,
    FontWeight weight,
    double letterSpacing,
    Color color,
  ) =>
      TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: debugFontFamily,
            color: color,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: letterSpacing,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  // ------------------------------------------------------------------- hud

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final phase = frame.sharedState['phase'] as String?;

    // Your own result is the disc on the canvas. The full field goes
    // underneath, in finishing order, so the round can be settled without
    // anybody walking round the table to look at somebody else's phone.
    if (phase == ChronoPhase.results) return _ResultsBoard(frame: frame);

    // Nothing that ticks while the clock runs. The canvas already says whether
    // this phone has committed.
    return null;
  }

  @override
  void dispose() {
    for (final p in _text.values) {
      p.dispose();
    }
    _text.clear();
  }
}

/// The whole field, in finishing order, under your own disc.
///
/// Everybody now, winner included — the middle of the screen belongs to the
/// person holding the phone, so this is the only place the full result exists.
/// Ordered rather than merely listed: a table settles the round off one screen
/// instead of four people comparing phones.
class _ResultsBoard extends StatelessWidget {
  const _ResultsBoard({required this.frame});

  final HudFrame frame;

  @override
  Widget build(BuildContext context) {
    final rows = frame.sharedState['results'];
    if (rows is! List || rows.isEmpty) return const SizedBox.shrink();

    final target = (frame.sharedState['target'] as num?)?.toDouble() ?? 0;
    final label = target == target.roundToDouble()
        ? '${target.round()}'
        : target.toStringAsFixed(1);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18, left: 12, right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TARGET  ${label}s',
              style: const TextStyle(
                color: Color(0x99FFF8E7),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < rows.length; i++)
                  _Chip(
                    encoded: rows[i] as String,
                    me: frame.phoneId,
                    place: i + 1,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One also-ran: their colour, their time, and how far off they were.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.encoded,
    required this.me,
    required this.place,
  });

  final String encoded;
  final String me;

  /// Finishing position, 1-based. Shown because the strip now carries the
  /// winner as well, and a list where first place looks like fourth is a list
  /// somebody has to work out.
  final int place;

  @override
  Widget build(BuildContext context) {
    final parts = encoded.split(':');
    if (parts.length < 4) return const SizedBox.shrink();

    final color = PlayerPalette.byId(parts[1])?.value ?? const Color(0xFFFFF8E7);
    final guess = parts[2];
    final mine = parts[0] == me;
    final won = place == 1;

    // A phone that never pressed says so, rather than showing a blank where a
    // number should be.
    final text = guess.isEmpty ? 'no press' : '${guess}s';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        // Your own chip is filled, not merely outlined: on a strip of four it
        // is the one a player finds first, and a slightly thicker border was
        // not enough to make it findable at a glance.
        color: mine ? color.withValues(alpha: 0.22) : const Color(0x33000000),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: mine ? color : color.withValues(alpha: 0.45),
          width: mine ? 2.0 : 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (won)
            const Padding(
              padding: EdgeInsets.only(right: 5),
              child: Text('★',
                  style: TextStyle(color: Color(0xFFFFF8E7), fontSize: 12)),
            ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFFFF8E7),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (guess.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              '+${parts[3]}',
              style: const TextStyle(
                color: Color(0x99FFF8E7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (mine) ...[
            const SizedBox(width: 6),
            const Text(
              'YOU',
              style: TextStyle(
                color: Color(0xCCFFF8E7),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
