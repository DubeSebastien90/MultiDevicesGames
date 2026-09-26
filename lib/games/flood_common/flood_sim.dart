import '../../sdk/audio/sounds.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/score/scoreboard.dart';
import 'flood_board.dart';
import 'flood_config.dart';

/// Phase names, shared with the views through `sharedState`.
class FloodPhase {
  static const countdown = 'countdown';
  static const live = 'live';
  static const over = 'over';
}

/// Keys in `sharedState`. Both views read these, so they are named once.
class FloodState {
  static const phase = 'phase';

  /// What to draw and what wins: already in [-1, +1], already clamped.
  static const boundary = 'boundary';

  /// Whole seconds still to wait, counting down to 0. What the view prints.
  ///
  /// Null for the opening [FloodConfig.briefingSeconds], while the briefing
  /// has the screen to itself — distinct from 0, which is the instant the wait
  /// ends. There is no number to show yet, rather than a number that is zero.
  ///
  /// Deliberately an int rather than the sim's raw elapsed float: this map is
  /// diffed and broadcast on change, and a float that moves every tick would
  /// make "on change" mean "always".
  static const countdown = 'countdown';

  /// Option B only: how wide the contested field still is, 0..1.
  static const rangeScale = 'range';

  /// Option A only: tap strength as a multiple of the base push.
  static const power = 'power';

  /// phoneId -> 'blue' | 'red', so every phone knows whose side it is on.
  static const teams = 'teams';

  /// Where the two rows meet, in world units — the line boundary 0 sits on.
  /// Not the board's centre when the rows differ in depth.
  static const seamY = 'seamY';

  /// Rises on a tap and decays, per team — the view's tap feedback.
  static const bluePulse = 'bluePulse';
  static const redPulse = 'redPulse';
}

/// What both Flood variants have in common, which is everything except how a
/// tap becomes a boundary.
///
/// The tug-of-war itself, the countdown, the teams, the win check and the
/// backstop are identical between the two READMEs; the variants differ in
/// exactly one place each. Option A scales the push by elapsed time
/// ([pushFor]); Option B leaves the push flat and shrinks the field the
/// boundary is measured against ([effectiveBoundary]). Everything else here is
/// shared so that playtesting one cannot accidentally change the other.
///
/// No physics: a tug-of-war on one float needs none, so this extends [GameSim]
/// directly rather than `Forge2DGameSim` — the contract explicitly allows it,
/// and it keeps a physics engine out of a game that is one addition per tap.
abstract class FloodSim extends GameSim {
  FloodSim(this.context, this.teams) : seamY = FloodBoard.seamOf(context);

  final BoardContext context;

  /// phoneId -> team. Fixed for the round.
  final Map<String, String> teams;

  /// Where the two rows meet — the world line boundary 0 sits on. Sent to
  /// every phone so a view never has to guess it from the board's centre,
  /// which is a different line whenever the rows differ in depth.
  final double seamY;

  /// The raw tug-of-war position, in [-1, +1]. What a tap moves.
  ///
  /// Option A moves it by a growing amount; option B always by [basePush] and
  /// then reads it through a shrinking window. Either way this is the one piece
  /// of authoritative state the whole game turns on.
  double boundary = 0;

  /// Seconds since the pre-round ended. Negative until then, so a single
  /// number carries both phases and the ramp maths never sees the wait as
  /// round time.
  double _elapsed = -FloodConfig.preRoundSeconds;

  /// Last tap per phone, for the rate limit. Round time, not wall clock.
  final Map<String, double> _lastTapAt = {};

  double _bluePulse = 0;
  double _redPulse = 0;

  /// Which boup plays next. Walks [Sounds.buttonPress] in turn rather than at
  /// random, so a run of taps still changes pitch and the sim stays
  /// deterministic.
  int _boupIndex = 0;

  GameOutcome? _outcome;

  double get elapsed => _elapsed;

  /// Round time, floored at zero — what a ramp or a shrink should be measured
  /// against, since neither should start running during the countdown.
  double get roundElapsed => _elapsed < 0 ? 0 : _elapsed;

  bool get isLive =>
      _elapsed >= 0 &&
      _outcome == null &&
      _elapsed < FloodConfig.maxRoundLength;

  String get phase {
    if (_outcome != null) return FloodPhase.over;
    return _elapsed < 0 ? FloodPhase.countdown : FloodPhase.live;
  }

  // ------------------------------------------------------- what each owns

  /// How far one tap moves [boundary], for a tap landing at [atElapsed]
  /// seconds into the round. Option A ramps this; option B does not.
  double pushFor(double atElapsed);

  /// [boundary] as it should be drawn and judged, in [-1, +1].
  ///
  /// Option A renders the raw value; option B divides it by a shrinking range,
  /// so the same raw lead reads as a larger and larger swing.
  double get effectiveBoundary;

  /// Anything a variant wants on top of the shared keys.
  Map<String, Object?> get extraState => const {};

  // --------------------------------------------------------------- input

  /// Every touch-down on any phone is one tap for that phone's team.
  ///
  /// Deliberately position-blind: the whole screen is the button, because
  /// asking someone mashing at ten taps a second to also aim is a worse game.
  /// Moves and ups are ignored, so a dragged finger is one tap, not a stream.
  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (!isLive) return;

    final team = teams[touch.phoneId];
    if (team == null) return;

    // Rate limit per phone, on round time so it stays deterministic.
    final last = _lastTapAt[touch.phoneId];
    if (last != null && _elapsed - last < FloodConfig.minTapIntervalSeconds) {
      return;
    }
    _lastTapAt[touch.phoneId] = _elapsed;

    final push = pushFor(_elapsed);
    if (team == FloodConfig.blue) {
      boundary -= push;
      _bluePulse = 1;
    } else {
      boundary += push;
      _redPulse = 1;
    }

    // Clamp the raw value too. Option B reads it through a window that can
    // magnify it, and an unbounded raw boundary would let a team bank an
    // invisible lead far past the win line while the field was still wide.
    boundary = boundary.clamp(-1.0, 1.0);

    _playBoup(touch.phoneId);

    _checkWin();
  }

  /// The tap, heard on the phone that made it — and only there, so each
  /// player hears their own taps land.
  void _playBoup(String phoneId) {
    final player = context.roster.byPhone(phoneId);
    if (player == null) return;
    final cues = Sounds.buttonPress;
    context.audio.playOnPhone(player, cues[_boupIndex % cues.length]);
    _boupIndex++;
  }

  // ---------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (_outcome != null) return;

    _elapsed += dt;

    // Tap feedback decays on the shared timeline, so every phone sees the same
    // flash at the same instant.
    _bluePulse = _decay(_bluePulse, dt);
    _redPulse = _decay(_redPulse, dt);

    if (_elapsed < 0) return;

    // The field moved under the boundary even though nobody tapped — option B
    // wins rounds this way, so the check belongs here as well as on a tap.
    _checkWin();
    if (_outcome != null) return;

    if (_elapsed >= FloodConfig.maxRoundLength) _resolveByLead();
  }

  static double _decay(double pulse, double dt) {
    final next = pulse - dt * 4;
    return next < 0 ? 0 : next;
  }

  void _checkWin() {
    final b = effectiveBoundary;
    if (b <= -FloodConfig.winAt) {
      _finish(FloodConfig.blue, 'blue flooded the board');
    } else if (b >= FloodConfig.winAt) {
      _finish(FloodConfig.red, 'red flooded the board');
    }
  }

  /// The backstop. Whoever is even marginally ahead takes it; dead level is a
  /// draw, which is rarer than it sounds but has to mean something.
  void _resolveByLead() {
    final b = effectiveBoundary;
    if (b == 0) {
      // Nobody won, said out loud rather than by everyone being congratulated.
      // Everyone shares every place, which is half the prize each.
      context.scores.awardPlacements([teams.keys.toSet()]);
      _outcome = const GameOutcome.draw(summary: 'time — dead level');
      return;
    }
    final winner = b < 0 ? FloodConfig.blue : FloodConfig.red;
    _finish(winner, 'time — $winner was ahead');
  }

  void _finish(String team, String summary) {
    if (_outcome != null) return;
    // Every winner takes first place's points and every loser last's, which
    // pays the table the same total as a ranked game of the same size. Score
    // belongs to the lobby and follows these players into the next minigame.
    final winners = <String>{};
    for (final entry in teams.entries) {
      if (entry.value != team) continue;
      context.scores.award(entry.key, Scoreboard.pointsPerGame);
      winners.add(entry.key);
    }
    // Named, so the losing side is told it lost rather than congratulated
    // alongside the winners.
    _outcome = GameOutcome.contest(winners: winners, summary: summary);
  }

  // ----------------------------------------------------------- snapshots

  /// Nothing moves that the platform could interpolate: the whole world is one
  /// float, it changes in steps rather than smoothly, and it belongs in
  /// `sharedState` where it is sent only when it changes.
  @override
  Iterable<Entity> get entities => const [];

  /// Quantised on purpose, because the platform diffs this map every tick and
  /// only sends it when something changed.
  ///
  /// A raw `_elapsed` moves by a hair sixty times a second, so every value here
  /// would differ from the last and Flood would broadcast a `shared` message on
  /// every single tick — turning a change-driven channel into a 60 Hz stream
  /// for a game whose state is one float. Rounding to what a screen can
  /// actually show fixes that: an idle board sends nothing at all.
  ///
  /// The precision kept is the precision that matters. The boundary is rounded
  /// to a thousandth of the axis — finer than a pixel on any phone — and the
  /// countdown to the whole second the HUD prints.
  @override
  Map<String, Object?> get sharedState => {
    FloodState.phase: phase,
    FloodState.boundary: _round(effectiveBoundary, 1000),
    // Nothing at all while the briefing is being read, then whole seconds.
    FloodState.countdown: _elapsed < -FloodConfig.countdownSeconds
        ? null
        : (_elapsed < 0 ? (-_elapsed).ceil() : 0),
    FloodState.teams: teams,
    FloodState.seamY: seamY,
    FloodState.bluePulse: _round(_bluePulse, 20),
    FloodState.redPulse: _round(_redPulse, 20),
    ...extraState,
  };

  static double _round(double value, int steps) =>
      (value * steps).roundToDouble() / steps;

  @override
  GameOutcome? get outcome => _outcome;

  @override
  void reset() {
    boundary = 0;
    _elapsed = -FloodConfig.preRoundSeconds;
    _lastTapAt.clear();
    _bluePulse = 0;
    _redPulse = 0;
    _boupIndex = 0;
    _outcome = null;
  }
}
