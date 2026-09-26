import 'dart:math' as math;

import '../model/coverage_map.dart';
import '../model/world_rect.dart';

/// The part of the board a game will actually let something stand on, built
/// from the screens themselves rather than from a rectangle drawn around them.
///
/// ## Why a rectangle is not enough
///
/// `Layouts.row` and `Layouts.grid` hand a game the *intersection* of the
/// phones' depths — the band every screen reaches — so that nothing can end up
/// somewhere no screen can draw it. With matched phones that is the whole
/// board and costs nothing. Put a 58 mm phone beside a 78 mm one and it is the
/// small phone's depth: the big phone's remaining screen sits outside the
/// playfield, shaded a different colour, unreachable. Half a screen paid as
/// rent on the smallest device at the table.
///
/// This is the other answer. The playable region is the **union** of the
/// screens, so every phone gets the whole of its own display, and the walls
/// follow the real outline — a staircase where a tall screen meets a short one
/// rather than a straight line across both.
///
/// ## The seams are part of it
///
/// Not a detail. `Gaps.casingsTouching` leaves a real bezel gap between two
/// phones, so the union of the *screens* is disconnected — wall it exactly and
/// a ball rebounds off the inside edge of each phone and can never reach a
/// neighbour, which is the seam trick the whole platform rests on. So the
/// region is the screens **plus** [CoverageMap.seamRects], which are precisely
/// the gaps a moving thing is meant to cross unseen.
///
/// The strips beside a small phone are not seams — there is no second screen on
/// the far side of them — so they are not added, and they stay walled. That
/// distinction is the entire difference between "the gap between two phones"
/// and "the space beside a short one", and `seamRects` already draws it.
///
/// ## How the shape is held
///
/// Every rectangle involved is axis-aligned, so the union is exact on the grid
/// of all their edges: slice the plane at every rectangle's x and at every
/// rectangle's y, and each cell of that grid is either wholly inside the region
/// or wholly outside it. No polygon clipping, no floating-point boundary cases,
/// and the walls fall out for free — a cell face with an inside cell on one
/// side and nothing on the other.
///
/// Screens turned to something other than a quarter turn are taken at their
/// bounding box, which is bigger than the screen. That is the same limit
/// [CoverageMap.seamRects] already works under, and no layout that reaches this
/// code turns a phone that way.
class PlayArea {
  PlayArea._(this._xs, this._ys, this._inside, this.walls, this.bounds);

  /// Grid lines, ascending. Cell `(i, j)` spans `_xs[i].._xs[i+1]` by
  /// `_ys[j].._ys[j+1]`.
  final List<double> _xs;
  final List<double> _ys;

  /// One flag per cell, row-major over `j` then `i`.
  final List<bool> _inside;

  /// Every face between an inside cell and the outside, with its normal
  /// pointing inward.
  final List<Wall> walls;

  /// The box around the whole region.
  final WorldRect bounds;

  /// Two edges nearer than this are the same edge. Screen positions come from
  /// millimetre arithmetic, so exact equality is not safe to rely on.
  static const _epsilon = 1e-6;

  static PlayArea of(CoverageMap coverage) {
    final rects = <WorldRect>[
      for (final screen in coverage.screens) screen.bounds,
      ...coverage.seamRects(),
    ];
    if (rects.isEmpty) {
      return PlayArea._(const [], const [], const [], const [], coverage.board);
    }

    final xs = _gridLines([for (final r in rects) r.left, for (final r in rects) r.right]);
    final ys = _gridLines([for (final r in rects) r.top, for (final r in rects) r.bottom]);

    final cols = xs.length - 1;
    final rows = ys.length - 1;
    final inside = List<bool>.filled(cols * rows, false);
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        // A cell never straddles an edge, so its middle decides the whole of
        // it — which is the point of cutting the grid where the edges are.
        final cx = (xs[i] + xs[i + 1]) / 2;
        final cy = (ys[j] + ys[j + 1]) / 2;
        for (final r in rects) {
          if (r.contains(cx, cy)) {
            inside[j * cols + i] = true;
            break;
          }
        }
      }
    }
    _fillJunctions(xs, ys, inside, cols, rows);

    return PlayArea._(
      xs,
      ys,
      inside,
      _wallsOf(xs, ys, inside, cols, rows),
      WorldRect(xs.first, ys.first, xs.last - xs.first, ys.last - ys.first),
    );
  }

  /// Where seams cross or meet, a bezel-sized patch belongs to no seam: the
  /// seam between two screens only runs as far as they overlap. In a grid it
  /// is the square at the middle of the cross, in a brick layout the one where
  /// the join above meets the phone below.
  ///
  /// Left out, it is a hole in the middle of the playfield with walls round
  /// it — a ball rebounds off nothing and a player snags on a corner nobody can
  /// see. So every patch of outside that is enclosed by the region and no
  /// bigger than a seam either way is taken in. Open table beside a short
  /// phone reaches the edge of the grid, so it is never enclosed and stays out.
  ///
  /// Patches rather than cells, because mismatched phones cut one junction
  /// into several cells, each with another piece of the hole beside it.
  static void _fillJunctions(
    List<double> xs,
    List<double> ys,
    List<bool> inside,
    int cols,
    int rows,
  ) {
    final seen = List<bool>.filled(cols * rows, false);
    for (var start = 0; start < cols * rows; start++) {
      if (inside[start] || seen[start]) continue;

      final patch = <int>[];
      final stack = [start];
      seen[start] = true;
      var enclosed = true;
      var left = double.infinity;
      var right = double.negativeInfinity;
      var top = double.infinity;
      var bottom = double.negativeInfinity;
      while (stack.isNotEmpty) {
        final k = stack.removeLast();
        patch.add(k);
        final i = k % cols;
        final j = k ~/ cols;
        left = math.min(left, xs[i]);
        right = math.max(right, xs[i + 1]);
        top = math.min(top, ys[j]);
        bottom = math.max(bottom, ys[j + 1]);
        for (final (di, dj) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
          final ni = i + di;
          final nj = j + dj;
          if (ni < 0 || nj < 0 || ni >= cols || nj >= rows) {
            enclosed = false;
            continue;
          }
          final n = nj * cols + ni;
          if (inside[n] || seen[n]) continue;
          seen[n] = true;
          stack.add(n);
        }
      }

      if (enclosed &&
          right - left <= CoverageMap.maxSeamWorld &&
          bottom - top <= CoverageMap.maxSeamWorld) {
        for (final k in patch) {
          inside[k] = true;
        }
      }
    }
  }

  static List<double> _gridLines(List<double> raw) {
    final sorted = [...raw]..sort();
    final out = <double>[sorted.first];
    for (final v in sorted.skip(1)) {
      if (v - out.last > _epsilon) out.add(v);
    }
    return out;
  }

  /// Every cell face with the region on one side and nothing on the other.
  static List<Wall> _wallsOf(
    List<double> xs,
    List<double> ys,
    List<bool> inside,
    int cols,
    int rows,
  ) {
    bool at(int i, int j) =>
        i >= 0 && j >= 0 && i < cols && j < rows && inside[j * cols + i];

    final walls = <Wall>[];
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        if (!at(i, j)) continue;
        // Normals point into the region, so a thing pushed along one ends up
        // where it is allowed to be.
        if (!at(i - 1, j)) {
          walls.add(Wall(xs[i], ys[j], xs[i], ys[j + 1], 1, 0));
        }
        if (!at(i + 1, j)) {
          walls.add(Wall(xs[i + 1], ys[j], xs[i + 1], ys[j + 1], -1, 0));
        }
        if (!at(i, j - 1)) {
          walls.add(Wall(xs[i], ys[j], xs[i + 1], ys[j], 0, 1));
        }
        if (!at(i, j + 1)) {
          walls.add(Wall(xs[i], ys[j + 1], xs[i + 1], ys[j + 1], 0, -1));
        }
      }
    }
    return walls;
  }

  bool contains(double x, double y) {
    final i = _cellIndex(_xs, x);
    final j = _cellIndex(_ys, y);
    if (i < 0 || j < 0) return false;
    return _inside[j * (_xs.length - 1) + i];
  }

  static int _cellIndex(List<double> lines, double v) {
    if (lines.length < 2 || v < lines.first || v >= lines.last) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) ~/ 2;
      if (v < lines[mid]) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return lo;
  }

  /// The nearest position to (x, y) where a disc of [radius] is clear of every
  /// wall.
  ///
  /// Pushing off each wall in turn and repeating settles the corners: a disc
  /// wedged into the inside angle where a tall screen meets a short one is over
  /// two walls at once, and one pass would leave it inside the other.
  ({double x, double y}) clamp(double x, double y, double radius) {
    var px = x;
    var py = y;

    if (!contains(px, py)) {
      final near = _nearestInside(px, py);
      px = near.x;
      py = near.y;
    }

    for (var pass = 0; pass < 4; pass++) {
      var moved = false;
      for (final wall in walls) {
        final closest = wall.closestPointTo(px, py);
        final dx = px - closest.x;
        final dy = py - closest.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= radius) continue;

        if (dist < _epsilon) {
          // Sitting on the wall: no direction to be pushed along except its
          // own normal.
          px = closest.x + wall.nx * radius;
          py = closest.y + wall.ny * radius;
        } else {
          px = closest.x + dx / dist * radius;
          py = closest.y + dy / dist * radius;
        }
        moved = true;
      }
      if (!moved) break;
    }
    return (x: px, y: py);
  }

  /// The nearest point inside the region, for something that has ended up
  /// outside it entirely.
  ({double x, double y}) _nearestInside(double x, double y) {
    var bestX = x;
    var bestY = y;
    var best = double.infinity;
    final cols = _xs.length - 1;

    for (var j = 0; j < _ys.length - 1; j++) {
      for (var i = 0; i < cols; i++) {
        if (!_inside[j * cols + i]) continue;
        final cx = x.clamp(_xs[i], _xs[i + 1]).toDouble();
        final cy = y.clamp(_ys[j], _ys[j + 1]).toDouble();
        final d = (cx - x) * (cx - x) + (cy - y) * (cy - y);
        if (d < best) {
          best = d;
          bestX = cx;
          bestY = cy;
        }
      }
    }
    return (x: bestX, y: bestY);
  }

  /// Reflect a moving disc off whatever wall it has run into.
  ///
  /// Returns the position and velocity unchanged when it has not hit anything,
  /// so a caller can apply this every step.
  ({double x, double y, double vx, double vy}) bounce(
    double x,
    double y,
    double vx,
    double vy,
    double radius,
  ) {
    Wall? hit;
    var deepest = 0.0;
    var hitDx = 0.0;
    var hitDy = 0.0;

    for (final wall in walls) {
      final closest = wall.closestPointTo(x, y);
      final dx = x - closest.x;
      final dy = y - closest.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final depth = radius - dist;
      // The wall it is furthest into is the one it hit; the others are
      // grazes it would be wrong to reflect off as well.
      if (depth > deepest) {
        deepest = depth;
        hit = wall;
        hitDx = dist < _epsilon ? wall.nx : dx / dist;
        hitDy = dist < _epsilon ? wall.ny : dy / dist;
      }
    }
    if (hit == null) return (x: x, y: y, vx: vx, vy: vy);

    final along = vx * hitDx + vy * hitDy;
    return (
      x: x + hitDx * deepest,
      y: y + hitDy * deepest,
      // Only reverse a velocity heading *into* the wall. Reflecting one that
      // is already leaving traps the disc against the wall, alternating.
      vx: along < 0 ? vx - 2 * along * hitDx : vx,
      vy: along < 0 ? vy - 2 * along * hitDy : vy,
    );
  }

  /// A point on the outer wall, [inset] in from it, and the direction pointing
  /// into the region — for spawning something that should arrive off an edge.
  ///
  /// Picked by length rather than by wall, so a long side is as likely as its
  /// share of the perimeter suggests. Choosing uniformly among walls would
  /// crowd whichever edge the grid happened to cut into the most pieces.
  ({double x, double y, double nx, double ny}) edgeSpawn(
    math.Random random,
    double inset,
  ) {
    if (walls.isEmpty) {
      return (x: bounds.centerX, y: bounds.centerY, nx: 0, ny: 1);
    }
    final total = walls.fold<double>(0, (sum, w) => sum + w.length);
    var pick = random.nextDouble() * total;
    var wall = walls.last;
    for (final w in walls) {
      if (pick < w.length) {
        wall = w;
        break;
      }
      pick -= w.length;
    }

    final t = random.nextDouble();
    final px = wall.x1 + (wall.x2 - wall.x1) * t + wall.nx * inset;
    final py = wall.y1 + (wall.y2 - wall.y1) * t + wall.ny * inset;
    final safe = clamp(px, py, inset);
    return (x: safe.x, y: safe.y, nx: wall.nx, ny: wall.ny);
  }
}

/// One straight run of boundary, with its normal pointing into the region.
class Wall {
  const Wall(this.x1, this.y1, this.x2, this.y2, this.nx, this.ny);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Unit, and pointing at the playable side.
  final double nx;
  final double ny;

  double get length => math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

  /// Nearest point on this wall to (x, y), ends included — so a disc at an
  /// inside corner is pushed away from the corner itself rather than through
  /// the wall beside it.
  ({double x, double y}) closestPointTo(double x, double y) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq < 1e-12) return (x: x1, y: y1);
    var t = ((x - x1) * dx + (y - y1) * dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    return (x: x1 + dx * t, y: y1 + dy * t);
  }
}
