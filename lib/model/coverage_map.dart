import 'arrangement.dart';
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
  const CoverageMap({
    required this.liveRects,
    required this.board,
    this.arrangement = Arrangement.strip,
  });

  /// One rectangle per phone's active area, in world coordinates.
  final List<WorldRect> liveRects;

  /// Bounding box of the playfield. v1 keeps this hugging the covered area so
  /// the only dead zones are real bezel gaps and every one means the same thing.
  final WorldRect board;

  /// Which axis the phones were laid out along. Only [seamRects] needs it: a
  /// seam runs across the board perpendicular to that axis.
  final Arrangement arrangement;

  bool isCovered(double x, double y) {
    for (final r in liveRects) {
      if (r.contains(x, y)) return true;
    }
    return false;
  }

  /// The gaps between consecutive screens, in layout order. These are
  /// physically real space a ball or bird must traverse.
  List<WorldRect> seamRects() {
    final seams = <WorldRect>[];
    if (arrangement.isHorizontal) {
      final sorted = List.of(liveRects)
        ..sort((a, b) => a.left.compareTo(b.left));
      for (var i = 0; i < sorted.length - 1; i++) {
        final gap = sorted[i + 1].left - sorted[i].right;
        if (gap > 1e-6) {
          seams.add(WorldRect(sorted[i].right, board.top, gap, board.height));
        }
      }
    } else {
      final sorted = List.of(liveRects)..sort((a, b) => a.top.compareTo(b.top));
      for (var i = 0; i < sorted.length - 1; i++) {
        final gap = sorted[i + 1].top - sorted[i].bottom;
        if (gap > 1e-6) {
          seams.add(WorldRect(board.left, sorted[i].bottom, board.width, gap));
        }
      }
    }
    return seams;
  }

  Map<String, dynamic> toJson() => {
    'live': [for (final r in liveRects) r.toJson()],
    'board': board.toJson(),
    'arrangement': arrangement.wireName,
  };

  static CoverageMap fromJson(Map<String, dynamic> j) => CoverageMap(
    liveRects: [
      for (final r in j['live'] as List)
        WorldRect.fromJson(r as Map<String, dynamic>),
    ],
    board: WorldRect.fromJson(j['board'] as Map<String, dynamic>),
    arrangement: ArrangementInfo.fromWire(j['arrangement'] as String?),
  );
}

/// What a game does with a dead zone. v1 only implements [ignore]; the others
/// are here to record that the choice belongs to the game, not the platform.
enum DeadZonePolicy { ignore, wall, void_ }
