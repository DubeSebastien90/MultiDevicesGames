import '../../sdk/audio/sounds.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/score/scoreboard.dart';
import 'flood_board.dart';
import 'flood_config.dart';

class FloodPhase {
  static const countdown = 'countdown';
  static const live = 'live';
  static const over = 'over';
}

class FloodState {
  static const phase = 'phase';

  static const boundary = 'boundary';

  static const countdown = 'countdown';

  static const rangeScale = 'range';

  static const power = 'power';

  static const teams = 'teams';

  static const seamY = 'seamY';

  static const bluePulse = 'bluePulse';
  static const redPulse = 'redPulse';
}

abstract class FloodSim extends GameSim {
  FloodSim(this.context, this.teams) : seamY = FloodBoard.seamOf(context);

  final BoardContext context;

  final Map<String, String> teams;

  final double seamY;

  double boundary = 0;

  double _elapsed = -FloodConfig.preRoundSeconds;

  final Map<String, double> _lastTapAt = {};

  double _bluePulse = 0;
  double _redPulse = 0;

  int _boupIndex = 0;

  GameOutcome? _outcome;

  double get elapsed => _elapsed;

  double get roundElapsed => _elapsed < 0 ? 0 : _elapsed;

  bool get isLive =>
      _elapsed >= 0 &&
      _outcome == null &&
      _elapsed < FloodConfig.maxRoundLength;

  String get phase {
    if (_outcome != null) return FloodPhase.over;
    return _elapsed < 0 ? FloodPhase.countdown : FloodPhase.live;
  }

  double pushFor(double atElapsed);

  double get effectiveBoundary;

  Map<String, Object?> get extraState => const {};

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (!isLive) return;

    final team = teams[touch.phoneId];
    if (team == null) return;

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

    boundary = boundary.clamp(-1.0, 1.0);

    _playBoup(touch.phoneId);

    _checkWin();
  }

  void _playBoup(String phoneId) {
    final player = context.roster.byPhone(phoneId);
    if (player == null) return;
    final cues = Sounds.buttonPress;
    context.audio.playOnPhone(player, cues[_boupIndex % cues.length]);
    _boupIndex++;
  }

  @override
  void step(double dt) {
    if (_outcome != null) return;

    _elapsed += dt;

    _bluePulse = _decay(_bluePulse, dt);
    _redPulse = _decay(_redPulse, dt);

    if (_elapsed < 0) return;

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

  void _resolveByLead() {
    final b = effectiveBoundary;
    if (b == 0) {
      context.scores.awardPlacements([teams.keys.toSet()]);
      _outcome = const GameOutcome.draw(summary: 'time — dead level');
      return;
    }
    final winner = b < 0 ? FloodConfig.blue : FloodConfig.red;
    _finish(winner, 'time — $winner was ahead');
  }

  void _finish(String team, String summary) {
    if (_outcome != null) return;

    final winners = <String>{};
    for (final entry in teams.entries) {
      if (entry.value != team) continue;
      context.scores.award(entry.key, Scoreboard.pointsPerGame);
      winners.add(entry.key);
    }

    _outcome = GameOutcome.contest(winners: winners, summary: summary);
  }

  @override
  Iterable<Entity> get entities => const [];

  @override
  Map<String, Object?> get sharedState => {
    FloodState.phase: phase,
    FloodState.boundary: _round(effectiveBoundary, 1000),
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
