part of 'pitch_cars_sim.dart';

extension _Progress on PitchCarsSim {
  void _resolveOffTrack(double dt) {
    const visualEnd =
        PitchCarsConfig.fallSeconds +
        PitchCarsConfig.fallVisualLagSeconds +
        PitchCarsConfig.fallVisualMarginSeconds;
    for (final id in _fallVisualFor.keys.toList()) {
      final t = _fallVisualFor[id]! + dt;
      if (t >= visualEnd) {
        _fallVisualFor.remove(id);
      } else {
        _fallVisualFor[id] = t;
      }
    }

    for (final id in _order) {
      if (_finished.contains(id)) continue;

      final falling = _fallenFor[id];
      if (falling != null) {
        final elapsed = falling + dt;
        _fallenFor[id] = elapsed;
        if (elapsed >= PitchCarsConfig.fallSeconds) {
          _land(id);
        } else {
          carOf(id).angularVelocity =
              PitchCarsConfig.fallSpinTurnsPerSecond * 2 * math.pi;
        }
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
    final Vector2 target;
    if (ownFault) {
      target = _preTurnPosition.clone();
    } else {
      final fell = _rawProgress[id] ?? 0.0;
      final back = math.max(0.0, fell - scale.knockBackWorld);
      final point = track.pointAtArclength(back);
      target = Vector2(point.x, point.y);
    }

    _fallenFor[id] = 0;
    _fallTarget[id] = target;
    _fallAngle[id] = carOf(id).angle;
    _fallVisualFor[id] = 0;

    _fixtureOf[id]?.setSensor(true);

    final pos = carOf(id).position;
    final phone = context.nearestPhone(pos.x, pos.y);
    if (phone != null) _playOn(phone, PitchCarsConfig.falling);
  }

  void _land(String id) {
    final car = carOf(id);
    final resetTo = _clearOfOthers(
      id,
      (_fallTarget[id] ?? _preTurnPosition).clone(),
    );

    car
      ..setTransform(resetTo, _fallAngle[id] ?? car.angle)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;

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
    _fallAngle.remove(id);
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
    final threshold = _finishStart - 1e-6;
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

    final endsTheRace = _order.length - _finished.length <= 1;
    final player = context.roster.byPhone(id);
    if (player != null && !endsTheRace) {
      context.audio.playOnPhone(player, player.soundHappy);
    }
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
