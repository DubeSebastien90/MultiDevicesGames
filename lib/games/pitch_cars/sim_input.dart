part of 'pitch_cars_sim.dart';

/// Pull-and-release aiming: dragging never moves the car, only `_pull`.
extension _Input on PitchCarsSim {
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
