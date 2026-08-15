import 'dart:math' as math;

import 'track.dart';

/// A barrier along the outside of one bend, as a polyline in world units.
class CornerWall {
  const CornerWall(this.points);

  /// Already offset to the track's edge, and thinned so no two consecutive
  /// points sit closer than Box2D will accept in a chain.
  final List<Waypoint> points;
}

/// Works out where a car needs a wall to stop it flying off the outside of a
/// bend, and where the road can be left open.
///
/// ## Why not just threshold the angle at each vertex
///
/// [TrackGenerator] samples its spline at eight points per control segment, so
/// on a small table the centerline's vertices are under a centimetre apart.
/// Spread over that many points, even a hairpin turns only a few degrees at any
/// single one of them. Pick a per-vertex threshold and it is either low enough
/// to wall the whole track or high enough to wall none of it; there is no
/// setting in between, because the quantity being measured depends on how
/// finely the spline happened to be sampled rather than on the shape of the
/// road.
///
/// ## What decides it instead
///
/// What actually throws a car off is how tight the bend is **relative to how
/// wide the road is**. Thirty degrees swept over twenty centimetres is a lazy
/// curve you can drive round; the same thirty degrees over two centimetres is a
/// hairpin that will spit you into the dead space. So the measure here is turn
/// per distance — curvature — and the distance it is measured over is one track
/// width:
///
///     wall where |Σ turn over one width of arc| ≥ [turnPerWidth]
///
/// Sampling density cancels out: halving the spacing halves each vertex's turn
/// and doubles how many fall in the window. And because the window and the
/// threshold are both expressed in track widths, one number means the same
/// thing on the 2.25 cm road a two-phone table gets and the 4.35 cm road an
/// eight-phone table gets — [PitchCarsScale] can move the width around without
/// anything here needing a second set of constants.
///
/// The sign of that sum says which way the road bends, and therefore which side
/// is the outside. That comes free with the measurement.
class CornerWalls {
  const CornerWalls._();

  /// The sweep this measures has an exact meaning, and it is worth stating
  /// because it turns this constant into a radius:
  ///
  ///     sweep over one width of arc  =  W / R      (radians)
  ///
  /// so a threshold of θ walls every bend of radius `R ≤ W / θ`. At 18° that
  /// is **R ≤ 3.2 road widths**.
  ///
  /// This was 30° — R ≤ 1.9 widths — and it was too strict by exactly the
  /// margin that leaves a track looking half-finished. A two-and-a-half-width
  /// bend sweeps 22.9°, sailed under the cutoff, and got no kerb at all, while
  /// the one-and-a-half-width bend next to it swept 38.3° and did. One S, one
  /// wall, and no way to tell from the road which of its two turns would hold
  /// you.
  ///
  /// A flicked car has no steering: it travels in a straight line and leaves a
  /// bend of *any* radius given enough speed. So the job here is not to find
  /// hairpins, it is to find every bend a shot can realistically carry a car
  /// off — which is a much more generous line than the first number drawn.
  static const double defaultTurnPerWidth = math.pi / 10;

  /// How far past each end of a bend the wall keeps going, in track widths.
  ///
  /// Not optional, and this is the reason: a wall that starts exactly where the
  /// curvature threshold is crossed presents its leading *end* to a car
  /// arriving fast, and the car goes round it into the dead space the wall was
  /// there to prevent. Starting early means the car meets the side of the wall,
  /// which is what a wall is for.
  ///
  /// Half a width rather than a whole one, because a whole one was overrunning
  /// visibly — it is applied at *both* ends, so it added two full track widths
  /// of kerb to every bend and the barriers read as longer than the corners
  /// they belonged to. Half still puts the car's first contact on the flank.
  ///
  /// This is the knob for "the walls are too long". The threshold is not: raise
  /// that and gentle bends stop being walled at all, which is a different
  /// complaint entirely — see [defaultTurnPerWidth].
  static const double defaultPadWidths = 0.5;

  /// Bends shorter than this — in track widths of arc — are left open.
  ///
  /// A stretch that only just crosses the threshold for two or three vertices
  /// is a wobble in the spline, not a corner, and walling it scatters stubs of
  /// barrier along a road that reads as straight.
  static const double defaultMinRunWidths = 0.5;

  /// No two points in a returned wall are closer than this.
  ///
  /// `ChainShape.createChain` *throws* on vertices nearer than Box2D's
  /// `linearSlop` (0.005), and the centerline can easily produce a pair that
  /// close — the spline sampler emits its control points exactly, so a
  /// boundary point can coincide with the sample beside it. Thinning at well
  /// above the limit rather than at it leaves room for the offset arithmetic
  /// to move points around without landing back on the floor.
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
      // Judged before padding: the pad is there to make a real corner's wall
      // usable, not to promote a wobble into one.
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

  // ── measuring the road ──────────────────────────────────────────────────────

  static List<double> _arcLengths(List<Waypoint> pts) {
    final arc = List<double>.filled(pts.length, 0);
    for (var i = 1; i < pts.length; i++) {
      arc[i] = arc[i - 1] + _dist(pts[i - 1], pts[i]);
    }
    return arc;
  }

  /// Signed turn at each interior vertex, positive one way round and negative
  /// the other. `atan2(cross, dot)` rather than `acos` of the dot product: the
  /// latter loses the sign, and the sign is the half of this that says which
  /// side of the road the wall goes on.
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

  /// How much the road turns in the width-of-arc centred on each vertex.
  ///
  /// Straight summation, including sign, so an S-bend's two halves do not add
  /// up — where the road stops turning one way and starts turning the other,
  /// the window covering the changeover reads near zero, which is right. That
  /// is a place with no outside to wall.
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

  // ── picking out the bends ───────────────────────────────────────────────────

  static List<_Run> _runsOverThreshold(List<double> swept, double threshold) {
    final runs = <_Run>[];
    var start = -1;
    var side = 0;

    for (var i = 0; i < swept.length; i++) {
      final over = swept[i].abs() >= threshold;
      final here = over ? (swept[i] > 0 ? 1 : -1) : 0;
      // A change of direction ends the run even though both halves are over
      // the threshold: they are two corners bending opposite ways, and they
      // want their walls on opposite sides of the road.
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

  /// Joins runs that padding has pushed into each other — but only when they
  /// bend the same way. Two opposite bends whose pads overlap stay two walls,
  /// on opposite sides, which is what an S actually needs.
  static List<_Run> _mergeSameSide(List<_Run> runs) {
    final merged = <_Run>[];
    for (final run in runs) {
      final last = merged.isEmpty ? null : merged.last;
      if (last != null && last.side == run.side && run.start <= last.end) {
        merged[merged.length - 1] =
            _Run(last.start, math.max(last.end, run.end), last.side);
      } else {
        merged.add(run);
      }
    }
    return merged;
  }

  // ── building the barrier ────────────────────────────────────────────────────

  /// The track's edge on the outside of [run].
  ///
  /// Each centerline point is pushed half a width along the normal facing away
  /// from the turn, and the results joined by straight chords. Those chords cut
  /// very slightly inside the true offset curve, which bulges out at a convex
  /// corner — so the wall sits a hair *inside* the road rather than a hair
  /// outside it. That is the right way round to be wrong: a car held by this
  /// wall is unambiguously still on the track by `PitchTrack.isOnTrack`, and
  /// will not be reset out from under the player.
  static List<Waypoint> _outerEdge(
    List<Waypoint> pts,
    _Run run,
    double width,
  ) {
    final half = width / 2;
    final edge = <Waypoint>[];

    for (var i = run.start; i <= run.end; i++) {
      final prev = pts[math.max(i - 1, 0)];
      final next = pts[math.min(i + 1, pts.length - 1)];
      final tx = next.x - prev.x;
      final ty = next.y - prev.y;
      final len = math.sqrt(tx * tx + ty * ty);
      if (len < 1e-9) continue;

      // Turning one way puts the outside on the right of travel, the other way
      // on the left. `run.side` carries which, from the sign of the sweep.
      final nx = run.side > 0 ? ty / len : -ty / len;
      final ny = run.side > 0 ? -tx / len : tx / len;
      edge.add(Waypoint(pts[i].x + nx * half, pts[i].y + ny * half));
    }
    return edge;
  }

  /// Drops points too close to the one before them — see [_minVertexGap].
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

/// A stretch of centerline that bends hard enough to need a wall, and which
/// way it bends.
class _Run {
  const _Run(this.start, this.end, this.side);
  final int start;
  final int end;

  /// +1 or -1, from the sign of the swept turn.
  final int side;
}
