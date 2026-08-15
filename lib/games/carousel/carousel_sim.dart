import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/render/shape_view.dart';
import 'carousel_config.dart';

/// A marker spins round the ring. Tap to push it on; let it die in your zone
/// to bank the landing.
///
/// **No physics engine, and no randomness either.** The whole world is one
/// angle and one angular speed, decelerating at a constant rate — exactly the
/// kind of thing [Forge2DGameSim] would be overkill for, and simple enough that
/// every outcome is deterministic from the taps that produced it. Everyone
/// shares the one marker and the one push direction: it only ever moves
/// forward round the ring, so the only real decision anybody makes is whether
/// to tap (push it past your own zone, hoping to strand it in somebody else's
/// past reach) or hold off (let friction maybe strand it in yours).
///
/// It still crosses the seam like every physics game here, because it is an
/// entity: easing its angle every tick makes it slide smoothly past each
/// screen in turn, in step, on every phone at once.
class CarouselSim implements GameSim {
  CarouselSim(this.context) {
    _theta = _ring.first.angle;
  }

  final BoardContext context;

  /// Seats sorted by their angle about the board's middle — the order they
  /// actually sit around the ring, not the reading order the board hands over.
  late final List<_Seat> _ring = _seatsByAngle();

  /// Distance from the board's middle to the ring — all seats sit the same
  /// distance out, so any one of them tells us the radius the marker rides.
  late final double _radius = _distanceToFirstSeat();

  double _theta = 0;
  double _omega = 0;
  double _elapsed = 0;

  bool _settling = false;
  double _settleUntil = 0;

  final _lastTapAt = <String, double>{};
  final _landings = <String, int>{};

  GameOutcome? _outcome;

  List<_Seat> _seatsByAngle() {
    final cx = context.board.centerX;
    final cy = context.board.centerY;
    final seats = [
      for (final s in context.slices)
        _Seat(
          s.phoneId,
          _normalize(math.atan2(s.screen.centerY - cy, s.screen.centerX - cx)),
        ),
    ];
    seats.sort((a, b) => a.angle.compareTo(b.angle));
    return seats;
  }

  double _distanceToFirstSeat() {
    final cx = context.board.centerX;
    final cy = context.board.centerY;
    final s = context.slices.first.screen;
    return math.sqrt(math.pow(s.centerX - cx, 2) + math.pow(s.centerY - cy, 2));
  }

  static double _normalize(double radians) =>
      radians < 0 ? radians + 2 * math.pi : radians;

  static double _circularDistance(double a, double b) {
    final d = (a - b).abs() % (2 * math.pi);
    return d > math.pi ? 2 * math.pi - d : d;
  }

  /// Whichever seat's angle is nearest [theta] owns the marker there.
  String _ownerOf(double theta) {
    var best = _ring.first;
    var bestDistance = double.infinity;
    for (final seat in _ring) {
      final d = _circularDistance(theta, seat.angle);
      if (d < bestDistance) {
        bestDistance = d;
        best = seat;
      }
    }
    return best.phoneId;
  }

  bool get _timeUp => _elapsed >= CarouselConfig.roundSeconds;
  bool get _someoneHitTarget =>
      _landings.values.any((n) => n >= CarouselConfig.targetLandings);
  bool get _over => _timeUp || _someoneHitTarget;

  int get _secondsLeft =>
      (CarouselConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (_over || _settling) return;

    final last = _lastTapAt[touch.phoneId];
    if (last != null && _elapsed - last < CarouselConfig.tapCooldown) return;
    _lastTapAt[touch.phoneId] = _elapsed;

    _omega = math.min(
      _omega + CarouselConfig.tapImpulse,
      CarouselConfig.maxOmega,
    );
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_over) return;
    _elapsed += dt;

    if (_settling) {
      if (_elapsed >= _settleUntil) _settling = false;
      return;
    }

    if (_omega <= 0) return;

    _theta = (_theta + _omega * dt) % (2 * math.pi);

    final decayed = _omega - CarouselConfig.friction * dt;
    if (decayed <= 0) {
      _omega = 0;
      _land();
    } else {
      _omega = decayed;
    }
  }

  void _land() {
    final owner = _ownerOf(_theta);
    _landings[owner] = (_landings[owner] ?? 0) + 1;
    context.scores.award(owner, CarouselConfig.pointsPerLanding);
    _settling = true;
    _settleUntil = _elapsed + CarouselConfig.settleSeconds;
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities sync* {
    final cx = context.board.centerX;
    final cy = context.board.centerY;
    final moving = _omega > 0;

    yield Entity(
      descriptor: EntityDescriptor(
        id: 'marker',
        kind: 'marker',
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: CarouselConfig.markerRadius,
          ShapeProps.color: moving
              ? CarouselConfig.colorMarker
              : CarouselConfig.colorMarkerSettled,
          ShapeProps.spin: moving,
        },
      ),
      x: cx + _radius * math.cos(_theta),
      y: cy + _radius * math.sin(_theta),
      angle: _theta,
    );
  }

  @override
  Map<String, Object?> get sharedState => {
    'owner': _ownerOf(_theta),
    'moving': _omega > 0,
    'settling': _settling,
    'landings': Map<String, int>.of(_landings),
    'secondsLeft': _secondsLeft,
    'target': CarouselConfig.targetLandings,
  };

  // --------------------------------------------------------------- outcome

  @override
  GameOutcome? get outcome {
    if (!_over) return null;
    return _outcome ??= _buildOutcome();
  }

  GameOutcome _buildOutcome() {
    if (_landings.isEmpty) {
      return const GameOutcome.draw(summary: 'nobody landed a spin');
    }
    final top = _landings.values.reduce(math.max);
    final winners = {
      for (final e in _landings.entries)
        if (e.value == top) e.key,
    };
    return GameOutcome.contest(
      winners: winners,
      summary: winners.length > 1
          ? 'a $top-landing tie'
          : '$top landings',
      lines: {
        for (final id in context.phoneIds)
          id: '${_landings[id] ?? 0} landings',
      },
    );
  }

  // ----------------------------------------------------------------- reset

  @override
  void reset() {
    _theta = _ring.first.angle;
    _omega = 0;
    _elapsed = 0;
    _settling = false;
    _settleUntil = 0;
    _lastTapAt.clear();
    _landings.clear();
    _outcome = null;
  }

  @override
  void dispose() {}
}

class _Seat {
  const _Seat(this.phoneId, this.angle);
  final String phoneId;
  final double angle;
}
