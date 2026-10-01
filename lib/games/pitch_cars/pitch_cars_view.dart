import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'pitch_cars_art.dart';
import 'pitch_cars_config.dart';

class PitchCarsView extends ShapeView {
  PitchCarsView({super.roster})
    : super(
        grid: false,
        background: const Color(_grassEdge),
        playfield: const Color(_grass),
      ) {
    PitchCarsArt.preload([for (final p in roster.players) p.color]);
  }

  static const double _carLength = 7;

  @override
  double get characterScale => 2.2;

  final _carLayer = Paint();

  static const _grass = 0xFFAEE294;
  static const _grassEdge = 0xFF8FCF79;
  static const _grassStripe = Color(0xFFA2D988);

  static const _stripe = 2.5;

  final _aim = Paint()..style = PaintingStyle.stroke;
  final _finishedFill = Paint();
  final _anchorDot = Paint();

  static const double _anchorTurnsPerSecond = 0.2;

  static const Color _anchorColor = Color(0xCC7FD1C4);

  final _ribbon = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  final _paths = <Object, Path>{};

  @override
  void renderBackground(Canvas canvas, Frame frame) {
    super.renderBackground(canvas, frame);
    _mowStripes(canvas, frame);
    _strokePolylines(canvas, frame, PitchCarsConfig.ribbonKind);
    _fillFinishTiles(canvas, frame);
    _strokePolylines(canvas, frame, PitchCarsConfig.wallKind);
  }

  final _tileFill = Paint();

  void _mowStripes(Canvas canvas, Frame frame) {
    final view = frame.visible;
    final board = frame.board;
    final left = math.max(view.left, board.left);
    final right = math.min(view.right, board.right);
    _tileFill.color = _grassStripe;
    for (
      var x = (left / (_stripe * 2)).floorToDouble() * _stripe * 2;
      x < right;
      x += _stripe * 2
    ) {
      canvas.drawRect(
        Rect.fromLTRB(
          math.max(x, board.left),
          board.top,
          math.min(x + _stripe, board.right),
          board.bottom,
        ),
        _tileFill,
      );
    }
  }

  void _fillFinishTiles(Canvas canvas, Frame frame) {
    for (final e in frame.ofKind(PitchCarsConfig.finishTileKind)) {
      final points = e.props[PitchCarsConfig.ribbonPoints];
      if (points is! List || points.length < 6) continue;

      final path = _paths.putIfAbsent(
        points,
        () => _pathThrough(points)..close(),
      );
      _tileFill.color = Color(
        e.propInt(
          PitchCarsConfig.ribbonColor,
          PitchCarsConfig.finishLineColorA,
        ),
      );

      canvas.save();

      final clip = e.props[PitchCarsConfig.finishClip];
      if (clip is List && clip.length == 3) {
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(
              center: Offset(
                (clip[0] as num).toDouble(),
                (clip[1] as num).toDouble(),
              ),
              radius: (clip[2] as num).toDouble(),
            ),
          ),
        );
      }
      canvas
        ..translate(e.x, e.y)
        ..rotate(e.angle)
        ..drawPath(path, _tileFill)
        ..restore();
    }
  }

  void _strokePolylines(Canvas canvas, Frame frame, String kind) {
    for (final e in frame.ofKind(kind)) {
      final points = e.props[PitchCarsConfig.ribbonPoints];

      if (points is! List || points.length < 4) continue;

      final path = _paths.putIfAbsent(points, () => _pathThrough(points));

      _ribbon
        ..color = Color(
          e.propInt(PitchCarsConfig.ribbonColor, PitchCarsConfig.colorTrack),
        )
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

  static Path _pathThrough(List<Object?> flat) {
    double at(int i) => (flat[i] as num).toDouble();

    final path = Path()..moveTo(at(0), at(1));
    for (var i = 2; i + 1 < flat.length; i += 2) {
      path.lineTo(at(i), at(i + 1));
    }
    return path;
  }

  @override
  void renderEntities(Canvas canvas, Frame frame) {
    _drawCars(canvas, frame);
    super.renderEntities(canvas, frame);
  }

  void _drawCars(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2.0);
    for (final e in frame.entities.values) {
      final player = roster.byPhone(
        e.props[ShapeProps.player] as String? ?? '',
      );
      if (player == null) continue;
      final car = PitchCarsArt.car(player.color);
      if (car == null) continue;

      final length =
          e.propDouble(ShapeProps.radius) * _carLength * entityScale(frame, e);
      if (e.x + length < view.left ||
          e.x - length > view.right ||
          e.y + length < view.top ||
          e.y - length > view.bottom) {
        continue;
      }
      final opacity = entityOpacity(frame, e).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      final scale = length / PitchCarsArt.length;
      canvas
        ..save()
        ..translate(e.x, e.y)
        ..rotate(e.angle);
      if (opacity < 1) {
        _carLayer.color = Color.fromRGBO(0, 0, 0, opacity);
        canvas.saveLayer(null, _carLayer);
      }
      canvas
        ..scale(scale)
        ..translate(-PitchCarsArt.cockpit.dx, -PitchCarsArt.cockpit.dy)
        ..drawPicture(car.picture);
      if (opacity < 1) canvas.restore();
      canvas.restore();
    }
  }

  static double _fallOf(Frame frame, RenderEntity e) =>
      (frame.sharedState['fall_${e.id}'] as num?)?.toDouble() ?? 0;

  @override
  double entityScale(Frame frame, RenderEntity e) {
    final t = _fallOf(frame, e);
    return 1 - 0.6 * t * t;
  }

  @override
  double entityOpacity(Frame frame, RenderEntity e) => 1 - _fallOf(frame, e);

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

    final maxPull =
        (frame.sharedState['maxPull'] as num?)?.toDouble() ??
        PitchCarsConfig.maxPull;

    if (pulled < maxPull * PitchCarsConfig.cancelPullFraction) return;

    _drawAimAnchor(canvas, frame, car);

    final strength = (pulled / maxPull).clamp(0.0, 1.0);
    final direction = -pullVector / pulled;

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

    const headAngle = 0.5;
    final headLen = maxPull * (0.1 + strength * 0.07);
    final dirAngle = math.atan2(direction.dy, direction.dx);
    for (final sign in [-1, 1]) {
      final wingAngle = dirAngle + math.pi - sign * headAngle;
      final wing =
          tip + Offset(math.cos(wingAngle), math.sin(wingAngle)) * headLen;
      canvas.drawLine(tip, wing, _aim);
    }
  }

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

  void _drawAimAnchor(Canvas canvas, Frame frame, RenderEntity car) {
    final ax = (frame.sharedState['anchorX'] as num?)?.toDouble();
    final ay = (frame.sharedState['anchorY'] as num?)?.toDouble();
    if (ax == null || ay == null) return;

    final r = car.propDouble(ShapeProps.radius) * 2.2;
    final center = Offset(ax, ay);
    final spin = frame.timeMs * 0.001 * _anchorTurnsPerSecond * 2 * math.pi;

    _aim
      ..color = _anchorColor
      ..strokeWidth = 1.5 * frame.onePixel;
    canvas.drawCircle(center, r, _aim);

    for (var i = 0; i < 4; i++) {
      final a = spin + i * math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * (r * 0.55),
        center + dir * (r * 1.45),
        _aim,
      );
    }

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
}
