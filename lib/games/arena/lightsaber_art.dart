import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/render/tinted_rive.dart';

class LightsaberArt {
  const LightsaberArt._();

  static final _art = TintedRive(
    'assets/icons/LightSaber.riv',
    property: 'LightSaberColor',
  );

  static const _centreX = 1001.5;

  static const _bladeBase = 1177.6;

  static const _bladeTip = 59.7;

  static void preload(Iterable<Color> colors) => _art.preload(colors);

  static bool isLoaded(Color color) => _art.artboard(color) != null;

  static bool draw(
    Canvas canvas,
    Color color, {
    required double length,
    double from = double.negativeInfinity,
    double to = double.infinity,
  }) {
    final artboard = _art.artboard(color);
    if (artboard == null) return false;
    if (to <= from) return true;
    final scale = length / (_bladeBase - _bladeTip);

    final reach = length * 2;
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTRB(
          math.max(from, -reach),
          -length,
          math.min(to, reach),
          length,
        ),
      )
      ..rotate(math.pi / 2)
      ..scale(scale)
      ..translate(-_centreX, -_bladeBase);
    TintedRive.paint(canvas, artboard);
    canvas.restore();
    return true;
  }
}
