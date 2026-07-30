import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import '../game/game_config.dart';
import '../model/coverage_map.dart';
import '../model/world_rect.dart';
import '../net/protocol.dart';

/// The authoritative world. Runs on the host only.
///
/// No Flutter, no Flame, no rendering: clients are render-only and this class
/// must never be able to depend on what any one screen can see. It is also
/// completely unaware of the seam — the whole point is that physics is
/// continuous and the coverage map is metadata a *game* may consult, not a
/// constraint on the simulation.
class SlingshotSim {
  SlingshotSim({required this.coverage})
    : _world = World(Vector2(0, GameConfig.gravity)) {
    _build();
  }

  final CoverageMap coverage;
  final World _world;

  WorldRect get board => coverage.board;

  final _specs = <EntitySpec>[];
  final _bodies = <String, Body>{};

  /// Where each target started, so a reset restores the tower.
  final _initialPoses = <String, ({Vector2 position, double angle})>{};

  late Vector2 _anchor;
  Vector2 get anchor => _anchor;

  int _tick = 0;
  int get tick => _tick;

  // Slingshot state.
  String? _draggingPhoneId;
  Vector2 _pull = Vector2.zero();
  bool _inFlight = false;
  Duration _sinceLaunch = Duration.zero;
  Duration _atRest = Duration.zero;

  /// Static description of every entity, sent once at start.
  List<EntitySpec> get specs => List.unmodifiable(_specs);

  static const _birdId = 'bird';

  void _build() {
    final b = board;
    _anchor = Vector2(
      b.left + b.width * GameConfig.anchorXFraction,
      b.top + b.height * GameConfig.anchorYFraction,
    );

    _addGround(b);
    _addWalls(b);
    _addBird();
    _addTargets(b);
  }

  void _addGround(WorldRect b) {
    const thickness = 1.0;
    final body = _world.createBody(
      BodyDef(position: Vector2(b.centerX, b.bottom + thickness / 2)),
    );
    body.createFixture(
      FixtureDef(PolygonShape()..setAsBoxXY(b.width / 2, thickness / 2),
          friction: 0.6),
    );
    _bodies['ground'] = body;
    _specs.add(EntitySpec(
      id: 'ground',
      shape: ShapeKind.box,
      radius: 0,
      width: b.width,
      height: thickness,
      colorValue: GameConfig.colorGround,
      role: 'ground',
    ));
  }

  /// Left and right walls keep the bird inside the board. They sit *outside* the
  /// visible area so they never read as scenery.
  void _addWalls(WorldRect b) {
    const thickness = 1.0;
    for (final (name, x) in [
      ('wallL', b.left - thickness / 2),
      ('wallR', b.right + thickness / 2),
    ]) {
      final body = _world.createBody(
        BodyDef(position: Vector2(x, b.centerY)),
      );
      body.createFixture(
        FixtureDef(
          PolygonShape()..setAsBoxXY(thickness / 2, b.height * 2),
          friction: 0.2,
          restitution: 0.3,
        ),
      );
      _bodies[name] = body;
    }
  }

  void _addBird() {
    // Static while idle so it hangs in the sling pouch instead of falling, and
    // so a drag can place it exactly under the finger. It only becomes dynamic
    // at launch.
    final body = _world.createBody(
      BodyDef(
        type: BodyType.static,
        position: _anchor.clone(),
        linearDamping: GameConfig.birdDamping,
        bullet: true,
      ),
    );
    body.createFixture(
      FixtureDef(
        CircleShape(radius: GameConfig.birdRadius),
        density: GameConfig.birdDensity,
        friction: 0.4,
        restitution: GameConfig.birdRestitution,
      ),
    );
    _bodies[_birdId] = body;
    _specs.add(EntitySpec(
      id: _birdId,
      shape: ShapeKind.circle,
      radius: GameConfig.birdRadius,
      width: 0,
      height: 0,
      colorValue: GameConfig.colorBird,
      role: 'bird',
    ));
  }

  /// A small tower near the right edge — i.e. on the *other* phone. Dynamic on
  /// purpose: several entities moving and rotating at once is a much better test
  /// of the snapshot/interpolation path than one flying circle.
  void _addTargets(WorldRect b) {
    const boxW = 0.7;
    final boxH = math.min(1.4, b.height / 4);
    final baseX = b.left + b.width * 0.82;
    final columns = [baseX, baseX + boxW * 2.4];

    var i = 0;
    for (final (colIndex, cx) in columns.indexed) {
      for (var row = 0; row < 3; row++) {
        final id = 'target$i';
        final pos = Vector2(cx, b.bottom - boxH / 2 - row * boxH * 1.02);
        final body = _world.createBody(
          BodyDef(
            type: BodyType.dynamic,
            position: pos,
            linearDamping: 0.1,
            angularDamping: 0.2,
          ),
        );
        body.createFixture(
          FixtureDef(
            PolygonShape()..setAsBoxXY(boxW / 2, boxH / 2),
            density: 0.4,
            friction: 0.5,
            restitution: 0.05,
          ),
        );
        _bodies[id] = body;
        _initialPoses[id] = (position: pos.clone(), angle: 0.0);
        _specs.add(EntitySpec(
          id: id,
          shape: ShapeKind.box,
          radius: 0,
          width: boxW,
          height: boxH,
          colorValue: colIndex.isEven
              ? GameConfig.colorTarget
              : GameConfig.colorTargetAlt,
          role: 'target',
        ));
        i++;
      }
    }
  }

  Body get _bird => _bodies[_birdId]!;

  bool get _birdIdle => !_inFlight;

  // ---------------------------------------------------------------- input

  /// A touch, already converted from that phone's local pixels to world space.
  ///
  /// The sim does not know or care which screen it came from, beyond honouring
  /// one drag at a time.
  void onTouch({
    required String phoneId,
    required double worldX,
    required double worldY,
    required String phase,
  }) {
    final p = Vector2(worldX, worldY);
    switch (phase) {
      case TouchPhase.down:
        if (!_birdIdle || _draggingPhoneId != null) return;
        final reach = GameConfig.birdRadius + GameConfig.grabSlack;
        if (p.distanceTo(_bird.position) > reach) return;
        _draggingPhoneId = phoneId;
        _pull = _clampPull(p);
        _bird.setTransform(_pull, 0);

      case TouchPhase.move:
        if (_draggingPhoneId != phoneId) return;
        _pull = _clampPull(p);
        _bird.setTransform(_pull, 0);

      case TouchPhase.up:
        if (_draggingPhoneId != phoneId) return;
        _launch();
    }
  }

  Vector2 _clampPull(Vector2 p) {
    final delta = p - _anchor;
    if (delta.length > GameConfig.maxPull) {
      delta
        ..normalize()
        ..scale(GameConfig.maxPull);
    }
    return _anchor + delta;
  }

  void _launch() {
    final pullBack = _anchor - _pull;
    _draggingPhoneId = null;

    // A tap with no meaningful pull should not fling the bird.
    if (pullBack.length < 0.15) {
      _bird.setTransform(_anchor.clone(), 0);
      return;
    }

    // Wider boards need a harder shot to cover the same fraction of them, and
    // range grows with the square of speed.
    final scale =
        math.sqrt(board.width / GameConfig.referenceBoardWidth);

    _bird
      ..setType(BodyType.dynamic)
      ..setTransform(_pull.clone(), 0)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setAwake(true)
      ..applyLinearImpulse(pullBack * (GameConfig.impulsePerPull * scale));

    _inFlight = true;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;
  }

  /// Put the bird back in the pouch and stand the tower back up.
  void reset() {
    _draggingPhoneId = null;
    _inFlight = false;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;

    _bird
      ..setType(BodyType.static)
      ..setTransform(_anchor.clone(), 0)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
    _pull = _anchor.clone();

    for (final entry in _initialPoses.entries) {
      final body = _bodies[entry.key]!;
      body
        ..setTransform(entry.value.position.clone(), entry.value.angle)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0
        ..setAwake(true);
    }
  }

  // ----------------------------------------------------------------- step

  void step(double dt) {
    _world.stepDt(dt);
    _tick++;

    if (_inFlight) {
      final elapsed = Duration(microseconds: (dt * 1e6).round());
      _sinceLaunch += elapsed;

      final speed = _bird.linearVelocity.length;
      _atRest = speed < GameConfig.restSpeed ? _atRest + elapsed : Duration.zero;

      if (_atRest >= GameConfig.restDelay ||
          _sinceLaunch >= GameConfig.maxFlightTime ||
          _isLost(_bird.position)) {
        reset();
      }
    }
  }

  bool _isLost(Vector2 p) {
    final b = board.inflate(GameConfig.outOfBoundsMargin);
    return !b.contains(p.x, p.y);
  }

  // ------------------------------------------------------------ snapshots

  /// Everything a client needs for this instant. Static scenery is included so a
  /// client that joins mid-game (or a phone whose slice only contains ground)
  /// still has something to draw.
  List<EntityState> entityStates() {
    final out = <EntityState>[];
    for (final spec in _specs) {
      final body = _bodies[spec.id];
      if (body == null) continue;
      final v = body.linearVelocity;
      out.add(EntityState(
        id: spec.id,
        x: body.position.x,
        y: body.position.y,
        angle: body.angle,
        vx: v.x,
        vy: v.y,
      ));
    }
    return out;
  }

  SlingState slingState() => SlingState(
    active: _draggingPhoneId != null,
    anchorX: _anchor.x,
    anchorY: _anchor.y,
    pullX: _draggingPhoneId != null ? _pull.x : _anchor.x,
    pullY: _draggingPhoneId != null ? _pull.y : _anchor.y,
    draggingPhoneId: _draggingPhoneId,
  );
}
