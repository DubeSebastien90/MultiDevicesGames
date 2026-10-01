import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import 'subway_skater_art.dart';
import 'subway_skater_config.dart';

class SubwaySkaterView extends GameView {
  SubwaySkaterView(this.context) {
    SubwaySkaterArt.preload();
  }

  final ViewContext context;

  static const _verge = Color(0xFFAEE294);
  static const _floor = Color(0xFF101A2E);
  static const _rail = Color(0xFF3D5A8A);
  static const _laneMark = Color(0xFFF2C230);
  static const _hazard = Color(0xFFFF6B3D);
  static const _hazardCore = Color(0xFF7A2410);
  static const _charge = Color(0xFFFFD166);

  final _paint = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  String _tumblingRaw = '';
  Set<String> _tumbling = const {};
  String _chargingRaw = '';
  Set<String> _charging = const {};

  @override
  void render(Canvas canvas, Frame frame) {
    _readShared(frame);

    _drawCorridor(canvas, frame);
    for (final o in frame.ofKind('obstacle')) {
      _drawObstacle(canvas, o);
    }
    for (final b in frame.ofKind('burst')) {
      _drawBurst(canvas, frame, b);
    }

    for (final s in frame.ofKind('skater')) {
      _drawSkater(canvas, frame, s);
    }
  }

  void _readShared(Frame frame) {
    final tumbling = frame.sharedState['tumbling'] as String? ?? '';
    if (tumbling != _tumblingRaw) {
      _tumblingRaw = tumbling;
      _tumbling = tumbling.isEmpty ? const {} : tumbling.split(',').toSet();
    }

    final charging = frame.sharedState['charging'] as String? ?? '';
    if (charging != _chargingRaw) {
      _chargingRaw = charging;
      _charging = charging.isEmpty ? const {} : charging.split(',').toSet();
    }
  }

  void _drawCorridor(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2);
    final board = frame.board;

    _paint.color = _verge;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _paint,
    );

    final left = math.max(view.left, board.left);
    final right = math.min(view.right, board.right);
    if (right <= left) return;

    final street = SubwaySkaterArt.street;
    if (street != null) {
      _drawStreet(canvas, frame, street, left, right);
    } else {
      _paint.color = _floor;
      canvas.drawRect(
        Rect.fromLTRB(left, board.top, right, board.bottom),
        _paint,
      );

      _stroke
        ..color = _rail
        ..strokeWidth = frame.onePixel * 2;
      canvas.drawLine(
        Offset(left, board.top),
        Offset(right, board.top),
        _stroke,
      );
      canvas.drawLine(
        Offset(left, board.bottom),
        Offset(right, board.bottom),
        _stroke,
      );
    }

    _drawLaneDashes(canvas, frame, left, right);
  }

  void _drawStreet(
    Canvas canvas,
    Frame frame,
    PictureInfo street,
    double left,
    double right,
  ) {
    final board = frame.board;
    final tile = board.height * SubwaySkaterArt.aspect(street);
    if (tile <= 0) return;
    final phase = SubwaySkaterConfig.travelAt(frame.timeMs / 1000) % tile;

    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(left, board.top, right, board.bottom));
    var x = ((left - phase) / tile).floorToDouble() * tile + phase;
    while (x < right) {
      SubwaySkaterArt.paint(
        canvas,
        street,
        Rect.fromLTWH(x, board.top, tile, board.height),
      );
      x += tile;
    }
    canvas.restore();
  }

  void _drawLaneDashes(Canvas canvas, Frame frame, double left, double right) {
    const period = 3.0;
    const dash = 1.6;

    final phase = SubwaySkaterConfig.travelAt(frame.timeMs / 1000) % period;
    final board = frame.board;

    _stroke
      ..color = _laneMark
      ..strokeWidth = 0.12;

    for (var lane = 1; lane < SubwaySkaterConfig.lanes; lane++) {
      final y = board.top + board.height * lane / SubwaySkaterConfig.lanes;

      var x = (left / period).floorToDouble() * period + phase - period;
      while (x < right) {
        final a = math.max(x, left);
        final b = math.min(x + dash, right);
        if (b > a) canvas.drawLine(Offset(a, y), Offset(b, y), _stroke);
        x += period;
      }
    }
  }

  void _drawObstacle(Canvas canvas, RenderEntity o) {
    final w = o.propDouble('w', SubwaySkaterConfig.obstacleLength);
    final h = o.propDouble('h', 1);
    final rect = Rect.fromCenter(center: Offset(o.x, o.y), width: w, height: h);

    final car = SubwaySkaterArt.car(o.propInt('car'));
    if (car != null) {
      final width = math.min(h, w / SubwaySkaterArt.aspect(car));
      SubwaySkaterArt.paint(
        canvas,
        car,
        Rect.fromCenter(center: rect.center, width: w, height: width),
      );
      return;
    }
    final rounded = RRect.fromRectXY(rect, h * 0.25, h * 0.25);

    _paint.color = _hazard;
    canvas.drawRRect(rounded, _paint);

    _paint.color = _hazardCore;
    canvas.drawRRect(
      RRect.fromRectXY(rect.deflate(h * 0.22), h * 0.12, h * 0.12),
      _paint,
    );
  }

  void _drawBurst(Canvas canvas, Frame frame, RenderEntity b) {
    final life = SubwaySkaterConfig.burstSeconds * 1000;
    final t = ((frame.timeMs - b.propDouble('born')) / life).clamp(0.0, 1.0);
    if (t >= 1) return;

    final size = b.propDouble('size', 1);

    final spread = 1 - (1 - t) * (1 - t);
    final fade = 1 - t;

    _stroke
      ..color = _charge.withValues(alpha: 0.8 * fade)
      ..strokeWidth = frame.onePixel * 2;
    canvas.drawCircle(Offset(b.x, b.y), size * (0.3 + 1.5 * spread), _stroke);

    _paint.color = _hazard.withValues(alpha: fade);
    final shard = size * 0.26 * fade;
    for (var i = 0; i < 5; i++) {
      final a = b.angle + i * 2 * math.pi / 5;
      final at =
          Offset(b.x, b.y) +
          Offset(math.cos(a), math.sin(a)) * (size * (0.2 + 1.7 * spread));
      canvas.drawRect(
        Rect.fromCenter(center: at, width: shard * 2, height: shard * 2),
        _paint,
      );
    }
  }

  void _drawSkater(Canvas canvas, Frame frame, RenderEntity s) {
    final r = s.propDouble('r', SubwaySkaterConfig.skaterRadius);
    final phoneId = s.props['phone'] as String?;
    final down = phoneId != null && _tumbling.contains(phoneId);
    final charged = phoneId != null && _charging.contains(phoneId);

    final player = phoneId == null ? null : context.roster.byPhone(phoneId);
    final color = player?.color.value ?? const Color(0xFFF2F4F8);
    final center = Offset(s.x, s.y);

    if (charged) {
      _paint.color = _charge.withValues(alpha: 0.28);
      canvas.drawCircle(center, r * 2.1, _paint);
      _paint.color = _charge.withValues(alpha: 0.5);
      canvas.drawCircle(center, r * 1.5, _paint);
    }

    if (player != null) {
      final speed =
          SubwaySkaterConfig.speedAt(frame.timeMs / 1000) /
          SubwaySkaterConfig.obstacleSpeed;
      final character = context.characters.of(player.color);
      character.start();
      character.draw(
        canvas,
        center,
        worldSize: r * 2,
        dt: frame.dt * speed,
        angle: s.angle,
        opacity: down ? 0.55 : 1,
      );
    } else {
      _paint.color = down ? color.withValues(alpha: 0.55) : color;
      canvas.drawCircle(center, r, _paint);
    }
  }
}
