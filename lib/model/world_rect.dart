/// A rectangle in world coordinates.
///
/// Deliberately not `dart:ui`'s `Rect`: the host's world model and physics must
/// stay renderer-agnostic, so a phone that is only a viewport can never be
/// confused with the source of truth.
class WorldRect {
  const WorldRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  bool contains(double x, double y) =>
      x >= left && x < right && y >= top && y < bottom;

  bool overlaps(WorldRect o) =>
      left < o.right && o.left < right && top < o.bottom && o.top < bottom;

  /// Grown by [d] on every side. Negative shrinks.
  WorldRect inflate(double d) =>
      WorldRect(left - d, top - d, width + 2 * d, height + 2 * d);

  Map<String, dynamic> toJson() => {'x': left, 'y': top, 'w': width, 'h': height};

  static WorldRect fromJson(Map<String, dynamic> j) => WorldRect(
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['w'] as num).toDouble(),
    (j['h'] as num).toDouble(),
  );

  @override
  String toString() =>
      'WorldRect(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}, '
      '${width.toStringAsFixed(2)} x ${height.toStringAsFixed(2)})';
}
