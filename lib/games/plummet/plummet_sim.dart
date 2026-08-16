import 'package:forge2d/forge2d.dart';

import 'plummet_config.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';

/// A wall spike, jutting in from one side of the shaft. Not a physics
/// fixture — the ball is never meant to bounce off one, only to be steered
/// clear of it, so a touch is a plain circle-vs-box distance check rather
/// than something Box2D needs to resolve.
class _Spike {
  const _Spike(this.cx, this.cy, this.halfW, this.halfH);
  final double cx;
  final double cy;
  final double halfW;
  final double halfH;

  bool hits(double bx, double by, double r) {
    final closestX = bx.clamp(cx - halfW, cx + halfW);
    final closestY = by.clamp(cy - halfH, cy + halfH);
    final dx = bx - closestX;
    final dy = by - closestY;
    return dx * dx + dy * dy <= r * r;
  }
}

/// A ball falls under real gravity down a narrow shaft built from every phone
/// on the table, stacked seam after seam. Wall spikes jut in from alternating
/// sides at every phone after the first, zigzagging down toward the floor;
/// touch one and the round is lost. A reach-gated tap swats the ball
/// sideways — a clean velocity set, not an accumulating shove — so dodging is
/// deliberate and repeatable rather than a matter of mashing the glass.
///
/// The only way out is down: gravity nets the ball's vertical speed downward
/// every tick regardless of what anybody taps, so the round is bounded by the
/// shaft's own height without needing a clock to enforce it. A generous timer
/// is kept anyway, purely as a backstop.
class PlummetSim extends Forge2DGameSim {
  PlummetSim(super.context)
    : super(gravity: Vector2(0, PlummetConfig.gravity)) {
    addBoundaryWalls(restitution: PlummetConfig.wallRestitution);
    _spikes = _buildSpikes();
    _addFloorLine();
    _addBall();
  }

  static const _ballId = 'ball';

  late final List<_Spike> _spikes;
  double _elapsed = 0;
  double _cooldown = 0;
  GameOutcome? _outcome;

  Vector2 get _spawn =>
      Vector2(board.centerX, board.top + PlummetConfig.ballRadius * 3);

  // ----------------------------------------------------------------- build

  /// One spike per phone after the first — the first phone is a clear drop
  /// so the table can see the ball fall before anything is asked of it — read
  /// from where the phones actually ended up, not from the order `planBoard`
  /// happened to return them in.
  List<_Spike> _buildSpikes() {
    final ordered = List.of(context.slices)
      ..sort((a, b) => a.viewport.centerY.compareTo(b.viewport.centerY));

    final spikeW = board.width * PlummetConfig.spikeWidthFraction;
    final spikes = <_Spike>[];
    for (var i = 1; i < ordered.length; i++) {
      final slice = ordered[i].viewport;
      final fromLeft = (i - 1).isEven;
      final cx =
          fromLeft ? board.left + spikeW / 2 : board.right - spikeW / 2;
      final halfH =
          slice.height * PlummetConfig.spikeThicknessFraction / 2;
      spikes.add(_Spike(cx, slice.centerY, spikeW / 2, halfH));

      addBody(
        'spike$i',
        'spike',
        BodyDef(position: Vector2(cx, slice.centerY)),
        props: {
          ShapeProps.shape: ShapeKind.box,
          ShapeProps.width: spikeW,
          ShapeProps.height: halfH * 2,
          ShapeProps.color: PlummetConfig.colorSpike,
        },
      );
    }
    return spikes;
  }

  /// Purely a visual marker for the finish — no fixture, so the ball actually
  /// falls past it rather than resting on it.
  void _addFloorLine() {
    final b = board;
    const thickness = 0.3;
    addBody(
      'floor',
      'floor',
      BodyDef(position: Vector2(b.centerX, b.bottom - thickness / 2)),
      props: {
        ShapeProps.shape: ShapeKind.box,
        ShapeProps.width: b.width,
        ShapeProps.height: thickness,
        ShapeProps.color: PlummetConfig.colorFloor,
      },
    );
  }

  void _addBall() {
    addBody(
      _ballId,
      'ball',
      BodyDef(type: BodyType.dynamic, position: _spawn, bullet: true),
      props: {
        ShapeProps.shape: ShapeKind.circle,
        ShapeProps.radius: PlummetConfig.ballRadius,
        ShapeProps.color: PlummetConfig.colorBall,
        ShapeProps.spin: true,
      },
    ).createFixture(
      FixtureDef(
        CircleShape(radius: PlummetConfig.ballRadius),
        density: PlummetConfig.ballDensity,
        friction: PlummetConfig.ballFriction,
        restitution: PlummetConfig.wallRestitution,
      ),
    );
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (_outcome != null || _cooldown > 0) return;

    final ball = bodyOf(_ballId)!;
    final dx = touch.worldX - ball.position.x;
    final dy = touch.worldY - ball.position.y;
    final reach = PlummetConfig.ballRadius + PlummetConfig.reachRadius;
    if (dx * dx + dy * dy > reach * reach) return;

    // Away from the tap, not toward it — a swat, not a magnet.
    final pushDir = dx >= 0 ? -1.0 : 1.0;
    ball.linearVelocity =
        Vector2(pushDir * PlummetConfig.pushSpeed, ball.linearVelocity.y);
    _cooldown = PlummetConfig.pushCooldown;
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_outcome != null) return;
    super.step(dt);
    _elapsed += dt;
    _cooldown = (_cooldown - dt) > 0 ? _cooldown - dt : 0;

    final ball = bodyOf(_ballId)!;
    final r = PlummetConfig.ballRadius;

    for (final spike in _spikes) {
      if (spike.hits(ball.position.x, ball.position.y, r)) {
        _outcome = GameOutcome.lost(summary: 'a spike caught the ball');
        return;
      }
    }

    if (ball.position.y - r > board.bottom) {
      scores.awardAll(PlummetConfig.bonusPerPhone);
      _outcome = GameOutcome.won(summary: 'reached the bottom of the shaft');
      return;
    }

    if (_elapsed >= PlummetConfig.maxRoundSeconds) {
      _outcome = GameOutcome.lost(summary: 'ran out of time');
    }
  }

  @override
  void reset() {
    _elapsed = 0;
    _cooldown = 0;
    _outcome = null;
    bodyOf(_ballId)!
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setTransform(_spawn, 0);
  }

  // ------------------------------------------------------------- snapshots

  @override
  Map<String, Object?> get sharedState => {
    'progressPct': _progressPct,
  };

  int get _progressPct {
    final ball = bodyOf(_ballId);
    if (ball == null) return 0;
    final travelled = ball.position.y - board.top;
    return ((travelled / board.height) * 100).clamp(0, 100).round();
  }

  @override
  GameOutcome? get outcome => _outcome;
}
