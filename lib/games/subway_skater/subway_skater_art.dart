import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The street and the cars on it, from `assets/icons/subwaySkater/`.
///
/// Kept as vector pictures rather than rasterised: they are drawn in world
/// units under the camera, at whatever size a centimetre is on this phone, and
/// a picture is crisp at all of them.
///
/// Nothing awaits the load. Until a picture lands — or for good, if it does
/// not — the view draws the flat shapes it drew before there was any art.
class SubwaySkaterArt {
  const SubwaySkaterArt._();

  static const _folder = 'assets/icons/subwaySkater';

  /// The cars, both drawn nose to +x — the way the obstacles travel.
  static const _cars = ['$_folder/car1.svg', '$_folder/car2.svg'];

  /// One stretch of road, drawn to repeat end to end along x.
  static const _street = '$_folder/street_tile.svg';

  static final _pictures = <String, PictureInfo>{};
  static Future<void>? _loading;

  /// Start loading, and hand control straight back. Safe to call every frame.
  static void preload() => _loading ??= _loadAll();

  static Future<void> _loadAll() async {
    for (final asset in [_street, ..._cars]) {
      try {
        _pictures[asset] = await vg.loadPicture(SvgAssetLoader(asset), null);
      } on Object catch (e) {
        debugPrint('[subway skater] $asset did not load: $e');
      }
    }
  }

  static PictureInfo? car(int index) {
    preload();
    return _pictures[_cars[index % _cars.length]];
  }

  static PictureInfo? get street {
    preload();
    return _pictures[_street];
  }

  /// Paints [art] into [rect], stretched to fill it.
  static void paint(Canvas canvas, PictureInfo art, Rect rect) {
    canvas
      ..save()
      ..translate(rect.left, rect.top)
      ..scale(rect.width / art.size.width, rect.height / art.size.height)
      ..drawPicture(art.picture)
      ..restore();
  }

  /// The aspect of [art], width over height.
  static double aspect(PictureInfo art) => art.size.width / art.size.height;
}
