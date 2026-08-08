part of 'pitch_cars_sim.dart';

/// Off-track recovery, lap progress and finish/turn resolution.
extension _Progress on PitchCarsSim {
  /// A car off the track resets to how far it had got before this turn's
  /// flick if it left under its own power, or to the last on-track point it
  /// passed through if another car's collision sent it there — punishing a
  /// reckless flick harder than being a sabotage victim.
  ///
  /// Both destinations snap onto the track's centerline at the reference
  /// point's arclength rather than being used literally: a literal reset can
  /// land right on the track edge, where the same shot goes off again next
  /// turn — a fixpoint that freezes a car at zero progress forever.
  ///
  /// Two cars can share an arclength (e.g. side-by-side on the starting
  /// grid), so that centerline point can already be occupied — in that
  /// case, slide along the centerline (not sideways off it) until clear, so
  /// the reset point stays exactly as safe as the plain centerline case.
  void _resolveOffTrack() {
    for (final id in _order) {
      final car = carOf(id);
      final pos = car.position;
      if (track.isOnTrack(pos.x, pos.y)) {
        _lastOnTrack[id] = pos.clone();
        continue;
      }
      final sinceHit = _sinceLaunch - (_lastHitAt[id] ?? Duration.zero);
      final hitRecently =
          _lastHitBy[id] != null &&
          sinceHit >= Duration.zero &&
          sinceHit <= PitchCarsConfig.hitGraceWindow;
      final selfFault = id == currentTurn && !hitRecently;
      final reference = selfFault
          ? _preTurnPosition
          : (_lastOnTrack[id] ?? _preTurnPosition);
      final resetTo = _clearCenterlinePoint(id, reference);
      car
        ..setTransform(resetTo, car.angle)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      _lastOnTrack[id] = resetTo.clone();
      _lastHitBy[id] = null;
    }
  }

  /// The centerline point at [reference]'s arclength, nudged forward along
  /// the track — one [PitchCarsConfig.carRadius]-and-a-bit step at a time —
  /// until it's clear of every other car.
  Vector2 _clearCenterlinePoint(String id, Vector2 reference) {
    final step = PitchCarsConfig.carRadius * 2 + 0.05;
    var s = track.progressAt(reference.x, reference.y);
    for (var attempt = 0; attempt < _order.length; attempt++) {
      final wp = track.pointAtArclength(s);
      final candidate = Vector2(wp.x, wp.y);
      final clear = _order.every(
        (other) =>
            other == id || carOf(other).position.distanceTo(candidate) >= step,
      );
      if (clear) return candidate;
      s += step;
    }
    final wp = track.pointAtArclength(s);
    return Vector2(wp.x, wp.y);
  }

  /// Unwraps each car's raw (positional, wrap-ambiguous) track progress into
  /// a monotonic cumulative distance, so "just finished a lap" is
  /// distinguishable from "still at the start".
  void _updateProgress() {
    for (final id in _order) {
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

  /// Winning requires reaching the finish band *and* coming to rest inside
  /// it. The progress threshold is the band's near edge, not `track.length`
  /// itself (that's the band's center), so a car resting in the near half
  /// of the checkerboard still counts.
  void _checkFinish() {
    final threshold = track.length - _finishBandLen / 2 - 1e-6;
    for (final id in _order) {
      if (_progress[id]! < threshold) continue;
      final pos = carOf(id).position;
      if (_inFinishZone(track.progressAt(pos.x, pos.y))) {
        _winner = id;
        return;
      }
    }
  }

  void _endTurn() {
    _moving = false;
    _checkFinish();
    _clearHitLedger();
    _currentIndex = (_currentIndex + 1) % _order.length;
    _preTurnPosition = carOf(currentTurn).position.clone();
  }
}
