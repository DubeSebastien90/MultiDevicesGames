import 'dart:math' as math;

import '../net/protocol.dart';

class Snapshot {
  Snapshot({
    required this.tick,
    required this.hostTimeMs,
    required this.entities,
  });

  final int tick;

  final double hostTimeMs;
  final Map<String, EntityState> entities;
}

class InterpolatedEntity {
  const InterpolatedEntity(this.x, this.y, this.angle);
  final double x;
  final double y;
  final double angle;
}

class SnapshotBuffer {
  double interpDelayMs = 80;

  static const double _maxExtrapolationMs = 120;

  static const double _resyncThresholdMs = 300;

  static const double _offsetDecay = 0.002;

  final _snaps = <Snapshot>[];

  double _localMs = 0;

  double? _offset;

  double _lastArrivalGapMs = 0;
  double? _lastArrivalHostTime;

  bool get extrapolating => _extrapolating;
  bool _extrapolating = false;

  double get renderTimeMs =>
      _offset == null ? 0 : _localMs + _offset! - interpDelayMs;

  int get bufferedSnapshots => _snaps.length;

  double get snapshotIntervalMs => _lastArrivalGapMs;

  bool get hasData => _snaps.isNotEmpty;

  void add(Snapshot s) {
    if (_lastArrivalHostTime != null) {
      _lastArrivalGapMs = s.hostTimeMs - _lastArrivalHostTime!;
    }
    _lastArrivalHostTime = s.hostTimeMs;

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

  void advance(double dtMs) {
    _localMs += dtMs;
    if (_snaps.isEmpty || _offset == null) return;

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

  Map<String, InterpolatedEntity> sampleAll() {
    if (_offset == null || _snaps.isEmpty) return const {};
    final t = renderTimeMs;

    final (before, after) = _bracket(t);

    if (after == null) {
      _extrapolating = true;
      final aheadMs = math.min(t - before.hostTimeMs, _maxExtrapolationMs);
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

  static double _shortestAngleDelta(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d;
  }
}
