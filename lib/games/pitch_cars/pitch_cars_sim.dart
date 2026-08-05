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
      final pos = carOf(id).position;
      _lastOnTrack[id] = pos.clone();
      _rawProgress[id] = track.progressAt(pos.x, pos.y);
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
  final _lastHitAt = <String, Duration>{};
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

  /// Where car [index] of [_order] sits on the starting grid. Shared by
  /// initial placement and [reset] so the two can never drift apart.
  ///
  /// A staggered two-lane grid, not one row across the ribbon: the track is
  /// only [PitchCarsConfig.trackWidthWorld] wide, so four cars abreast would
  /// have to sit closer than their own diameter (spawning *overlapping*, which
  /// Forge2D then resolves with a shove and a spurious contact event) and
  /// would put the outer two hard against the track edge, where a shot has no
  /// room to deviate before going off. Two lanes, several rows deep, keeps
  /// every car a comfortable distance from both its neighbours and the edge.
  Vector2 _startPositionFor(int index) {
    final lane = index.isEven ? -1 : 1;
    final row = index ~/ 2;
    final arc = row * PitchCarsConfig.startRowSpacingWorld;
    final start = track.pointAtArclength(arc);
    final tangent = track.tangentAt(arc);
    final normal = Vector2(-tangent.y, tangent.x);
    final offset = lane * PitchCarsConfig.startLaneOffsetWorld;
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
    // The hit ledger is timestamped against `_sinceLaunch`, which restarts
    // here — so any contact recorded during the idle window between the last
    // `_endTurn` and this launch (the pull-back `setTransform` nudging a
    // neighbour at the packed start line, say) would otherwise carry a
    // timestamp from the *previous* turn's flight clock and read as "hit
    // 0.4s in the future", i.e. permanently recent. Clearing the ledger with
    // the clock keeps the two in the same time base.
    _clearHitLedger();
  }

  void _clearHitLedger() {
    for (final id in _order) {
      _lastHitBy[id] = null;
      _lastHitAt.remove(id);
    }
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    super.step(dt);
    if (_winner != null) return;

    _resolveOffTrack();
    _updateProgress();

    if (_winner != null && !_awarded) {
      _awarded = true;
      context.scores.award(_winner!, 1);
      return;
    }

    if (!_moving) return;

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

  /// A car off the track is reset immediately: back to how far it had got
  /// before this turn's flick if it left under its own power, or back to the
  /// last on-track point it passed through if another car's collision sent it
  /// there. The asymmetry is deliberate — it punishes a reckless flick harder
  /// than being a sabotage victim.
  ///
  /// Both destinations are snapped onto the track's **centerline** at the
  /// reference point's arclength rather than used literally. A literal reset
  /// is an unrecoverable trap: the reference is often a point right on the
  /// track's edge (the last on-track sample before an exit is, by definition,
  /// at the boundary), and from the edge the very same shot goes off again on
  /// the next turn, and the next — a deterministic fixpoint that froze cars
  /// at zero progress forever on a ring board. On the centerline a car always
  /// has the full half-width to deviate into, so no position is ever a dead
  /// end. Which arclength you go back to still carries the whole penalty.
  void _resolveOffTrack() {
    for (final id in _order) {
      final car = carOf(id);
      final pos = car.position;
      if (track.isOnTrack(pos.x, pos.y)) {
        _lastOnTrack[id] = pos.clone();
        continue;
      }
      final sinceHit = _sinceLaunch - (_lastHitAt[id] ?? Duration.zero);
      final hitRecently = _lastHitBy[id] != null &&
          sinceHit >= Duration.zero &&
          sinceHit <= PitchCarsConfig.hitGraceWindow;
      final selfFault = id == currentTurn && !hitRecently;
      final reference = selfFault ? _preTurnPosition : (_lastOnTrack[id] ?? _preTurnPosition);
      final resetTo = _onCenterline(reference);
      car
        ..setTransform(resetTo, car.angle)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      _lastOnTrack[id] = resetTo.clone();
      _lastHitBy[id] = null;
    }
  }

  /// The centerline point at [reference]'s arclength along the track.
  Vector2 _onCenterline(Vector2 reference) {
    final wp = track.pointAtArclength(track.progressAt(reference.x, reference.y));
    return Vector2(wp.x, wp.y);
  }

  /// Unwraps each car's raw (positional, wrap-ambiguous) track progress into
  /// a monotonic cumulative distance travelled, so a loop's "just finished a
  /// lap" is distinguishable from "still at the start".
  void _updateProgress() {
    for (final id in _order) {
      final pos = carOf(id).position;
      final raw = track.progressAt(pos.x, pos.y);
      final prevRaw = _rawProgress[id] ?? 0.0;
      var delta = raw - prevRaw;
      if (track.closed) {
        if (delta < -track.length / 2) delta += track.length;
        if (delta > track.length / 2) delta -= track.length;
      }
      _progress[id] = (_progress[id] ?? 0.0) + delta;
      _rawProgress[id] = raw;

      if (_winner == null && _progress[id]! >= track.length - 1e-6) {
        _winner = id;
      }
    }
  }

  String get _winnerLabel =>
      context.slices.firstWhere((s) => s.phoneId == _winner).label;

  void _endTurn() {
    _moving = false;
    _clearHitLedger();
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
        for (final id in _order)
          'progress_$id': track.length < 1e-9
              ? 0.0
              : double.parse(((_progress[id] ?? 0) / track.length).clamp(0.0, 1.0).toStringAsFixed(3)),
      };

  @override
  GameOutcome? get outcome =>
      _winner == null ? null : GameOutcome.won(summary: '$_winnerLabel wins the race');

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
    _lastHitAt.clear();

    for (var i = 0; i < _order.length; i++) {
      final pos = _startPositionFor(i);
      final car = carOf(_order[i])
        ..setTransform(pos, 0)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0
        ..setAwake(true);
      _lastOnTrack[_order[i]] = car.position.clone();
      _rawProgress[_order[i]] = track.progressAt(car.position.x, car.position.y);
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
      sim._lastHitAt[a] = sim._sinceLaunch;
      sim._lastHitAt[b] = sim._sinceLaunch;
    }
  }

  @override
  void endContact(Contact contact) {}
  @override
  void preSolve(Contact contact, Manifold oldManifold) {}
  @override
  void postSolve(Contact contact, ContactImpulse impulse) {}
}
