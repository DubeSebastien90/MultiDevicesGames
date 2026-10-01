import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'hungry_hippos_config.dart';

class HungryHipposView extends ShapeView {
  HungryHipposView(this.context) : super(roster: context.roster);

  final ViewContext context;

  final _rim = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(HungryHipposConfig.colorBowl);

  final _dish = Paint()..style = PaintingStyle.fill;

  final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final _chargingFor = <String, double>{};

  final _flashes = <String, _Flash>{};
  final _seenShoves = <String, String>{};

  static const double _flashSeconds = 0.25;

  final _ripple = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(HungryHipposConfig.colorRipple);

  static const _rippleGap = 1.6;

  @override
  void renderBackground(Canvas canvas, Frame frame) {
    final board = frame.board;
    final centre = Offset(board.centerX, board.centerY);
    _drawPond(canvas, frame, centre);

    final radius = _dishRadius(frame);

    _dish.shader = ui.Gradient.radial(centre, radius, [
      const Color(0x40FFFFFF),
      const Color(0x00FFFFFF),
    ]);
    canvas.drawCircle(centre, radius, _dish);
    _dish.shader = null;

    _rim.strokeWidth = frame.onePixel * 2;
    canvas.drawCircle(centre, radius, _rim);
  }

  @override
  double entityOpacity(Frame frame, RenderEntity e) {
    if (e.kind != 'hippo') return 1;
    final player = e.props[ShapeProps.player] as String?;
    return _statusOf(frame, player) == 's' ? 0.4 : 1;
  }

  @override
  void renderForeground(Canvas canvas, Frame frame) {
    _drawCharges(canvas, frame);
    _drawShoves(canvas, frame);
  }

  void _drawCharges(Canvas canvas, Frame frame) {
    for (final e in frame.ofKind('hippo')) {
      final player = e.props[ShapeProps.player] as String? ?? e.id;
      if (_statusOf(frame, player) != 'c') {
        _chargingFor.remove(player);
        continue;
      }
      final t = (_chargingFor[player] ?? 0) + frame.dt;
      _chargingFor[player] = t;
      final charge = (t / HungryHipposConfig.chargeFullSeconds).clamp(0.0, 1.0);

      _ring
        ..color = const Color(HungryHipposConfig.colorCharge)
        ..strokeWidth = frame.onePixel * 4;
      final r = HungryHipposConfig.hippoRadius * 1.9;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(e.x, e.y), radius: r),
        -math.pi / 2,
        2 * math.pi * charge,
        false,
        _ring,
      );
    }
  }

  void _drawShoves(Canvas canvas, Frame frame) {
    final shoves = frame.sharedState['shoves'];
    if (shoves is Map) {
      for (final entry in shoves.entries) {
        final tag = entry.value as String?;
        if (tag == null || _seenShoves[entry.key] == tag) continue;
        _seenShoves[entry.key] = tag;
        final parts = tag.split(':');
        if (parts.length != 3) continue;
        final x = double.tryParse(parts[1]);
        final y = double.tryParse(parts[2]);
        if (x == null || y == null) continue;
        _flashes[tag] = _Flash(x, y);
      }
    }

    _flashes.removeWhere((_, f) => (f.age += frame.dt) >= _flashSeconds);
    for (final f in _flashes.values) {
      final p = f.age / _flashSeconds;
      _ring
        ..color = const Color(
          HungryHipposConfig.colorPush,
        ).withValues(alpha: 0x88 / 255 * (1 - p))
        ..strokeWidth = frame.onePixel * 3;
      canvas.drawCircle(
        Offset(f.x, f.y),
        HungryHipposConfig.mouthRadius +
            (HungryHipposConfig.pushRadius - HungryHipposConfig.mouthRadius) *
                p,
        _ring,
      );
    }
  }

  String? _statusOf(Frame frame, String? player) {
    final hippos = frame.sharedState['hippos'];
    if (hippos is! Map || player == null) return null;
    return hippos[player] as String?;
  }

  void _drawPond(Canvas canvas, Frame frame, Offset centre) {
    final view = frame.visible;
    final board = frame.board;
    final everything = Rect.fromLTWH(
      view.left,
      view.top,
      view.width,
      view.height,
    );
    _dish.color = const Color(HungryHipposConfig.colorWaterEdge);
    canvas.drawRect(everything, _dish);
    _dish.color = const Color(HungryHipposConfig.colorWater);
    canvas.drawRect(
      Rect.fromLTWH(board.left, board.top, board.width, board.height),
      _dish,
    );

    final corners = [
      Offset(view.left, view.top),
      Offset(view.right, view.top),
      Offset(view.left, view.bottom),
      Offset(view.right, view.bottom),
    ];
    var far = 0.0;
    for (final c in corners) {
      far = far > (c - centre).distance ? far : (c - centre).distance;
    }
    _ripple.strokeWidth = 0.07;
    for (var r = _rippleGap; r <= far; r += _rippleGap) {
      canvas.drawCircle(centre, r, _ripple);
    }
  }

  double _dishRadius(Frame frame) =>
      (frame.sharedState['dish'] as num?)?.toDouble() ?? 0;
}

class _Flash {
  _Flash(this.x, this.y);
  final double x;
  final double y;
  double age = 0;
}
