import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import 'ball_bin_config.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';

/// Balls fall down a tall board; slide the bin along the bottom to catch them.
///
/// The same seam trick as the slingshot, turned ninety degrees: a ball spawned
/// on the top phone falls through every gap on its way down, and the sim never
/// learns that the gaps exist.
///
/// This is also the project's first per-phone scoring. A catch is credited to
/// whichever phone the bin was standing on, which is the question
/// [BoardContext.phoneAt] exists to answer.
class BallBinSim extends Forge2DGameSim {
  BallBinSim(super.context, {math.Random? random})
    : _random = random ?? math.Random(),
      super(gravity: Vector2(0, BallBinConfig.gravity)) {
    _binFloorY = board.bottom - BallBinConfig.binBottomMargin;
    _binX = board.centerX;
    _binTargetX = _binX;

    addBoundaryWalls();
    _addFloor();
    _addBin();
    _addBallPool();
  }

  static const _binId = 'bin';

  final math.Random _random;

  /// Ball ids currently falling. A ball not in here is parked and hidden.
  final _live = <String>{};

  /// Parked ball ids, ready to be reused. Bodies are created once and recycled,
  /// so nothing is created or destroyed mid-step.
  final _idle = <String>[];

  int _caught = 0;
  Duration _sinceSpawn = Duration.zero;
  String? _draggingPhoneId;

  late double _binX;
  late double _binTargetX;
  late double _binFloorY;

  // ----------------------------------------------------------------- build

  /// The miss line. Drawn, because a ball hitting it is the moment you know
  /// you were too slow.
  void _addFloor() {
    final b = board;
    const thickness = 0.6;
    addBody(
      'floor',
      'ground',
      BodyDef(position: Vector2(b.centerX, b.bottom + thickness / 2)),
      props: {
        ShapeProps.shape: ShapeKind.box,
        ShapeProps.width: b.width,
        ShapeProps.height: thickness,
        ShapeProps.color: BallBinConfig.colorFloor,
      },
    ).createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(b.width / 2, thickness / 2),
        friction: 0.7,
      ),
    );
  }

  /// A kinematic U that balls really bounce off.
  ///
  /// Kinematic rather than dynamic so a caught ball cannot shove it around, and
  /// so its position is exactly what the player asked for. The body origin is
  /// the *centre* of the trough, so the entity transform is what a renderer
  /// wants without any correction.
  void _addBin() {
    const w = BallBinConfig.binWidth;
    const h = BallBinConfig.binHeight;
    const t = BallBinConfig.binWallThickness;

    final body = addBody(
      _binId,
      'bin',
      BodyDef(
        type: BodyType.kinematic,
        position: Vector2(_binX, _binFloorY - h / 2),
      ),
      props: {
        ShapeProps.shape: ShapeKind.box,
        ShapeProps.width: w,
        ShapeProps.height: h,
        ShapeProps.color: BallBinConfig.colorBin,
      },
    );

    // Floor across the bottom, then the two rims, all relative to the centre.
    body.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(w / 2, t / 2, Vector2(0, h / 2 - t / 2), 0),
        friction: 0.6,
        restitution: 0.05,
      ),
    );
    for (final side in [-1.0, 1.0]) {
      body.createFixture(
        FixtureDef(
          PolygonShape()
            ..setAsBox(t / 2, h / 2, Vector2(side * (w / 2 - t / 2), 0), 0),
          friction: 0.4,
          restitution: 0.15,
        ),
      );
    }
  }

  /// Every ball that can ever exist, created once and parked.
  ///
  /// Box2D dislikes bodies being destroyed inside a step, and a fixed pool
  /// sidesteps that entirely — a parked ball is simply hidden, and the platform
  /// stops mentioning it in snapshots.
  void _addBallPool() {
    for (var i = 0; i < BallBinConfig.maxLiveBalls; i++) {
      final id = 'ball$i';
      addBody(
        id,
        'ball',
        BodyDef(
          type: BodyType.dynamic,
          position: _parkingSpot,
          bullet: true,
        ),
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: BallBinConfig.ballRadius,
          ShapeProps.color:
              i.isEven ? BallBinConfig.colorBall : BallBinConfig.colorBallAlt,
          ShapeProps.spin: true,
        },
        visible: false,
      ).createFixture(
        FixtureDef(
          CircleShape(radius: BallBinConfig.ballRadius),
          density: BallBinConfig.ballDensity,
          friction: 0.3,
          restitution: BallBinConfig.ballRestitution,
        ),
      );
      _idle.add(id);
    }
  }

  Vector2 get _parkingSpot => Vector2(board.left - 50, board.top - 50);

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    switch (touch.phase) {
      case TouchPhase.down:
        // Grab anywhere on the bin, generously — including a little above the
        // rim, because that is where a thumb naturally lands.
        final withinX = (touch.worldX - _binX).abs() <=
            BallBinConfig.binWidth / 2 + BallBinConfig.binGrabSlack;
        final withinY = touch.worldY >=
                _binFloorY - BallBinConfig.binHeight - BallBinConfig.binGrabSlack &&
            touch.worldY <= _binFloorY + BallBinConfig.binGrabSlack;
        if (!withinX || !withinY || _draggingPhoneId != null) return;
        _draggingPhoneId = touch.phoneId;
        _binTargetX = _clampBinX(touch.worldX);

      case TouchPhase.move:
        if (_draggingPhoneId != touch.phoneId) return;
        _binTargetX = _clampBinX(touch.worldX);

      case TouchPhase.up:
        if (_draggingPhoneId != touch.phoneId) return;
        _draggingPhoneId = null;
    }
  }

  double _clampBinX(double x) {
    final half = BallBinConfig.binWidth / 2;
    return x.clamp(board.left + half, board.right - half);
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    _moveBin(dt);
    super.step(dt);

    if (outcome == null) {
      _sinceSpawn += Duration(microseconds: (dt * 1e6).round());
      if (_sinceSpawn >= _currentSpawnGap && _idle.isNotEmpty) {
        _sinceSpawn = Duration.zero;
        _spawnBall();
      }
    }

    _collect();
  }

  /// Chase the finger at a fixed speed rather than snapping. Kinematic bodies
  /// move by velocity, so a ball resting in the trough is carried along instead
  /// of being teleported through the wall.
  void _moveBin(double dt) {
    final body = bodyOf(_binId)!;
    final delta = _binTargetX - _binX;
    final maxStep = BallBinConfig.binSpeed * dt;
    final move = delta.abs() <= maxStep ? delta : maxStep * delta.sign;
    _binX += move;
    body
      ..linearVelocity = Vector2(dt > 0 ? move / dt : 0, 0)
      ..setTransform(
        Vector2(_binX, _binFloorY - BallBinConfig.binHeight / 2),
        0,
      );
  }

  Duration get _currentSpawnGap {
    final t = (_caught / (BallBinConfig.goal * BallBinConfig.rampFraction))
        .clamp(0.0, 1.0);
    final ms = BallBinConfig.spawnGap.inMilliseconds +
        (BallBinConfig.minSpawnGap.inMilliseconds -
                BallBinConfig.spawnGap.inMilliseconds) *
            t;
    return Duration(milliseconds: ms.round());
  }

  void _spawnBall() {
    final id = _idle.removeAt(0);
    final inset = board.width * BallBinConfig.spawnInset;
    final x =
        board.left + inset + _random.nextDouble() * (board.width - inset * 2);

    show(id);
    bodyOf(id)!
      ..setTransform(Vector2(x, board.top + BallBinConfig.ballRadius * 2), 0)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = (_random.nextDouble() - 0.5) * 2
      ..setAwake(true);
    _live.add(id);
  }

  /// Score the balls that made it in, retire the ones that did not. Both
  /// happen *after* the step, never inside a physics callback.
  void _collect() {
    if (_live.isEmpty) return;

    final mouthLeft = _binX - BallBinConfig.binWidth / 2;
    final mouthRight = _binX + BallBinConfig.binWidth / 2;
    final mouthTop = _binFloorY - BallBinConfig.binHeight;

    for (final id in _live.toList()) {
      final p = bodyOf(id)!.position;

      final inBin = p.x > mouthLeft &&
          p.x < mouthRight &&
          p.y > mouthTop &&
          p.y < _binFloorY;
      if (inBin) {
        _caught++;
        // Credit whoever's screen the bin was standing on. In a gap between
        // screens, the nearest one takes it — a ball caught over a bezel still
        // belongs to somebody.
        final owner = context.phoneAt(_binX, _binFloorY) ??
            context.nearestPhone(_binX, _binFloorY);
        if (owner != null) scores.award(owner, 1);
        _retire(id);
        continue;
      }

      if (p.y > board.bottom + 2 || !p.y.isFinite || !p.x.isFinite) {
        _retire(id);
      }
    }
  }

  void _retire(String id) {
    bodyOf(id)!
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setTransform(_parkingSpot, 0);
    hide(id);
    _live.remove(id);
    _idle.add(id);
  }

  @override
  void reset() {
    for (final id in _live.toList()) {
      _retire(id);
    }
    _caught = 0;
    _sinceSpawn = Duration.zero;
    _draggingPhoneId = null;
    _binX = board.centerX;
    _binTargetX = _binX;
    bodyOf(_binId)!
      ..linearVelocity = Vector2.zero()
      ..setTransform(
        Vector2(_binX, _binFloorY - BallBinConfig.binHeight / 2),
        0,
      );
  }

  // ------------------------------------------------------------- snapshots

  int get caught => _caught;

  @override
  Map<String, Object?> get sharedState => {
    'caught': _caught,
    'goal': BallBinConfig.goal,
  };

  @override
  GameOutcome? get outcome => _caught >= BallBinConfig.goal
      ? GameOutcome.won(summary: '$_caught caught')
      : null;
}
