import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../sdk/model/player_color.dart';

class PitchCarsArt {
  const PitchCarsArt._();

  static const cockpit = Offset(1257, 726.5);

  static const length = 2421.0;

  static final _pictures = <String, PictureInfo>{};
  static final _started = <String>{};

  static void preload(Iterable<PlayerColor> colors) {
    for (final color in colors) {
      car(color);
    }
  }

  static PictureInfo? car(PlayerColor color) {
    final asset = _assetOf(color);
    if (_started.add(asset)) unawaited(_load(asset));
    return _pictures[asset];
  }

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
