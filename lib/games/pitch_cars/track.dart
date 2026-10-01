import 'dart:math' as math;

import '../../sdk/contract/sim.dart' show PhoneSlice;
import '../../sdk/layout/board_links.dart';
import '../../sdk/model/world_rect.dart';
import 'pitch_cars_config.dart';
import 'pitch_cars_scale.dart';

class Waypoint {
  const Waypoint(this.x, this.y);
  final double x;
  final double y;
}

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

  double get length => _cumulative.last;

  late final List<Waypoint> collisionOutline = List.unmodifiable(_points);

  double lateralDistance(double x, double y) {
    var best = double.infinity;
    for (var i = 0; i < _points.length - 1; i++) {
      final d = _pointToSegmentDistance(x, y, _points[i], _points[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  bool isOnTrack(double x, double y) => lateralDistance(x, y) <= widthWorld / 2;

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

  Waypoint pointAtArclength(double s) {
    final clamped = closed ? s % length : s.clamp(0.0, length);
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
    double x,
    double y,
    Waypoint a,
    Waypoint b,
  ) {
    final t = _projectT(x, y, a, b);
    final px = a.x + (b.x - a.x) * t;
    final py = a.y + (b.y - a.y) * t;
    final dx = x - px;
    final dy = y - py;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class TrackGenerator {
  const TrackGenerator._();

  static PitchTrack generate({
    required List<PhoneSlice> slices,
    required math.Random random,
    PitchCarsScale? scale,
  }) {
    assert(slices.length >= 2, 'a track needs at least two phones');
    final tuning = scale ?? PitchCarsScale.forPlayers(slices.length);
    final widthWorld = tuning.trackWidthWorld;
    final chain = _recoverChainOrder(slices);
    final markers = BoardLinks.of(chain);
    final seams = [
      for (var i = 0; i < chain.length - 1; i++)
        _seamPoint(markers, chain[i].phoneId, chain[i + 1].phoneId),
    ];

    final control = <Waypoint>[];
    for (var i = 0; i < chain.length; i++) {
      final viewport = chain[i].viewport;
      final entry = i == 0
          ? _outerPoint(viewport, seams[0], widthWorld)
          : seams[i - 1];
      final exit = i == chain.length - 1
          ? _outerPoint(viewport, seams[i - 1], widthWorld)
          : seams[i];

      final relation = i == 0 || i == chain.length - 1
          ? _Relation.opposite
          : _classify(
              _nearestEdge(entry, viewport),
              _nearestEdge(exit, viewport),
            );

      if (i == 0) control.add(entry);
      control.addAll(
        _bendPoints(
          entry: entry,
          exit: exit,
          viewport: viewport,
          straightThrough: relation == _Relation.opposite,
          tuning: tuning,
          random: random,
        ),
      );
      control.add(exit);
    }

    final waypoints = _sampleCatmullRom(
      control,
      PitchCarsConfig.splineSamplesPerSegment,
    );
    return PitchTrack(
      waypoints: waypoints,
      widthWorld: widthWorld,
      closed: false,
    );
  }

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

    List<String> walkFrom(String startId) {
      final ordered = <String>[];
      final visited = <String>{};
      var current = startId;
      while (true) {
        ordered.add(current);
        visited.add(current);
        final next = neighbors[current]!.firstWhere(
          (id) => !visited.contains(id),
          orElse: () => '',
        );
        if (next.isEmpty) break;
        current = next;
      }
      return ordered;
    }

    final degreeOneStarts = neighbors.entries
        .where((e) => e.value.length <= 1)
        .map((e) => e.key);
    final starts = degreeOneStarts.isNotEmpty
        ? degreeOneStarts
        : neighbors.keys;

    var best = <String>[];
    for (final start in starts) {
      final walk = walkFrom(start);
      if (walk.length > best.length) best = walk;
    }

    return [for (final id in best) byId[id]!];
  }

  static Waypoint _seamPoint(List<EdgeMarker> markers, String aId, String bId) {
    for (final m in markers) {
      if (m.phoneId == aId && m.partnerId == bId) {
        return Waypoint((m.x1 + m.x2) / 2, (m.y1 + m.y2) / 2);
      }
    }
    throw StateError('no join marker between $aId and $bId');
  }

  static Waypoint _outerPoint(
    WorldRect viewport,
    Waypoint towardSeam,
    double widthWorld,
  ) {
    final margin = widthWorld / 2;
    final left = math.min(viewport.left + margin, viewport.centerX);
    final right = math.max(viewport.right - margin, viewport.centerX);
    final top = math.min(viewport.top + margin, viewport.centerY);
    final bottom = math.max(viewport.bottom - margin, viewport.centerY);
    final x = (2 * viewport.centerX - towardSeam.x).clamp(left, right);
    final y = (2 * viewport.centerY - towardSeam.y).clamp(top, bottom);
    return Waypoint(x, y);
  }

  static _Edge _nearestEdge(Waypoint p, WorldRect v) {
    final dl = (p.x - v.left).abs();
    final dr = (p.x - v.right).abs();
    final dt = (p.y - v.top).abs();
    final db = (p.y - v.bottom).abs();
    final m = math.min(math.min(dl, dr), math.min(dt, db));
    if (m == dl) return _Edge.left;
    if (m == dr) return _Edge.right;
    if (m == dt) return _Edge.top;
    return _Edge.bottom;
  }

  static bool _isOpposite(_Edge a, _Edge b) =>
      (a == _Edge.left && b == _Edge.right) ||
      (a == _Edge.right && b == _Edge.left) ||
      (a == _Edge.top && b == _Edge.bottom) ||
      (a == _Edge.bottom && b == _Edge.top);

  static _Relation _classify(_Edge a, _Edge b) =>
      _isOpposite(a, b) ? _Relation.opposite : _Relation.adjacent;

  static List<Waypoint> _bendPoints({
    required Waypoint entry,
    required Waypoint exit,
    required WorldRect viewport,
    required bool straightThrough,
    required PitchCarsScale tuning,
    required math.Random random,
  }) {
    final count = tuning.bendsPerPhone;
    if (count <= 0) return const [];

    final dx = exit.x - entry.x;
    final dy = exit.y - entry.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
      return [Waypoint((entry.x + exit.x) / 2, (entry.y + exit.y) / 2)];
    }
    final nx = -dy / len;
    final ny = dx / len;

    final baseAmplitude = straightThrough
        ? tuning.lineAmplitudeWorld
        : tuning.cornerAmplitudeWorld;
    final halfWidth = tuning.trackWidthWorld / 2;

    const safetyFactor = 0.5;

    final along = count == 1 ? <double>[0.5] : <double>[1 / 3, 2 / 3];
    final firstSign = random.nextBool() ? 1.0 : -1.0;

    final bends = <Waypoint>[];
    for (var k = 0; k < along.length; k++) {
      final t = along[k];
      final px = entry.x + dx * t;
      final py = entry.y + dy * t;

      final maxPos =
          _maxOffsetAlong(px, py, nx, ny, halfWidth, viewport) * safetyFactor;
      final maxNeg =
          _maxOffsetAlong(px, py, -nx, -ny, halfWidth, viewport) * safetyFactor;
      final capped = math.min(baseAmplitude, math.min(maxPos, maxNeg));

      final sign = firstSign * (k.isEven ? 1.0 : -1.0);
      final amount = capped * sign * (0.5 + random.nextDouble() * 0.5);
      bends.add(Waypoint(px + nx * amount, py + ny * amount));
    }
    return bends;
  }

  static double _maxOffsetAlong(
    double x,
    double y,
    double dx,
    double dy,
    double margin,
    WorldRect v,
  ) {
    final left = v.left + margin;
    final right = v.right - margin;
    final top = v.top + margin;
    final bottom = v.bottom - margin;
    if (right <= left || bottom <= top) return 0.0;

    var tMax = double.infinity;
    if (dx > 1e-9) {
      tMax = math.min(tMax, (right - x) / dx);
    } else if (dx < -1e-9) {
      tMax = math.min(tMax, (left - x) / dx);
    }
    if (dy > 1e-9) {
      tMax = math.min(tMax, (bottom - y) / dy);
    } else if (dy < -1e-9) {
      tMax = math.min(tMax, (top - y) / dy);
    }
    return tMax.isFinite ? math.max(tMax, 0.0) : 0.0;
  }

  static List<Waypoint> _sampleCatmullRom(
    List<Waypoint> control,
    int samplesPerSegment,
  ) {
    if (control.length < 2) return control;
    final pts = [control.first, ...control, control.last];
    final result = <Waypoint>[];
    for (var i = 1; i < pts.length - 2; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2];
      final startJ = i == 1 ? 0 : 1;
      for (var j = startJ; j <= samplesPerSegment; j++) {
        if (j == 0) {
          result.add(p1);
          continue;
        }
        if (j == samplesPerSegment) {
          result.add(p2);
          continue;
        }
        final t = j / samplesPerSegment;
        result.add(_catmullRomPoint(p0, p1, p2, p3, t));
      }
    }
    return result;
  }

  static Waypoint _catmullRomPoint(
    Waypoint p0,
    Waypoint p1,
    Waypoint p2,
    Waypoint p3,
    double t,
  ) {
    final t2 = t * t;
    final t3 = t2 * t;
    double blend(double v0, double v1, double v2, double v3) =>
        0.5 *
        ((2 * v1) +
            (-v0 + v2) * t +
            (2 * v0 - 5 * v1 + 4 * v2 - v3) * t2 +
            (-v0 + 3 * v1 - 3 * v2 + v3) * t3);
    return Waypoint(
      blend(p0.x, p1.x, p2.x, p3.x),
      blend(p0.y, p1.y, p2.y, p3.y),
    );
  }
}

enum _Edge { left, right, top, bottom }

enum _Relation { opposite, adjacent }
