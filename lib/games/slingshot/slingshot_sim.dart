import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import 'slingshot_config.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';

/// Pull the bird back, let go, hit the tower.
///
/// Completely unaware of the seam: physics is continuous, and the bird's
/// position through the dead millimetres between two phones is whatever
/// momentum says it is.
class SlingshotSim extends Forge2DGameSim {
  SlingshotSim(super.context)
    : super(gravity: Vector2(0, SlingshotConfig.gravity)) {
    final b = board;
    _anchor = Vector2(
      b.left + b.width * SlingshotConfig.anchorXFraction,
      b.top + b.height * SlingshotConfig.anchorYFraction,
    );
    _pull = _anchor.clone();

    _addGround();
    addBoundaryWalls();
    _addBird();
    _addTargets();

    // The whole win condition: the bird touching the tower. A contact listener
    // catches the graze that barely nudges a box as surely as the shot that
    // flattens it, which polling positions afterwards would not.
    world.setContactListener(_BirdHitListener(() => _won = true));
  }

  static const _birdId = 'bird';
  static const _pouchId = 'pouch';
  static const _targetTag = 'target';

  late final Vector2 _anchor;
  late Vector2 _pull;

  /// Where each target started, so a reset stands the tower back up.
  final _initialPoses = <String, ({Vector2 position, double angle})>{};

  String? _draggingPhoneId;
  bool _inFlight = false;
  bool _won = false;
  Duration _sinceLaunch = Duration.zero;
  Duration _atRest = Duration.zero;

  Body get _bird => bodyOf(_birdId)!;

  // ----------------------------------------------------------------- build

  void _addGround() {
    final b = board;
    const thickness = 1.0;
    addBody(
      'ground',
      'ground',
      BodyDef(position: Vector2(b.centerX, b.bottom + thickness / 2)),
      props: {
        ShapeProps.shape: ShapeKind.box,
        ShapeProps.width: b.width,
        ShapeProps.height: thickness,
        ShapeProps.color: SlingshotConfig.colorGround,
      },
    ).createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(b.width / 2, thickness / 2),
        friction: 0.6,
      ),
    );
  }

  void _addBird() {
    // Static while idle so it hangs in the pouch instead of falling, and so a
    // drag can place it exactly under the finger. It becomes dynamic at launch.
    addBody(
      _birdId,
      'bird',
      BodyDef(
        type: BodyType.static,
        position: _anchor.clone(),
        linearDamping: SlingshotConfig.birdDamping,
        bullet: true,
      ),
      props: {
        ShapeProps.shape: ShapeKind.circle,
        ShapeProps.radius: SlingshotConfig.birdRadius,
        ShapeProps.color: SlingshotConfig.colorBird,
        ShapeProps.spin: true,
      },
    ).createFixture(
      FixtureDef(
        CircleShape(radius: SlingshotConfig.birdRadius),
        density: SlingshotConfig.birdDensity,
        friction: 0.4,
        restitution: SlingshotConfig.birdRestitution,
      ),
    );
  }

  /// A small tower near the far edge — on the *other* phone. Dynamic on
  /// purpose: several bodies moving and rotating at once is a much better test
  /// of the snapshot path than one flying circle.
  void _addTargets() {
    final b = board;
    const boxW = 0.7;
    final boxH = math.min(1.4, b.height / 4);
    final baseX = b.left + b.width * 0.82;
    final columns = [baseX, baseX + boxW * 2.4];

    var i = 0;
    for (final (colIndex, cx) in columns.indexed) {
      for (var row = 0; row < 3; row++) {
        final id = 'target$i';
        final pos = Vector2(cx, b.bottom - boxH / 2 - row * boxH * 1.02);
        final body = addBody(
          id,
          _targetTag,
          BodyDef(
            type: BodyType.dynamic,
            position: pos,
            linearDamping: 0.1,
            angularDamping: 0.2,
          ),
          props: {
            ShapeProps.shape: ShapeKind.box,
            ShapeProps.width: boxW,
            ShapeProps.height: boxH,
            ShapeProps.color: colIndex.isEven
                ? SlingshotConfig.colorTarget
                : SlingshotConfig.colorTargetAlt,
          },
        );
        body.createFixture(
          FixtureDef(
            PolygonShape()..setAsBoxXY(boxW / 2, boxH / 2),
            density: 0.4,
            friction: 0.5,
            restitution: 0.05,
          ),
        );
        _initialPoses[id] = (position: pos.clone(), angle: 0.0);
        i++;
      }
    }
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    final p = Vector2(touch.worldX, touch.worldY);
    switch (touch.phase) {
      case TouchPhase.down:
        if (_inFlight || _won || _draggingPhoneId != null) return;
        final reach = SlingshotConfig.birdRadius + SlingshotConfig.grabSlack;
        if (p.distanceTo(_bird.position) > reach) return;
        _draggingPhoneId = touch.phoneId;
        _pull = _clampPull(p);
        _bird.setTransform(_pull, 0);

      case TouchPhase.move:
        if (_draggingPhoneId != touch.phoneId) return;
        _pull = _clampPull(p);
        _bird.setTransform(_pull, 0);

      case TouchPhase.up:
        if (_draggingPhoneId != touch.phoneId) return;
        _launch();
    }
  }

  Vector2 _clampPull(Vector2 p) {
    final delta = p - _anchor;
    if (delta.length > SlingshotConfig.maxPull) {
      delta
        ..normalize()
        ..scale(SlingshotConfig.maxPull);
    }
    return _anchor + delta;
  }

  void _launch() {
    final pullBack = _anchor - _pull;
    _draggingPhoneId = null;

    // A tap with no meaningful pull should not fling the bird.
    if (pullBack.length < 0.15) {
      _bird.setTransform(_anchor.clone(), 0);
      _pull = _anchor.clone();
      return;
    }

    // Wider boards need a harder shot to cover the same fraction of them, and
    // range grows with the square of speed.
    final scale = math.sqrt(board.width / SlingshotConfig.referenceBoardWidth);

    _bird
      ..setType(BodyType.dynamic)
      ..setTransform(_pull.clone(), 0)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setAwake(true)
      ..applyLinearImpulse(pullBack * (SlingshotConfig.impulsePerPull * scale));

    _inFlight = true;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    super.step(dt);

    // Once the tower has been hit the round is over: let the boxes finish
    // tumbling on screen, but never yank the bird back for another go.
    if (_won) return;

    if (_inFlight) {
      final elapsed = Duration(microseconds: (dt * 1e6).round());
      _sinceLaunch += elapsed;

      final speed = _bird.linearVelocity.length;
      _atRest = speed < SlingshotConfig.restSpeed ? _atRest + elapsed : Duration.zero;

      if (_atRest >= SlingshotConfig.restDelay ||
          _sinceLaunch >= SlingshotConfig.maxFlightTime ||
          _isLost(_bird.position)) {
        reset();
      }
    }
  }

  bool _isLost(Vector2 p) {
    final b = board.inflate(SlingshotConfig.outOfBoundsMargin);
    return !b.contains(p.x, p.y);
  }

  @override
  void reset() {
    _draggingPhoneId = null;
    _inFlight = false;
    _won = false;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;

    _bird
      ..setType(BodyType.static)
      ..setTransform(_anchor.clone(), 0)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
    _pull = _anchor.clone();

    for (final entry in _initialPoses.entries) {
      bodyOf(entry.key)!
        ..setTransform(entry.value.position.clone(), entry.value.angle)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0
        ..setAwake(true);
    }
  }

  // ------------------------------------------------------------- snapshots

  /// The pouch is an ordinary entity, which is the whole trick.
  ///
  /// The band has to move in lockstep with the bird — draw them from different
  /// clocks and the rubber visibly lags the thing it is flinging. Making the
  /// pouch an entity puts it on the same interpolated timeline as everything
  /// else, for free, and needed no support from the platform at all.
  @override
  Iterable<Entity> get entities sync* {
    yield* super.entities;
    yield Entity(
      descriptor: const EntityDescriptor(
        id: _pouchId,
        kind: 'pouch',
        props: {},
      ),
      x: _pull.x,
      y: _pull.y,
    );
  }

  @override
  Map<String, Object?> get sharedState => {
    'anchorX': _anchor.x,
    'anchorY': _anchor.y,
    'dragging': _draggingPhoneId,
  };

  @override
  GameOutcome? get outcome =>
      _won ? const GameOutcome.won(summary: 'the tower fell') : null;
}

/// Fires the first time the bird touches a tower box.
class _BirdHitListener extends ContactListener {
  _BirdHitListener(this.onHit);

  final void Function() onHit;

  @override
  void beginContact(Contact contact) {
    final a = contact.fixtureA.body.userData;
    final b = contact.fixtureB.body.userData;
    final hit = (a == SlingshotSim._birdId && _isTarget(b)) ||
        (b == SlingshotSim._birdId && _isTarget(a));
    if (hit) onHit();
  }

  static bool _isTarget(Object? userData) =>
      userData is String && userData.startsWith('target');

  @override
  void endContact(Contact contact) {}

  @override
  void preSolve(Contact contact, Manifold oldManifold) {}

  @override
  void postSolve(Contact contact, ContactImpulse impulse) {}
}
