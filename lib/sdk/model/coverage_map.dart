import 'world_rect.dart';

/// Which parts of the board are backed by a real screen.
///
/// The world is continuous and physics runs *everywhere*, including the dead
/// millimetres between two phones. This map is metadata on top, so a game can
/// choose a policy per dead zone. v1's slingshot uses [DeadZonePolicy.ignore]:
/// the bird crosses the bezel gap invisibly and reappears exactly where momentum
/// says it should. That is the seam trick, generalised — a dead zone is just a
/// wider seam.
///
/// A plain list of rectangles plus point-in-rect tests is correct for a handful
/// of screens. A grid/quadtree/bitmask only pays off with many screens or
/// per-pixel queries, so it is deliberately not here.
class CoverageMap {
  const CoverageMap({required this.liveRects, required this.board});

  /// One rectangle per phone's active area, in world coordinates.
  final List<WorldRect> liveRects;

  /// Bounding box of the playfield. It hugs the covered area, so the only dead
  /// zones are real gaps between screens and every one means the same thing.
  final WorldRect board;

  bool isCovered(double x, double y) {
    for (final r in liveRects) {
      if (r.contains(x, y)) return true;
    }
    return false;
  }

  /// The gaps between neighbouring screens — physically real space a ball or a
  /// bird must cross.
  ///
  /// Worked out geometrically rather than from a declared axis, because a game
  /// may lay the phones out any way it likes: a row has vertical seams, a
  /// column horizontal ones, and a grid or an L has both. Two screens are
  /// neighbours when they are separated along one axis while overlapping on the
  /// other, and the seam is the band between them, as wide as that overlap.
  ///
  /// Only *adjacent* screens make a seam. In a three-phone column the top and
  /// bottom phones are also separated and also overlap, but the space between
  /// them is mostly the middle phone — so a candidate band is discarded when
  /// any other screen sits inside it.
  List<WorldRect> seamRects() {
    const epsilon = 1e-6;
    final seams = <WorldRect>[];

    for (var i = 0; i < liveRects.length; i++) {
      for (var j = i + 1; j < liveRects.length; j++) {
        final a = liveRects[i];
        final b = liveRects[j];

        // Side by side, sharing some height → a vertical seam.
        final overlapTop = a.top > b.top ? a.top : b.top;
        final overlapBottom = a.bottom < b.bottom ? a.bottom : b.bottom;
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
            if (_nothingInside(band, a, b, epsilon)) seams.add(band);
            continue;
          }
        }

        // Stacked, sharing some width → a horizontal seam.
        final overlapLeft = a.left > b.left ? a.left : b.left;
        final overlapRight = a.right < b.right ? a.right : b.right;
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
            if (_nothingInside(band, a, b, epsilon)) seams.add(band);
          }
        }
      }
    }
    return seams;
  }

  /// True when no screen other than [a] and [b] intrudes into [band].
  bool _nothingInside(WorldRect band, WorldRect a, WorldRect b, double eps) {
    for (final other in liveRects) {
      if (identical(other, a) || identical(other, b)) continue;
      final overlaps = other.left < band.right - eps &&
          other.right > band.left + eps &&
          other.top < band.bottom - eps &&
          other.bottom > band.top + eps;
      if (overlaps) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'live': [for (final r in liveRects) r.toJson()],
    'board': board.toJson(),
  };

  static CoverageMap fromJson(Map<String, dynamic> j) => CoverageMap(
    liveRects: [
      for (final r in j['live'] as List)
        WorldRect.fromJson(r as Map<String, dynamic>),
    ],
    board: WorldRect.fromJson(j['board'] as Map<String, dynamic>),
  );
}

/// What a game does with a dead zone. v1 only implements [ignore]; the others
/// are here to record that the choice belongs to the game, not the platform.
enum DeadZonePolicy { ignore, wall, void_ }
