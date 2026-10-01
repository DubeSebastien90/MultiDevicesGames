import 'dart:math' as math;

import 'track.dart';

class CornerWall {
  const CornerWall(this.points);

  final List<Waypoint> points;
}

class CornerWalls {
  const CornerWalls._();

  static const double defaultTurnPerWidth = math.pi / 10;

  static const double defaultPadWidths = 0.5;

  static const double defaultMinRunWidths = 0.5;

  static const double _minVertexGap = 0.02;

  static List<CornerWall> of(
    PitchTrack track, {
    double turnPerWidth = defaultTurnPerWidth,
    double padWidths = defaultPadWidths,
    double minRunWidths = defaultMinRunWidths,
  }) {
    final pts = track.collisionOutline;
    final n = pts.length;
    if (n < 3) return const [];

    final width = track.widthWorld;
    if (width <= 0) return const [];

    final arc = _arcLengths(pts);
    final turn = _turnAngles(pts);
    final swept = _sweptOverWindow(turn, arc, width);

    final runs = _runsOverThreshold(swept, turnPerWidth);
    final kept = <_Run>[];
    for (final run in runs) {
      if (arc[run.end] - arc[run.start] < minRunWidths * width) continue;
      kept.add(_pad(run, arc, padWidths * width, n));
    }

    final walls = <CornerWall>[];
    for (final run in _mergeSameSide(kept)) {
      final points = _thin(_outerEdge(pts, run, width));
      if (points.length >= 2) walls.add(CornerWall(points));
    }
    return walls;
  }

  static List<double> _arcLengths(List<Waypoint> pts) {
    final arc = List<double>.filled(pts.length, 0);
    for (var i = 1; i < pts.length; i++) {
      arc[i] = arc[i - 1] + _dist(pts[i - 1], pts[i]);
    }
    return arc;
  }

  static List<double> _turnAngles(List<Waypoint> pts) {
    final turn = List<double>.filled(pts.length, 0);
    for (var i = 1; i < pts.length - 1; i++) {
      final ax = pts[i].x - pts[i - 1].x;
      final ay = pts[i].y - pts[i - 1].y;
      final bx = pts[i + 1].x - pts[i].x;
      final by = pts[i + 1].y - pts[i].y;
      turn[i] = math.atan2(ax * by - ay * bx, ax * bx + ay * by);
    }
    return turn;
  }

  static List<double> _sweptOverWindow(
    List<double> turn,
    List<double> arc,
    double width,
  ) {
    final n = turn.length;
    final half = width / 2;
    final swept = List<double>.filled(n, 0);

    for (var i = 0; i < n; i++) {
      var sum = turn[i];
      for (var j = i - 1; j >= 0 && arc[i] - arc[j] <= half; j--) {
        sum += turn[j];
      }
      for (var j = i + 1; j < n && arc[j] - arc[i] <= half; j++) {
        sum += turn[j];
      }
      swept[i] = sum;
    }
    return swept;
  }

  static List<_Run> _runsOverThreshold(List<double> swept, double threshold) {
    final runs = <_Run>[];
    var start = -1;
    var side = 0;

    for (var i = 0; i < swept.length; i++) {
      final over = swept[i].abs() >= threshold;
      final here = over ? (swept[i] > 0 ? 1 : -1) : 0;

      if (here != side) {
        if (side != 0) runs.add(_Run(start, i - 1, side));
        start = i;
        side = here;
      }
    }
    if (side != 0) runs.add(_Run(start, swept.length - 1, side));
    return runs;
  }

  static _Run _pad(_Run run, List<double> arc, double pad, int n) {
    var start = run.start;
    var end = run.end;
    while (start > 0 && arc[run.start] - arc[start - 1] < pad) {
      start--;
    }
    while (end < n - 1 && arc[end + 1] - arc[run.end] < pad) {
      end++;
    }
    return _Run(start, end, run.side);
  }

  static List<_Run> _mergeSameSide(List<_Run> runs) {
    final merged = <_Run>[];
    for (final run in runs) {
      final last = merged.isEmpty ? null : merged.last;
      if (last != null && last.side == run.side && run.start <= last.end) {
        merged[merged.length - 1] = _Run(
          last.start,
          math.max(last.end, run.end),
          last.side,
        );
      } else {
        merged.add(run);
      }
    }
    return merged;
  }

  static List<Waypoint> _outerEdge(List<Waypoint> pts, _Run run, double width) {
    final half = width / 2;
    final edge = <Waypoint>[];

    for (var i = run.start; i <= run.end; i++) {
      final prev = pts[math.max(i - 1, 0)];
      final next = pts[math.min(i + 1, pts.length - 1)];
      final tx = next.x - prev.x;
      final ty = next.y - prev.y;
      final len = math.sqrt(tx * tx + ty * ty);
      if (len < 1e-9) continue;

      final nx = run.side > 0 ? ty / len : -ty / len;
      final ny = run.side > 0 ? -tx / len : tx / len;
      edge.add(Waypoint(pts[i].x + nx * half, pts[i].y + ny * half));
    }
    return edge;
  }

  static List<Waypoint> _thin(List<Waypoint> points) {
    if (points.isEmpty) return points;
    final out = <Waypoint>[points.first];
    for (final p in points.skip(1)) {
      if (_dist(out.last, p) >= _minVertexGap) out.add(p);
    }
    return out;
  }

  static double _dist(Waypoint a, Waypoint b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _Run {
  const _Run(this.start, this.end, this.side);
  final int start;
  final int end;

  final int side;
}
