import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/render/shape_view.dart';
import 'hot_potato_config.dart';

/// Pass the potato before the fuse runs out.
///
/// **No physics.** This is the first game to extend [GameSim] directly rather
/// than the Forge2D base class, and it is the proof that the contract meant it:
/// there is nothing here to integrate — no forces, no contacts, no gravity. The
/// whole world is "who is holding it" and "how long is left".
///
/// It still uses an *entity* for the potato, and that is the distinction worth
/// keeping straight. Physics is optional; the platform's interpolation is not.
/// Because the potato is an entity, easing it from one phone to the next makes
/// it visibly slide across the table on every screen at once, in step, for the
/// price of a lerp.
class HotPotatoSim implements GameSim {
  HotPotatoSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _holderIndex = _random.nextInt(_order.length);
    _potato = _seatOf(_holderIndex);
    _target = _potato;
  }

  final BoardContext context;
  final math.Random _random;

  /// The passing order *is* the board order, which for a ring runs clockwise
  /// from the top. Neighbours in this list are neighbours on the table.
  List<String> get _order => context.phoneIds;

  static const _potatoId = 'potato';

  late int _holderIndex;
  late _Point _potato;
  late _Point _target;

  double _fuseLeft = HotPotatoConfig.fuseSeconds;
  double _elapsed = 0;
  bool _exploded = false;
  bool _awarded = false;

  /// Swipes in progress, by phone. A pass is a down and an up far enough apart.
  final _swipeStart = <String, _Point>{};

  String get holder => _order[_holderIndex];

  int get _tick => (_elapsed * 60).round();

  // ----------------------------------------------------------------- seats

  /// The middle of a phone's screen — where the potato rests when held.
  _Point _seatOf(int index) {
    final slice = context.slices[index % context.slices.length];
    return _Point(slice.screen.centerX, slice.screen.centerY);
  }

  /// Which way "clockwise around the ring" points at this phone.
  ///
  /// A swipe arrives in *world* coordinates, and in a circle every phone faces
  /// a different way, so there is no fixed "right". Comparing the swipe against
  /// the direction of the next seat is orientation-free and works for a ring, a
  /// row, or anything else a game invents.
  _Point _towardNeighbour(int from, int step) {
    final here = _seatOf(from);
    final there = _seatOf((from + step + _order.length) % _order.length);
    final dx = there.x - here.x;
    final dy = there.y - here.y;
    final len = math.sqrt(dx * dx + dy * dy);
    return len < 1e-9 ? const _Point(1, 0) : _Point(dx / len, dy / len);
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (_exploded) return;
    // Only the phone actually holding it can pass it on.
    if (touch.phoneId != holder) return;

    switch (touch.phase) {
      case TouchPhase.down:
        _swipeStart[touch.phoneId] = _Point(touch.worldX, touch.worldY);

      case TouchPhase.up:
        final start = _swipeStart.remove(touch.phoneId);
        if (start == null) return;
        final dx = touch.worldX - start.x;
        final dy = touch.worldY - start.y;
        if (math.sqrt(dx * dx + dy * dy) < HotPotatoConfig.minSwipeWorld) {
          return; // A tap, not a throw.
        }
        _passInDirection(dx, dy);
    }
  }

  /// Send it whichever way the swipe was actually pointing.
  void _passInDirection(double dx, double dy) {
    final forward = _towardNeighbour(_holderIndex, 1);
    final backward = _towardNeighbour(_holderIndex, -1);
    final alongForward = dx * forward.x + dy * forward.y;
    final alongBackward = dx * backward.x + dy * backward.y;

    final step = alongForward >= alongBackward ? 1 : -1;
    _holderIndex = (_holderIndex + step + _order.length) % _order.length;
    _target = _seatOf(_holderIndex);
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    _elapsed += dt;

    if (!_exploded) {
      _fuseLeft -= dt;
      if (_fuseLeft <= 0) {
        _fuseLeft = 0;
        _exploded = true;
      }
    }

    // Ease toward whoever holds it. The platform interpolates the transform,
    // so this reads as one continuous slide across the table on every screen.
    final speed = _exploded ? 0.0 : HotPotatoConfig.passSpeed;
    if (speed > 0) {
      final dx = _target.x - _potato.x;
      final dy = _target.y - _potato.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > 1e-6) {
        final stepLength = math.min(distance, speed * dt);
        _potato = _Point(
          _potato.x + dx / distance * stepLength,
          _potato.y + dy / distance * stepLength,
        );
      }
    }

    // Award once, here rather than in `outcome` — that getter is polled more
    // than once a tick, and points must not be charged twice.
    if (_exploded && !_awarded) {
      _awarded = true;
      context.scores.award(holder, -HotPotatoConfig.explosionPenalty);
    }
  }

  @override
  void reset() {
    _fuseLeft = HotPotatoConfig.fuseSeconds;
    _elapsed = 0;
    _exploded = false;
    _awarded = false;
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
    _swipeStart.clear();
    _holderIndex = _random.nextInt(_order.length);
    _potato = _seatOf(_holderIndex);
    _target = _potato;
  }

  // ------------------------------------------------------------- snapshots

  @override
  Iterable<Entity> get entities sync* {
    // The fuse drives the potato's size and colour, so every screen sees it
    // swell and redden in step without a single extra message.
    final urgency = 1 - (_fuseLeft / HotPotatoConfig.fuseSeconds);
    final radius = HotPotatoConfig.potatoRadius *
        (1 + urgency * HotPotatoConfig.swellAtZero);

    yield Entity(
      descriptor: EntityDescriptor(
        id: _potatoId,
        kind: _exploded ? 'blast' : 'potato',
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: _exploded
              ? HotPotatoConfig.potatoRadius * HotPotatoConfig.blastScale
              : radius,
          ShapeProps.color: _exploded
              ? HotPotatoConfig.colorBlast
              : HotPotatoConfig.colorPotato,
          ShapeProps.spin: true,
        },
      ),
      x: _potato.x,
      y: _potato.y,
      // Spinning faster as the fuse burns down.
      angle: _elapsed * (1 + urgency * 6),
    );
  }

  @override
  Map<String, Object?> get sharedState => {
    'holder': holder,
    'secondsLeft': double.parse(_fuseLeft.toStringAsFixed(2)),
    'fuse': HotPotatoConfig.fuseSeconds,
    'exploded': _exploded,
    'tick': _tick,
  };

  @override
  GameOutcome? get outcome {
    if (!_exploded) return null;

    // Everyone who passed it on in time; the holder is the one person at the
    // table who did not. Built once — `outcome` is polled several times a tick.
    return _outcome ??= GameOutcome.contest(
      winners: {for (final id in _order) if (id != holder) id},
      summary: 'the potato went off',
      lines: {holder: 'You were holding it'},
    );
  }

  GameOutcome? _outcome;

  @override
  void dispose() {}
}

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;
}
