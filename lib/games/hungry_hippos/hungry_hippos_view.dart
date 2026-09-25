import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'hungry_hippos_config.dart';

/// The dish, then the marbles and hippos on top of it, then the tells: a
/// charge filling up, a shove going off, a hippo seeing stars.
///
/// Everything that moves is an ordinary entity, so [ShapeView] draws it and the
/// platform interpolates it. The bowl is not a thing in the simulation at all,
/// only a force, and would otherwise be invisible.
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

  /// How long each hippo has been charging, counted here rather than sent:
  /// shared state only says *that* it is charging, and a meter that fills a
  /// frame late on one phone than another does not matter to anybody.
  final _chargingFor = <String, double>{};

  /// Shoves still fading out, by the sim's `count:x:y` tag.
  final _flashes = <String, _Flash>{};
  final _seenShoves = <String, String>{};

  static const double _flashSeconds = 0.25;

  @override
  void renderBackground(Canvas canvas, Frame frame) {
    final board = frame.board;
    final centre = Offset(board.centerX, board.centerY);

    // Wide enough to reach under every hippo, so the dish looks like the thing
    // they are all leaning into.
    final radius = _dishRadius(frame);

    // A soft dip rather than a flat disc: the marbles behave as though the
    // middle is lower, and the picture should agree with the physics.
    _dish.shader = ui.Gradient.radial(centre, radius, [
      const Color(0x1AFFFFFF),
      const Color(0x00FFFFFF),
    ]);
    canvas.drawCircle(centre, radius, _dish);
    _dish.shader = null;

    _rim.strokeWidth = frame.onePixel * 2;
    canvas.drawCircle(centre, radius, _rim);
  }

  /// A dazed hippo is drawn faded, so its player — and everyone else — can see
  /// it is out of the game for a moment.
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

  /// A ring closing around a charging hippo, full when the charge is.
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

  /// An expanding ring where a lunge went off, as wide as what it shoved.
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

  /// Straight from the simulation, which sized it. Working it out again here
  /// would be a second implementation of one fact, and the rim people aim at
  /// has to be the rim the marbles were dealt into.
  double _dishRadius(Frame frame) =>
      (frame.sharedState['dish'] as num?)?.toDouble() ?? 0;

  // No HUD. The marbles are on the table: a count of them in the corner was
  // the same fact written twice, once where the players are looking and once
  // where they are not.
}

class _Flash {
  _Flash(this.x, this.y);
  final double x;
  final double y;
  double age = 0;
}
