part of 'pitch_cars_sim.dart';

/// Pull-and-release aiming: dragging never moves the car, only `_pull` — and
/// `_pull` is the finger's displacement from `_dragOrigin`, not the finger
/// itself, so a draw started away from the car aims it just the same.
extension _Input on PitchCarsSim {
  Vector2 _clampPull(Vector2 p) {
    final delta = p - _preTurnPosition;
    if (delta.length > scale.maxPull) {
      delta
        ..normalize()
        ..scale(scale.maxPull);
    }
    return _preTurnPosition + delta;
  }

  void _launch() {
    final pullBack = _preTurnPosition - _pull!;
    final aimedFrom = _draggingPhoneId;
    _draggingPhoneId = null;
    _dragOrigin = null;
    _pull = null;
    _stopHold();
    final car = carOf(currentTurn);

    // A tap, not a shot — see [PitchCarsConfig.cancelPullFraction].
    if (pullBack.length < scale.maxPull * PitchCarsConfig.cancelPullFraction) {
      car.setTransform(_preTurnPosition.clone(), car.angle);
      return; // the turn is not consumed
    }

    if (aimedFrom != null) _playOn(aimedFrom, PitchCarsConfig.shot);

    car
      ..setTransform(_preTurnPosition.clone(), _headingOf(pullBack))
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setAwake(true)
      ..applyLinearImpulse(pullBack * scale.impulsePerPull);

    _moving = true;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;
    _stallAnchor = _preTurnPosition.clone();
    _sinceStallAnchor = Duration.zero;
    // Hit ledger is timestamped against `_sinceLaunch`, which just reset —
    // clear it too so a stale hit can't misread as freshly recent.
    _clearHitLedger();
  }

  /// Turn the car being aimed to point where it will go, so the driver is
  /// already looking down the shot before it is fired — and the launch below
  /// does not snap them round. Only once the pull would really fire: inside
  /// the dead zone the aim is not drawn, and neither is the turn.
  void _faceTheShot(Body car) {
    final pullBack = _preTurnPosition - _pull!;
    if (pullBack.length < scale.maxPull * PitchCarsConfig.cancelPullFraction) {
      return;
    }
    car.setTransform(car.position.clone(), _headingOf(pullBack));
  }

  /// The angle a shot along [shot] points at, in the convention the car and
  /// its driver are drawn in: 0 is nose to +x.
  double _headingOf(Vector2 shot) => math.atan2(shot.y, shot.x);

  void _clearHitLedger() {
    for (final id in _order) {
      _lastHitBy[id] = null;
      _lastHitAt.remove(id);
    }
  }
}
