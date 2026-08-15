import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'tandem_config.dart';

/// Two neighbours light up together. Both have to tap before the ring runs
/// out, or the attempt is wasted and a different pair gets a turn.
///
/// **No physics, no entities.** Like Reaction Time, nothing crosses the seam
/// and nothing moves — the whole world is "which two screens are lit right
/// now" and "who of the two has tapped so far", carried entirely in
/// [sharedState].
///
/// The pairing is read off [BoardContext.slices], not chosen by the sim: a
/// column board is compiled in reading order — top to bottom — which for a
/// single line of phones is already the physical order they stand in, so
/// consecutive slices are neighbours for real.
class TandemSim implements GameSim {
  TandemSim(this.context, {math.Random? random})
      : _random = random ?? math.Random(),
        _pairs = [
          for (var i = 0; i < context.slices.length - 1; i++)
            (context.slices[i].phoneId, context.slices[i + 1].phoneId),
        ] {
    assert(_pairs.isNotEmpty, 'Tandem needs at least two phones');
    _nextLightAt = TandemConfig.initialDelaySeconds;
  }

  final BoardContext context;
  final math.Random _random;

  /// Adjacent phone pairs, in board order — the only neighbours who are ever
  /// asked to sync a tap together.
  final List<(String, String)> _pairs;

  double _elapsed = 0;
  double _nextLightAt = 0;

  /// Index into [_pairs] of the pair currently lit, or null between attempts.
  int? _activePair;
  double _litAt = 0;
  bool _tappedA = false;
  bool _tappedB = false;
  int _lastPair = -1;

  int _successes = 0;

  /// A resolved attempt, win or miss, told apart from "nothing happened yet"
  /// by a running number rather than a flag — two attempts resolving in the
  /// same tick would otherwise collapse into one piece of feedback. Scalars
  /// rather than a record: `sharedState` is diffed by `==`, and a fresh record
  /// literal every tick would never compare equal to the last one even when
  /// nothing changed.
  int _resultSeq = 0;
  String? _resultA;
  String? _resultB;
  bool _resultWasSuccess = false;

  GameOutcome? _outcome;

  bool get _timeUp => _elapsed >= TandemConfig.roundSeconds;
  bool get _reachedTarget => _successes >= TandemConfig.targetSuccesses;
  bool get _over => _timeUp || _reachedTarget;

  int get secondsLeft =>
      (TandemConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_over) return;
    _elapsed += dt;
    if (_over) {
      _activePair = null;
      return;
    }

    if (_activePair == null) {
      if (_elapsed >= _nextLightAt) _light();
      return;
    }

    if (_elapsed - _litAt >= TandemConfig.windowSeconds) {
      _resolve(success: false);
    }
  }

  void _light() {
    var next = _random.nextInt(_pairs.length);
    if (_pairs.length > 1) {
      while (next == _lastPair) {
        next = _random.nextInt(_pairs.length);
      }
    }
    _lastPair = next;
    _activePair = next;
    _litAt = _elapsed;
    _tappedA = false;
    _tappedB = false;
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (_over || touch.phase != TouchPhase.down) return;
    final pair = _activePair;
    if (pair == null) return;

    final (a, b) = _pairs[pair];
    if (touch.phoneId == a) {
      _tappedA = true;
    } else if (touch.phoneId == b) {
      _tappedB = true;
    } else {
      return; // Not one of the two phones this attempt is asking anything of.
    }

    if (_tappedA && _tappedB) _resolve(success: true);
  }

  void _resolve({required bool success}) {
    final (a, b) = _pairs[_activePair!];
    if (success) {
      _successes++;
      context.scores.award(a, TandemConfig.pointsPerSuccess);
      context.scores.award(b, TandemConfig.pointsPerSuccess);
    }
    _resultSeq++;
    _resultA = a;
    _resultB = b;
    _resultWasSuccess = success;

    _activePair = null;
    _nextLightAt = _elapsed + TandemConfig.cooldownSeconds;
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities => const [];

  @override
  Map<String, Object?> get sharedState {
    final pair = _activePair;
    return {
      'litA': pair == null ? null : _pairs[pair].$1,
      'litB': pair == null ? null : _pairs[pair].$2,
      'tappedA': _tappedA,
      'tappedB': _tappedB,
      'windowLeft': pair == null
          ? null
          : double.parse(
              (TandemConfig.windowSeconds - (_elapsed - _litAt))
                  .clamp(0, TandemConfig.windowSeconds)
                  .toStringAsFixed(2),
            ),
      'successes': _successes,
      'target': TandemConfig.targetSuccesses,
      'resultSeq': _resultSeq,
      'resultA': _resultA,
      'resultB': _resultB,
      'resultWasSuccess': _resultWasSuccess,
      'secondsLeft': secondsLeft,
      'over': _over,
    };
  }

  // --------------------------------------------------------------- outcome

  @override
  GameOutcome? get outcome {
    if (!_over) return null;
    if (_reachedTarget) {
      return _outcome ??= GameOutcome.won(
        summary: '${TandemConfig.targetSuccesses} synced taps, together',
      );
    }
    return _outcome ??= GameOutcome.lost(
      summary:
          'ran out of time on $_successes of ${TandemConfig.targetSuccesses}',
    );
  }

  // ----------------------------------------------------------------- reset

  @override
  void reset() {
    _elapsed = 0;
    _nextLightAt = TandemConfig.initialDelaySeconds;
    _activePair = null;
    _litAt = 0;
    _tappedA = false;
    _tappedB = false;
    _lastPair = -1;
    _successes = 0;
    _resultSeq = 0;
    _resultA = null;
    _resultB = null;
    _resultWasSuccess = false;
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
  }

  @override
  void dispose() {}
}
