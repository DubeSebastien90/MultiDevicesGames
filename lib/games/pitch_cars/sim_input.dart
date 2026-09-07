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
    _draggingPhoneId = null;
    _dragOrigin = null;
    _pull = null;
    final car = carOf(currentTurn);

    // A tap, not a shot — see [PitchCarsConfig.cancelPullFraction].
    if (pullBack.length < scale.maxPull * PitchCarsConfig.cancelPullFraction) {
      car.setTransform(_preTurnPosition.clone(), car.angle);
      return; // the turn is not consumed
    }

    car
      ..setTransform(_preTurnPosition.clone(), car.angle)
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

  void _clearHitLedger() {
    for (final id in _order) {
      _lastHitBy[id] = null;
      _lastHitAt.remove(id);
    }
  }
}
