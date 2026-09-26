import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The potato, from `assets/icons/hotPotato/`: a calm face and an alarmed one.
///
/// Kept as vector pictures rather than rasterised: they are drawn in world
/// units under the camera, swelling as the fuse burns, and a picture is crisp
/// at every size it passes through.
///
/// Nothing awaits the load. Until a picture lands — or for good, if it does
/// not — the view draws the oval potato it drew before there was any art.
class HotPotatoArt {
  const HotPotatoArt._();

  static const _calm = 'assets/icons/hotPotato/potatoCalm.svg';
  static const _excited = 'assets/icons/hotPotato/potatoNotCalm.svg';

  // Where the potato is on the drawing, in its own units (2203 x 2236,
  // top-left origin). Read off the outline, so they move if it is redrawn.

  /// The middle of the potato, which is what it spins about.
  static const centre = Offset(1170, 1005);

  /// The potato's longest side, top to bottom.
  static const length = 1850.0;

  static final _pictures = <String, PictureInfo>{};
  static Future<void>? _loading;

  /// Start loading, and hand control straight back. Safe to call every frame.
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

  /// The face for how worried it should look, or null until it has loaded.
  static PictureInfo? of({required bool excited}) {
    preload();
    return _pictures[excited ? _excited : _calm];
  }
}
