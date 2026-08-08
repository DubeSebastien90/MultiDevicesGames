import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'reaction_config.dart';

/// One screen lights up at a time. Tap yours the instant it does.
///
/// **No entities and no seam.** Nothing crosses the gap between phones and
/// nothing moves, so this game draws entirely from [sharedState]; the platform
/// is here for the single authoritative clock and the single chooser, which is
/// what makes "everyone got the same number of turns" a promise one machine can
/// keep.
///
/// Reaction is measured on the host, from the tick that lit a screen to the
/// tick its touch arrived, so it includes the trip back over the network. On a
/// LAN that is a couple of milliseconds against human reactions of two to three
/// hundred, and the alternative — trusting each phone's own clock — is both
/// harder and forgeable.
class ReactionSim implements GameSim {
  ReactionSim(this.context, {math.Random? random})
      : _random = random ?? math.Random() {
    _scheduleNext(from: 0);
  }

  final BoardContext context;
  final math.Random _random;

  double _elapsed = 0;

  /// Whose screen is lit, and when it lit. Null between prompts.
  String? _lit;
  double _litAt = 0;

  /// Where on that screen the dot sits, in world units.
  double _dotX = 0;
  double _dotY = 0;

  /// Mistakes per phone, only ever going up.
  final _faults = <String, int>{};

  /// The last fumble: who, and which one it was.
  ///
  /// Two scalars rather than the map above, because the host diffs shared state
  /// value by value with `==` — and two Maps are never equal in Dart, however
  /// identical their contents. Publishing the map meant a packet sixty times a
  /// second for a game in which nothing moves at all.
  ///
  /// A running number rather than a flag: two fumbles in quick succession are
  /// two pieces of feedback, and a flag that was already raised would swallow
  /// the second.
  int _faultSeq = 0;
  String? _faultBy;

  /// When the next screen lights.
  double _nextPromptAt = 0;

  /// Total time and number of answers, per phone. Kept as a running total
  /// rather than a list: the average is all anybody sees.
  final _total = <String, double>{};
  final _count = <String, int>{};

  /// Prompts actually answered, as opposed to missed or jumped. A phone that
  /// never managed one is not in the running: misses and false starts are
  /// recorded at the same fixed length, so a table where nobody played would
  /// otherwise be a table where everybody tied for first.
  final _answers = <String, int>{};

  /// Turns still owed in this pass. Refilled and reshuffled when it empties, so
  /// nobody is lit twice while somebody else waits — with averages at stake,
  /// an uneven number of turns is an uneven game.
  final _bag = <String>[];

  bool _awarded = false;
  GameOutcome? _outcome;

  bool get _over => _elapsed >= ReactionConfig.roundSeconds;

  /// Seconds remaining, whole. Deliberately not the raw float: `sharedState` is
  /// diffed every tick and a value that always differs is a packet every tick.
  int get secondsLeft =>
      (ReactionConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  /// This phone's average answer in milliseconds, or null if it never answered.
  double? averageMsOf(String phoneId) {
    final n = _count[phoneId] ?? 0;
    if (n == 0) return null;
    return _total[phoneId]! / n * 1000;
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_over) return;
    _elapsed += dt;

    // Awarded on the very tick the round ends, not the one after it. The
    // platform stops stepping as soon as `outcome` goes non-null, so anything
    // left for "next time" never happens — and awarding from the getter is
    // worse, since that is polled repeatedly and would pay out every poll.
    if (_over) {
      _lit = null;
      _awardOnce();
      return;
    }

    final lit = _lit;
    if (lit == null) {
      if (_elapsed >= _nextPromptAt) _light();
      return;
    }

    // Given up on. Counts as the worst answer rather than as nothing, or
    // putting the phone down would be a way to protect an average.
    if (_elapsed - _litAt >= ReactionConfig.maxWaitSeconds) {
      _record(lit, ReactionConfig.maxWaitSeconds);
      _lit = null;
      _scheduleNext(from: _elapsed);
    }
  }

  void _light() {
    if (_bag.isEmpty) {
      _bag.addAll(context.phoneIds);
      _bag.shuffle(_random);
    }
    _lit = _bag.removeLast();
    _litAt = _elapsed;
    _placeDot(_lit!);
  }

  /// Somewhere on that phone's own screen, never half off the edge.
  ///
  /// Chosen in the screen's own frame and then turned into the world, because a
  /// phone in a ring sits at whatever angle its place on the rim demands — a
  /// point picked in world coordinates would drift outside a turned panel.
  void _placeDot(String phoneId) {
    final screen = context.slices
        .firstWhere((s) => s.phoneId == phoneId)
        .screen;

    final inset = ReactionConfig.dotRadiusWorld * 1.2;
    final halfU = math.max(0.0, screen.width / 2 - inset);
    final halfV = math.max(0.0, screen.height / 2 - inset);
    final u = (_random.nextDouble() * 2 - 1) * halfU;
    final v = (_random.nextDouble() * 2 - 1) * halfV;

    final cos = math.cos(screen.turnRadians);
    final sin = math.sin(screen.turnRadians);
    _dotX = screen.centerX + u * cos - v * sin;
    _dotY = screen.centerY + u * sin + v * cos;
  }

  bool _isOnDot(double x, double y) {
    final dx = x - _dotX;
    final dy = y - _dotY;
    final reach = ReactionConfig.dotRadiusWorld * ReactionConfig.hitTolerance;
    return dx * dx + dy * dy <= reach * reach;
  }

  void _fault(String phoneId) {
    _faults[phoneId] = (_faults[phoneId] ?? 0) + 1;
    _faultSeq++;
    _faultBy = phoneId;
    _record(phoneId, ReactionConfig.falseStartSeconds);
  }

  /// How many mistakes [phoneId] has made this round.
  int faultsOf(String phoneId) => _faults[phoneId] ?? 0;

  void _scheduleNext({required double from}) {
    final spread = ReactionConfig.maxDarkSeconds - ReactionConfig.minDarkSeconds;
    _nextPromptAt = from +
        ReactionConfig.settleSeconds +
        ReactionConfig.minDarkSeconds +
        _random.nextDouble() * spread;
  }

  void _record(String phoneId, double seconds) {
    _total[phoneId] = (_total[phoneId] ?? 0) + seconds;
    _count[phoneId] = (_count[phoneId] ?? 0) + 1;
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down || _over) return;

    if (touch.phoneId == _lit) {
      if (_isOnDot(touch.worldX, touch.worldY)) {
        _answers[touch.phoneId] = (_answers[touch.phoneId] ?? 0) + 1;
        _record(touch.phoneId, _elapsed - _litAt);
      } else {
        // Landed on the black. The turn is spent either way, or hammering the
        // screen would beat looking at it.
        _fault(touch.phoneId);
      }
      _lit = null;
      _scheduleNext(from: _elapsed);
      return;
    }

    // A tap on a black screen — either before your own turn or during somebody
    // else's. Charged as the slowest possible answer, which is what stops
    // hammering the glass from being the best strategy.
    _fault(touch.phoneId);
  }

  // ------------------------------------------------------------- snapshots

  /// Nothing to draw but a colour, so there is nothing to interpolate.
  @override
  Iterable<Entity> get entities => const [];

  @override
  Map<String, Object?> get sharedState => {
    'lit': _lit,
    // The colour is resolved here rather than on each phone: the view is handed
    // a `phoneId` and nothing else, and which colour belongs to whom is the one
    // thing every player must never get wrong.
    'litColor': _lit == null ? null : context.colorOf(_lit!)?.id,
    'dotX': _lit == null ? null : double.parse(_dotX.toStringAsFixed(2)),
    'dotY': _lit == null ? null : double.parse(_dotY.toStringAsFixed(2)),
    'dotR': ReactionConfig.dotRadiusWorld,
    // Only ever change when somebody gets it wrong, so a clean round costs
    // nothing.
    'faultSeq': _faultSeq,
    'faultBy': _faultBy,
    'secondsLeft': secondsLeft,
    'over': _over,
  };

  // --------------------------------------------------------------- outcome

  /// Points for the fastest average, sliding to zero for the slowest.
  ///
  /// By position rather than by margin, so one outlier cannot flatten everyone
  /// else's score, and phones sharing an average share a position — losing a
  /// tie-break you did not lose would be worse than the tie.
  void _awardOnce() {
    if (_awarded) return;
    _awarded = true;

    // Only phones that answered something. The rest score nothing, which is
    // already where the curve would have put them.
    final ranked = _rankedByAverage()
        .where((e) => (_answers[e.id] ?? 0) > 0)
        .toList();
    if (ranked.isEmpty) return;
    if (ranked.length == 1) {
      context.scores.award(ranked.first.id, ReactionConfig.bestScore);
      return;
    }

    final last = ranked.length - 1;
    for (var i = 0; i < ranked.length; i++) {
      // Everybody tied at this value shares the best position among them.
      final position = ranked.indexWhere((e) => e.ms == ranked[i].ms);
      final points =
          (ReactionConfig.bestScore * (last - position) / last).round();
      if (points != 0) context.scores.award(ranked[i].id, points);
    }
  }

  /// Fastest first. A phone that never answered sorts last, at infinity.
  ///
  /// Rounded to whole milliseconds — the same number the player is shown —
  /// because that is what makes a tie a tie. Comparing raw averages for
  /// equality would mean two people who both read "312 ms" are separated by a
  /// difference neither of them can see, on the last bits of a double.
  List<({String id, double ms})> _rankedByAverage() => [
        for (final id in context.phoneIds)
          (id: id, ms: averageMsOf(id)?.roundToDouble() ?? double.infinity),
      ]..sort((a, b) => a.ms.compareTo(b.ms));

  @override
  GameOutcome? get outcome {
    if (!_over) return null;

    // Nobody is out and nobody is chasing anybody, so this is not a win or a
    // loss — it is what your own hands managed. Built once: `outcome` is polled
    // several times a tick and this one carries a line per phone.
    return _outcome ??= GameOutcome.perPhone(
      {for (final id in context.phoneIds) id: _lineFor(id)},
      summary: _fastestLine(),
    );
  }

  String _lineFor(String phoneId) {
    final ms = averageMsOf(phoneId);
    if (ms == null) return 'You never tapped';
    return 'You averaged ${ms.round()} ms';
  }

  String _fastestLine() {
    final ranked = _rankedByAverage();
    if (ranked.isEmpty || !ranked.first.ms.isFinite) return 'nobody tapped';
    if (ranked.length > 1 && ranked[0].ms == ranked[1].ms) {
      return 'a dead heat at ${ranked.first.ms.round()} ms';
    }
    final label =
        context.scores.view.entryFor(ranked.first.id)?.label ?? ranked.first.id;
    return '$label was fastest, ${ranked.first.ms.round()} ms';
  }

  // ----------------------------------------------------------------- reset

  @override
  void reset() {
    _elapsed = 0;
    _lit = null;
    _litAt = 0;
    _total.clear();
    _count.clear();
    _answers.clear();
    _faults.clear();
    _faultSeq = 0;
    _faultBy = null;
    _bag.clear();
    _awarded = false;
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
    _scheduleNext(from: 0);
  }

  @override
  void dispose() {}
}
