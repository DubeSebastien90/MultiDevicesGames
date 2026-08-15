import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'copycat_config.dart';

/// The three things the team is ever doing.
enum CopycatPhase {
  /// A tile is playing back, one at a time.
  watch,

  /// The dark beat between two tiles of a playback.
  gap,

  /// Waiting for the next correct tap.
  input,
}

/// Watch the tiles light up, then tap them back in the same order — a shared
/// hand of Simon played across every phone on the table at once.
///
/// **No physics, no entities, no seam.** Like Reaction Time, the whole game is
/// "which screen is lit right now", so it is carried entirely in
/// [sharedState] and a phone lights itself up by comparing its own id against
/// it. What is new here is the shape of the round: not one flash to answer,
/// but a sequence that grows by one every time the team gets it right — a
/// memory game, cooperative from the first tap to the last, where every other
/// game with a clock is either a race or a reflex test.
class CopycatSim implements GameSim {
  CopycatSim(this.context, {math.Random? random})
      : _random = random ?? math.Random() {
    _sequence.add(_randomTile());
  }

  final BoardContext context;
  final math.Random _random;

  final List<String> _sequence = [];

  CopycatPhase _phase = CopycatPhase.watch;

  /// Which tile of [_sequence] is lit, during [CopycatPhase.watch].
  int _showIndex = 0;

  /// How many taps of [_sequence] have landed correctly, during
  /// [CopycatPhase.input].
  int _inputIndex = 0;

  /// Seconds spent in the current phase.
  double _phaseElapsed = 0;

  /// Seconds spent in the round as a whole, for the hard cap.
  double _roundElapsed = 0;

  bool _awarded = false;
  GameOutcome? _outcome;

  /// The pattern so far, oldest tile first. For tests — a phone never sees
  /// more of it than [sharedState]'s `lit` reveals one tile at a time.
  List<String> get sequence => List.unmodifiable(_sequence);

  String _randomTile() =>
      context.phoneIds[_random.nextInt(context.phoneIds.length)];

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_outcome != null) return;

    _roundElapsed += dt;
    if (_roundElapsed >= CopycatConfig.roundSeconds) {
      _lose('ran out of time');
      return;
    }

    _phaseElapsed += dt;
    switch (_phase) {
      case CopycatPhase.watch:
        if (_phaseElapsed >= CopycatConfig.showSeconds) {
          _phase = CopycatPhase.gap;
          _phaseElapsed = 0;
        }
      case CopycatPhase.gap:
        if (_phaseElapsed >= CopycatConfig.gapSeconds) {
          _phaseElapsed = 0;
          _showIndex++;
          if (_showIndex >= _sequence.length) {
            _phase = CopycatPhase.input;
            _inputIndex = 0;
          } else {
            _phase = CopycatPhase.watch;
          }
        }
      case CopycatPhase.input:
        if (_phaseElapsed >= CopycatConfig.inputTimeoutSeconds) {
          _lose('nobody tapped in time');
        }
    }
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (_outcome != null) return;
    if (touch.phase != TouchPhase.down) return;
    if (_phase != CopycatPhase.input) return;

    _phaseElapsed = 0; // a live table always earns another beat of patience

    if (touch.phoneId != _sequence[_inputIndex]) {
      _lose('the wrong tile lit up');
      return;
    }

    _inputIndex++;
    if (_inputIndex < _sequence.length) return;

    if (_sequence.length >= CopycatConfig.targetLength) {
      _win();
      return;
    }

    _sequence.add(_randomTile());
    _phase = CopycatPhase.watch;
    _showIndex = 0;
    _phaseElapsed = 0;
  }

  // --------------------------------------------------------------- outcome

  void _win() {
    _outcome ??= GameOutcome.won(summary: 'the whole pattern, in order');
    _awardOnce();
  }

  void _lose(String reason) {
    _outcome ??= GameOutcome.lost(summary: reason);
  }

  void _awardOnce() {
    if (_awarded) return;
    _awarded = true;
    context.scores.awardAll(CopycatConfig.winBonus);
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities => const [];

  @override
  Map<String, Object?> get sharedState => {
        'phase': _phase.name,
        'lit': _phase == CopycatPhase.watch ? _sequence[_showIndex] : null,
        'length': _sequence.length,
        'target': CopycatConfig.targetLength,
        'secondsLeft':
            (CopycatConfig.roundSeconds - _roundElapsed).ceil().clamp(0, 999),
      };

  @override
  GameOutcome? get outcome => _outcome;

  // ----------------------------------------------------------------- reset

  @override
  void reset() {
    _sequence
      ..clear()
      ..add(_randomTile());
    _phase = CopycatPhase.watch;
    _showIndex = 0;
    _inputIndex = 0;
    _phaseElapsed = 0;
    _roundElapsed = 0;
    _awarded = false;
    _outcome = null;
  }

  @override
  void dispose() {}
}
