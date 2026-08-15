/// A player's picture, as something you can draw rather than something you
/// have to load.
///
/// The API deliberately does not say what the art *is*. Not a path, not an
/// image, not an SVG — a handle with a [PlayerArt.draw] on it. A game asks for
/// a player's picture and paints it at a world position; whether that resolved
/// to a rasterised vector, a sprite sheet or eleven lines of geometry is the
/// SDK's business, and it will change at least once.
///
/// That indirection is what makes the whole feature shippable before any art
/// exists. What is here today paints a coloured circle and a coloured square.
/// It is not a stub — it is a complete implementation of the interface, which
/// means games can be written against the real API now and start looking like
/// something the day the assets land, with no game edited.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/player_character.dart';
import '../model/player_color.dart';

/// Which picture of a character.
///
/// Closed and small on purpose. Two views is a promise eight characters can
/// actually keep; "whatever the game needs" is one that gets broken by the
/// fourth game. A game wanting a third angle draws it itself, as they all do
/// today.
enum PlayerArtSlot {
  /// From above: the piece on the board. Small, rotated, read from two metres.
  topdown,

  /// From the side: a portrait. Upright, larger, has a face.
  face,
}

/// One player's picture in one slot.
///
/// **[draw] always paints something.** The sprite loader this replaced handed
/// the not-ready case back to its caller, and every caller solved it the same
/// way — Slingshot drew a circle — so this solves it once, on the inside. There
/// is no `false` to check and no fallback for a game to write: art that has not
/// loaded, or does not exist, is the placeholder geometry, and the round
/// neither waits nor looks broken. Artwork is not allowed to decide whether a
/// game starts, a rule this codebase learned the hard way — see
/// `test/sprite_loading_test.dart`.
abstract class PlayerArt {
  /// The art for a colour, in a slot. Cached — these are stateless and shared,
  /// so a game may call this in a render loop.
  factory PlayerArt.of(PlayerColor color, PlayerArtSlot slot) {
    final key = '${color.id}/${slot.name}';
    return _cache[key] ??= _ShapeArt(color, slot);
  }

  static final _cache = <String, PlayerArt>{};

  /// Start decoding the art for these colours, and hand control straight back.
  ///
  /// Called during placement, which is dead time — people are pushing phones
  /// together — so the picture is ready before the first frame. **Nothing
  /// awaits it.** A stalled decode must not be able to decide whether a round
  /// starts; a phone was once left on a screen that never appeared for exactly
  /// that reason. Here the worst case is a second of flat colour.
  ///
  /// Only the colours in play, rather than all sixteen images: a four-player
  /// round has no reason to hold eight pictures nobody is looking at.
  static void preload(Iterable<PlayerColor> colors) {
    for (final color in colors) {
      for (final slot in PlayerArtSlot.values) {
        PlayerArt.of(color, slot).beginLoading();
      }
    }
  }

  /// Decode this picture in the background if it has not been started.
  ///
  /// Safe to call repeatedly and safe never to call at all — the first [draw]
  /// starts it too. Until it finishes, the geometry is what gets painted.
  void beginLoading();

  /// Whether the file has arrived. For tests and a debug panel; a game has no
  /// reason to ask, because there is no case where nothing is drawn.
  bool get isLoaded;

  /// Paints centred on [center], scaled so the picture fills [worldSize] world
  /// units, turned by [angle] radians.
  ///
  /// The canvas arrives with the camera already applied, so this is world
  /// space: the same call on two phones puts the picture in the same physical
  /// place on the table.
  ///
  /// [opacity] is here because fading a player out is something games keep
  /// needing — knocked over, out of the round, not your turn — and the
  /// alternative is every caller wrapping this in a `saveLayer`, which is both
  /// more code and more expensive than multiplying two colours.
  void draw(
    Canvas canvas,
    Offset center, {
    required double worldSize,
    double angle = 0,
    double opacity = 1,
  });

  /// The same picture as a widget, for a HUD, the lobby or the results screen.
  ///
  /// Shares [draw]'s painting code rather than reimplementing it, so the
  /// portrait on the scoreboard and the piece on the board can never drift into
  /// being two different drawings of the same character.
  Widget widget({double size});
}

/// The placeholder: geometry in the player's colour.
///
/// A filled circle from above and a rounded square from the side — enough to be
/// unmistakably *somebody*, and honest about being unfinished. The outline is
/// [PlayerColor.onColor], the shade already chosen per entry to sit legibly on
/// that swatch, so a yellow player is still visible on a light background
/// without anyone computing a luminance at draw time.
class _ShapeArt implements PlayerArt {
  _ShapeArt(this.color, this.slot);

  final PlayerColor color;
  final PlayerArtSlot slot;

  final _fill = Paint()..isAntiAlias = true;
  final _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  /// Repainted when the picture lands, so a widget drawn before the decode
  /// finished does not sit on flat colour forever. The canvas path needs no
  /// such signal — it is already redrawing sixty times a second.
  final _arrived = ValueNotifier<int>(0);

  ui.Image? _image;
  bool _started = false;

  @override
  bool get isLoaded => _image != null;

  /// Where this picture lives, or null for a character nobody has drawn yet.
  String? get _asset => switch (slot) {
    PlayerArtSlot.topdown => Cast.of(color).topdownAsset,
    PlayerArtSlot.face => Cast.of(color).faceAsset,
  };

  @override
  void beginLoading() {
    if (_started) return;
    _started = true;
    final asset = _asset;
    if (asset == null) return;
    // Not awaited by anyone. A failure — a missing file, a codec that does not
    // like it — leaves [_image] null, which is simply the geometry, and is the
    // same outcome as a character that has not been drawn yet.
    unawaited(_load(asset));
  }

  Future<void> _load(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _image = frame.image;
      _arrived.value++;
    } on Object catch (e) {
      debugPrint('[player art] $asset did not load: $e');
    }
  }

  @override
  void draw(
    Canvas canvas,
    Offset center, {
    required double worldSize,
    double angle = 0,
    double opacity = 1,
  }) {
    // The first draw is also what starts the decode, so a game that never
    // preloads still ends up with pictures — a frame or two later.
    beginLoading();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (angle != 0) canvas.rotate(angle);
    _paint(canvas, worldSize, opacity);
    canvas.restore();
  }

  /// Paints centred on the origin, filling a [size] square.
  ///
  /// The picture when there is one, the geometry until then. Both are drawn to
  /// the same box, so the swap is a change of detail rather than of silhouette
  /// — nothing on the board moves or resizes when a decode finishes.
  void _paint(Canvas canvas, double size, [double opacity = 1]) {
    final image = _image;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: size, height: size),
        // The paint's alpha is what modulates an image; its colour is ignored.
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.medium
          ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity),
      );
      return;
    }

    final half = size / 2;
    _fill.color = color.value.withValues(alpha: opacity);
    _stroke
      ..color = color.onColor.withValues(alpha: opacity)
      // Proportional, not absolute: this is drawn at three world units on a
      // board and at forty-eight logical pixels in a HUD, and a fixed width
      // would be invisible in one and a black ring in the other.
      ..strokeWidth = size * 0.06;

    switch (slot) {
      case PlayerArtSlot.topdown:
        canvas
          ..drawCircle(Offset.zero, half, _fill)
          ..drawCircle(Offset.zero, half - _stroke.strokeWidth / 2, _stroke);
      case PlayerArtSlot.face:
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: size, height: size),
          Radius.circular(size * 0.22),
        );
        canvas
          ..drawRRect(rect, _fill)
          ..drawRRect(rect.deflate(_stroke.strokeWidth / 2), _stroke);
    }
  }

  @override
  Widget widget({double size = 48}) {
    beginLoading();
    return SizedBox(
      width: size,
      height: size,
      // Repainting on [_arrived] rather than rebuilding the widget: the art
      // outlives every screen that shows it, and a decode landing should not
      // require whoever drew it to be listening.
      child: CustomPaint(painter: _ShapeArtPainter(this, _arrived)),
    );
  }
}

class _ShapeArtPainter extends CustomPainter {
  const _ShapeArtPainter(this.art, Listenable repaint) : super(repaint: repaint);

  final _ShapeArt art;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.translate(size.width / 2, size.height / 2);
    art._paint(canvas, side);
  }

  @override
  bool shouldRepaint(_ShapeArtPainter old) => !identical(old.art, art);
}
