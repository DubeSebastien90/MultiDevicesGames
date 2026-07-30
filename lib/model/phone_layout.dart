import 'world_rect.dart';

/// What calibration produces for one phone: where its screen sits in the world,
/// plus everything needed to convert touches up and entities down.
///
/// The two transforms here are exact inverses. If they ever drift apart, a
/// finger and the thing it grabs stop agreeing, and the seam stops lining up.
class PhoneLayout {
  const PhoneLayout({
    required this.phoneId,
    required this.index,
    required this.total,
    required this.worldOffsetX,
    required this.worldOffsetY,
    required this.mmToWorld,
    required this.dpi,
    required this.devicePixelRatio,
    required this.activePxWidth,
    required this.activePxHeight,
    required this.board,
    required this.placement,
  });

  final String phoneId;

  /// Position in the left-to-right strip, 0-based.
  final int index;
  final int total;

  /// Where this screen's top-left active pixel lands in world coordinates.
  final double worldOffsetX;
  final double worldOffsetY;

  /// World units per millimetre. **Shared by every phone** — this is what gives
  /// the world one consistent physical size across different densities.
  final double mmToWorld;

  final double dpi;
  final double devicePixelRatio;
  final double activePxWidth;
  final double activePxHeight;

  /// The whole board, for context (drawing out-of-board areas, clamping).
  final WorldRect board;

  /// Human instruction, e.g. "right of phone 1, top edges aligned".
  final String placement;

  /// World units per physical pixel.
  double get worldPerPhysicalPx => (25.4 / dpi) * mmToWorld;

  /// World units per Flutter logical pixel (what `Canvas` and gestures use).
  double get worldPerLogicalPx => worldPerPhysicalPx * devicePixelRatio;

  /// Logical pixels per world unit — the camera zoom that makes one world unit
  /// occupy its true physical size on this particular screen.
  double get logicalPxPerWorldUnit => 1 / worldPerLogicalPx;

  /// This screen's slice of the world.
  WorldRect get viewport => WorldRect(
    worldOffsetX,
    worldOffsetY,
    activePxWidth * worldPerPhysicalPx,
    activePxHeight * worldPerPhysicalPx,
  );

  /// Touch -> world. Matches the spec formula:
  /// `worldPos = worldOffset + (localPx / dpi) * mmToWorld`.
  /// Input is *physical* pixels so the wire format is density-independent.
  ({double x, double y}) physicalPxToWorld(double px, double py) => (
    x: worldOffsetX + px * worldPerPhysicalPx,
    y: worldOffsetY + py * worldPerPhysicalPx,
  );

  /// The exact inverse, for rendering.
  ({double x, double y}) worldToPhysicalPx(double wx, double wy) => (
    x: (wx - worldOffsetX) / worldPerPhysicalPx,
    y: (wy - worldOffsetY) / worldPerPhysicalPx,
  );

  Map<String, dynamic> toJson() => {
    'phoneId': phoneId,
    'index': index,
    'total': total,
    'worldOffset': {'x': worldOffsetX, 'y': worldOffsetY},
    'mmToWorld': mmToWorld,
    'dpi': dpi,
    'dpr': devicePixelRatio,
    'activePx': {'w': activePxWidth, 'h': activePxHeight},
    'board': board.toJson(),
    'placement': placement,
  };

  static PhoneLayout fromJson(Map<String, dynamic> j) {
    final off = j['worldOffset'] as Map<String, dynamic>;
    final px = j['activePx'] as Map<String, dynamic>;
    return PhoneLayout(
      phoneId: j['phoneId'] as String,
      index: (j['index'] as num).toInt(),
      total: (j['total'] as num).toInt(),
      worldOffsetX: (off['x'] as num).toDouble(),
      worldOffsetY: (off['y'] as num).toDouble(),
      mmToWorld: (j['mmToWorld'] as num).toDouble(),
      dpi: (j['dpi'] as num).toDouble(),
      devicePixelRatio: (j['dpr'] as num).toDouble(),
      activePxWidth: (px['w'] as num).toDouble(),
      activePxHeight: (px['h'] as num).toDouble(),
      board: WorldRect.fromJson(j['board'] as Map<String, dynamic>),
      placement: j['placement'] as String,
    );
  }
}
