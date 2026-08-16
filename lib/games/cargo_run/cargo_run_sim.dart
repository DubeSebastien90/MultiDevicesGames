import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/render/shape_view.dart';
import 'cargo_run_config.dart';

class _Crate {
  _Crate(this.id);

  final String id;

  bool live = false;
  bool good = true;
  double x = 0;
  double y = 0;
}

/// A belt down the middle of the row, and a stream of crates rolling along it
/// at a constant speed — over every phone on the table in turn, through the
/// real gap between each pair of casings, until they roll off the far end
/// unclaimed.
///
/// A crate tapped while it is within reach is caught: a green one scores its
/// tapper a point, a red one costs them one. A crate nobody was near just
/// keeps rolling — the only penalty for missing a green one is the point not
/// taken, the same rule Guac-a-Mole uses for an escaped mole.
///
/// No physics: a straight-line kinematic drift, the same shape Subway
/// Skater's obstacles use, run the full length of the board rather than
/// scrolling past one fixed post.
class CargoRunSim implements GameSim {
  CargoRunSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _lane = context.board.centerY;
    _pool = [
      for (var i = 0; i < CargoRunConfig.poolSize(context.phoneIds.length); i++)
        _Crate('crate$i'),
    ];
  }

  final BoardContext context;
  final math.Random _random;

  late final double _lane;
  late final List<_Crate> _pool;

  double _elapsed = 0;
  double _sinceSpawn = 0;

  bool get _over => _elapsed >= CargoRunConfig.roundSeconds;

  /// Whole seconds — `sharedState` is diffed every tick, and a raw float that
  /// always differs is a packet every tick.
  int get secondsLeft =>
      (CargoRunConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (outcome != null) return;
    _elapsed += dt;

    final limit = context.board.right + CargoRunConfig.crateRadius * 2;
    for (final c in _pool) {
      if (!c.live) continue;
      c.x += CargoRunConfig.crateSpeed * dt;
      if (c.x > limit) c.live = false;
    }

    _sinceSpawn += dt;
    if (_sinceSpawn >= _spawnGap) {
      _sinceSpawn = 0;
      _spawn();
    }
  }

  /// How far through the difficulty ramp we are, 0 to 1.
  double get _ramp {
    final t = CargoRunConfig.roundSeconds * CargoRunConfig.rampFraction;
    if (t <= 0) return 1;
    return (_elapsed / t).clamp(0.0, 1.0);
  }

  double get _spawnGap =>
      CargoRunConfig.spawnGapStart +
      (CargoRunConfig.spawnGapEnd - CargoRunConfig.spawnGapStart) * _ramp;

  void _spawn() {
    final crate = _freeCrate();
    if (crate == null) return;
    crate
      ..live = true
      ..good = _random.nextDouble() < CargoRunConfig.goodChance
      ..x = context.board.left - CargoRunConfig.crateRadius * 2
      ..y = _lane;
  }

  _Crate? _freeCrate() {
    for (final c in _pool) {
      if (!c.live) return c;
    }
    return null;
  }

  // ------------------------------------------------------------------ input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (outcome != null) return;

    final hit = _crateAt(touch.worldX, touch.worldY);
    if (hit == null) return;

    hit.live = false;
    final points = hit.good
        ? CargoRunConfig.pointsGood
        : -CargoRunConfig.pointsBadPenalty;
    context.scores.award(touch.phoneId, points);
  }

  /// The nearest live crate within reach, or null.
  _Crate? _crateAt(double x, double y) {
    _Crate? best;
    var bestD2 = double.infinity;
    for (final c in _pool) {
      if (!c.live) continue;
      final dx = x - c.x;
      final dy = y - c.y;
      final d2 = dx * dx + dy * dy;
      if (d2 > CargoRunConfig.tapReach * CargoRunConfig.tapReach) continue;
      if (d2 < bestD2) {
        bestD2 = d2;
        best = c;
      }
    }
    return best;
  }

  // -------------------------------------------------------------- entities

  @override
  Iterable<Entity> get entities sync* {
    for (final c in _pool) {
      if (!c.live) continue;
      yield Entity(
        descriptor: EntityDescriptor(
          id: c.id,
          kind: 'crate',
          props: {
            ShapeProps.shape: ShapeKind.box,
            ShapeProps.width: CargoRunConfig.crateRadius * 2,
            ShapeProps.height: CargoRunConfig.crateRadius * 2,
            ShapeProps.color: c.good
                ? CargoRunConfig.colorGood
                : CargoRunConfig.colorBad,
            'good': c.good,
          },
        ),
        x: c.x,
        y: c.y,
        vx: CargoRunConfig.crateSpeed,
      );
    }
  }

  @override
  Map<String, Object?> get sharedState => {'secondsLeft': secondsLeft};

  // ----------------------------------------------------------------- ending

  GameOutcome? _outcome;

  @override
  GameOutcome? get outcome {
    if (!_over) return null;
    return _outcome ??= _buildOutcome();
  }

  GameOutcome _buildOutcome() {
    final view = context.scores.view;
    final ranked = [
      for (final id in context.phoneIds) (id: id, points: view.roundDelta(id)),
    ]..sort((a, b) => b.points.compareTo(a.points));

    final lines = {for (final r in ranked) r.id: _lineFor(r.points)};

    if (ranked.isEmpty || ranked.first.points <= 0) {
      return GameOutcome.draw(summary: 'nobody ran a profit', lines: lines);
    }

    final top = ranked.first.points;
    final winners = {
      for (final r in ranked)
        if (r.points == top) r.id,
    };
    return GameOutcome.contest(
      winners: winners,
      summary: _summaryFor(ranked.first, winners.length),
      lines: lines,
    );
  }

  String _lineFor(int points) =>
      points >= 0 ? 'You cleared $points' : 'You cost the line $points';

  String _summaryFor(({String id, int points}) leader, int winnerCount) {
    if (winnerCount > 1) return 'a tie at ${leader.points}';
    final label = context.scores.view.entryFor(leader.id)?.label ?? leader.id;
    return '$label cleared the most, ${leader.points}';
  }

  @override
  void reset() {
    for (final c in _pool) {
      c.live = false;
    }
    _elapsed = 0;
    _sinceSpawn = 0;
    _outcome = null;
  }

  @override
  void dispose() {}
}
