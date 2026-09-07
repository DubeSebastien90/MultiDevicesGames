import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'pitch_cars_config.dart';

/// Pitch Cars' look: the default shapes for cars and track segments, plus a
/// turn/progress readout.
class PitchCarsView extends ShapeView {
  PitchCarsView({required this.phoneId, super.roster})
    : super(grid: false, playfield: const Color(0xFF141C33));

  final String phoneId;

  final _aim = Paint()..style = PaintingStyle.stroke;
  final _finishedFill = Paint();
  final _anchorDot = Paint();

  /// How fast the aim crosshair spins, in full turns per second. Slow: it is
  /// there to say "your drag is anchored here", not to demand attention while
  /// somebody is trying to line up a shot.
  static const double _anchorTurnsPerSecond = 0.2;

  /// The cool end of the aim arrow's own gradient, so the crosshair and the
  /// shot it is producing read as one gesture. Flat rather than
  /// strength-tinted: the anchor means the same thing at every draw length,
  /// and a colour that moved would suggest otherwise.
  static const Color _anchorColor = Color(0xCC7FD1C4);

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

    // Below the sim's own cancel threshold nothing is drawn at all — no
    // arrow, and no anchor crosshair either. Everything the aim puts on the
    // screen appears and vanishes together on this one line, so what is drawn
    // is exactly the promise that letting go will fire a shot. Drag back into
    // the dead zone and the whole aim disappears, which is the clearest way to
    // say the release has become a no-op.
    if (pulled < maxPull * PitchCarsConfig.cancelPullFraction) return;

    _drawAimAnchor(canvas, frame, car);

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

  /// A spinning crosshair on the point an off-car drag is aiming from.
  ///
  /// Only ever drawn for a drag that started away from the car, because that
  /// is precisely when the pivot is invisible: the draw is being measured from
  /// a patch of empty board, and with nothing marking it there is no way to
  /// read how far you have pulled or which way. A drag that started on the car
  /// needs none of this — the car is standing on its own anchor.
  ///
  /// Called only once the draw has cleared the cancel zone, so the crosshair
  /// keeps exactly the same company as the arrow: both are on screen when the
  /// release would fire, and both are gone when it would not.
  ///
  /// The spin is phased off [Frame.timeMs] — the host's clock, identical on
  /// every phone — and never a local one. An anchor can sit right on the seam
  /// between two screens with half the crosshair drawn on each, and two
  /// devices animating from their own clocks would tear it in half.
  void _drawAimAnchor(Canvas canvas, Frame frame, RenderEntity car) {
    final ax = (frame.sharedState['anchorX'] as num?)?.toDouble();
    final ay = (frame.sharedState['anchorY'] as num?)?.toDouble();
    if (ax == null || ay == null) return;

    // Sized off the car rather than a constant, so the crosshair is the same
    // mark relative to everything else on a two-phone table and an eight.
    final r = car.propDouble(ShapeProps.radius) * 2.2;
    final center = Offset(ax, ay);
    final spin = frame.timeMs * 0.001 * _anchorTurnsPerSecond * 2 * math.pi;

    _aim
      ..color = _anchorColor
      ..strokeWidth = 1.5 * frame.onePixel;
    canvas.drawCircle(center, r, _aim);

    // Four ticks straddling the ring, quartered — so the figure reads as a
    // crosshair rather than a target, and its rotation is legible.
    for (var i = 0; i < 4; i++) {
      final a = spin + i * math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * (r * 0.55),
        center + dir * (r * 1.45),
        _aim,
      );
    }

    // The pivot itself. The ring says roughly where; this says exactly.
    _anchorDot.color = _anchorColor;
    canvas.drawCircle(center, 2 * frame.onePixel, _anchorDot);
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
