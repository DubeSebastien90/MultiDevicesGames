import 'package:forge2d/forge2d.dart';

import 'beach_ball_config.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';

/// One ball, gravity, and a row of phones trying to keep it off the ground.
///
/// Purely cooperative — there is nothing to win against, only the clock — but
/// every save is credited to whoever's tap connected, the same idea Ball Bin
/// uses for its catches. A bump only lands while the ball is falling, which is
/// what stops the table from just tapping it into a permanent hover: you have
/// to wait for it to come back down.
class BeachBallSim extends Forge2DGameSim {
  BeachBallSim(super.context)
    : super(gravity: Vector2(0, BeachBallConfig.gravity)) {
    addBoundaryWalls();
    _addGroundLine();
    _addBall();
  }

  static const _ballId = 'ball';

  double _elapsed = 0;
  double _cooldown = 0;
  int _saves = 0;
  GameOutcome? _outcome;

  Vector2 get _spawn =>
      Vector2(board.centerX, board.top + BeachBallConfig.ballRadius * 3);

  // ----------------------------------------------------------------- build

  /// Purely a visual marker for the fail line — no fixture, so the ball
  /// actually falls past it rather than resting on it.
  void _addGroundLine() {
    final b = board;
    const thickness = 0.3;
    addBody(
      'groundline',
      'groundline',
      BodyDef(position: Vector2(b.centerX, b.bottom - thickness / 2)),
      props: {
        ShapeProps.shape: ShapeKind.box,
        ShapeProps.width: b.width,
        ShapeProps.height: thickness,
        ShapeProps.color: BeachBallConfig.colorGroundLine,
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
        ShapeProps.radius: BeachBallConfig.ballRadius,
        ShapeProps.color: BeachBallConfig.colorBall,
        ShapeProps.spin: true,
      },
    ).createFixture(
      FixtureDef(
        CircleShape(radius: BeachBallConfig.ballRadius),
        density: BeachBallConfig.ballDensity,
        friction: 0.2,
        restitution: BeachBallConfig.ballRestitution,
      ),
    );
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (_outcome != null || _cooldown > 0) return;

    final ball = bodyOf(_ballId)!;
    if (ball.linearVelocity.y <= BeachBallConfig.mustBeFallingVy) return;

    final dx = touch.worldX - ball.position.x;
    final dy = touch.worldY - ball.position.y;
    final reach = BeachBallConfig.reachRadius;
    if (dx * dx + dy * dy > reach * reach) return;

    final aimVx = (dx * BeachBallConfig.aimFactor)
        .clamp(-BeachBallConfig.maxAimVx, BeachBallConfig.maxAimVx);
    ball.linearVelocity = Vector2(aimVx, -BeachBallConfig.bumpSpeed);

    _cooldown = BeachBallConfig.bumpCooldown;
    _saves++;
    scores.award(touch.phoneId, 1);
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    super.step(dt);
    if (_outcome != null) return;

    _cooldown = (_cooldown - dt) > 0 ? _cooldown - dt : 0;

    final ball = bodyOf(_ballId)!;
    if (ball.position.y - BeachBallConfig.ballRadius > board.bottom) {
      _outcome = GameOutcome.lost(summary: 'the ball hit the ground');
      return;
    }

    _elapsed += dt;
    if (_elapsed >= BeachBallConfig.targetSeconds) {
      _outcome = GameOutcome.won(
        summary: 'kept it up for ${BeachBallConfig.targetSeconds.round()} '
            'seconds',
      );
    }
  }

  @override
  void reset() {
    _elapsed = 0;
    _cooldown = 0;
    _saves = 0;
    _outcome = null;
    bodyOf(_ballId)!
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setTransform(_spawn, 0);
  }

  // ------------------------------------------------------------- snapshots

  int get saves => _saves;
  double get elapsed => _elapsed;

  int get _secondsLeft => (BeachBallConfig.targetSeconds - _elapsed)
      .ceil()
      .clamp(0, BeachBallConfig.targetSeconds.round());

  @override
  Map<String, Object?> get sharedState => {
    'secondsLeft': _secondsLeft,
    'target': BeachBallConfig.targetSeconds.round(),
    'saves': _saves,
  };

  @override
  GameOutcome? get outcome => _outcome;
}
