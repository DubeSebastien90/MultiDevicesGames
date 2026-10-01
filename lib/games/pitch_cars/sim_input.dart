part of 'pitch_cars_sim.dart';

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

    if (pullBack.length < scale.maxPull * PitchCarsConfig.cancelPullFraction) {
      car.setTransform(_preTurnPosition.clone(), car.angle);
      return;
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

    _clearHitLedger();
  }

  void _faceTheShot(Body car) {
    final pullBack = _preTurnPosition - _pull!;
    if (pullBack.length < scale.maxPull * PitchCarsConfig.cancelPullFraction) {
      return;
    }
    car.setTransform(car.position.clone(), _headingOf(pullBack));
  }

  double _headingOf(Vector2 shot) => math.atan2(shot.y, shot.x);

  void _clearHitLedger() {
    for (final id in _order) {
      _lastHitBy[id] = null;
      _lastHitAt.remove(id);
    }
  }
}
