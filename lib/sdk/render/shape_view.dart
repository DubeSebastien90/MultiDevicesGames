import 'dart:math' as math;
import 'dart:ui';

import '../contract/entity.dart';
import '../contract/view.dart';

/// Prop keys [ShapeView] understands. A game using it declares these when it
/// creates an entity; anything else is ignored.
class ShapeProps {
  static const shape = 'shape'; // 'circle' | 'box'
  static const radius = 'r';
  static const width = 'w';
  static const height = 'h';
  static const color = 'color'; // ARGB int
  static const spin = 'spin'; // bool: draw a rotation tell
}

class ShapeKind {
  static const circle = 'circle';
  static const box = 'box';
}

/// Draws entities from their props: circles, boxes, colours, rotation.
///
/// This used to be the only renderer there was. It is now the default one — a
/// game that has not got as far as art gets a working picture for free, and can
/// replace it with a real [GameView] later without touching anything else.
///
/// Use it directly, or extend it and override [renderBackground] /
/// [renderForeground] to keep the shapes and add your own layers around them.
class ShapeView extends GameView {
  ShapeView({
    this.background = const Color(0xFF0B1020),
    this.playfield = const Color(0xFF141C33),
    this.grid = true,
    this.showSeams = false,
  });

  /// Outside the board.
  final Color background;

  /// The board itself.
  final Color playfield;

  /// A 1cm world grid. Because every phone draws the *same* world grid, lines
  /// running unbroken across the physical gap are a live calibration check: if
  /// they step, a measurement is wrong.
  final bool grid;

  /// Mark where this screen's coverage ends and the gap begins.
  final bool showSeams;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas, Frame frame) {
    renderBackground(canvas, frame);
    renderEntities(canvas, frame);
    renderForeground(canvas, frame);
  }

  void renderBackground(Canvas canvas, Frame frame) {
    final view = frame.visible;
    final board = frame.board;

    _fill.color = background;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
    _fill.color = playfield;
    canvas.drawRect(
      Rect.fromLTWH(board.left, board.top, board.width, board.height),
      _fill,
    );

    if (grid) _drawGrid(canvas, frame);
    if (showSeams) _drawSeams(canvas, frame);
  }

  /// Every entity that declared a shape.
  void renderEntities(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2.0);

    for (final e in frame.entities.values) {
      final shape = e.props[ShapeProps.shape] as String?;
      if (shape == null) continue;

      // Cull what this screen cannot see. The entity still exists and is still
      // simulated — drawing it is just somebody else's job. Boxes use the
      // half-diagonal so a rotated one is never clipped early.
      final reach = shape == ShapeKind.circle
          ? e.propDouble(ShapeProps.radius)
          : math.sqrt(
                math.pow(e.propDouble(ShapeProps.width), 2) +
                    math.pow(e.propDouble(ShapeProps.height), 2),
              ) /
              2;
      if (e.x + reach < view.left ||
          e.x - reach > view.right ||
          e.y + reach < view.top ||
          e.y - reach > view.bottom) {
        continue;
      }

      _fill.color = Color(e.propInt(ShapeProps.color, 0xFFFFFFFF));
      switch (shape) {
        case ShapeKind.circle:
          _drawCircle(canvas, e);
        case ShapeKind.box:
          _drawBox(canvas, e);
      }
    }
  }

  /// Override to draw on top of the shapes.
  void renderForeground(Canvas canvas, Frame frame) {}

  void _drawCircle(Canvas canvas, RenderEntity e) {
    final r = e.propDouble(ShapeProps.radius);
    canvas.drawCircle(Offset(e.x, e.y), r, _fill);
    if (e.props[ShapeProps.spin] == true) {
      // A rotation tell, so a rolling ball reads as rolling.
      _fill.color = const Color(0x88FFFFFF);
      canvas.drawCircle(
        Offset(
          e.x + math.cos(e.angle) * r * 0.45,
          e.y + math.sin(e.angle) * r * 0.45,
        ),
        r * 0.22,
        _fill,
      );
    }
  }

  void _drawBox(Canvas canvas, RenderEntity e) {
    final w = e.propDouble(ShapeProps.width);
    final h = e.propDouble(ShapeProps.height);
    canvas
      ..save()
      ..translate(e.x, e.y)
      ..rotate(e.angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Radius.circular(math.min(w, h) * 0.12),
      ),
      _fill,
    );
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Frame frame) {
    final view = frame.visible;
    final board = frame.board;

    // Cull to what this screen can actually see.
    final x0 = math.max(board.left, view.left).floorToDouble();
    final x1 = math.min(board.right, view.right).ceilToDouble();
    final y0 = math.max(board.top, view.top).floorToDouble();
    final y1 = math.min(board.bottom, view.bottom).ceilToDouble();
    final thin = frame.onePixel;

    for (var x = x0; x <= x1; x += 1) {
      final major = (x % 5).abs() < 1e-6;
      _stroke
        ..color = major ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF)
        ..strokeWidth = thin * (major ? 1.5 : 1);
      canvas.drawLine(Offset(x, y0), Offset(x, y1), _stroke);
    }
    for (var y = y0; y <= y1; y += 1) {
      final major = (y % 5).abs() < 1e-6;
      _stroke
        ..color = major ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF)
        ..strokeWidth = thin * (major ? 1.5 : 1);
      canvas.drawLine(Offset(x0, y), Offset(x1, y), _stroke);
    }
  }

  void _drawSeams(Canvas canvas, Frame frame) {
    _stroke
      ..color = const Color(0x66FF3B6B)
      ..strokeWidth = frame.onePixel * 2;
    for (final seam in frame.coverage.seamRects()) {
      canvas.drawRect(
        Rect.fromLTWH(seam.left, seam.top, seam.width, seam.height),
        _stroke,
      );
    }
  }
}
