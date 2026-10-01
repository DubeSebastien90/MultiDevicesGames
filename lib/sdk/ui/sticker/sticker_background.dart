import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'sticker_motion.dart';
import 'sticker_tokens.dart';

enum ShapeKind { circle, rounded, square, pill }

class StickerShape {
  const StickerShape(this.x, this.y, this.size, this.kind, [this.rotDeg = 0]);

  final double x;
  final double y;
  final double size;
  final double rotDeg;
  final ShapeKind kind;
}

const homeShapes = [
  StickerShape(.08, .12, 46, ShapeKind.circle),
  StickerShape(.72, .08, 38, ShapeKind.rounded, 20),
  StickerShape(.80, .30, 54, ShapeKind.circle),
  StickerShape(.04, .42, 30, ShapeKind.square, 45),
  StickerShape(.62, .52, 26, ShapeKind.circle),
  StickerShape(.14, .74, 40, ShapeKind.rounded, 45),
  StickerShape(.78, .70, 34, ShapeKind.pill, -20),
  StickerShape(.40, .20, 22, ShapeKind.circle),
  StickerShape(.44, .88, 28, ShapeKind.square, 10),
];

const lobbyShapes = [
  StickerShape(.06, .20, 40, ShapeKind.circle),
  StickerShape(.80, .16, 34, ShapeKind.rounded, 20),
  StickerShape(.84, .44, 48, ShapeKind.circle),
  StickerShape(.02, .52, 28, ShapeKind.square, 45),
  StickerShape(.70, .64, 24, ShapeKind.circle),
  StickerShape(.10, .82, 36, ShapeKind.rounded, 45),
  StickerShape(.76, .86, 30, ShapeKind.pill, -20),
  StickerShape(.44, .08, 20, ShapeKind.circle),
  StickerShape(.46, .94, 26, ShapeKind.square, 10),
];

const pickerShapes = [
  StickerShape(.06, .04, 30, ShapeKind.circle),
  StickerShape(.84, .05, 26, ShapeKind.rounded, 20),
  StickerShape(.88, .40, 36, ShapeKind.circle),
  StickerShape(.01, .48, 24, ShapeKind.square, 45),
  StickerShape(.86, .76, 28, ShapeKind.pill, -20),
  StickerShape(.03, .88, 30, ShapeKind.rounded, 45),
];

class StickerBackground extends StatefulWidget {
  const StickerBackground({
    super.key,
    required this.child,
    this.shapes = homeShapes,
    this.colors = St.shapeColors,
    this.color = St.bg,
  });

  final Widget child;
  final List<StickerShape> shapes;
  final List<Color> colors;
  final Color color;

  @override
  State<StickerBackground> createState() => _StickerBackgroundState();
}

class _StickerBackgroundState extends State<StickerBackground>
    with SingleTickerProviderStateMixin {
  final _secs = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(
    (d) => _secs.value = d.inMicroseconds / 1e6,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final moving = StickerMotion.of(context);
    if (!moving && _ticker.isActive) _ticker.stop();
    if (moving && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _secs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: widget.color,
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BgPainter(_secs, widget.shapes, widget.colors),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    ),
  );
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.secs, this.shapes, this.colors) : super(repaint: secs);

  final ValueNotifier<double> secs;
  final List<StickerShape> shapes;
  final List<Color> colors;

  static const _grid = 18.0;
  static final _dot = Paint()..color = const Color(0x1A000000);
  static final _ink = Paint()..color = St.ink;
  static final _fill = Paint();
  static final _stroke = Paint()
    ..color = St.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final t = secs.value;

    final shift = (t / 3 * 36) % _grid;
    for (double y = shift - _grid; y < size.height + _grid; y += _grid) {
      for (double x = shift - _grid; x < size.width + _grid; x += _grid) {
        canvas.drawCircle(Offset(x + 9, y + 9), 2, _dot);
      }
    }

    for (var i = 0; i < shapes.length; i++) {
      final s = shapes[i];
      final period = 5 + (i % 4) * 1.5;
      final p = ((t + i * .7) / period) % 1;
      final e = (1 - math.cos(2 * math.pi * p)) / 2;
      final dx = (i.isOdd ? 14 : -12) * e;
      final dy = (i % 3 != 0 ? -18 : 14) * e;
      final rot = s.rotDeg + (i.isOdd ? 25 : -30) * e;

      final w = s.kind == ShapeKind.pill ? s.size * 1.8 : s.size;
      final h = s.size;
      final cx = s.x * size.width + dx + w / 2;
      final cy = s.y * size.height + dy + h / 2;
      final r = switch (s.kind) {
        ShapeKind.circle || ShapeKind.pill => h / 2,
        ShapeKind.rounded => 10.0,
        ShapeKind.square => 8.0,
      };
      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Radius.circular(r),
      );

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rot * math.pi / 180);
      canvas.drawRRect(rr.shift(const Offset(3, 3)), _ink);
      _fill.color = colors[i % colors.length].withValues(alpha: .9);
      canvas.drawRRect(rr, _fill);
      canvas.drawRRect(rr.deflate(1.5), _stroke);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) =>
      old.shapes != shapes || old.colors != colors;
}

class DotsPainter extends CustomPainter {
  const DotsPainter({
    this.color = const Color(0x2EFFFFFF),
    this.spacing = 22,
    this.radius = 3,
  });

  final Color color;
  final double spacing;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotsPainter old) => false;
}
