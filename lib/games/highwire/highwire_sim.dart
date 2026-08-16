import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/render/shape_view.dart';
import 'highwire_config.dart';

/// A single walker inches along a wire strung the length of the board. It only
/// moves forward while the phone currently underneath it is held down; let go
/// and its balance drains until it falls off.
///
/// No physics and no impulses — the wire is a straight line at a fixed height
/// and [_walkerX] is the entire piece of state that matters. Which phone's
/// screen the walker is over is read straight off [BoardContext.phoneAt] every
/// tick, so responsibility for holding it up changes hands exactly when the
/// walker's world position actually crosses from one screen to the next.
/// Crossing the bezel gap in between needs nobody at all: nothing on the table
/// can reach it there, so the wire itself carries it the rest of the way.
class HighwireSim implements GameSim {
  HighwireSim(this.context) {
    _wireY = context.board.centerY;
    _speed = context.board.width / HighwireConfig.crossingSeconds;
    _walkerX = context.board.left + HighwireConfig.walkerRadius;
    _wireDescriptor = EntityDescriptor(
      id: 'wire',
      kind: 'wire',
      props: {
        ShapeProps.shape: ShapeKind.box,
        ShapeProps.width: context.board.width,
        ShapeProps.height: HighwireConfig.wireThickness,
        ShapeProps.color: 0xFFB8BEDA,
      },
    );
  }

  final BoardContext context;
  late final double _wireY;
  late final double _speed;
  late final EntityDescriptor _wireDescriptor;

  static const _walkerDescriptor = EntityDescriptor(
    id: 'walker',
    kind: 'walker',
    props: {
      ShapeProps.shape: ShapeKind.circle,
      ShapeProps.radius: HighwireConfig.walkerRadius,
      ShapeProps.color: 0xFFFFD54A,
    },
  );

  late double _walkerX;
  double _balance = 1;
  double _elapsed = 0;

  /// How many fingers are currently down on each phone. A count rather than a
  /// flag, so a second finger lifting is never mistaken for the first one
  /// letting go.
  final _fingersDown = <String, int>{};

  bool _finished = false;
  GameOutcome? _outcome;

  /// The phone whose screen the walker is over right now, or null in a gap.
  String? get holder => context.phoneAt(_walkerX, _wireY);

  double get balance => _balance;

  double get walkerX => _walkerX;

  @override
  void onTouch(TouchEvent touch) {
    if (_finished) return;
    switch (touch.phase) {
      case TouchPhase.down:
        _fingersDown.update(
          touch.phoneId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      case TouchPhase.up:
        final left = (_fingersDown[touch.phoneId] ?? 1) - 1;
        if (left <= 0) {
          _fingersDown.remove(touch.phoneId);
        } else {
          _fingersDown[touch.phoneId] = left;
        }
      case TouchPhase.move:
        break;
    }
  }

  @override
  void step(double dt) {
    if (_finished) return;
    _elapsed += dt;

    if (_elapsed >= HighwireConfig.timeLimitSeconds) {
      _finish(GameOutcome.lost(summary: 'time ran out on the wire'));
      return;
    }

    final current = holder;
    final supported = current != null && _fingersDown.containsKey(current);

    if (supported || current == null) {
      _walkerX += _speed * dt;
      if (supported) {
        _balance = math.min(
          1,
          _balance + dt / HighwireConfig.balanceRegainSeconds,
        );
      }
    } else {
      _balance = math.max(
        0,
        _balance - dt / HighwireConfig.balanceDrainSeconds,
      );
      if (_balance <= 0) {
        _finish(GameOutcome.lost(summary: 'the walker fell'));
        return;
      }
    }

    if (_walkerX >= context.board.right) {
      _walkerX = context.board.right;
      context.scores.awardAll(HighwireConfig.crossingBonus);
      _finish(GameOutcome.won(summary: 'made it across the wire'));
    }
  }

  void _finish(GameOutcome outcome) {
    if (_finished) return;
    _finished = true;
    _outcome = outcome;
  }

  @override
  Iterable<Entity> get entities => [
    Entity(descriptor: _wireDescriptor, x: context.board.centerX, y: _wireY),
    Entity(descriptor: _walkerDescriptor, x: _walkerX, y: _wireY),
  ];

  @override
  Map<String, Object?> get sharedState => {
    // Rounded to a hundredth: a raw float here would be a packet every tick
    // for the whole round, most of it below what the balance bar can show.
    'balance': double.parse(_balance.toStringAsFixed(2)),
    'holder': holder,
    'secondsLeft': (HighwireConfig.timeLimitSeconds - _elapsed)
        .ceil()
        .clamp(0, 999),
  };

  @override
  GameOutcome? get outcome => _outcome;

  @override
  void reset() {
    _walkerX = context.board.left + HighwireConfig.walkerRadius;
    _balance = 1;
    _elapsed = 0;
    _fingersDown.clear();
    _finished = false;
    _outcome = null;
  }

  @override
  void dispose() {}
}
