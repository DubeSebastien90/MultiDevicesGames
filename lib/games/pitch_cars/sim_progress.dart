part of 'pitch_cars_sim.dart';

/// Off-track recovery, lap progress and finish/turn resolution.
extension _Progress on PitchCarsSim {
  /// Cars that have left the road: let them fall, then put them back.
  ///
  /// This used to happen in one tick — a car crossed the edge and was already
  /// home again before the frame was drawn, which looked like it had *stopped*
  /// at the edge. Two things were wrong with that. Nobody watching could see
  /// that a car had been knocked anywhere, and a car knocked off came back to
  /// the exact spot it was standing on, so shoving a rival cost them nothing
  /// and there was no reason to aim at anybody.
  ///
  /// Now the car sails on for [PitchCarsConfig.fallSeconds] — as a sensor, so
  /// it passes through everything on its way out — and then reappears:
  ///
  /// - **Its own fault** (the player flicked themselves off): back where the
  ///   turn started, as before. Losing the shot is the whole penalty.
  /// - **Knocked off by somebody**: back on the centerline
  ///   [PitchCarsScale.knockBackWorld] *behind* where it went over.
  ///
  /// Where it lands is settled the moment it leaves, not when it arrives. The
  /// turn can end mid-fall, and `_preTurnPosition` means somebody else by then.
  void _resolveOffTrack(double dt) {
    for (final id in _order) {
      if (_finished.contains(id)) continue;

      final falling = _fallenFor[id];
      if (falling != null) {
        final elapsed = falling + dt;
        _fallenFor[id] = elapsed;
        if (elapsed >= PitchCarsConfig.fallSeconds) _land(id);
        continue;
      }

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

      _beginFall(id, ownFault: id == currentTurn && !hitRecently);
    }
  }

  void _beginFall(String id, {required bool ownFault}) {
    final pos = carOf(id).position;

    final Vector2 target;
    if (ownFault) {
      target = _preTurnPosition.clone();
    } else {
      final fell = track.progressAt(pos.x, pos.y);
      final back = math.max(0.0, fell - scale.knockBackWorld);
      final point = track.pointAtArclength(back);
      target = Vector2(point.x, point.y);
    }

    _fallenFor[id] = 0;
    _fallTarget[id] = target;
    // Through everything on the way down. A car tumbling into the void should
    // not clip a rival still on the road, and should not be stopped by the
    // kerb it has already cleared.
    _fixtureOf[id]?.setSensor(true);
  }

  void _land(String id) {
    final car = carOf(id);
    final resetTo = _clearOfOthers(
      id,
      (_fallTarget[id] ?? _preTurnPosition).clone(),
    );

    car
      ..setTransform(resetTo, car.angle)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;

    // Progress is tracked as a running total of small deltas, and this is a
    // jump rather than a delta — so both halves are restated together. Without
    // it the road given up would be handed straight back on the next step.
    final landedArc = track.progressAt(resetTo.x, resetTo.y);
    final lost = (_rawProgress[id] ?? landedArc) - landedArc;
    if (lost > 0) {
      _progress[id] = math.max(0.0, (_progress[id] ?? 0) - lost);
    }
    _rawProgress[id] = landedArc;

    _lastOnTrack[id] = resetTo.clone();
    _lastHitBy[id] = null;
    _fallenFor.remove(id);
    _fallTarget.remove(id);
    _fixtureOf[id]?.setSensor(false);
  }

  Vector2 _clearOfOthers(String id, Vector2 target) {
    final minGap = scale.minCarGap;
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
      // A car in the void is not getting anywhere. Left running, its projection
      // onto the centerline would keep drifting while it tumbled — and could
      // sail past the finish threshold, winning the race from off the board.
      if (_fallenFor.containsKey(id)) continue;
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
