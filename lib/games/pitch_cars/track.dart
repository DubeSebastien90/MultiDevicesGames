import 'dart:math' as math;

import '../../sdk/contract/sim.dart' show PhoneSlice;
import '../../sdk/layout/board_links.dart';
import '../../sdk/model/world_rect.dart';
import 'pitch_cars_config.dart';

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

/// Builds a random [PitchTrack] that follows the phones' physical chain.
class TrackGenerator {
  const TrackGenerator._();

  static PitchTrack generate({
    required List<PhoneSlice> slices,
    required math.Random random,
    double widthWorld = PitchCarsConfig.trackWidthWorld,
  }) {
    assert(slices.length >= 2, 'a track needs at least two phones');
    final chain = _recoverChainOrder(slices);
    final markers = BoardLinks.of(chain);
    final seams = [
      for (var i = 0; i < chain.length - 1; i++)
        _seamPoint(markers, chain[i].phoneId, chain[i + 1].phoneId),
    ];

    final start = _outerPoint(chain.first.viewport, seams.first);
    final end = _outerPoint(chain.last.viewport, seams.last);
    final waypoints = [start, ...seams, end];

    return PitchTrack(waypoints: waypoints, widthWorld: widthWorld, closed: false);
  }

  /// Recovers the phones in physical connection order from the compiled,
  /// reading-order slice list, using [BoardLinks] — the same adjacency the
  /// connector stripes are drawn from — rather than re-deriving it by hand.
  static List<PhoneSlice> _recoverChainOrder(List<PhoneSlice> slices) {
    if (slices.length <= 1) return slices;
    final byId = {for (final s in slices) s.phoneId: s};
    final neighbors = <String, List<String>>{
      for (final s in slices) s.phoneId: <String>[],
    };
    for (final v in BoardLinks.explain(slices)) {
      if (!v.joined) continue;
      neighbors[v.aId]!.add(v.bId);
      neighbors[v.bId]!.add(v.aId);
    }

    // One end of the chain has exactly one neighbour. Falls back to any
    // node if none does, which keeps a malformed (non-`Layouts.path`) board
    // from throwing here rather than producing a track.
    final startId = neighbors.entries
        .firstWhere((e) => e.value.length <= 1, orElse: () => neighbors.entries.first)
        .key;

    final ordered = <PhoneSlice>[];
    final visited = <String>{};
    var current = startId;
    while (true) {
      ordered.add(byId[current]!);
      visited.add(current);
      final next =
          neighbors[current]!.firstWhere((id) => !visited.contains(id), orElse: () => '');
      if (next.isEmpty) break;
      current = next;
    }

    // Defensive: a disconnected board (should never happen for
    // `Layouts.path`) still produces a track instead of throwing.
    for (final s in slices) {
      if (!visited.contains(s.phoneId)) ordered.add(s);
    }
    return ordered;
  }

  /// The midpoint of the shared edge between two joined phones — the same
  /// geometry the connector stripes are drawn from, read back off
  /// [BoardLinks.of]'s markers rather than recomputed independently.
  static Waypoint _seamPoint(List<EdgeMarker> markers, String aId, String bId) {
    // `BoardLinks.of` emits one marker per phone at that phone's own facing
    // edge, not a single shared line — with a real bezel gap between phones
    // (the common case), those two edges sit a few millimetres apart, and
    // averaging both lands the seam in the dead space between screens,
    // covered by neither. Using [aId]'s own edge instead keeps the seam on
    // an actual screen; when the boards are flush (no gap) the two edges
    // coincide anyway, so this is a no-op there.
    for (final m in markers) {
      if (m.phoneId == aId && m.partnerId == bId) {
        return Waypoint((m.x1 + m.x2) / 2, (m.y1 + m.y2) / 2);
      }
    }
    throw StateError('no join marker between $aId and $bId');
  }

  /// A point on [viewport]'s own boundary, on the opposite side from
  /// [towardSeam] — reflecting the seam through the phone's center and
  /// clamping to its rectangle. Used for the track's very start and end,
  /// which have no seam on one side.
  ///
  /// Inset by [_edgeEpsilon] on the far side: a seam that sits exactly on a
  /// phone's near edge (the common flush-board case) reflects to exactly its
  /// far edge, which `WorldRect.contains` excludes (`x < right`, not `<=`).
  static Waypoint _outerPoint(WorldRect viewport, Waypoint towardSeam) {
    const eps = _edgeEpsilon;
    final x = (2 * viewport.centerX - towardSeam.x)
        .clamp(viewport.left, viewport.right - eps);
    final y = (2 * viewport.centerY - towardSeam.y)
        .clamp(viewport.top, viewport.bottom - eps);
    return Waypoint(x, y);
  }

  static const double _edgeEpsilon = 1e-6;
}
