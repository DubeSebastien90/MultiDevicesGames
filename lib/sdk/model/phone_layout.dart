import 'dart:math' as math;

import 'world_rect.dart';

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

  final int index;
  final int total;

  final double worldCenterX;
  final double worldCenterY;

  final double mmToWorld;

  final double dpi;
  final double devicePixelRatio;

  final double activePxWidth;
  final double activePxHeight;

  final double turnRadians;

  final WorldRect board;

  final String placement;

  double get worldPerPhysicalPx => (25.4 / dpi) * mmToWorld;

  double get worldPerLogicalPx => worldPerPhysicalPx * devicePixelRatio;

  double get logicalPxPerWorldUnit => 1 / worldPerLogicalPx;

  double get halfWidth => activePxWidth * worldPerPhysicalPx / 2;
  double get halfHeight => activePxHeight * worldPerPhysicalPx / 2;

  bool get isTurned => turnRadians.abs() > 1e-9;

  WorldRect get viewport {
    final c = math.cos(turnRadians).abs();
    final s = math.sin(turnRadians).abs();
    final hw = halfWidth * c + halfHeight * s;
    final hh = halfWidth * s + halfHeight * c;
    return WorldRect(worldCenterX - hw, worldCenterY - hh, hw * 2, hh * 2);
  }

  bool containsWorld(double wx, double wy) {
    final local = _toLocalUnits(wx, wy);
    return local.u.abs() <= halfWidth && local.v.abs() <= halfHeight;
  }

  ({double x, double y}) physicalPxToWorld(double px, double py) {
    final s = worldPerPhysicalPx;

    final u = px * s - halfWidth;
    final v = py * s - halfHeight;
    final cos = math.cos(turnRadians);
    final sin = math.sin(turnRadians);
    return (
      x: worldCenterX + u * cos - v * sin,
      y: worldCenterY + u * sin + v * cos,
    );
  }

  ({double x, double y}) worldToPhysicalPx(double wx, double wy) {
    final local = _toLocalUnits(wx, wy);
    final s = worldPerPhysicalPx;
    return (x: (local.u + halfWidth) / s, y: (local.v + halfHeight) / s);
  }

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
