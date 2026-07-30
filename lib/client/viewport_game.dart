import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../game/game_config.dart';
import '../model/phone_layout.dart';
import '../net/protocol.dart';
import 'client_session.dart';
import 'snapshot_buffer.dart';

/// Renders this phone's slice of the shared world.
///
/// The camera is not a creative choice: [PhoneLayout.logicalPxPerWorldUnit] is
/// set so one world unit occupies its true physical size on *this* panel, and
/// the viewfinder's top-left is pinned to this phone's world offset. Two phones
/// with different resolutions and densities therefore draw the same world at the
/// same real-world scale, which is the whole reason the seam can line up.
class ViewportGame extends FlameGame {
  ViewportGame({required this.session});

  final ClientSession session;

  /// A 1cm world grid. Because every phone draws the *same* world grid, the
  /// lines running unbroken across the physical gap are a live calibration
  /// check: if they step, the measurements are wrong.
  bool showGrid = true;

  /// Highlight where this screen's coverage ends and the bezel gap begins.
  bool showSeams = false;

  Map<String, InterpolatedEntity> entities = const {};
  SlingState? sling;

  PhoneLayout? _appliedLayout;

  @override
  Color backgroundColor() => const Color(0xFF0B1020);

  @override
  Future<void> onLoad() async {
    world.add(_BoardPainter(this));
    _applyLayout();
  }

  void _applyLayout() {
    final l = session.layout;
    if (l == null || l == _appliedLayout) return;
    _appliedLayout = l;
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..zoom = l.logicalPxPerWorldUnit
      ..position = Vector2(l.worldOffsetX, l.worldOffsetY);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _applyLayout();
    // Walk the shared timeline forward, then read this instant off it.
    session.buffer.advance(dt * 1000);
    entities = session.buffer.sampleAll();
    sling = session.buffer.sampleSling();
  }
}

class _BoardPainter extends Component {
  _BoardPainter(this.game);

  final ViewportGame game;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    final layout = game.session.layout;
    if (layout == null) return;

    final view = layout.viewport;
    final board = layout.board;

    // Out-of-board backdrop, then the playfield.
    _fill.color = const Color(0xFF0B1020);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
    _fill.color = const Color(0xFF141C33);
    canvas.drawRect(
      Rect.fromLTWH(board.left, board.top, board.width, board.height),
      _fill,
    );

    if (game.showGrid) _drawGrid(canvas, layout);
    if (game.showSeams) _drawSeams(canvas, layout);

    _drawEntities(canvas);
    _drawSling(canvas);
  }

  void _drawGrid(Canvas canvas, PhoneLayout layout) {
    final view = layout.viewport;
    final board = layout.board;

    // Cull to what this screen can actually see.
    final x0 = math.max(board.left, view.left).floorToDouble();
    final x1 = math.min(board.right, view.right).ceilToDouble();
    final y0 = math.max(board.top, view.top).floorToDouble();
    final y1 = math.min(board.bottom, view.bottom).ceilToDouble();

    // Stroke widths are in world units, so convert from the pixels we want.
    final thin = 1.0 / layout.logicalPxPerWorldUnit;

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

  void _drawSeams(Canvas canvas, PhoneLayout layout) {
    final coverage = game.session.coverage;
    if (coverage == null) return;
    final thin = 2.0 / layout.logicalPxPerWorldUnit;
    _stroke
      ..color = const Color(0x66FF3B6B)
      ..strokeWidth = thin;
    for (final seam in coverage.seamRects()) {
      canvas.drawLine(
        Offset(seam.left, seam.top),
        Offset(seam.left, seam.bottom),
        _stroke,
      );
      canvas.drawLine(
        Offset(seam.right, seam.top),
        Offset(seam.right, seam.bottom),
        _stroke,
      );
    }
  }

  void _drawEntities(Canvas canvas) {
    final layout = game.session.layout!;
    final view = layout.viewport.inflate(2.0);

    for (final spec in game.session.specs) {
      final e = game.entities[spec.id];
      if (e == null) continue;

      // Cull anything this screen cannot see. The entity still exists and is
      // still simulated — it is just somebody else's problem to draw. Boxes use
      // the half-diagonal so a rotated one is never clipped early.
      final reach = spec.shape == ShapeKind.circle
          ? spec.radius
          : math.sqrt(spec.width * spec.width + spec.height * spec.height) / 2;
      if (e.x + reach < view.left ||
          e.x - reach > view.right ||
          e.y + reach < view.top ||
          e.y - reach > view.bottom) {
        continue;
      }

      _fill.color = Color(spec.colorValue);
      switch (spec.shape) {
        case ShapeKind.circle:
          canvas.drawCircle(Offset(e.x, e.y), spec.radius, _fill);
          // A rotation tell, so a rolling bird reads as rolling.
          _fill.color = const Color(0x88FFFFFF);
          canvas.drawCircle(
            Offset(
              e.x + math.cos(e.angle) * spec.radius * 0.45,
              e.y + math.sin(e.angle) * spec.radius * 0.45,
            ),
            spec.radius * 0.22,
            _fill,
          );
        case ShapeKind.box:
          canvas
            ..save()
            ..translate(e.x, e.y)
            ..rotate(e.angle);
          final r = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: spec.width,
              height: spec.height,
            ),
            Radius.circular(math.min(spec.width, spec.height) * 0.12),
          );
          canvas
            ..drawRRect(r, _fill)
            ..restore();
      }
    }
  }

  void _drawSling(Canvas canvas) {
    final s = game.sling;
    final layout = game.session.layout;
    if (s == null || layout == null) return;

    final anchor = Offset(s.anchorX, s.anchorY);
    final px = 1.0 / layout.logicalPxPerWorldUnit;

    // The pouch marker is always drawn, so you can see where to grab.
    _stroke
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.5 * px;
    canvas.drawCircle(anchor, GameConfig.birdRadius * 1.5, _stroke);

    if (!s.active) return;

    final pull = Offset(s.pullX, s.pullY);
    final stretch = (pull - anchor).distance / GameConfig.maxPull;
    _stroke
      ..color = Color.lerp(
        const Color(0xFF7FD1C4),
        const Color(0xFFFF4D4D),
        stretch.clamp(0.0, 1.0),
      )!
      ..strokeWidth = 3 * px;
    canvas.drawLine(anchor, pull, _stroke);
  }
}
