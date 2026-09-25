import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/render/tinted_rive.dart';

/// The lightsaber, from `LightSaber.riv`: one drawing, its blade in whatever
/// colour it is asked for through `LightSaberColor` on `LightSaberVM`.
///
/// Drawn in a sword entity's own frame — the hilt at the origin, the blade
/// running down +x for the entity's length — so the drawn blade and the
/// hitbox are the same segment.
class LightsaberArt {
  const LightsaberArt._();

  static final _art = TintedRive(
    'assets/icons/LightSaber.riv',
    property: 'LightSaberColor',
  );

  // Where things are on the artboard, in its own units (2000 x 2000, top-left
  // origin, blade pointing up). Read off the drawing, so they move if it is
  // redrawn.

  /// Down the middle of the blade and the grip.
  static const _centreX = 1001.5;

  /// Where the blade leaves the emitter: the top of the hilt.
  static const _bladeBase = 1177.6;

  /// The very tip of the glow.
  static const _bladeTip = 59.7;

  /// Start loading these colours, and hand control straight back.
  static void preload(Iterable<Color> colors) => _art.preload(colors);

  /// Whether [color] can be drawn yet. Starts it loading if it was not.
  static bool isLoaded(Color color) => _art.artboard(color) != null;

  /// Paints the saber with its blade [length] long, keeping only the part
  /// between [from] and [to] along the blade — negative is the grip.
  ///
  /// False, having drawn nothing, until the art has loaded, and for good on a
  /// platform without Rive: the caller draws its own blade instead.
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
    // The whole saber, grip included, is a little under twice the blade.
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
      // The drawing points up, and the blade here points along +x.
      ..rotate(math.pi / 2)
      ..scale(scale)
      ..translate(-_centreX, -_bladeBase);
    TintedRive.paint(canvas, artboard);
    canvas.restore();
    return true;
  }
}
