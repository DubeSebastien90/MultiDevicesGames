import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class HotPotatoArt {
  const HotPotatoArt._();

  static const _calm = 'assets/icons/hotPotato/potatoCalm.svg';
  static const _excited = 'assets/icons/hotPotato/potatoNotCalm.svg';

  static const centre = Offset(1170, 1005);

  static const length = 1850.0;

  static final _pictures = <String, PictureInfo>{};
  static Future<void>? _loading;

  static void preload() => _loading ??= _loadAll();

  static Future<void> _loadAll() async {
    for (final asset in [_calm, _excited]) {
      try {
        _pictures[asset] = await vg.loadPicture(SvgAssetLoader(asset), null);
      } on Object catch (e) {
        debugPrint('[hot potato] $asset did not load: $e');
      }
    }
  }

  static PictureInfo? of({required bool excited}) {
    preload();
    return _pictures[excited ? _excited : _calm];
  }
}
