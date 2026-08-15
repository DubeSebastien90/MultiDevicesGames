import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/render/shape_view.dart';
import 'echo_config.dart';

/// The two things a round can be doing.
class EchoPhase {
  static const reveal = 'reveal';
  static const recall = 'recall';
}

/// Watch the ring light up in order, then tap it back — from memory.
///
/// **No physics, no seam.** Every seat is a fixed point on the board and
/// nothing ever travels between them; what crosses the table is attention, not
/// an entity. Each level is a fresh random order of whoever is still in, shown
/// once and then expected back exactly. A wrong tap puts that phone out and the
/// level restarts for whoever is left — down to one, who wins.
///
/// Deliberately not a growing Simon sequence carried across levels: that would
/// mean a later level's replay could reference a phone eliminated since it was
/// recorded, with no honest way to satisfy it. Building a fresh permutation of
/// the *currently* active phones every level sidesteps the whole problem, and
/// the reveal getting quicker each level is what keeps the difficulty climbing
/// instead.
class EchoSim implements GameSim {
  EchoSim(this.context, {math.Random? random})
      : _random = random ?? math.Random() {
    _seatColor = {
      for (var i = 0; i < context.phoneIds.length; i++)
        context.phoneIds[i]:
            EchoConfig.seatPalette[i % EchoConfig.seatPalette.length],
    };
    _startLevel(advance: false);
  }

  final BoardContext context;
  final math.Random _random;

  late final Map<String, int> _seatColor;

  final _eliminated = <String>{};

  /// Kept as one persistent list and only ever appended to, so an unchanged
  /// round hands the platform the exact same instance back — which is what
  /// keeps a quiet round from being a packet every tick. See Chronometer's
  /// `_landed` for the same trick.
  final _eliminatedOrder = <String>[];

  List<String> get _active =>
      [for (final id in context.phoneIds) if (!_eliminated.contains(id)) id];

  int _round = 1;
  List<String> _sequence = const [];
  int _revealIndex = 0;
  int _recallIndex = 0;
  String _phase = EchoPhase.reveal;
  double _phaseElapsed = 0;

  bool _awardedWinner = false;
  GameOutcome? _outcome;

  double get _revealSeconds => math.max(
        EchoConfig.revealSecondsFloor,
        EchoConfig.revealSecondsStart -
            (_round - 1) * EchoConfig.revealSecondsStep,
      );

  double get _revealStepSeconds => _revealSeconds + EchoConfig.revealGapSeconds;

  /// For tests: what this round's order is.
  List<String> get sequence => _sequence;

  int get round => _round;

  // ------------------------------------------------------------------ setup

  void _startLevel({required bool advance}) {
    if (advance) _round++;
    _sequence = List.of(_active)..shuffle(_random);
    _revealIndex = 0;
    _recallIndex = 0;
    _phase = EchoPhase.reveal;
    _phaseElapsed = 0;
  }

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (_outcome != null) return;
    if (_phase != EchoPhase.reveal) return;

    _phaseElapsed += dt;
    while (_phase == EchoPhase.reveal && _phaseElapsed >= _revealStepSeconds) {
      _phaseElapsed -= _revealStepSeconds;
      _revealIndex++;
      if (_revealIndex >= _sequence.length) {
        _phase = EchoPhase.recall;
        _phaseElapsed = 0;
        break;
      }
    }
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (_outcome != null) return;
    if (touch.phase != TouchPhase.down) return;
    if (_phase != EchoPhase.recall) return;
    if (_eliminated.contains(touch.phoneId)) return;

    final expected = _sequence[_recallIndex];
    if (touch.phoneId == expected) {
      _recallIndex++;
      if (_recallIndex >= _sequence.length) _startLevel(advance: true);
      return;
    }

    _eliminate(touch.phoneId);
  }

  void _eliminate(String phoneId) {
    _eliminated.add(phoneId);
    _eliminatedOrder.add(phoneId);
    context.scores.award(phoneId, EchoConfig.pointsPerRoundSurvived * _round);

    final remaining = _active;
    if (remaining.length <= 1) {
      final winner = remaining.isEmpty ? null : remaining.single;
      if (winner != null && !_awardedWinner) {
        _awardedWinner = true;
        context.scores.award(winner, EchoConfig.winnerBonus);
      }
      _outcome = GameOutcome.contest(
        winners: winner == null ? const {} : {winner},
        summary: winner == null
            ? 'everybody broke the sequence'
            : 'was the last one still remembering it',
        lines: {
          for (final id in _eliminatedOrder)
            id: 'You broke the sequence in round $_round',
        },
      );
      return;
    }

    _startLevel(advance: false);
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities sync* {
    final lit = _phase == EchoPhase.reveal && _revealIndex < _sequence.length
        ? _sequence[_revealIndex]
        : null;

    for (final slice in context.slices) {
      final id = slice.phoneId;
      final out = _eliminated.contains(id);
      final color = out
          ? EchoConfig.colorEliminated
          : (id == lit ? _seatColor[id]! : EchoConfig.colorIdle);

      yield Entity(
        descriptor: EntityDescriptor(
          id: 'orb_$id',
          kind: out ? 'orb_out' : 'orb',
          props: {
            ShapeProps.shape: ShapeKind.circle,
            ShapeProps.radius: EchoConfig.orbRadius,
            ShapeProps.color: color,
          },
        ),
        x: slice.screen.centerX,
        y: slice.screen.centerY,
      );
    }
  }

  @override
  Map<String, Object?> get sharedState => {
        'phase': _phase,
        'round': _round,
        'litSeat':
            _phase == EchoPhase.reveal && _revealIndex < _sequence.length
                ? _sequence[_revealIndex]
                : null,
        'recallIndex': _recallIndex,
        'sequenceLength': _sequence.length,
        'eliminated': _eliminatedOrder,
        'over': _outcome != null,
      };

  @override
  GameOutcome? get outcome => _outcome;

  @override
  void reset() {
    _eliminated.clear();
    _eliminatedOrder.clear();
    _round = 1;
    _awardedWinner = false;
    _outcome = null;
    _startLevel(advance: false);
  }

  @override
  void dispose() {}
}
