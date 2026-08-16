part of 'pitch_cars_sim.dart';

/// Pull-and-release aiming: dragging never moves the car, only `_pull`.
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
    _pull = null;
    final car = carOf(currentTurn);

    // A tap, not a shot. Measured against the pull this table allows rather
    // than a fixed distance, so the dead zone stays the same *gesture* whether
    // the road is narrow or wide.
    if (pullBack.length < scale.maxPull * 0.05) {
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
