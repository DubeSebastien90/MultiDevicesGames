import 'dart:math' as math;
import 'dart:ui';

import '../contract/entity.dart';
import '../contract/view.dart';
import '../model/player.dart';
import 'player_art.dart';

class ShapeProps {
  static const shape = 'shape';
  static const radius = 'r';
  static const width = 'w';
  static const height = 'h';
  static const color = 'color';
  static const spin = 'spin';

  static const player = 'player';
}

class ShapeKind {
  static const circle = 'circle';
  static const box = 'box';
}

class ShapeView extends GameView {
  ShapeView({
    this.background = const Color(0xFF0B1020),
    this.playfield = const Color(0xFF141C33),
    this.grid = true,
    this.showSeams = false,
    this.roster = Roster.empty,
  });

  final Color background;

  final Color playfield;

  final bool grid;

  final bool showSeams;

  final Roster roster;

  double get characterScale => 3;

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

  double entityScale(Frame frame, RenderEntity e) => 1;

  double entityOpacity(Frame frame, RenderEntity e) => 1;

  void renderEntities(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2.0);

    for (final e in frame.entities.values) {
      final shape = e.props[ShapeProps.shape] as String?;
      if (shape == null) continue;

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

      final opacity = entityOpacity(frame, e).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      final scale = entityScale(frame, e);

      final player = roster.byPhone(
        e.props[ShapeProps.player] as String? ?? '',
      );
      if (player != null) {
        PlayerArt.of(player.color, PlayerArtSlot.topdown).draw(
          canvas,
          Offset(e.x, e.y),
          worldSize: e.propDouble(ShapeProps.radius) * characterScale * scale,
          angle: e.angle,
          opacity: opacity,
        );
        continue;
      }

      final color = Color(e.propInt(ShapeProps.color, 0xFFFFFFFF));
      _fill.color = color.withValues(alpha: color.a * opacity);
      switch (shape) {
        case ShapeKind.circle:
          _drawCircle(canvas, e, scale, opacity);
        case ShapeKind.box:
          _drawBox(canvas, e, scale);
      }
    }
  }

  void renderForeground(Canvas canvas, Frame frame) {}

  void _drawCircle(
    Canvas canvas,
    RenderEntity e,
    double scale,
    double opacity,
  ) {
    final r = e.propDouble(ShapeProps.radius) * scale;
    canvas.drawCircle(Offset(e.x, e.y), r, _fill);
    if (e.props[ShapeProps.spin] == true) {
      _fill.color = const Color(
        0x88FFFFFF,
      ).withValues(alpha: 0x88 / 255 * opacity);
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

  void _drawBox(Canvas canvas, RenderEntity e, double scale) {
    final w = e.propDouble(ShapeProps.width) * scale;
    final h = e.propDouble(ShapeProps.height) * scale;
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
