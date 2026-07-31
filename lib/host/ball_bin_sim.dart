import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import '../game/game_config.dart';
import '../game/mini_game.dart';
import '../model/coverage_map.dart';
import '../model/world_rect.dart';
import '../net/protocol.dart';

/// Balls fall down a tall board; you slide a bin along the bottom to catch
/// them. Ten caught wins.
///
/// The board here is a stack — one phone wide, several tall — so a ball spawned
/// on the top phone falls through every seam on its way down. Same trick as the
/// slingshot, rotated ninety degrees: the sim knows nothing about seams, and the
/// ball's position through the dead millimetres is whatever momentum says.
class BallBinSim implements MiniGameSim {
  BallBinSim({required this.coverage, math.Random? random})
    : _world = World(Vector2(0, BinConfig.gravity)),
      _random = random ?? math.Random() {
    _build();
  }

  final CoverageMap coverage;
  final World _world;
  final math.Random _random;

  WorldRect get board => coverage.board;

  final _specs = <EntitySpec>[];
  final _bodies = <String, Body>{};

  /// Ball ids currently in play. A ball not in here is parked and invisible:
  /// it is left out of [entityStates], and the renderer draws only what a
  /// snapshot mentions.
  final _live = <String>{};

  /// Parked ball ids, ready to be reused. Bodies are created once and recycled
  /// so nothing is destroyed mid-step.
  final _idle = <String>[];

  int _tick = 0;
  int _caught = 0;
  Duration _sinceSpawn = Duration.zero;

  String? _draggingPhoneId;

  /// Where the bin is heading — the x the finger last asked for.
  late double _binTargetX;
  late double _binX;
  late double _binFloorY;

  static const _binId = 'bin';

  @override
  int get tick => _tick;

  @override
  bool get won => _caught >= BinConfig.goal;

  @override
  List<EntitySpec> get specs => List.unmodifiable(_specs);

  @override
  GameProgress? get progress => GameProgress(
    value: _caught,
    goal: BinConfig.goal,
    label: 'caught',
  );

  @override
  Map<String, dynamic> worldInitExtras() => {
    'goal': BinConfig.goal,
    'binWidth': BinConfig.binWidth,
  };

  // ----------------------------------------------------------------- build

  void _build() {
    final b = board;
    _binFloorY = b.bottom - BinConfig.binBottomMargin;
    _binX = b.centerX;
    _binTargetX = _binX;

    _addWalls(b);
    _addFloor(b);
    _addBin();
    _addBallPool();
  }

  /// Left and right walls, just outside the visible area, so a ball that drifts
  /// sideways comes back rather than escaping down the side.
  void _addWalls(WorldRect b) {
    const thickness = 1.0;
    for (final (name, x) in [
      ('wallL', b.left - thickness / 2),
      ('wallR', b.right + thickness / 2),
    ]) {
      final body = _world.createBody(BodyDef(position: Vector2(x, b.centerY)));
      body.createFixture(
        FixtureDef(
          PolygonShape()..setAsBoxXY(thickness / 2, b.height),
          friction: 0.1,
          restitution: 0.2,
        ),
      );
      _bodies[name] = body;
    }
  }

  /// The miss line. Drawn, because a ball hitting it is the moment you know you
  /// were too slow.
  void _addFloor(WorldRect b) {
    const thickness = 0.6;
    final body = _world.createBody(
      BodyDef(position: Vector2(b.centerX, b.bottom + thickness / 2)),
    );
    body.createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(b.width / 2, thickness / 2),
        friction: 0.7,
      ),
    );
    _bodies['floor'] = body;
    _specs.add(EntitySpec(
      id: 'floor',
      shape: ShapeKind.box,
      radius: 0,
      width: b.width,
      height: thickness,
      colorValue: BinConfig.colorFloor,
      role: 'ground',
    ));
  }

  /// The bin is a kinematic U: a floor and two walls that balls really bounce
  /// off. Kinematic rather than dynamic so a caught ball cannot shove it around,
  /// and so its position is exactly what the player asked for.
  void _addBin() {
    const w = BinConfig.binWidth;
    const h = BinConfig.binHeight;
    const t = BinConfig.binWallThickness;

    final body = _world.createBody(
      BodyDef(
        type: BodyType.kinematic,
        position: Vector2(_binX, _binFloorY),
      ),
    );

    // Floor, then the two rims. Offsets are relative to the body origin, which
    // sits at the middle of the bin's floor.
    body.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(w / 2, t / 2, Vector2(0, 0), 0),
        friction: 0.6,
        restitution: 0.05,
      ),
    );
    for (final side in [-1.0, 1.0]) {
      body.createFixture(
        FixtureDef(
          PolygonShape()
            ..setAsBox(t / 2, h / 2, Vector2(side * (w / 2 - t / 2), -h / 2), 0),
          friction: 0.4,
          restitution: 0.15,
        ),
      );
    }

    _bodies[_binId] = body;
    // Drawn as one box the size of the whole bin: the renderer has no notion of
    // multi-fixture bodies, and a solid trough reads better than three bars.
    _specs.add(EntitySpec(
      id: _binId,
      shape: ShapeKind.box,
      radius: 0,
      width: w,
      height: h,
      colorValue: BinConfig.colorBin,
      role: 'bin',
    ));
  }

  /// Every ball that can ever exist, created once and parked off-board.
  ///
  /// Box2D dislikes bodies being destroyed inside a step, and the protocol
  /// sends the entity list once — recycling a fixed pool sidesteps both.
  void _addBallPool() {
    for (var i = 0; i < BinConfig.maxLiveBalls; i++) {
      final id = 'ball$i';
      final body = _world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: _parkingSpot,
          bullet: true,
        ),
      );
      body.createFixture(
        FixtureDef(
          CircleShape(radius: BinConfig.ballRadius),
          density: BinConfig.ballDensity,
          friction: 0.3,
          restitution: BinConfig.ballRestitution,
        ),
      );
      body.setActive(false);
      _bodies[id] = body;
      _idle.add(id);
      _specs.add(EntitySpec(
        id: id,
        shape: ShapeKind.circle,
        radius: BinConfig.ballRadius,
        width: 0,
        height: 0,
        colorValue:
            i.isEven ? BinConfig.colorBall : BinConfig.colorBallAlt,
        role: 'ball',
      ));
    }
  }

  /// Well outside the board, where an inactive ball waits its turn.
  Vector2 get _parkingSpot => Vector2(board.left - 50, board.top - 50);

  // ----------------------------------------------------------------- input

  @override
  void onTouch({
    required String phoneId,
    required double worldX,
    required double worldY,
    required String phase,
  }) {
    switch (phase) {
      case TouchPhase.down:
        // Grab anywhere on the bin, generously — including a little above the
        // rim, because that is where a thumb naturally lands.
        final withinX = (worldX - _binX).abs() <=
            BinConfig.binWidth / 2 + BinConfig.binGrabSlack;
        final withinY = worldY >= _binFloorY - BinConfig.binHeight -
                BinConfig.binGrabSlack &&
            worldY <= _binFloorY + BinConfig.binGrabSlack;
        if (!withinX || !withinY) return;
        if (_draggingPhoneId != null) return;
        _draggingPhoneId = phoneId;
        _binTargetX = _clampBinX(worldX);

      case TouchPhase.move:
        if (_draggingPhoneId != phoneId) return;
        _binTargetX = _clampBinX(worldX);

      case TouchPhase.up:
        if (_draggingPhoneId != phoneId) return;
        _draggingPhoneId = null;
    }
  }

  double _clampBinX(double x) {
    final half = BinConfig.binWidth / 2;
    return x.clamp(board.left + half, board.right - half);
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    _moveBin(dt);
    _world.stepDt(dt);
    _tick++;

    if (!won) {
      _sinceSpawn += Duration(microseconds: (dt * 1e6).round());
      if (_sinceSpawn >= _currentSpawnGap && _idle.isNotEmpty) {
        _sinceSpawn = Duration.zero;
        _spawnBall();
      }
    }

    _collect();
  }

  /// Chase the finger at a fixed speed rather than snapping. Kinematic bodies
  /// move by velocity, which also means a ball resting on the floor is carried
  /// along instead of being teleported through.
  void _moveBin(double dt) {
    final body = _bodies[_binId]!;
    final delta = _binTargetX - _binX;
    final maxStep = BinConfig.binSpeed * dt;
    final move = delta.abs() <= maxStep ? delta : maxStep * delta.sign;
    _binX += move;
    body
      ..linearVelocity = Vector2(dt > 0 ? move / dt : 0, 0)
      ..setTransform(Vector2(_binX, _binFloorY), 0);
  }

  Duration get _currentSpawnGap {
    // Ramp from the opening pace to the fastest by [rampFraction] of the goal.
    final t = (_caught / (BinConfig.goal * BinConfig.rampFraction))
        .clamp(0.0, 1.0);
    final ms = BinConfig.spawnGap.inMilliseconds +
        (BinConfig.minSpawnGap.inMilliseconds -
                BinConfig.spawnGap.inMilliseconds) *
            t;
    return Duration(milliseconds: ms.round());
  }

  void _spawnBall() {
    final id = _idle.removeAt(0);
    final body = _bodies[id]!;

    final inset = board.width * BinConfig.spawnInset;
    final x = board.left +
        inset +
        _random.nextDouble() * (board.width - inset * 2);

    body
      ..setActive(true)
      ..setTransform(Vector2(x, board.top + BinConfig.ballRadius * 2), 0)
      ..linearVelocity = Vector2(0, 0)
      ..angularVelocity = (_random.nextDouble() - 0.5) * 2
      ..setAwake(true);
    _live.add(id);
  }

  /// Score the balls that made it into the bin, and retire the ones that did
  /// not. Both happen *after* the step, never inside a callback.
  void _collect() {
    if (_live.isEmpty) return;

    final mouthLeft = _binX - BinConfig.binWidth / 2;
    final mouthRight = _binX + BinConfig.binWidth / 2;
    final mouthTop = _binFloorY - BinConfig.binHeight;

    for (final id in _live.toList()) {
      final body = _bodies[id]!;
      final p = body.position;

      final inBin = p.x > mouthLeft &&
          p.x < mouthRight &&
          p.y > mouthTop &&
          p.y < _binFloorY;
      if (inBin) {
        _caught++;
        _retire(id);
        continue;
      }

      // Past the bin, or somehow out of the world: a miss, no penalty beyond
      // the ball you did not get.
      if (p.y > board.bottom + 2 || !p.y.isFinite || !p.x.isFinite) {
        _retire(id);
      }
    }
  }

  void _retire(String id) {
    final body = _bodies[id]!;
    body
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setTransform(_parkingSpot, 0)
      ..setActive(false);
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
    _bodies[_binId]!
      ..linearVelocity = Vector2.zero()
      ..setTransform(Vector2(_binX, _binFloorY), 0);
  }

  // ------------------------------------------------------------- snapshots

  @override
  List<EntityState> entityStates() {
    final out = <EntityState>[];
    for (final spec in _specs) {
      // A parked ball is left out entirely; that absence is what makes it
      // disappear on every screen at once.
      if (spec.role == 'ball' && !_live.contains(spec.id)) continue;
      final body = _bodies[spec.id];
      if (body == null) continue;

      // The bin body's origin is the middle of its floor, but it is drawn as a
      // full-height box — so report the centre of that box.
      final isBin = spec.id == _binId;
      final v = body.linearVelocity;
      out.add(EntityState(
        id: spec.id,
        x: body.position.x,
        y: isBin ? body.position.y - BinConfig.binHeight / 2 : body.position.y,
        angle: body.angle,
        vx: v.x,
        vy: v.y,
      ));
    }
    return out;
  }

  @override
  SlingState? slingState() => null;
}
