import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/model/world_rect.dart';
import '../../sdk/render/shape_view.dart';
import 'driftwood_config.dart';

/// A log rides a current the whole length of the board. Steer it clear of the
/// rocks fixed along the way, or watch it run aground.
///
/// **No physics.** There is exactly one moving thing, and its motion is
/// "constant forward speed, plus whatever the taps have added vertically" —
/// nothing here needs contacts or gravity, so this extends [GameSim] directly,
/// the way Hot Potato does. The log is still an *entity*, which is what lets it
/// visibly sweep across every phone on the table, through the gap between two
/// of them, on the shared clock — not merely appear on whichever screen its `x`
/// happens to fall on.
class DriftwoodSim implements GameSim {
  DriftwoodSim(this.context, {int? hazardCount})
    : _hazards = _layHazards(
        context.board,
        hazardCount ?? DriftwoodConfig.hazardCount,
      ),
      _startX =
          context.board.left +
          context.board.width * DriftwoodConfig.startMarginFraction {
    _x = _startX;
    _y = context.board.centerY;
  }

  final BoardContext context;
  final List<_Hazard> _hazards;
  final double _startX;

  double _x = 0;
  double _y = 0;
  double _vy = 0;
  bool _crashed = false;
  bool _won = false;
  bool _awarded = false;
  GameOutcome? _outcome;

  static const _logId = 'log';

  /// Rocks spread evenly between the two configured fractions of the board,
  /// alternating which side of the centreline they sit on — a zigzag that
  /// forces the log to actually swing across the lane rather than hug one edge.
  static List<_Hazard> _layHazards(WorldRect board, int count) {
    if (count <= 0) return const [];
    final halfLane = board.height / 2;
    final offset = halfLane * DriftwoodConfig.hazardOffsetFraction;
    final startX = board.left + board.width * DriftwoodConfig.hazardStartFraction;
    final endX = board.left + board.width * DriftwoodConfig.hazardEndFraction;
    final step = count > 1 ? (endX - startX) / (count - 1) : 0.0;
    return [
      for (var i = 0; i < count; i++)
        _Hazard(
          id: 'rock$i',
          x: startX + step * i,
          y: board.centerY + (i.isEven ? offset : -offset),
        ),
    ];
  }

  double get finishX =>
      context.board.right - context.board.width * DriftwoodConfig.finishMarginFraction;

  // ------------------------------------------------------------------ input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (_crashed || _won) return;

    final dx = touch.worldX - _x;
    final dy = touch.worldY - _y;
    if (dx * dx + dy * dy > DriftwoodConfig.reachWorld * DriftwoodConfig.reachWorld) {
      return; // Too far from the log right now to reach it.
    }

    final direction = dy >= 0 ? 1.0 : -1.0;
    _vy = (_vy + direction * DriftwoodConfig.steerImpulse).clamp(
      -DriftwoodConfig.vyMax,
      DriftwoodConfig.vyMax,
    );
  }

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (_crashed || _won) return;

    // Decays toward zero, so a tap is a nudge kept alive only by more taps —
    // not a heading set once and held forever.
    _vy *= math.exp(-DriftwoodConfig.steerDamping * dt);

    _x += DriftwoodConfig.currentSpeed * dt;
    _y += _vy * dt;

    final top = context.board.top + DriftwoodConfig.logRadius;
    final bottom = context.board.bottom - DriftwoodConfig.logRadius;
    if (_y < top) {
      _y = top;
      _vy = _vy.abs();
    } else if (_y > bottom) {
      _y = bottom;
      _vy = -_vy.abs();
    }

    final reach = DriftwoodConfig.logRadius + DriftwoodConfig.rockRadius;
    for (final rock in _hazards) {
      final ddx = _x - rock.x;
      final ddy = _y - rock.y;
      if (ddx * ddx + ddy * ddy <= reach * reach) {
        _crashed = true;
        return;
      }
    }

    if (_x >= finishX) {
      _x = finishX;
      _won = true;
    }

    // Award once, on the tick it happens — the outcome getter is polled more
    // than once a tick and must never charge twice.
    if (_won && !_awarded) {
      _awarded = true;
      context.scores.awardAll(DriftwoodConfig.winBonus);
    }
  }

  @override
  void reset() {
    _x = _startX;
    _y = context.board.centerY;
    _vy = 0;
    _crashed = false;
    _won = false;
    _awarded = false;
    _outcome = null;
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities sync* {
    yield Entity(
      descriptor: const EntityDescriptor(
        id: _logId,
        kind: 'log',
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: DriftwoodConfig.logRadius,
          ShapeProps.color: DriftwoodConfig.colorLog,
          ShapeProps.spin: true,
        },
      ),
      x: _x,
      y: _y,
    );
    for (final rock in _hazards) {
      yield Entity(
        descriptor: EntityDescriptor(
          id: rock.id,
          kind: 'rock',
          props: const {
            ShapeProps.shape: ShapeKind.circle,
            ShapeProps.radius: DriftwoodConfig.rockRadius,
            ShapeProps.color: DriftwoodConfig.colorRock,
          },
        ),
        x: rock.x,
        y: rock.y,
      );
    }
  }

  @override
  Map<String, Object?> get sharedState => {
    // Rounded to a hundredth: a HUD showing whole percent has no use for a
    // value that changes every tick, and broadcasting one anyway is exactly
    // the always-different-float trap Flood's countdown fell into.
    'progress': double.parse(
      (((_x - _startX) / (finishX - _startX)).clamp(0, 1)).toStringAsFixed(2),
    ),
    'crashed': _crashed,
    'won': _won,
  };

  @override
  GameOutcome? get outcome {
    if (_won) {
      return _outcome ??= const GameOutcome.won(summary: 'reached the far bank');
    }
    if (_crashed) {
      return _outcome ??= const GameOutcome.lost(summary: 'ran aground');
    }
    return null;
  }

  @override
  void dispose() {}
}

class _Hazard {
  const _Hazard({required this.id, required this.x, required this.y});
  final String id;
  final double x;
  final double y;
}
