import 'dart:math' as math;

import 'world_rect.dart';

class ScreenRect {
  const ScreenRect({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    this.turnRadians = 0,
  });

  final double centerX;
  final double centerY;

  final double width;
  final double height;

  final double turnRadians;

  WorldRect get bounds {
    final c = math.cos(turnRadians).abs();
    final s = math.sin(turnRadians).abs();
    final hw = (width / 2) * c + (height / 2) * s;
    final hh = (width / 2) * s + (height / 2) * c;
    return WorldRect(centerX - hw, centerY - hh, hw * 2, hh * 2);
  }

  bool get isTurned => turnRadians.abs() > 1e-9;

  bool contains(double x, double y) {
    final dx = x - centerX;
    final dy = y - centerY;
    final cos = math.cos(turnRadians);
    final sin = math.sin(turnRadians);
    final u = dx * cos + dy * sin;
    final v = -dx * sin + dy * cos;
    return u.abs() <= width / 2 && v.abs() <= height / 2;
  }

  Map<String, dynamic> toJson() => {
    'cx': centerX,
    'cy': centerY,
    'w': width,
    'h': height,
    if (turnRadians != 0) 'turn': turnRadians,
  };

  static ScreenRect fromJson(Map<String, dynamic> j) => ScreenRect(
    centerX: (j['cx'] as num).toDouble(),
    centerY: (j['cy'] as num).toDouble(),
    width: (j['w'] as num).toDouble(),
    height: (j['h'] as num).toDouble(),
    turnRadians: (j['turn'] as num?)?.toDouble() ?? 0,
  );
}

class CoverageMap {
  const CoverageMap({required this.screens, required this.board});

  final List<ScreenRect> screens;

  final WorldRect board;

  List<WorldRect> get liveRects => [for (final s in screens) s.bounds];

  static const double maxSeamWorld = 3.0;

  bool isCovered(double x, double y) {
    for (final s in screens) {
      if (s.contains(x, y)) return true;
    }
    return false;
  }

  List<WorldRect> seamRects() {
    const epsilon = 1e-6;
    final seams = <WorldRect>[];
    if (screens.any((s) => s.isTurned && !_isQuarterTurn(s.turnRadians))) {
      return seams;
    }
    final rects = liveRects;

    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final a = rects[i];
        final b = rects[j];

        final overlapTop = math.max(a.top, b.top);
        final overlapBottom = math.min(a.bottom, b.bottom);
        if (overlapBottom - overlapTop > epsilon) {
          final left = a.right <= b.left ? a : b;
          final right = identical(left, a) ? b : a;
          final gap = right.left - left.right;
          if (gap > epsilon) {
            final band = WorldRect(
              left.right,
              overlapTop,
              gap,
              overlapBottom - overlapTop,
            );
            if (gap <= maxSeamWorld &&
                _nothingInside(rects, band, a, b, epsilon)) {
              seams.add(band);
            }
            continue;
          }
        }

        final overlapLeft = math.max(a.left, b.left);
        final overlapRight = math.min(a.right, b.right);
        if (overlapRight - overlapLeft > epsilon) {
          final top = a.bottom <= b.top ? a : b;
          final bottom = identical(top, a) ? b : a;
          final gap = bottom.top - top.bottom;
          if (gap > epsilon) {
            final band = WorldRect(
              overlapLeft,
              top.bottom,
              overlapRight - overlapLeft,
              gap,
            );
            if (gap <= maxSeamWorld &&
                _nothingInside(rects, band, a, b, epsilon)) {
              seams.add(band);
            }
          }
        }
      }
    }
    return seams;
  }

  static bool _isQuarterTurn(double radians) {
    final quarters = radians / (math.pi / 2);
    return (quarters - quarters.roundToDouble()).abs() < 1e-6;
  }

  static bool _nothingInside(
    List<WorldRect> rects,
    WorldRect band,
    WorldRect a,
    WorldRect b,
    double eps,
  ) {
    for (final other in rects) {
      if (identical(other, a) || identical(other, b)) continue;
      final overlaps =
          other.left < band.right - eps &&
          other.right > band.left + eps &&
          other.top < band.bottom - eps &&
          other.bottom > band.top + eps;
      if (overlaps) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'screens': [for (final s in screens) s.toJson()],
    'board': board.toJson(),
  };

  static CoverageMap fromJson(Map<String, dynamic> j) => CoverageMap(
    screens: [
      for (final s in j['screens'] as List)
        ScreenRect.fromJson(s as Map<String, dynamic>),
    ],
    board: WorldRect.fromJson(j['board'] as Map<String, dynamic>),
  );
}
