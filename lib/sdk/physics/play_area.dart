import 'dart:math' as math;

import '../model/coverage_map.dart';
import '../model/world_rect.dart';

class PlayArea {
  PlayArea._(this._xs, this._ys, this._inside, this.walls, this.bounds);

  final List<double> _xs;
  final List<double> _ys;

  final List<bool> _inside;

  final List<Wall> walls;

  final WorldRect bounds;

  static const _epsilon = 1e-6;

  static PlayArea of(CoverageMap coverage) {
    final rects = <WorldRect>[
      for (final screen in coverage.screens) screen.bounds,
      ...coverage.seamRects(),
    ];
    if (rects.isEmpty) {
      return PlayArea._(const [], const [], const [], const [], coverage.board);
    }

    final xs = _gridLines([
      for (final r in rects) r.left,
      for (final r in rects) r.right,
    ]);
    final ys = _gridLines([
      for (final r in rects) r.top,
      for (final r in rects) r.bottom,
    ]);

    final cols = xs.length - 1;
    final rows = ys.length - 1;
    final inside = List<bool>.filled(cols * rows, false);
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
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
      vx: along < 0 ? vx - 2 * along * hitDx : vx,
      vy: along < 0 ? vy - 2 * along * hitDy : vy,
    );
  }

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

class Wall {
  const Wall(this.x1, this.y1, this.x2, this.y2, this.nx, this.ny);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  final double nx;
  final double ny;

  double get length => math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

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
