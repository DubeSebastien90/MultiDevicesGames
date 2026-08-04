import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';
import 'pitch_cars_config.dart';
import 'track.dart';

/// Flick your car around a randomized track. Turn-based: exactly one
/// player's car may be flicked at a time, in join order.
///
/// Input is gated by **proximity to the current turn's car**, never by
/// [TouchEvent.phoneId] — the board spans multiple phones, so a car can end
/// up physically under a different phone's screen than the one its owner
/// joined from. `SlingshotSim` gates its single shared bird the same way,
/// for a different reason (any phone may grab it); here the same mechanic
/// makes ownership by chip, not by device, work.
class PitchCarsSim extends Forge2DGameSim {
  PitchCarsSim(super.context, {math.Random? random})
      : _random = random ?? math.Random() {
    track = TrackGenerator.generate(
      topology: _detectTopology(context),
      board: context.board,
      random: _random,
    );
    _buildTrackEntities();
    _order = context.phoneIds;
    _placeCars();
    _preTurnPosition = carOf(currentTurn).position.clone();
    for (final id in _order) {
      _lastOnTrack[id] = carOf(id).position.clone();
      _rawProgress[id] = 0;
      _progress[id] = 0;
    }
    world.setContactListener(_CarContactListener(this));
  }

  final math.Random _random;
  late final PitchTrack track;
  late final List<String> _order;
  final _trackEntities = <Entity>[];

  late int _currentIndex = 0;
  String get currentTurn => _order[_currentIndex];

  final _lastHitBy = <String, String?>{};
  final _lastOnTrack = <String, Vector2>{};
  final _rawProgress = <String, double>{};
  final _progress = <String, double>{};
  late Vector2 _preTurnPosition;

  String? _draggingPhoneId;
  Vector2? _pull;
  bool _moving = false;
  Duration _sinceLaunch = Duration.zero;
  Duration _atRest = Duration.zero;

  String? _winner;
  bool _awarded = false;

  Body carOf(String id) => bodyOf(id)!;

  /// `Layouts.row` turns every phone by the same amount; `Layouts.circle`
  /// turns each phone differently, to face outward. Checking whether every
  /// slice shares one rotation tells the two topologies apart without any
  /// new field on `BoardContext`.
  PitchTrackTopology _detectTopology(BoardContext context) {
    final rotations = context.slices.map((s) => s.screen.turnRadians).toSet();
    return rotations.length > 1 ? PitchTrackTopology.loop : PitchTrackTopology.line;
  }

  /// Where car [index] of [_order] sits at the start line, side by side
  /// across the track's width. Shared by initial placement and [reset] so
  /// the two can never drift apart.
  Vector2 _startPositionFor(int index) {
    final maxSpread = PitchCarsConfig.trackWidthWorld - PitchCarsConfig.carRadius * 2;
    final spacing = _order.length <= 1
        ? 0.0
        : math.min(1.25, math.max(0.0, maxSpread) / (_order.length - 1));
    final start = track.pointAtArclength(0);
    final tangent = track.tangentAt(0);
    final normal = Vector2(-tangent.y, tangent.x);
    final offset = (index - (_order.length - 1) / 2) * spacing;
    return Vector2(start.x + normal.x * offset, start.y + normal.y * offset);
  }

  void _placeCars() {
    for (var i = 0; i < _order.length; i++) {
      final pos = _startPositionFor(i);
      addBody(
        _order[i],
        'car',
        BodyDef(
          type: BodyType.dynamic,
          position: pos,
          linearDamping: PitchCarsConfig.carLinearDamping,
          bullet: true,
        ),
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: PitchCarsConfig.carRadius,
          ShapeProps.color: PitchCarsConfig.carColors[i % PitchCarsConfig.carColors.length],
          ShapeProps.spin: true,
        },
      ).createFixture(
        FixtureDef(
          CircleShape(radius: PitchCarsConfig.carRadius),
          density: PitchCarsConfig.carDensity,
          friction: PitchCarsConfig.carFriction,
          restitution: PitchCarsConfig.carRestitution,
        ),
      );
    }
  }

  void _buildTrackEntities() {
    final pts = track.closed
        ? [...track.waypoints, track.waypoints.first]
        : track.waypoints;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final segLen = math.sqrt(dx * dx + dy * dy);
      if (segLen < 1e-6) continue;
      _trackEntities.add(Entity(
        descriptor: EntityDescriptor(
          id: 'trackSeg$i',
          kind: 'trackSegment',
          props: {
            ShapeProps.shape: ShapeKind.box,
            ShapeProps.width: segLen,
            ShapeProps.height: track.widthWorld,
            ShapeProps.color: PitchCarsConfig.colorTrack,
          },
        ),
        x: (a.x + b.x) / 2,
        y: (a.y + b.y) / 2,
        angle: math.atan2(dy, dx),
      ));
    }
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (_winner != null || _moving) return;
    final car = carOf(currentTurn);
    final p = Vector2(touch.worldX, touch.worldY);

    switch (touch.phase) {
      case TouchPhase.down:
        if (_draggingPhoneId != null) return;
        final reach = PitchCarsConfig.carRadius + PitchCarsConfig.grabSlack;
        if (p.distanceTo(car.position) > reach) return;
        _draggingPhoneId = touch.phoneId;
        _pull = car.position.clone();

      case TouchPhase.move:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;
        _pull = _clampPull(p);
        car.setTransform(_pull!, car.angle);

      case TouchPhase.up:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;
        _launch();
    }
  }

  Vector2 _clampPull(Vector2 p) {
    final delta = p - _preTurnPosition;
    if (delta.length > PitchCarsConfig.maxPull) {
      delta
        ..normalize()
        ..scale(PitchCarsConfig.maxPull);
    }
    return _preTurnPosition + delta;
  }

  void _launch() {
    final pullBack = _preTurnPosition - _pull!;
    _draggingPhoneId = null;
    _pull = null;
    final car = carOf(currentTurn);

    if (pullBack.length < 0.15) {
      car.setTransform(_preTurnPosition.clone(), car.angle);
      return; // a tap, not a shot — the turn is not consumed
    }

    car
      ..setTransform(_preTurnPosition.clone(), car.angle)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setAwake(true)
      ..applyLinearImpulse(pullBack * PitchCarsConfig.impulsePerPull);

    _moving = true;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    super.step(dt);
    if (_winner != null || !_moving) return;

    final elapsed = Duration(microseconds: (dt * 1e6).round());
    _sinceLaunch += elapsed;
    var maxSpeed = 0.0;
    for (final id in _order) {
      final speed = carOf(id).linearVelocity.length;
      if (speed > maxSpeed) maxSpeed = speed;
    }
    _atRest = maxSpeed < PitchCarsConfig.restSpeed ? _atRest + elapsed : Duration.zero;

    if (_atRest >= PitchCarsConfig.restDelay ||
        _sinceLaunch >= PitchCarsConfig.maxFlightTime) {
      _endTurn();
    }
  }

  void _endTurn() {
    _moving = false;
    for (final id in _order) {
      _lastHitBy[id] = null;
    }
    _currentIndex = (_currentIndex + 1) % _order.length;
    _preTurnPosition = carOf(currentTurn).position.clone();
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities sync* {
    yield* super.entities;
    yield* _trackEntities;
  }

  @override
  Map<String, Object?> get sharedState => {
        'currentTurn': _winner == null ? currentTurn : null,
        'winner': _winner,
      };

  @override
  GameOutcome? get outcome => null; // finished in Task 4

  @override
  void reset() {
    _currentIndex = 0;
    _draggingPhoneId = null;
    _pull = null;
    _moving = false;
    _winner = null;
    _awarded = false;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;
    _lastHitBy.clear();

    for (var i = 0; i < _order.length; i++) {
      final pos = _startPositionFor(i);
      final car = carOf(_order[i])
        ..setTransform(pos, 0)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0
        ..setAwake(true);
      _lastOnTrack[_order[i]] = car.position.clone();
      _rawProgress[_order[i]] = 0;
      _progress[_order[i]] = 0;
    }
    _preTurnPosition = carOf(currentTurn).position.clone();
  }
}

/// Records which car last touched which, for the off-track reset rule
/// finished in Task 4.
class _CarContactListener extends ContactListener {
  _CarContactListener(this.sim);
  final PitchCarsSim sim;

  @override
  void beginContact(Contact contact) {
    final a = contact.fixtureA.body.userData;
    final b = contact.fixtureB.body.userData;
    if (a is String && b is String && sim._order.contains(a) && sim._order.contains(b)) {
      sim._lastHitBy[a] = b;
      sim._lastHitBy[b] = a;
    }
  }

  @override
  void endContact(Contact contact) {}
  @override
  void preSolve(Contact contact, Manifold oldManifold) {}
  @override
  void postSolve(Contact contact, ContactImpulse impulse) {}
}
