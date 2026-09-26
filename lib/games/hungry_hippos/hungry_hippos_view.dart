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
  HungryHipposView(this.context) : super(roster: context.roster);

  final ViewContext context;

  final _rim = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(HungryHipposConfig.colorBowl);

  final _dish = Paint()..style = PaintingStyle.fill;

  final _ripple = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(HungryHipposConfig.colorRipple);

  /// How far apart the ripples round the middle of the pond are.
  static const _rippleGap = 1.6;

  @override
  void renderBackground(Canvas canvas, Frame frame) {
    final board = frame.board;
    final centre = Offset(board.centerX, board.centerY);
    _drawPond(canvas, frame, centre);

    // Wide enough to reach under every hippo, so the dish looks like the thing
    // they are all leaning into.
    final radius = _dishRadius(frame);

    // A soft dip rather than a flat disc: the marbles behave as though the
    // middle is lower, and the picture should agree with the physics.
    _dish.shader = ui.Gradient.radial(centre, radius, [
      const Color(0x40FFFFFF),
      const Color(0x00FFFFFF),
    ]);
    canvas.drawCircle(centre, radius, _dish);
    _dish.shader = null;

    _rim.strokeWidth = frame.onePixel * 2;
    canvas.drawCircle(centre, radius, _rim);
  }

  /// The water: a darker edge round the table, and rings spreading from the
  /// middle of it, centred on the board so they are one set of rings across
  /// every phone rather than a set per screen.
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

    // Only the rings this screen can see.
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

  /// Straight from the simulation, which sized it. Working it out again here
  /// would be a second implementation of one fact, and the rim people aim at
  /// has to be the rim the marbles were dealt into.
  double _dishRadius(Frame frame) =>
      (frame.sharedState['dish'] as num?)?.toDouble() ?? 0;

  // No HUD. The marbles are on the table: a count of them in the corner was
  // the same fact written twice, once where the players are looking and once
  // where they are not.
}
