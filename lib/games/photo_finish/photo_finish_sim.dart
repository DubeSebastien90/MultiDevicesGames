import 'dart:math' as math;

import 'photo_finish_config.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/model/world_rect.dart';
import '../../sdk/render/shape_view.dart';
import '../../sdk/score/scoreboard.dart';

/// One runner: a lane, a position along it, and how fast it is moving.
class _Runner {
  _Runner(this.laneY, this.color, this.x);

  final double laneY;
  final int color;
  double x;
  double v = 0;
}

/// A straight sprint the width of the whole board. Every phone owns exactly
/// one runner; tapping your own screen — anywhere on it, since it is *your*
/// runner and not whichever one happens to be nearest — gives it a shove
/// forward. Friction bleeds the shove off every tick, so holding still is not
/// a strategy: only a runner tapped in rhythm crosses every phone on the
/// table ahead of the others.
///
/// No physics engine and no collisions between runners: one x and one
/// velocity per phone, integrated by hand, the way Hot Potato integrates its
/// fuse. Runners passing clean through each other is deliberate — the race is
/// about who reaches the far edge first, not about jostling for a lane.
class PhotoFinishSim implements GameSim {
  PhotoFinishSim(this.context) {
    final ids = context.phoneIds;
    final laneSpan = board.height - PhotoFinishConfig.laneMargin * 2;
    for (var i = 0; i < ids.length; i++) {
      final laneY = board.top +
          PhotoFinishConfig.laneMargin +
          (i + 0.5) * laneSpan / ids.length;
      final color = context.colorOf(ids[i])?.value.toARGB32() ?? 0xFFFFFFFF;
      _runners[ids[i]] = _Runner(laneY, color, _startX);
    }
  }

  final BoardContext context;

  final _runners = <String, _Runner>{};

  double _elapsed = 0;
  String? _winnerId;
  bool _awarded = false;
  GameOutcome? _cachedOutcome;

  WorldRect get board => context.board;
  Scoreboard get scores => context.scores;

  double get _startX => board.left + PhotoFinishConfig.startInset;
  double get _finishX => board.right - PhotoFinishConfig.finishInset;

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down || _winnerId != null) return;
    final runner = _runners[touch.phoneId];
    if (runner == null) return;
    runner.v = math.min(
      runner.v + PhotoFinishConfig.boostPerTap,
      PhotoFinishConfig.maxSpeed,
    );
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_winnerId != null) return;

    _elapsed += dt;
    for (final entry in _runners.entries) {
      final runner = entry.value;
      runner.v = math.max(0, runner.v - PhotoFinishConfig.friction * dt);
      runner.x = math.min(runner.x + runner.v * dt, _finishX);
      if (_winnerId == null && runner.x >= _finishX) {
        _winnerId = entry.key;
      }
    }

    if (_winnerId != null && !_awarded) {
      _awarded = true;
      scores.award(_winnerId!, PhotoFinishConfig.winBonus);
    }
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities => [
    for (final entry in _runners.entries)
      Entity(
        descriptor: EntityDescriptor(
          id: 'runner_${entry.key}',
          kind: 'runner',
          props: {
            ShapeProps.shape: ShapeKind.circle,
            ShapeProps.radius: PhotoFinishConfig.runnerRadius,
            ShapeProps.color: entry.value.color,
          },
        ),
        x: entry.value.x,
        y: entry.value.laneY,
      ),
  ];

  @override
  Map<String, Object?> get sharedState => {
    // Constant for the round, so this is sent once and never adds noise.
    'finishX': _finishX,
  };

  @override
  GameOutcome? get outcome {
    if (_winnerId != null) {
      return _cachedOutcome ??= GameOutcome.contest(
        winners: {_winnerId!},
        summary: 'first across the line',
      );
    }
    if (_elapsed >= PhotoFinishConfig.backstopSeconds) {
      return _cachedOutcome ??=
          const GameOutcome.draw(summary: 'nobody finished the sprint');
    }
    return null;
  }

  @override
  void reset() {
    for (final runner in _runners.values) {
      runner
        ..x = _startX
        ..v = 0;
    }
    _elapsed = 0;
    _winnerId = null;
    _awarded = false;
    _cachedOutcome = null;
  }

  @override
  void dispose() {}
}
