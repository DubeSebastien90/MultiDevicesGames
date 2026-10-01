import 'package:forge2d/forge2d.dart';

import '../model/world_rect.dart';
import '../contract/entity.dart';
import '../contract/sim.dart';
import '../score/scoreboard.dart';

abstract class Forge2DGameSim implements GameSim {
  Forge2DGameSim(this.context, {Vector2? gravity})
    : world = World(gravity ?? Vector2.zero());

  final BoardContext context;
  final World world;

  final _bodies = <String, Body>{};
  final _descriptors = <String, EntityDescriptor>{};

  final _hidden = <String>{};

  int _tick = 0;

  WorldRect get board => context.board;
  Scoreboard get scores => context.scores;
  int get tick => _tick;

  Body addBody(
    String id,
    String kind,
    BodyDef def, {
    Map<String, Object?> props = const {},
    bool visible = true,
  }) {
    assert(!_bodies.containsKey(id), 'entity "$id" already exists');
    final body = world.createBody(def)..userData = id;
    _bodies[id] = body;
    _descriptors[id] = EntityDescriptor(id: id, kind: kind, props: props);
    if (!visible) _hidden.add(id);
    return body;
  }

  Body? bodyOf(String id) => _bodies[id];

  void hide(String id) {
    if (!_hidden.add(id)) return;
    _bodies[id]?.setActive(false);
  }

  void show(String id) {
    if (!_hidden.remove(id)) return;
    _bodies[id]?.setActive(true);
  }

  bool isHidden(String id) => _hidden.contains(id);

  Iterable<String> get visibleIds =>
      _descriptors.keys.where((id) => !_hidden.contains(id));

  @override
  Iterable<Entity> get entities sync* {
    for (final entry in _descriptors.entries) {
      if (_hidden.contains(entry.key)) continue;
      final body = _bodies[entry.key];
      if (body == null) continue;
      final v = body.linearVelocity;
      yield Entity(
        descriptor: entry.value,
        x: body.position.x,
        y: body.position.y,
        angle: body.angle,
        vx: v.x,
        vy: v.y,
      );
    }
  }

  @override
  void step(double dt) {
    world.stepDt(dt);
    _tick++;
  }

  @override
  Map<String, Object?> get sharedState => const {};

  @override
  void dispose() {}

  void addBoundaryWalls({
    double thickness = 1.0,
    double restitution = 0.3,
    double friction = 0.2,
    bool top = false,
    bool bottom = false,
    bool left = true,
    bool right = true,
  }) {
    final b = board;
    void wall(String name, double x, double y, double hw, double hh) {
      final body = world.createBody(BodyDef(position: Vector2(x, y)))
        ..userData = name;
      body.createFixture(
        FixtureDef(
          PolygonShape()..setAsBoxXY(hw, hh),
          friction: friction,
          restitution: restitution,
        ),
      );
    }

    if (left) {
      wall('wallL', b.left - thickness / 2, b.centerY, thickness / 2, b.height);
    }
    if (right) {
      wall(
        'wallR',
        b.right + thickness / 2,
        b.centerY,
        thickness / 2,
        b.height,
      );
    }
    if (top) {
      wall('wallT', b.centerX, b.top - thickness / 2, b.width, thickness / 2);
    }
    if (bottom) {
      wall(
        'wallB',
        b.centerX,
        b.bottom + thickness / 2,
        b.width,
        thickness / 2,
      );
    }
  }
}
