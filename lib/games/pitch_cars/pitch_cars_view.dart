import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'pitch_cars_config.dart';

/// Pitch Cars' look: the default shapes for cars and track segments, plus a
/// turn/progress readout.
class PitchCarsView extends ShapeView {
  PitchCarsView({required this.phoneId})
    : super(grid: false, playfield: const Color(0xFF141C33));

  final String phoneId;

  final _aim = Paint()..style = PaintingStyle.stroke;
  final _finishedFill = Paint();

  /// The road surface.
  ///
  /// Round on both counts, and neither is decoration. `PitchTrack.isOnTrack`
  /// passes a car within half a width of the centerline polyline, and the set
  /// of such points is that polyline's Minkowski sum with a disc of that
  /// radius — which is exactly what a round-capped, round-joined stroke paints.
  /// Square either one and the picture starts lying: mitred joins would cut the
  /// arc off the outside of every bend, and flat caps would drop the half-disc
  /// of real tarmac past the start and the finish.
  final _ribbon = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Built once each and kept, keyed on the points list they came from.
  ///
  /// A centerline is fixed for the round — it arrives in an [EntityDescriptor],
  /// the half of an entity that by contract never changes — so rebuilding a
  /// hundred-odd point path sixty times a second would be work with no possible
  /// effect. Identity is the right key precisely *because* of that contract:
  /// the client decodes each descriptor once and hands back the same list every
  /// frame. Bounded by the number of polylines in a round, which is the road
  /// plus one per walled bend.
  final _paths = <Object, Path>{};

  /// Under the entities, so cars and the finish checkerboard sit on the road
  /// rather than beneath it — and the kerbs over the road, since they stand on
  /// its edge.
  @override
  void renderBackground(Canvas canvas, Frame frame) {
    super.renderBackground(canvas, frame);
    _strokePolylines(canvas, frame, PitchCarsConfig.ribbonKind);
    _strokePolylines(canvas, frame, PitchCarsConfig.wallKind);
  }

  /// Every polyline entity of one kind, stroked round-capped and round-joined.
  ///
  /// The road and the kerbs share this for a reason beyond saving a method:
  /// both are the set of points within half their stroke width of a polyline,
  /// and drawing them the same way is what keeps a kerb sitting exactly on the
  /// edge of the road it was offset from.
  void _strokePolylines(Canvas canvas, Frame frame, String kind) {
    for (final e in frame.ofKind(kind)) {
      final points = e.props[PitchCarsConfig.ribbonPoints];
      // Two coordinates make one point, and one point is not a line.
      if (points is! List || points.length < 4) continue;

      final path = _paths.putIfAbsent(points, () => _pathThrough(points));

      _ribbon
        ..color = Color(
          e.propInt(PitchCarsConfig.ribbonColor, PitchCarsConfig.colorTrack),
        )
        // The full width, not half: a stroke straddles its path, so the road's
        // reaches `widthWorld / 2` either side — the very number `isOnTrack`
        // compares against.
        ..strokeWidth = e.propDouble(
          PitchCarsConfig.ribbonWidth,
          PitchCarsConfig.trackWidthWorld,
        );

      canvas
        ..save()
        ..translate(e.x, e.y)
        ..rotate(e.angle)
        ..drawPath(path, _ribbon)
        ..restore();
    }
  }

  /// A flat `[x0,y0,x1,y1,…]` as an open path.
  ///
  /// Straight segments on purpose. The centerline is already a Catmull-Rom
  /// spline sampled by [TrackGenerator], and every distance the game measures
  /// is measured to these chords — so smoothing them here would draw a road
  /// nobody's collision test agrees with. What makes the result read as curved
  /// is the round joins, not a curve in the path.
  static Path _pathThrough(List<Object?> flat) {
    double at(int i) => (flat[i] as num).toDouble();

    final path = Path()..moveTo(at(0), at(1));
    for (var i = 2; i + 1 < flat.length; i += 2) {
      path.lineTo(at(i), at(i + 1));
    }
    return path;
  }

  @override
  void renderForeground(Canvas canvas, Frame frame) {
    _drawFinished(canvas, frame);
    _drawTurnHighlight(canvas, frame);

    final currentTurn = frame.sharedState['currentTurn'] as String?;
    final pullX = frame.sharedState['pullX'] as double?;
    final pullY = frame.sharedState['pullY'] as double?;
    if (currentTurn == null || pullX == null || pullY == null) return;

    final car = frame.byId(currentTurn);
    if (car == null) return;

    final origin = Offset(car.x, car.y);
    final pullVector = Offset(pullX, pullY) - origin;
    final pulled = pullVector.distance;

    // The pull a full-strength shot needs depends on the size of the table, so
    // it is told to us rather than assumed: a fixed number here would have the
    // arrow reading full power at a third of the draw on a big board.
    final maxPull =
        (frame.sharedState['maxPull'] as num?)?.toDouble() ??
        PitchCarsConfig.maxPull;

    // Not enough to read as a real pull yet — as a fraction of the draw, so
    // the arrow appears at the same point in the gesture on any board.
    if (pulled < maxPull * 0.02) return;

    final strength = (pulled / maxPull).clamp(0.0, 1.0);
    final direction = -pullVector / pulled; // opposite the pull = the shot

    final shaftLen =
        car.propDouble(ShapeProps.radius) * 1.5 + strength * maxPull * 1.5;
    final tip = origin + direction * shaftLen;

    final px = frame.onePixel;
    _aim
      ..color = Color.lerp(
        const Color(0xFF7FD1C4),
        const Color(0xFFFF4D4D),
        strength,
      )!
      ..strokeWidth = (2.0 + strength * 2.0) * px;

    canvas.drawLine(origin, tip, _aim);

    // Arrowhead: two short strokes angled back from the tip.
    const headAngle = 0.5; // radians either side of the shaft
    final headLen = maxPull * (0.1 + strength * 0.07);
    final dirAngle = math.atan2(direction.dy, direction.dx);
    for (final sign in [-1, 1]) {
      final wingAngle = dirAngle + math.pi - sign * headAngle;
      final wing =
          tip + Offset(math.cos(wingAngle), math.sin(wingAngle)) * headLen;
      canvas.drawLine(tip, wing, _aim);
    }
  }

  /// Grey out a car once it's crossed the finish line — a flat overlay
  /// painted on top of its own colour, since a car's colour is baked into
  /// its entity props at creation and never mutates per-frame.
  void _drawFinished(Canvas canvas, Frame frame) {
    for (final entry in frame.sharedState.entries) {
      if (!entry.key.startsWith('finished_') || entry.value != true) continue;
      final car = frame.byId(entry.key.substring('finished_'.length));
      if (car == null) continue;
      _finishedFill.color = const Color(0xB2707070);
      canvas.drawCircle(
        Offset(car.x, car.y),
        car.propDouble(ShapeProps.radius),
        _finishedFill,
      );
    }
  }

  void _drawTurnHighlight(Canvas canvas, Frame frame) {
    final currentTurn = frame.sharedState['currentTurn'] as String?;
    if (currentTurn == null) return;
    if (frame.sharedState['pullX'] != null) return;
    if (frame.sharedState['moving'] == true) return;

    final car = frame.byId(currentTurn);
    if (car == null) return;

    final r = car.propDouble(ShapeProps.radius) * 1.8;
    _aim
      ..color = Color(car.propInt(ShapeProps.color, 0xFFFFFFFF))
      ..strokeWidth = 2.0 * frame.onePixel;
    canvas.drawCircle(Offset(car.x, car.y), r, _aim);
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final winner = frame.sharedState['winner'];
    if (winner is String) {
      final mine = winner == phoneId;
      return _pill(mine ? 'You win!' : 'Race over', highlight: mine);
    }
    return null;
  }

  Widget _pill(String label, {required bool highlight}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0x99000000),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: highlight ? const Color(0xFFFFD166) : const Color(0xFFFFFFFF),
      ),
    ),
  );
}
