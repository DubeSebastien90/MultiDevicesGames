import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../sdk/model/player_color.dart';

/// The racing cars, from `assets/icons/pitchCars/`: one drawing per player
/// colour, named after it — `GreenCar.svg`, `RedCar.svg`, and so on.
///
/// Kept as vector pictures rather than rasterised: they are drawn in world
/// units under the camera, and a picture is crisp at whatever size a
/// centimetre is on this phone.
///
/// Nothing awaits the load. Until a car lands — or for good, for a colour with
/// no car of its own — the driver is drawn without one, as before.
class PitchCarsArt {
  const PitchCarsArt._();

  // Where things are on the drawing, in its own units (2421 x 1453, top-left
  // origin, nose pointing +x). Read off the drawing, so they move if it is
  // redrawn.

  /// The middle of the cockpit, where the driver sits: the point that goes on
  /// the car's position, and what it turns about.
  static const cockpit = Offset(1257, 726.5);

  /// Nose to rear wing.
  static const length = 2421.0;

  static final _pictures = <String, PictureInfo>{};
  static final _started = <String>{};

  /// Start loading these colours' cars, and hand control straight back.
  static void preload(Iterable<PlayerColor> colors) {
    for (final color in colors) {
      car(color);
    }
  }

  /// The car in [color], or null until it has loaded — and for good for a
  /// colour nobody drew a car for. The first ask starts the load.
  static PictureInfo? car(PlayerColor color) {
    final asset = _assetOf(color);
    if (_started.add(asset)) unawaited(_load(asset));
    return _pictures[asset];
  }

  /// `green` is `GreenCar.svg`.
  static String _assetOf(PlayerColor color) {
    final id = color.id;
    final name = id.isEmpty ? id : id[0].toUpperCase() + id.substring(1);
    return 'assets/icons/pitchCars/${name}Car.svg';
  }

  static Future<void> _load(String asset) async {
    try {
      _pictures[asset] = await vg.loadPicture(SvgAssetLoader(asset), null);
    } on Object catch (e) {
      debugPrint('[pitch cars] $asset did not load: $e');
    }
  }
}
