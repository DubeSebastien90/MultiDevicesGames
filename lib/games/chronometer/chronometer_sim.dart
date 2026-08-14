import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'chronometer_config.dart';

/// The phases of a round, in the order they happen.
///
/// Named on the wire rather than numbered: the view switches on this every
/// frame and a string that says `reveal` survives being read in a packet dump,
/// where a `2` does not.
class ChronoPhase {
  static const reveal = 'reveal';
  static const countdown = 'countdown';
  static const running = 'running';
  static const results = 'results';
}

/// Hold the number in your head, then press when you think it has elapsed.
///
/// **No entities and no seam.** Nothing crosses the gap between phones; every
/// screen draws the same dial from [sharedState]. What the platform is here for
/// is the one thing this game cannot do without and no phone can provide for
/// itself: a *single clock*. Every guess is measured on the host, from the tick
/// the round started to the tick the touch arrived, so two players pressing at
/// the same real instant get the same number whatever their phones think the
/// time is.
///
/// That the network trip is inside the measurement is deliberate and, here,
/// nearly free: a LAN hop is a couple of milliseconds against guesses that miss
/// by hundreds. The alternative — each phone timestamping its own press — trades
/// a two-millisecond bias for two unsynchronised clocks and a wide-open door for
/// anybody who fancies editing their own guess.
class ChronometerSim implements GameSim {
  ChronometerSim(this.context, {math.Random? random})
      : _random = random ?? math.Random() {
    _target = _drawTarget();
  }

  final BoardContext context;
  final math.Random _random;

  /// The number everyone was shown, in seconds.
  late double _target;

  /// Time inside the current phase, and the phase itself.
  String _phase = ChronoPhase.reveal;
  double _phaseElapsed = 0;

  /// Seconds since the clock started. Only meaningful once running; this is
  /// what a guess is measured against.
  double _clock = 0;

  /// Each phone's guess, in seconds from the start of the clock. A phone that
  /// has not pressed is absent — distinct from one that pressed at zero.
  final _guesses = <String, double>{};

  /// The order guesses landed in, so a pip can be drawn per press without
  /// shipping a Map that would never compare equal twice.
  ///
  /// The host diffs shared state value by value with `==`, and two Dart Maps
  /// are never equal however identical their contents. Publishing `_guesses`
  /// directly meant a packet every tick for a game in which nothing moves. A
  /// flat list of encoded strings does compare equal, so a quiet round is
  /// genuinely quiet.
  final _landed = <String>[];

  bool _awarded = false;
  GameOutcome? _outcome;

  // ------------------------------------------------------------------ phases

  double get _phaseLength => switch (_phase) {
        ChronoPhase.reveal => ChronometerConfig.revealSeconds,
        ChronoPhase.countdown => ChronometerConfig.countdownSeconds,
        // The clock runs for the target plus however long the stragglers get.
        ChronoPhase.running => _target + ChronometerConfig.graceSeconds,
        _ => ChronometerConfig.resultsSeconds,
      };

  /// The target, for the view and for tests.
  double get targetSeconds => _target;

  /// What [phoneId] guessed, or null if they never pressed.
  double? guessOf(String phoneId) => _guesses[phoneId];

  /// How far off [phoneId] was, in seconds. A phone that never pressed is
  /// scored at the full grace window rather than left out.
  double errorOf(String phoneId) {
    final guess = _guesses[phoneId];
    if (guess == null) return ChronometerConfig.noGuessErrorSeconds;
    return (guess - _target).abs();
  }

  bool get _everyoneIn => _guesses.length >= context.phoneIds.length;

  double _drawTarget() {
    const span = ChronometerConfig.maxTargetSeconds -
        ChronometerConfig.minTargetSeconds;
    return (ChronometerConfig.minTargetSeconds + _random.nextInt(span + 1))
        .toDouble();
  }

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (_phase == ChronoPhase.results && _phaseElapsed >= _phaseLength) return;

    _phaseElapsed += dt;
    if (_phase == ChronoPhase.running) _clock += dt;

    if (_phaseElapsed < _phaseLength) return;

    switch (_phase) {
      case ChronoPhase.reveal:
        _enter(ChronoPhase.countdown);
      case ChronoPhase.countdown:
        _enter(ChronoPhase.running);
      case ChronoPhase.running:
        // The window closed with somebody still thinking about it. They are
        // scored as a miss, which is what [errorOf] already says.
        _enter(ChronoPhase.results);
        _awardOnce();
      default:
        break;
    }
  }

  void _enter(String phase) {
    _phase = phase;
    _phaseElapsed = 0;
    if (phase == ChronoPhase.running) _clock = 0;
  }

  // ------------------------------------------------------------------ input

  /// Anywhere on your own screen. There is nothing to aim at — the game is
  /// asking when, not where, and making it a target would measure something
  /// else.
  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (_phase != ChronoPhase.running) return;

    // One guess each. A second press is not a correction: the whole game is
    // committing to an instant, and letting anyone press twice would make the
    // right strategy a burst of taps around the target.
    if (_guesses.containsKey(touch.phoneId)) return;

    _guesses[touch.phoneId] = _clock;
    _landed.add(_encode(touch.phoneId, _clock));

    // Everybody has committed, so there is nothing left to wait for. The grace
    // window exists for people who have not pressed, not as a pause.
    if (_everyoneIn) {
      _enter(ChronoPhase.results);
      _awardOnce();
    }
  }

  /// `phoneId:colorId:seconds`, at two decimals.
  ///
  /// Flattened rather than nested so the whole list is a `List<String>` — which
  /// Dart's `==` compares element by element, and so goes quiet the moment
  /// nobody is pressing. The colour rides along because the view is handed a
  /// `phoneId` and nothing else, and which pip belongs to whom is the one thing
  /// no player should have to guess.
  String _encode(String phoneId, double at) {
    final color = context.colorOf(phoneId)?.id ?? '';
    return '$phoneId:$color:${at.toStringAsFixed(2)}';
  }

  // -------------------------------------------------------------- snapshots

  /// Nothing to draw but a dial and some marks, so there is nothing to
  /// interpolate.
  @override
  Iterable<Entity> get entities => const [];

  /// Who is wearing which colour, as `phoneId:colorId`, fixed for the round.
  ///
  /// Built once rather than per tick: the seating cannot change mid-round, and
  /// a fresh list every frame would be a fresh packet every frame. The view
  /// needs this from the very first frame — it paints each phone in its own
  /// player's colour — and `PhoneLayout` carries no colour, so asking here is
  /// the only way to know without guessing.
  late final List<String> _seating = [
    for (final id in context.phoneIds) '$id:${context.colorOf(id)?.id ?? ''}',
  ];

  @override
  Map<String, Object?> get sharedState => {
        'phase': _phase,
        'target': _target,
        'seating': _seating,
        // Whole digits: the view wants '3', '2', '1', and a raw float here
        // would be a packet every tick for a number nobody reads that finely.
        'countIn': _phase == ChronoPhase.countdown
            ? (ChronometerConfig.countdownSeconds - _phaseElapsed).ceil()
            : 0,
        // Deliberately *not* the running clock. Shipping it would put a live
        // timer on the wire, and any phone could render the answer — which is
        // the one thing this game is about not knowing.
        'guesses': _landed,
        'sweep': _target + ChronometerConfig.graceSeconds,
        // Only revealed once nobody can act on it.
        'results': _phase == ChronoPhase.results ? _resultRows() : const [],
        'over': _phase == ChronoPhase.results,
      };

  /// One row per phone, sorted closest first: `phoneId:colorId:guess:error`.
  /// A phone that never pressed reports an empty guess.
  List<String> _resultRows() => [
        for (final r in _ranked())
          '${r.id}:${context.colorOf(r.id)?.id ?? ''}:'
              '${_guesses[r.id]?.toStringAsFixed(2) ?? ''}:'
              '${r.error.toStringAsFixed(2)}',
      ];

  // ---------------------------------------------------------------- outcome

  /// Closest first. Phones that never pressed sort last, together.
  ///
  /// Rounded to hundredths — the same number the player is shown — because that
  /// is what makes a tie a tie. Comparing raw errors for equality would
  /// separate two people who both read "0.31 s" by a difference neither of them
  /// can see, on the last bits of a double.
  List<({String id, double error})> _ranked() => [
        for (final id in context.phoneIds)
          (
            id: id,
            error: double.parse(errorOf(id).toStringAsFixed(2)),
          ),
      ]..sort((a, b) => a.error.compareTo(b.error));

  /// Points for the closest guess, sliding to zero for the furthest, plus a
  /// bonus for landing inside the bullseye.
  ///
  /// By position rather than by margin, so one wild guess cannot flatten
  /// everyone else's score, and phones sharing an error share a position —
  /// losing a tie-break you did not lose would be worse than the tie.
  void _awardOnce() {
    if (_awarded) return;
    _awarded = true;

    // Only phones that actually guessed. The rest score nothing, which is
    // already where the curve would have put them.
    final ranked = _ranked().where((e) => _guesses.containsKey(e.id)).toList();
    if (ranked.isEmpty) return;

    final last = ranked.length - 1;
    for (var i = 0; i < ranked.length; i++) {
      var points = ChronometerConfig.bestScore;
      if (last > 0) {
        // Everybody tied at this error shares the best position among them.
        final position = ranked.indexWhere((e) => e.error == ranked[i].error);
        points = (ChronometerConfig.bestScore * (last - position) / last)
            .round();
      }
      if (ranked[i].error <= ChronometerConfig.bullseyeSeconds) {
        points += ChronometerConfig.bullseyeBonus;
      }
      if (points != 0) context.scores.award(ranked[i].id, points);
    }
  }

  @override
  GameOutcome? get outcome {
    // Held back until the marks have been on screen long enough to read. The
    // platform tears the round down the instant this goes non-null.
    if (_phase != ChronoPhase.results ||
        _phaseElapsed < ChronometerConfig.resultsSeconds) {
      return null;
    }

    // Built once and kept: `outcome` is polled several times a tick and this
    // one carries a line per phone.
    return _outcome ??= _buildOutcome();
  }

  GameOutcome _buildOutcome() {
    final lines = {
      for (final id in context.phoneIds) id: _lineFor(id),
    };

    final guessed = _ranked().where((e) => _guesses.containsKey(e.id)).toList();
    if (guessed.isEmpty) {
      return GameOutcome.draw(
        summary: 'nobody pressed — the ${_targetLabel()} went by unmarked',
        lines: lines,
      );
    }

    final best = guessed.first.error;
    final winners = {
      for (final e in guessed)
        if (e.error == best) e.id,
    };

    // Everybody dead level. A contest naming every single player as a winner
    // reads as a bug; a draw is what actually happened.
    if (winners.length == context.phoneIds.length && winners.length > 1) {
      return GameOutcome.draw(
        summary: 'a dead heat — everybody off by ${_secs(best)}',
        lines: lines,
      );
    }

    return GameOutcome.contest(
      winners: winners,
      summary: _summaryLine(guessed.first.id, best, winners.length),
      lines: lines,
    );
  }

  String _summaryLine(String bestId, double error, int winnerCount) {
    final target = _targetLabel();
    if (winnerCount > 1) {
      return 'a $winnerCount-way tie on $target, off by ${_secs(error)}';
    }
    final label = context.scores.view.entryFor(bestId)?.label ?? bestId;
    if (error <= ChronometerConfig.bullseyeSeconds) {
      return '$label nailed $target — ${_secs(error)} off';
    }
    return '$label was closest to $target, ${_secs(error)} off';
  }

  String _lineFor(String phoneId) {
    final guess = _guesses[phoneId];
    if (guess == null) return 'You never pressed';

    final error = guess - _target;
    if (error.abs() <= ChronometerConfig.bullseyeSeconds) {
      return 'You pressed at ${_secs(guess)} — spot on';
    }
    final way = error < 0 ? 'early' : 'late';
    return 'You pressed at ${_secs(guess)} — ${_secs(error.abs())} $way';
  }

  /// '7 s' for a whole target, '7.4 s' only when the decimal carries something.
  String _targetLabel() {
    final t = _target;
    return t == t.roundToDouble() ? '${t.round()} s' : _secs(t);
  }

  static String _secs(double v) => '${v.toStringAsFixed(2)} s';

  // ------------------------------------------------------------------ reset

  @override
  void reset() {
    _phase = ChronoPhase.reveal;
    _phaseElapsed = 0;
    _clock = 0;
    _guesses.clear();
    _landed.clear();
    _awarded = false;
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
    // A fresh number, or the second round is a memory test.
    _target = _drawTarget();
  }

  @override
  void dispose() {}
}
