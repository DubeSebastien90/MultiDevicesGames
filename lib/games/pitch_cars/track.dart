import 'dart:math' as math;

/// A point on a track's centerline, in world units.
class Waypoint {
  const Waypoint(this.x, this.y);
  final double x;
  final double y;
}

/// Which shape a generated track takes.
enum PitchTrackTopology { line, loop }

/// A racing line: a centerline with a fixed width, either open (a line, run
/// once from start to finish) or closed (a loop, one lap back to the start).
///
/// Anything beyond `widthWorld / 2` from the centerline is dead space a car
/// can fall into — this is the game's own analogue of the platform's
/// `CoverageMap`, deliberately kept independent of it.
class PitchTrack {
  PitchTrack({
    required this.waypoints,
    required this.widthWorld,
    required this.closed,
  }) : assert(waypoints.length >= 2, 'a track needs at least two waypoints') {
    _points = closed ? [...waypoints, waypoints.first] : waypoints;
    _cumulative = _buildCumulative();
  }

  final List<Waypoint> waypoints;
  final double widthWorld;
  final bool closed;

  late final List<Waypoint> _points;
  late final List<double> _cumulative;

  List<double> _buildCumulative() {
    final cum = <double>[0];
    for (var i = 1; i < _points.length; i++) {
      final dx = _points[i].x - _points[i - 1].x;
      final dy = _points[i].y - _points[i - 1].y;
      cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
    }
    return cum;
  }

  /// Total length of the centerline — the finish distance for a line, one
  /// full circuit for a loop.
  double get length => _cumulative.last;

  /// Perpendicular distance from (x, y) to the nearest point on the
  /// centerline.
  double lateralDistance(double x, double y) {
    var best = double.infinity;
    for (var i = 0; i < _points.length - 1; i++) {
      final d = _pointToSegmentDistance(x, y, _points[i], _points[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  bool isOnTrack(double x, double y) =>
      lateralDistance(x, y) <= widthWorld / 2;

  /// Arclength of the point on the centerline nearest to (x, y), from 0 at
  /// the start up to [length].
  ///
  /// This is a *positional* projection: on a closed track it cannot tell
  /// "still at the start" from "just completed a lap". Callers that need
  /// monotonic lap progress must unwrap it themselves against the previous
  /// reading (see `PitchCarsSim._updateProgress`).
  double progressAt(double x, double y) {
    var best = double.infinity;
    var bestArc = 0.0;
    for (var i = 0; i < _points.length - 1; i++) {
      final a = _points[i];
      final b = _points[i + 1];
      final t = _projectT(x, y, a, b);
      final px = a.x + (b.x - a.x) * t;
      final py = a.y + (b.y - a.y) * t;
      final dx = x - px;
      final dy = y - py;
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        final segLen = _cumulative[i + 1] - _cumulative[i];
        bestArc = _cumulative[i] + segLen * t;
      }
    }
    return bestArc;
  }

  /// The centerline point at arclength [s]. Wraps for a closed track.
  Waypoint pointAtArclength(double s) {
    final clamped = closed
        ? s % length
        : s.clamp(0.0, length);
    for (var i = 0; i < _cumulative.length - 1; i++) {
      if (clamped <= _cumulative[i + 1] || i == _cumulative.length - 2) {
        final segLen = _cumulative[i + 1] - _cumulative[i];
        final t = segLen < 1e-9 ? 0.0 : (clamped - _cumulative[i]) / segLen;
        final a = _points[i];
        final b = _points[i + 1];
        return Waypoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
      }
    }
    return _points.last;
  }

  /// Unit tangent direction of the centerline at arclength [s].
  Waypoint tangentAt(double s) {
    const eps = 0.01;
    final a = pointAtArclength(closed ? s - eps : math.max(0, s - eps));
    final b = pointAtArclength(closed ? s + eps : math.min(length, s + eps));
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    return len < 1e-9 ? const Waypoint(1, 0) : Waypoint(dx / len, dy / len);
  }

  static double _projectT(double x, double y, Waypoint a, Waypoint b) {
    final abx = b.x - a.x;
    final aby = b.y - a.y;
    final lenSq = abx * abx + aby * aby;
    if (lenSq < 1e-9) return 0;
    final t = ((x - a.x) * abx + (y - a.y) * aby) / lenSq;
    return t.clamp(0.0, 1.0);
  }

  static double _pointToSegmentDistance(
      double x, double y, Waypoint a, Waypoint b) {
    final t = _projectT(x, y, a, b);
    final px = a.x + (b.x - a.x) * t;
    final py = a.y + (b.y - a.y) * t;
    final dx = x - px;
    final dy = y - py;
    return math.sqrt(dx * dx + dy * dy);
  }
}
