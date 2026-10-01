import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SubwaySkaterArt {
  const SubwaySkaterArt._();

  static const _folder = 'assets/icons/subwaySkater';

  static const _cars = ['$_folder/car1.svg', '$_folder/car2.svg'];

  static const _street = '$_folder/street_tile.svg';

  static final _pictures = <String, PictureInfo>{};
  static Future<void>? _loading;

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

  static void paint(Canvas canvas, PictureInfo art, Rect rect) {
    canvas
      ..save()
      ..translate(rect.left, rect.top)
      ..scale(rect.width / art.size.width, rect.height / art.size.height)
      ..drawPicture(art.picture)
      ..restore();
  }

  static double aspect(PictureInfo art) => art.size.width / art.size.height;
}
