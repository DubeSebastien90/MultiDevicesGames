part of 'pitch_cars_sim.dart';

/// Off-track recovery, lap progress and finish/turn resolution.
extension _Progress on PitchCarsSim {
  /// A car off the track resets to where it was before this turn's flick if
  /// it left under its own power, or to the last on-track point it passed
  /// through if another car's collision sent it there — punishing a
  /// reckless flick harder than being a sabotage victim.
  ///
  /// Reset literally to that reference point, not to the track's centerline
  /// at its arclength: two cars can share an arclength (e.g. side-by-side
  /// on the starting grid) while sitting at different lateral offsets, and
  /// collapsing both onto the centerline would stack them on top of each
  /// other. The reference is always a point the car itself was already
  /// resting at, so it's never off-track.
  void _resolveOffTrack() {
    for (final id in _order) {
      final car = carOf(id);
      final pos = car.position;
      final sinceHit = _sinceLaunch - (_lastHitAt[id] ?? Duration.zero);
      final hitRecently =
          _lastHitBy[id] != null &&
          sinceHit >= Duration.zero &&
          sinceHit <= PitchCarsConfig.hitGraceWindow;
      if (track.isOnTrack(pos.x, pos.y)) {
        // While a hit is recent, [_snapshotBeforeHit] already holds the
        // authoritative reference (the position from *before* that hit's
        // contact was resolved). Skip the routine update here, or a car
        // still being shoved across the track — on-track for several more
        // frames on its way to the edge — would have that reference dragged
        // along with it instead of staying anchored to where it was hit.
        if (!hitRecently) _lastOnTrack[id] = pos.clone();
        continue;
      }
      final selfFault = id == currentTurn && !hitRecently;
      final reference = selfFault
          ? _preTurnPosition
          : (_lastOnTrack[id] ?? _preTurnPosition);
      final resetTo = reference.clone();
      car
        ..setTransform(resetTo, car.angle)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      _lastOnTrack[id] = resetTo.clone();
      _lastHitBy[id] = null;
    }
  }

  /// Called from the contact listener the instant a hit is detected, while
  /// the body still sits at the position it had *before* this physics step
  /// resolves the contact — the true "before the hit" point, uncontaminated
  /// by however far the collision response then carries it this same tick.
  void _snapshotBeforeHit(String id) {
    final pos = carOf(id).position;
    if (track.isOnTrack(pos.x, pos.y)) {
      _lastOnTrack[id] = pos.clone();
    }
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
