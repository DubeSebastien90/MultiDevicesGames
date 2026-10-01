import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/world_rect.dart';
import 'flood_config.dart';
import 'flood_sim.dart';

abstract class FloodView extends GameView {
  FloodView(this.context);

  final ViewContext context;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;
  final _foam = Paint();

  final _text = <String, TextPainter>{};

  static const _briefing =
      'Tap as fast as you can on the screen to flood the other team!';

  static const double _briefingPulse = 0.07;
  static const double _briefingPulseSeconds = 1.6;

  static const double _briefingWidthFraction = 0.82;

  static const double _countSizeFraction = 0.20;
  static const double _briefingSizeFraction = 0.083;

  static const double _briefingGapFraction = 0.11;

  double waterlineY(Frame frame, double boundary) {
    final board = frame.board;
    final seam =
        (frame.sharedState[FloodState.seamY] as num?)?.toDouble() ??
        board.centerY;
    return boundary < 0
        ? seam - boundary * (board.bottom - seam)
        : seam - boundary * (seam - board.top);
  }

  void renderContested(
    Canvas canvas,
    Frame frame,
    WorldRect band,
    double waterY,
  ) {}

  @override
  void render(Canvas canvas, Frame frame) {
    final boundary =
        (frame.sharedState[FloodState.boundary] as num?)?.toDouble() ?? 0.0;
    final phase = frame.sharedState[FloodState.phase] as String?;
    final view = frame.visible;
    final waterY = waterlineY(frame, boundary);

    final wave = _wave(frame, waterY, view.left, view.right);

    _fill.color = const Color(FloodConfig.colorRed);
    canvas.drawRect(
      Rect.fromLTRB(view.left, view.top, view.right, view.bottom),
      _fill,
    );

    _fill.color = const Color(FloodConfig.colorBlue);
    final blue = Path()
      ..moveTo(view.left, view.top)
      ..lineTo(view.right, view.top);
    for (final point in wave.reversed) {
      blue.lineTo(point.dx, point.dy);
    }
    blue.close();
    canvas.drawPath(blue, _fill);

    renderContested(canvas, frame, view, waterY);
    _renderWaterline(canvas, frame, wave);

    if (phase == FloodPhase.countdown) {
      _renderCountdownWash(canvas, frame);
      _renderCountdown(canvas, frame);
    }
  }

  static const double _waveAmplitude = 0.28;
  static const double _waveLength = 3.4;
  static const double _waveSeconds = 2.6;

  List<Offset> _wave(Frame frame, double waterY, double left, double right) {
    final t = frame.timeMs / 1000;
    final k = 2 * math.pi / _waveLength;
    final w = 2 * math.pi / _waveSeconds;

    final step = math.max(frame.onePixel * 4, 1e-3);
    final points = <Offset>[];
    for (var x = left; ; x += step) {
      final at = math.min(x, right);
      final y =
          waterY +
          _waveAmplitude * math.sin(k * at - w * t) +
          _waveAmplitude * 0.35 * math.sin(k * 1.9 * at + w * 0.7 * t + 1.3);
      points.add(Offset(at, y));
      if (at >= right) break;
    }
    return points;
  }

  void _renderWaterline(Canvas canvas, Frame frame, List<Offset> wave) {
    final bluePulse =
        (frame.sharedState[FloodState.bluePulse] as num?)?.toDouble() ?? 0;
    final redPulse =
        (frame.sharedState[FloodState.redPulse] as num?)?.toDouble() ?? 0;

    final swell = 0.35 + 0.5 * math.max(bluePulse, redPulse);

    final line = Path()..addPolygon(wave, false);

    final foam = Color.lerp(
      const Color(0x66FFFFFF),
      const Color(0xCCFFFFFF),
      math.max(bluePulse, redPulse),
    )!;
    _foam
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = swell * 2
      ..color = foam.withValues(alpha: foam.a * 0.3);
    canvas.drawPath(line, _foam);
    _foam
      ..strokeWidth = swell
      ..color = foam.withValues(alpha: foam.a * 0.45);
    canvas.drawPath(line, _foam);

    _stroke
      ..color = const Color(0xE6FFFFFF)
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = frame.onePixel * 2;
    canvas.drawPath(line, _stroke);
  }

  void _renderCountdownWash(Canvas canvas, Frame frame) {
    final view = frame.visible;
    _fill.color = const Color(0x99000000);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
  }

  void _renderCountdown(Canvas canvas, Frame frame) {
    final count = (frame.sharedState[FloodState.countdown] as num?)?.toInt();

    final me = frame.me;

    final pxPerUnit = me.logicalPxPerWorldUnit;
    final screen = me.halfWidth * 2 * pxPerUnit;
    final maxWidth = screen * _briefingWidthFraction;

    final message = _painterFor(
      _briefing,
      size: screen * _briefingSizeFraction,
      weight: FontWeight.w700,
      color: const Color(0xFFFFFFFF),
      lineHeight: 1.3,
      maxWidth: maxWidth,
    );

    final number = _painterFor(
      count == null
          ? '0'
          : count > 0
          ? '$count'
          : 'GO',
      size: screen * _countSizeFraction,
      weight: FontWeight.w800,
      color: const Color(0xFFFFFFFF),
    );

    final pulse =
        1 +
        _briefingPulse *
            math.sin(frame.timeMs / 1000 * 2 * math.pi / _briefingPulseSeconds);

    final gap = screen * _briefingGapFraction;

    final blockHeight = number.height + gap + message.height;

    canvas.save();

    canvas
      ..translate(me.worldCenterX, me.worldCenterY)
      ..rotate(me.turnRadians)
      ..scale(1 / pxPerUnit);

    final top = -blockHeight / 2;
    if (count != null) {
      number.paint(canvas, Offset(-number.width / 2, top));
    }

    final messageTop = top + number.height + gap;
    final middle = messageTop + message.height / 2;
    canvas
      ..save()
      ..translate(0, middle)
      ..scale(pulse)
      ..translate(0, -middle);
    message.paint(canvas, Offset(-message.width / 2, messageTop));
    canvas
      ..restore()
      ..restore();
  }

  TextPainter _painterFor(
    String value, {
    required double size,
    required FontWeight weight,
    required Color color,
    double lineHeight = 1.0,
    double? maxWidth,
  }) {
    final key =
        '$value|${size.toStringAsFixed(3)}|$weight|${color.toARGB32()}'
        '|$lineHeight|${maxWidth?.toStringAsFixed(2)}';
    return _text.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            height: lineHeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: maxWidth ?? double.infinity),
    );
  }

  @override
  void dispose() {
    for (final p in _text.values) {
      p.dispose();
    }
    _text.clear();
    super.dispose();
  }
}
