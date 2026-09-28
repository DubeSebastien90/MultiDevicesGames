import 'dart:typed_data';

/// Smooth outlines for the paint, from the grid the rules keep it in.
///
/// The sim paints in cells because cells make the rules exact: a loop is
/// filled by a flood, a cut is a lookup, an area is a count. Drawn as cells,
/// though, every edge is a staircase. So each phone traces the edge of every
/// territory instead, and rounds it off:
///
/// 1. **Marching squares** walks the grid a square of four cell centres at a
///    time and puts a point on every side where one centre is inside and the
///    next is not — halfway between them. That already turns every staircase
///    step into a diagonal.
/// 2. The segments are **joined into closed loops**. Outlines and holes come
///    out alike; filling them even-odd is what makes a hole a hole.
/// 3. Each loop is **relaxed** with Taubin smoothing. On a shallow slope
///    marching squares leaves a long flat run and then a one-cell step;
///    corner-cutting alone only rounds the step off, which reads as a ripple.
///    Pulling every point toward its neighbours spreads the step over the run —
///    but done plainly it also shrinks the whole shape, which lost half of a
///    small block and opened a gap between two neighbours. Taubin alternates
///    that pull with a slightly stronger push back out, which irons out the
///    steps and leaves the size alone.
/// 4. **Chaikin** corner-cutting finishes it: every corner is replaced by two
///    points a quarter of the way along its sides.
///
/// Two territories side by side share the same halfway points, so their
/// outlines meet rather than leaving a hairline of paper between them.
class PaintContours {
  const PaintContours._();

  /// Taubin's pull and push, and how many rounds of the pair. The push has to
  /// be a little stronger than the pull for the shape to keep its size.
  static const double relaxPull = 0.5;
  static const double relaxPush = -0.53;
  static const int relaxRounds = 12;

  /// How many points either side each point is pulled toward, a cell apart.
  /// A step on a shallow slope is a run of several cells: pulling toward only
  /// the two nearest points smooths the corner of the step and leaves the
  /// ripple, so the pull looks further along.
  ///
  /// Never more than a twelfth of the loop: on a small shape the far points
  /// are across a corner rather than along a step, and pulling toward them
  /// shrinks it however hard Taubin pushes back.
  static const int relaxReach = 4;

  /// Rounds of corner-cutting after that. Each doubles the points.
  static const int smoothing = 2;

  /// The paint as a grid of owners — a painter's index, or -1 — decoded from
  /// the sim's run-length string: a letter per owner (`.` for nobody), then
  /// how many cells of it, row after row.
  static Int8List decode(String raw) {
    final runs = <(int, int)>[];
    var cells = 0;
    var i = 0;
    while (i < raw.length) {
      final owner = raw.codeUnitAt(i);
      i++;
      var n = 0;
      while (i < raw.length) {
        final c = raw.codeUnitAt(i);
        if (c < 48 || c > 57) break;
        n = n * 10 + (c - 48);
        i++;
      }
      runs.add((owner == 46 ? -1 : owner - 97, n));
      cells += n;
    }
    final owners = Int8List(cells);
    var k = 0;
    for (final (owner, n) in runs) {
      owners.fillRange(k, k + n, owner);
      k += n;
    }
    return owners;
  }

  /// Every closed outline of [owner]'s paint, smoothed, in world coordinates.
  ///
  /// The grid is [gw] cells across, each [cell] wide, its corner at ([gx],
  /// [gy]). Outside the grid counts as unpainted, so a territory against the
  /// edge of the board is outlined along that edge.
  static List<List<(double, double)>> outlines(
    Int8List owners, {
    required int owner,
    required int gw,
    required double gx,
    required double gy,
    required double cell,
  }) {
    final gh = owners.length ~/ gw;
    bool inside(int i, int j) =>
        i >= 0 && j >= 0 && i < gw && j < gh && owners[j * gw + i] == owner;

    // A point on a side between two cell centres, as one integer: the square
    // to the right of or below a centre, and which of the two sides it is.
    final stride = gw + 2;
    int across(int i, int j) => ((j + 1) * stride + (i + 1)) * 2; // i ~ i+1
    int down(int i, int j) => ((j + 1) * stride + (i + 1)) * 2 + 1; // j ~ j+1

    final links = <int, List<int>>{};
    void link(int a, int b) {
      (links[a] ??= <int>[]).add(b);
      (links[b] ??= <int>[]).add(a);
    }

    // Each square is the four centres (i, j), (i+1, j), (i+1, j+1), (i, j+1).
    // Diagonal-only neighbours are kept apart (the two saddle cases), which is
    // what the flood in the sim does too.
    for (var j = -1; j < gh; j++) {
      for (var i = -1; i < gw; i++) {
        final a = inside(i, j);
        final b = inside(i + 1, j);
        final c = inside(i + 1, j + 1);
        final d = inside(i, j + 1);
        final index = (a ? 8 : 0) | (b ? 4 : 0) | (c ? 2 : 0) | (d ? 1 : 0);
        if (index == 0 || index == 15) continue;

        final top = across(i, j);
        final bottom = across(i, j + 1);
        final left = down(i, j);
        final right = down(i + 1, j);

        switch (index) {
          case 1 || 14:
            link(left, bottom);
          case 2 || 13:
            link(bottom, right);
          case 3 || 12:
            link(left, right);
          case 4 || 11:
            link(top, right);
          case 6 || 9:
            link(top, bottom);
          case 7 || 8:
            link(top, left);
          case 5:
            link(top, right);
            link(left, bottom);
          case 10:
            link(top, left);
            link(bottom, right);
        }
      }
    }

    (double, double) pointOf(int key) {
      final vertical = key.isOdd;
      final base = key ~/ 2;
      final i = base % stride - 1;
      final j = base ~/ stride - 1;
      // Centres sit at (i + 0.5) cells; a side point is halfway to the next.
      return vertical
          ? (gx + (i + 0.5) * cell, gy + (j + 1) * cell)
          : (gx + (i + 1) * cell, gy + (j + 0.5) * cell);
    }

    final loops = <List<(double, double)>>[];
    final seen = <int>{};
    for (final start in links.keys) {
      if (seen.contains(start)) continue;
      final loop = <(double, double)>[];
      var previous = -1;
      var current = start;
      while (true) {
        seen.add(current);
        loop.add(pointOf(current));
        final next = links[current]!;
        final step = next[0] != previous ? next[0] : next[1];
        previous = current;
        current = step;
        if (current == start || seen.contains(current)) break;
      }
      if (loop.length >= 3) loops.add(_chaikin(_straighten(_relax(loop))));
    }
    return loops;
  }

  /// Taubin smoothing: each round, every point is moved toward the average of
  /// the [relaxReach] points either side of it by [relaxPull], then away by
  /// [relaxPush]. A loop too short to smooth is left alone — it is a speck.
  static List<(double, double)> _relax(List<(double, double)> loop) {
    final n = loop.length;
    if (n < 5) return loop;
    final reach = (n ~/ 12).clamp(1, relaxReach);
    final xs = Float64List(n);
    final ys = Float64List(n);
    for (var k = 0; k < n; k++) {
      final (x, y) = loop[k];
      xs[k] = x;
      ys[k] = y;
    }
    final nx = Float64List(n);
    final ny = Float64List(n);
    void move(double by) {
      for (var k = 0; k < n; k++) {
        var sx = 0.0;
        var sy = 0.0;
        for (var d = 1; d <= reach; d++) {
          final a = (k - d + n) % n;
          final b = (k + d) % n;
          sx += xs[a] + xs[b];
          sy += ys[a] + ys[b];
        }
        final w = reach * 2;
        nx[k] = xs[k] + by * (sx / w - xs[k]);
        ny[k] = ys[k] + by * (sy / w - ys[k]);
      }
      xs.setAll(0, nx);
      ys.setAll(0, ny);
    }

    for (var round = 0; round < relaxRounds; round++) {
      move(relaxPull);
      move(relaxPush);
    }
    return [for (var k = 0; k < n; k++) (xs[k], ys[k])];
  }

  /// Drops the points in the middle of straight runs: a long flat edge is
  /// dozens of halfway points in a line, and cutting their corners is work
  /// that changes nothing.
  static List<(double, double)> _straighten(List<(double, double)> loop) {
    final n = loop.length;
    final out = <(double, double)>[];
    for (var k = 0; k < n; k++) {
      final (px, py) = loop[(k - 1 + n) % n];
      final (x, y) = loop[k];
      final (nx, ny) = loop[(k + 1) % n];
      final cross = (x - px) * (ny - y) - (y - py) * (nx - x);
      if (cross.abs() > 1e-9) out.add(loop[k]);
    }
    return out.length >= 3 ? out : loop;
  }

  static List<(double, double)> _chaikin(List<(double, double)> loop) {
    var points = loop;
    for (var round = 0; round < smoothing; round++) {
      final n = points.length;
      final next = <(double, double)>[];
      for (var k = 0; k < n; k++) {
        final (x0, y0) = points[k];
        final (x1, y1) = points[(k + 1) % n];
        next
          ..add((x0 * 0.75 + x1 * 0.25, y0 * 0.75 + y1 * 0.25))
          ..add((x0 * 0.25 + x1 * 0.75, y0 * 0.25 + y1 * 0.75));
      }
      points = next;
    }
    return points;
  }
}
