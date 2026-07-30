import 'dart:math' as math;

import '../net/protocol.dart';

/// One broadcast instant, as received.
class Snapshot {
  Snapshot({
    required this.tick,
    required this.hostTimeMs,
    required this.entities,
    required this.sling,
  });

  final int tick;

  /// The host's sim clock when this state was true.
  final double hostTimeMs;
  final Map<String, EntityState> entities;
  final SlingState? sling;
}

/// An entity's transform at the current render instant.
class InterpolatedEntity {
  const InterpolatedEntity(this.x, this.y, this.angle);
  final double x;
  final double y;
  final double angle;
}

/// Plays snapshots back on a deliberately delayed clock.
///
/// **This is the thing that makes the seam work.** Rendering the newest snapshot
/// as soon as it lands means every screen shows whatever the network happened to
/// deliver most recently, so two phones sit a few milliseconds apart and the
/// bird visibly steps sideways as it crosses the gap. Instead, every phone
/// renders the same moment of the *host's* timeline, [interpDelayMs] in the
/// past, and interpolates between the two snapshots bracketing it. All screens
/// then agree on where the bird is, and each one is smooth in isolation.
///
/// The render clock is built as `localTime + offset - delay`, where `offset`
/// estimates how far ahead the host's clock runs. That construction matters: the
/// clock then advances at exactly local frame rate, so *how* a phone chunks its
/// frames cannot affect where it thinks the bird is. An earlier version nudged
/// the clock's rate toward `newest - delay` instead, and a phone rendering at a
/// different frame rate settled at a different offset — about 0.8mm of
/// disagreement at 20cm/s, which is precisely the step at the seam this class
/// exists to prevent. (See the frame-pacing test.)
///
/// The offset is estimated the way one-way network delay always is: it rises
/// immediately and decays slowly. Latency can only ever make a snapshot look
/// *older* than it is, so the largest offset seen recently is the best estimate
/// of the truth, and slow decay still absorbs real clock drift. No explicit
/// clock synchronisation is needed — the timeline falls out of the stream.
class SnapshotBuffer {
  /// How far behind the host we render. Larger is smoother and more tolerant of
  /// jitter; smaller feels more responsive to the phone doing the dragging.
  double interpDelayMs = 80;

  /// Never invent more than this much motion past the newest snapshot.
  static const double _maxExtrapolationMs = 120;

  /// Past this much disagreement, the stream restarted or the app was
  /// suspended: jump rather than crawl.
  static const double _resyncThresholdMs = 300;

  /// Per-snapshot pull toward a *lower* offset. Deliberately tiny — this only
  /// has to track crystal drift, so its time constant is seconds.
  static const double _offsetDecay = 0.002;

  final _snaps = <Snapshot>[];

  /// Accumulated local frame time.
  double _localMs = 0;

  /// Estimated `hostTime - localTime`.
  double? _offset;

  double _lastArrivalGapMs = 0;
  double? _lastArrivalHostTime;

  /// Whether we are currently having to guess (no snapshot ahead of us).
  bool get extrapolating => _extrapolating;
  bool _extrapolating = false;

  /// The instant of the host's timeline we are currently drawing.
  double get renderTimeMs =>
      _offset == null ? 0 : _localMs + _offset! - interpDelayMs;

  int get bufferedSnapshots => _snaps.length;

  /// Observed spacing between arriving snapshots, for the debug overlay.
  double get snapshotIntervalMs => _lastArrivalGapMs;

  bool get hasData => _snaps.isNotEmpty;

  void add(Snapshot s) {
    if (_lastArrivalHostTime != null) {
      _lastArrivalGapMs = s.hostTimeMs - _lastArrivalHostTime!;
    }
    _lastArrivalHostTime = s.hostTimeMs;

    // The host restarted its clock (a re-calibrated board): drop the old
    // timeline rather than interpolating across the discontinuity.
    if (_snaps.isNotEmpty && s.hostTimeMs < _snaps.last.hostTimeMs) {
      _snaps.clear();
      _offset = null;
    }

    _snaps.add(s);
    if (_snaps.length > 120) _snaps.removeRange(0, _snaps.length - 120);

    final raw = s.hostTimeMs - _localMs;
    final current = _offset;
    if (current == null || (raw - current).abs() > _resyncThresholdMs) {
      _offset = raw;
    } else if (raw > current) {
      // This snapshot reached us sooner than any recent one, so it carries the
      // best information about the host's true clock. Take it immediately.
      _offset = raw;
    } else {
      _offset = current + (raw - current) * _offsetDecay;
    }
  }

  void clear() {
    _snaps.clear();
    _offset = null;
    _localMs = 0;
    _lastArrivalHostTime = null;
  }

  /// Advance the render clock by one frame of local time.
  void advance(double dtMs) {
    _localMs += dtMs;
    if (_snaps.isEmpty || _offset == null) return;

    // Keep one snapshot behind the render clock (it is the lerp's left end) and
    // discard everything older.
    final t = renderTimeMs;
    var keepFrom = 0;
    for (var i = 0; i < _snaps.length; i++) {
      if (_snaps[i].hostTimeMs <= t) {
        keepFrom = i;
      } else {
        break;
      }
    }
    if (keepFrom > 0) _snaps.removeRange(0, keepFrom);
  }

  /// Every entity at the current render instant.
  Map<String, InterpolatedEntity> sampleAll() {
    if (_offset == null || _snaps.isEmpty) return const {};
    final t = renderTimeMs;

    final (before, after) = _bracket(t);

    if (after == null) {
      // Nothing newer to aim at: carry on along the last known velocity, but
      // only briefly. Better a few extra millimetres than a stall-then-jump.
      _extrapolating = true;
      final aheadMs =
          math.min(t - before.hostTimeMs, _maxExtrapolationMs);
      final aheadS = aheadMs / 1000;
      return {
        for (final e in before.entities.values)
          e.id: InterpolatedEntity(
            e.x + e.vx * aheadS,
            e.y + e.vy * aheadS,
            e.angle,
          ),
      };
    }

    _extrapolating = false;
    final span = after.hostTimeMs - before.hostTimeMs;
    final alpha = span <= 0
        ? 1.0
        : ((t - before.hostTimeMs) / span).clamp(0.0, 1.0);

    final out = <String, InterpolatedEntity>{};
    for (final a in before.entities.values) {
      final b = after.entities[a.id];
      if (b == null) {
        out[a.id] = InterpolatedEntity(a.x, a.y, a.angle);
        continue;
      }
      out[a.id] = InterpolatedEntity(
        a.x + (b.x - a.x) * alpha,
        a.y + (b.y - a.y) * alpha,
        a.angle + _shortestAngleDelta(a.angle, b.angle) * alpha,
      );
    }
    return out;
  }

  /// The sling band at the current render instant, on the same delayed clock as
  /// the entities so the band and the bird never disagree.
  SlingState? sampleSling() {
    if (_offset == null || _snaps.isEmpty) return null;
    final t = renderTimeMs;
    final (before, after) = _bracket(t);
    final a = before.sling;
    if (a == null) return null;
    final b = after?.sling;
    if (b == null || !a.active) return a;

    final span = after!.hostTimeMs - before.hostTimeMs;
    final alpha =
        span <= 0 ? 1.0 : ((t - before.hostTimeMs) / span).clamp(0.0, 1.0);
    return SlingState(
      active: a.active,
      anchorX: a.anchorX + (b.anchorX - a.anchorX) * alpha,
      anchorY: a.anchorY + (b.anchorY - a.anchorY) * alpha,
      pullX: a.pullX + (b.pullX - a.pullX) * alpha,
      pullY: a.pullY + (b.pullY - a.pullY) * alpha,
      draggingPhoneId: a.draggingPhoneId,
    );
  }

  /// The pair of snapshots surrounding [t]. `after` is null when we have run off
  /// the end of what has arrived.
  (Snapshot, Snapshot?) _bracket(double t) {
    var before = _snaps.first;
    for (var i = 0; i < _snaps.length; i++) {
      final s = _snaps[i];
      if (s.hostTimeMs <= t) {
        before = s;
      } else {
        return (before, s);
      }
    }
    return (before, null);
  }

  /// Box2D angles accumulate past 2π, so a naive lerp between 359° and 1° spins
  /// the long way round.
  static double _shortestAngleDelta(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d;
  }
}
