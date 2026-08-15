import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'nerve_config.dart';

enum _Phase {
  /// Nobody's turn. A short pause before the next one is dealt.
  betweenTurns,

  /// It is somebody's turn, but they have not put a finger down yet.
  waitingToStart,

  /// Held down, climbing toward a threshold only the sim knows.
  holding,
}

/// Press and hold as long as you dare. Let go before the hidden threshold and
/// you bank what you held; hold past it and the turn is worth nothing.
///
/// **No physics, and no entities.** Like Reaction Time and Chronometer,
/// nothing crosses the gap between phones and nothing moves, so the whole
/// game lives in [sharedState]: whose turn it is, and how long they have been
/// holding. What makes it a different game from either of those is the
/// *shape* of the decision. Reaction rewards speed against a signal;
/// Chronometer rewards a single estimate against a shown target. Nerve gives
/// nothing to estimate and nothing to react to — only a choice, made fresh
/// every instant a finger stays down, between banking what is already
/// earned and risking it for more.
///
/// The threshold is drawn fresh per turn and never published: a player who
/// could read it off the wire would not be holding their nerve, they would be
/// reading a countdown.
class NerveSim implements GameSim {
  NerveSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _startNextTurn();
  }

  final BoardContext context;
  final math.Random _random;

  double _elapsed = 0;
  _Phase _phase = _Phase.betweenTurns;
  double _phaseTime = 0;

  String? _current;
  double _heldSeconds = 0;
  double _burstAt = 0;

  /// Turns still owed in this pass, so nobody gets a second go before
  /// everybody else has had a first.
  final _bag = <String>[];

  final _totalHeldSeconds = <String, double>{};
  final _turnsBanked = <String, int>{};

  int _bankSeq = 0;
  String? _bankBy;
  double _bankedSeconds = 0;

  int _burstSeq = 0;
  String? _burstBy;

  bool _ended = false;
  GameOutcome? _outcome;

  bool get _over => _elapsed >= NerveConfig.roundSeconds;

  int get secondsLeft =>
      (NerveConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_ended) return;
    _elapsed += dt;

    if (_over) {
      _current = null;
      _finalizeOnce();
      return;
    }

    _phaseTime += dt;
    switch (_phase) {
      case _Phase.betweenTurns:
        if (_phaseTime < NerveConfig.settleSeconds) return;
        _phaseTime = 0;
        _startNextTurn();
      case _Phase.waitingToStart:
        if (_phaseTime < NerveConfig.startTimeoutSeconds) return;
        _phaseTime = 0;
        _current = null;
        _phase = _Phase.betweenTurns;
      case _Phase.holding:
        _heldSeconds += dt;
        if (_heldSeconds < _burstAt) return;
        _burst();
    }
  }

  void _startNextTurn() {
    if (_bag.isEmpty) {
      _bag.addAll(context.phoneIds);
      _bag.shuffle(_random);
    }
    _current = _bag.removeLast();
    _burstAt =
        NerveConfig.minBurstSeconds +
        _random.nextDouble() *
            (NerveConfig.maxBurstSeconds - NerveConfig.minBurstSeconds);
    _heldSeconds = 0;
    _phase = _Phase.waitingToStart;
    _phaseTime = 0;
  }

  void _burst() {
    _burstSeq++;
    _burstBy = _current;
    _current = null;
    _phase = _Phase.betweenTurns;
    _phaseTime = 0;
  }

  void _bank() {
    final id = _current!;
    final seconds = _heldSeconds;
    context.scores.award(id, (seconds * NerveConfig.pointsPerSecond).round());
    _totalHeldSeconds[id] = (_totalHeldSeconds[id] ?? 0) + seconds;
    _turnsBanked[id] = (_turnsBanked[id] ?? 0) + 1;

    _bankSeq++;
    _bankBy = id;
    _bankedSeconds = double.parse(seconds.toStringAsFixed(1));

    _current = null;
    _phase = _Phase.betweenTurns;
    _phaseTime = 0;
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (_over || touch.phoneId != _current) return;

    if (_phase == _Phase.waitingToStart && touch.phase == TouchPhase.down) {
      _phase = _Phase.holding;
      _phaseTime = 0;
      return;
    }

    if (_phase == _Phase.holding && touch.phase == TouchPhase.up) {
      _bank();
    }
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities => const [];

  @override
  Map<String, Object?> get sharedState => {
    'current': _current,
    'holding': _phase == _Phase.holding,
    // Whole seconds — the precision a screen can actually show, so a
    // held turn is not a float changing every tick.
    'heldSeconds': _phase == _Phase.holding ? _heldSeconds.floor() : 0,
    'secondsLeft': secondsLeft,
    'bankSeq': _bankSeq,
    'bankBy': _bankBy,
    'bankedSeconds': _bankedSeconds,
    'burstSeq': _burstSeq,
    'burstBy': _burstBy,
    'over': _over,
  };

  // --------------------------------------------------------------- outcome

  void _finalizeOnce() {
    if (_ended) return;
    _ended = true;

    final totals = {
      for (final id in context.phoneIds) id: _totalHeldSeconds[id] ?? 0,
    };
    final best = totals.values.isEmpty
        ? 0.0
        : totals.values.reduce((a, b) => a > b ? a : b);

    if (best <= 0) {
      _outcome = GameOutcome.draw(summary: 'nobody banked a single second');
      return;
    }

    final winners = {
      for (final e in totals.entries)
        if (e.value == best) e.key,
    };

    _outcome = GameOutcome.contest(
      winners: winners,
      summary:
          '${_labelOf(winners.first)} banked the most, '
          '${best.toStringAsFixed(1)}s worth',
      lines: {
        for (final id in context.phoneIds)
          id:
              'You banked ${(totals[id] ?? 0).toStringAsFixed(1)}s across '
              '${_turnsBanked[id] ?? 0} turn'
              '${(_turnsBanked[id] ?? 0) == 1 ? '' : 's'}',
      },
    );
  }

  String _labelOf(String phoneId) =>
      context.scores.view.entryFor(phoneId)?.label ?? phoneId;

  @override
  GameOutcome? get outcome => _outcome;

  // ----------------------------------------------------------------- reset

  @override
  void reset() {
    _elapsed = 0;
    _phase = _Phase.betweenTurns;
    _phaseTime = 0;
    _current = null;
    _heldSeconds = 0;
    _burstAt = 0;
    _bag.clear();
    _totalHeldSeconds.clear();
    _turnsBanked.clear();
    _bankSeq = 0;
    _bankBy = null;
    _bankedSeconds = 0;
    _burstSeq = 0;
    _burstBy = null;
    _ended = false;
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
    _startNextTurn();
  }

  @override
  void dispose() {}
}
