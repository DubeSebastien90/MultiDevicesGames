import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'hungry_hippos_config.dart';

/// The dish, then the marbles and hippos on top of it.
///
/// Everything that moves is an ordinary entity, so [ShapeView] draws it and the
/// platform interpolates it. All this adds is the bowl itself — which is not a
/// thing in the simulation at all, only a force, and would otherwise be
/// invisible.
class HungryHipposView extends ShapeView {
  HungryHipposView(this.context);

  final ViewContext context;

  final _rim = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(HungryHipposConfig.colorBowl);

  final _dish = Paint()..style = PaintingStyle.fill;

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

  /// Straight from the simulation, which sized it. Working it out again here
  /// would be a second implementation of one fact, and the rim people aim at
  /// has to be the rim the marbles were dealt into.
  double _dishRadius(Frame frame) =>
      (frame.sharedState['dish'] as num?)?.toDouble() ?? 0;

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) => Text(
    frame.sharedState['over'] == true
        ? 'All gone'
        : '${frame.sharedState['marblesLeft']} left',
    style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 12),
  );
}
