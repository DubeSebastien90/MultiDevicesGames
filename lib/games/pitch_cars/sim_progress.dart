part of 'pitch_cars_sim.dart';

/// Off-track recovery, lap progress and finish/turn resolution.
extension _Progress on PitchCarsSim {
  void _resolveOffTrack() {
    for (final id in _order) {
      if (_finished.contains(id)) continue;
      final car = carOf(id);
      final pos = car.position;
      final sinceHit = _sinceLaunch - (_lastHitAt[id] ?? Duration.zero);
      final hitRecently =
          _lastHitBy[id] != null &&
          sinceHit >= Duration.zero &&
          sinceHit <= PitchCarsConfig.hitGraceWindow;
      if (track.isOnTrack(pos.x, pos.y)) {
        if (!hitRecently) _lastOnTrack[id] = pos.clone();
        continue;
      }
      final selfFault = id == currentTurn && !hitRecently;
      final reference = selfFault
          ? _preTurnPosition
          : (_lastOnTrack[id] ?? _preTurnPosition);
      final resetTo = _clearOfOthers(id, reference.clone());
      car
        ..setTransform(resetTo, car.angle)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      _lastOnTrack[id] = resetTo.clone();
      _lastHitBy[id] = null;
    }
  }

  Vector2 _clearOfOthers(String id, Vector2 target) {
    const minGap = PitchCarsConfig.carRadius * 2 + 1e-4;
    for (final other in _order) {
      if (other == id || _finished.contains(other)) continue;
      final otherPos = carOf(other).position;
      final delta = target - otherPos;
      final dist = delta.length;
      if (dist < minGap) {
        final direction = dist < 1e-9 ? Vector2(1, 0) : delta / dist;
        target = otherPos + direction * minGap;
      }
    }
    return target;
  }

  void _snapshotBeforeHit(String id) {
    final pos = carOf(id).position;
    if (track.isOnTrack(pos.x, pos.y)) {
      _lastOnTrack[id] = pos.clone();
    }
  }

  void _updateProgress() {
    for (final id in _order) {
      if (_finished.contains(id)) continue;
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
    }
  }

  void _checkFinish() {
    final threshold = track.length - _finishBandLen / 2 - 1e-6;
    for (final id in _order) {
      if (_finished.contains(id) || _progress[id]! < threshold) continue;
      final pos = carOf(id).position;
      if (_inFinishZone(track.progressAt(pos.x, pos.y))) _markFinished(id);
    }
  }

  void _markFinished(String id) {
    _finished.add(id);
    _finishOrder.add(id);
    _fixtureOf[id]?.setSensor(true);
    if (_order.length - _finished.length == 1) {
      final last = _order.firstWhere((o) => !_finished.contains(o));
      _finished.add(last);
      _finishOrder.add(last);
      _fixtureOf[last]?.setSensor(true);
    }
  }

  void _endTurn() {
    _moving = false;
    _checkFinish();
    _clearHitLedger();
    if (_roundOver) return;
    do {
      _currentIndex = (_currentIndex + 1) % _order.length;
    } while (_finished.contains(currentTurn));
    _preTurnPosition = carOf(currentTurn).position.clone();
  }
}
