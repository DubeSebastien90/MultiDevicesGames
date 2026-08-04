import 'dart:math' as math;

import 'world_rect.dart';

/// Where one screen sits in the world, and how to convert between its pixels
/// and world coordinates.
///
/// The two transforms here are exact inverses. If they ever drift apart, a
/// finger and the thing it grabs stop agreeing, and the seam stops lining up.
///
/// A screen is described by its **centre and its turn**, not by a top-left
/// corner. Once a phone can be laid at any angle there is no meaningful
/// axis-aligned corner to anchor to, and centre-plus-angle is the only
/// parameterisation that stays honest at 37° as well as at 90°.
class PhoneLayout {
  const PhoneLayout({
    required this.phoneId,
    required this.index,
    required this.total,
    required this.worldCenterX,
    required this.worldCenterY,
    required this.mmToWorld,
    required this.dpi,
    required this.devicePixelRatio,
    required this.activePxWidth,
    required this.activePxHeight,
    required this.board,
    required this.placement,
    this.turnRadians = 0,
  });

  final String phoneId;

  /// Position in the board's reading order, 0-based.
  final int index;
  final int total;

  /// Where the middle of this screen lands in world coordinates.
  final double worldCenterX;
  final double worldCenterY;

  /// World units per millimetre. **Shared by every phone** — this is what gives
  /// the world one consistent physical size across different densities.
  final double mmToWorld;

  final double dpi;
  final double devicePixelRatio;

  /// The lit area in physical pixels, in the phone's own **portrait** frame.
  /// Never swapped: the turn is carried by [turnRadians] and applied by the
  /// transforms, so there is exactly one place rotation is handled.
  final double activePxWidth;
  final double activePxHeight;

  /// How far this phone is turned within the board, clockwise, in radians.
  ///
  /// The app itself never rotates. This is the game's placement, and the phone
  /// turns its camera and its UI by the same amount so the board reads upright
  /// to whoever is standing in front of it.
  final double turnRadians;

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

  /// Half the screen's extent in world units, before any turn.
  double get halfWidth => activePxWidth * worldPerPhysicalPx / 2;
  double get halfHeight => activePxHeight * worldPerPhysicalPx / 2;

  bool get isTurned => turnRadians.abs() > 1e-9;

  /// The axis-aligned box this screen occupies once turned.
  ///
  /// Conservative on purpose: it is what culling and coarse overlap tests want,
  /// and for an unturned phone it is the screen exactly. Use [containsWorld]
  /// when the answer has to be right rather than cheap.
  WorldRect get viewport {
    final c = math.cos(turnRadians).abs();
    final s = math.sin(turnRadians).abs();
    final hw = halfWidth * c + halfHeight * s;
    final hh = halfWidth * s + halfHeight * c;
    return WorldRect(
      worldCenterX - hw,
      worldCenterY - hh,
      hw * 2,
      hh * 2,
    );
  }

  /// Is this world point actually on this screen? Exact, turn included.
  bool containsWorld(double wx, double wy) {
    final local = _toLocalUnits(wx, wy);
    return local.u.abs() <= halfWidth && local.v.abs() <= halfHeight;
  }

  /// Touch -> world. Input is *physical* pixels in the phone's own portrait
  /// frame, so the wire format carries no notion of this device's scale.
  ({double x, double y}) physicalPxToWorld(double px, double py) {
    final s = worldPerPhysicalPx;
    // Offset from the middle of the panel, in world units.
    final u = px * s - halfWidth;
    final v = py * s - halfHeight;
    final cos = math.cos(turnRadians);
    final sin = math.sin(turnRadians);
    return (
      x: worldCenterX + u * cos - v * sin,
      y: worldCenterY + u * sin + v * cos,
    );
  }

  /// The exact inverse, for rendering.
  ({double x, double y}) worldToPhysicalPx(double wx, double wy) {
    final local = _toLocalUnits(wx, wy);
    final s = worldPerPhysicalPx;
    return (
      x: (local.u + halfWidth) / s,
      y: (local.v + halfHeight) / s,
    );
  }

  /// World point -> offset from this screen's middle, in world units, with the
  /// turn undone.
  ({double u, double v}) _toLocalUnits(double wx, double wy) {
    final dx = wx - worldCenterX;
    final dy = wy - worldCenterY;
    final cos = math.cos(turnRadians);
    final sin = math.sin(turnRadians);
    return (u: dx * cos + dy * sin, v: -dx * sin + dy * cos);
  }

  Map<String, dynamic> toJson() => {
    'phoneId': phoneId,
    'index': index,
    'total': total,
    'center': {'x': worldCenterX, 'y': worldCenterY},
    'mmToWorld': mmToWorld,
    'dpi': dpi,
    'dpr': devicePixelRatio,
    'activePx': {'w': activePxWidth, 'h': activePxHeight},
    'board': board.toJson(),
    'placement': placement,
    'turn': turnRadians,
  };

  static PhoneLayout fromJson(Map<String, dynamic> j) {
    final c = j['center'] as Map<String, dynamic>;
    final px = j['activePx'] as Map<String, dynamic>;
    return PhoneLayout(
      phoneId: j['phoneId'] as String,
      index: (j['index'] as num).toInt(),
      total: (j['total'] as num).toInt(),
      worldCenterX: (c['x'] as num).toDouble(),
      worldCenterY: (c['y'] as num).toDouble(),
      mmToWorld: (j['mmToWorld'] as num).toDouble(),
      dpi: (j['dpi'] as num).toDouble(),
      devicePixelRatio: (j['dpr'] as num).toDouble(),
      activePxWidth: (px['w'] as num).toDouble(),
      activePxHeight: (px['h'] as num).toDouble(),
      board: WorldRect.fromJson(j['board'] as Map<String, dynamic>),
      placement: j['placement'] as String,
      turnRadians: (j['turn'] as num?)?.toDouble() ?? 0,
    );
  }
}
