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
import 'package:rive/rive.dart' as rive;

import '../model/player_character.dart';
import '../model/player_color.dart';
import '../ui/intro_animation.dart';

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
/// way, by drawing a circle — so this solves it once, on the inside. There
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
    return _cache[key] ??= switch (slot) {
      // The piece on the board is one vector character, coloured per player
      // from its view model — see [_TopdownArt]. The portrait is still one
      // drawn image per colour.
      PlayerArtSlot.topdown => _TopdownArt(color),
      PlayerArtSlot.face => _ShapeArt(color, slot),
    };
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
  ///
  /// Looked up rather than defaulted: a colour with no character of its own —
  /// [PlayerPalette.away] — is the geometry in its own shade, not Green's
  /// picture.
  String? get _asset => switch (slot) {
    PlayerArtSlot.topdown => Cast.byColorId(color.id)?.topdownAsset,
    PlayerArtSlot.face => Cast.byColorId(color.id)?.faceAsset,
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

/// The piece on the board: one `.riv` character, painted in a player's colours.
///
/// One file for the whole cast rather than an image per colour, because the
/// character is the same drawing eight times over and the only thing that
/// differs is three fills. Those come off [PlayerColor] — [PlayerColor.value],
/// [PlayerColor.skinLight] and [PlayerColor.skinDark] — and are bound to the
/// artboard's own view model, so re-tinting the cast is editing the palette
/// rather than re-exporting eight images.
///
/// **It is a ladder, not a replacement.** Rive does not render on every
/// platform this is developed on — Windows takes the process down, see
/// [IntroAnimation.platformSupportsRive] — and a file can always fail to
/// parse. Either way this falls through to [_ShapeArt], which is the drawn
/// topdown image and, under that, the flat geometry. Every rung paints
/// something, which is the rule this class exists inside of: art never decides
/// whether a round starts.
class _TopdownArt implements PlayerArt {
  _TopdownArt(this.color);

  final PlayerColor color;

  /// The drawn image, and the geometry under it. Built up front rather than on
  /// failure: it is what paints every frame until the artboard is ready, and
  /// on a platform without Rive it is what paints for the whole session.
  late final _fallback = _ShapeArt(color, PlayerArtSlot.topdown);

  /// Which way the character is drawn, in the same convention as an entity's
  /// angle: 0 is +x, `pi / 2` is down the screen — which is how this one is
  /// drawn. Everything is turned by the difference between where the player is
  /// heading and this.
  static const _facing = 1.5707963267948966; // pi / 2

  /// Repainted when the artboard lands, so a widget drawn before the file
  /// arrived does not sit on the fallback forever. The canvas path needs no
  /// such signal — it is already redrawing sixty times a second.
  final _arrived = ValueNotifier<int>(0);

  rive.Artboard? _artboard;
  bool _started = false;

  @override
  bool get isLoaded => _artboard != null || _fallback.isLoaded;

  @override
  void beginLoading() {
    _fallback.beginLoading();
    if (_started) return;
    _started = true;
    // Not awaited by anyone, exactly like the image decode below it.
    unawaited(_load());
  }

  Future<void> _load() async {
    final file = await _RiveCast.file();
    if (file == null) return;
    try {
      // `frameOrigin: true` puts the artboard's top-left at (0, 0). The
      // centring is done by hand in [_paint], which is the only version of it
      // that behaves the same on every runtime.
      final artboard = file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final machine = artboard.defaultStateMachine();
      _bind(file, artboard, machine);
      // Once, and only ever once: this is a still. Advancing by zero is what
      // applies the binding, and never advancing again is what keeps the
      // character from walking off on its own clock.
      machine?.advanceAndApply(0);
      _artboard = artboard;
      _arrived.value++;
    } on Object catch (e) {
      debugPrint('[player art] no topdown character for ${color.id}: $e');
    }
  }

  /// Put a player's three shades on their character.
  ///
  /// By name, unlike the walking character's single fill, because there are
  /// three of them and position in the list is not a contract. A property that
  /// is not there is said out loud and skipped: two shades on a character is
  /// worth more than none.
  void _bind(rive.File file, rive.Artboard artboard, rive.StateMachine? machine) {
    final viewModel = file.defaultArtboardViewModel(artboard);
    final instance = viewModel?.createDefaultInstance();
    if (viewModel == null || instance == null) {
      debugPrint('[player art] ${_RiveCast.asset} has no view model — '
          'characters keep the colours they were drawn');
      return;
    }
    // Each artboard binds its *own* instance: a shared one would repaint every
    // character on the table the colour of whoever was coloured last.
    artboard.bindViewModelInstance(instance);
    machine?.bindViewModelInstance(instance);
    const skins = {
      'SkinPrincipal': 'value',
      'SkinLight': 'skinLight',
      'SkinDark': 'skinDark',
    };
    final shades = <String, Color>{
      'SkinPrincipal': color.value,
      'SkinLight': color.skinLight,
      'SkinDark': color.skinDark,
    };
    for (final entry in shades.entries) {
      final property = instance.color(entry.key);
      if (property == null) {
        debugPrint('[player art] ${viewModel.name} has no ${entry.key} '
            '(expected the ${skins[entry.key]} shade)');
        continue;
      }
      property.value = entry.value;
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
    // The first draw is also what starts the load, so a game that never
    // preloads still ends up with characters — a frame or two later.
    beginLoading();

    final artboard = _artboard;
    if (artboard == null) {
      _fallback.draw(canvas, center,
          worldSize: worldSize, angle: angle, opacity: opacity);
      return;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle - _facing);
    _paint(canvas, artboard, worldSize, opacity);
    canvas.restore();
  }

  /// Paints the artboard centred on the origin, its longest side filling
  /// [size].
  void _paint(
      Canvas canvas, rive.Artboard artboard, double size, double opacity) {
    final bounds = artboard.bounds;
    final longest = bounds.width > bounds.height ? bounds.width : bounds.height;
    if (longest == 0) return;

    canvas.save();
    canvas.scale(size / longest);
    // The artboard draws from its top-left, so pull it back by half its size:
    // the origin is then the middle of the character, and the rotation above
    // turns about that same point.
    canvas.translate(-bounds.width / 2, -bounds.height / 2);
    // A fresh renderer each frame, so the modulation starts from full and does
    // not accumulate over a fade.
    final renderer = rive.Renderer.make(canvas);
    if (opacity < 1) renderer.modulateOpacity(opacity);
    artboard.draw(renderer);
    canvas.restore();
  }

  @override
  Widget widget({double size = 48}) {
    beginLoading();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TopdownArtPainter(this, _arrived)),
    );
  }
}

/// Drawn upright, not turned to [_TopdownArt._facing]: a piece on the board
/// points where the player is heading, but a picture in a HUD points at the
/// person reading it.
class _TopdownArtPainter extends CustomPainter {
  const _TopdownArtPainter(this.art, Listenable repaint)
      : super(repaint: repaint);

  final _TopdownArt art;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final artboard = art._artboard;
    canvas.translate(size.width / 2, size.height / 2);
    if (artboard == null) {
      art._fallback._paint(canvas, side);
      return;
    }
    art._paint(canvas, artboard, side, 1);
  }

  @override
  bool shouldRepaint(_TopdownArtPainter old) => !identical(old.art, art);
}

/// The one character file, opened once for the whole app.
///
/// Static because the cast it feeds is: [PlayerArt._cache] holds its artboards
/// for the life of the process, and a file per colour would be eight parses of
/// the same kilobyte. Nothing here throws — a platform that cannot render Rive
/// and a file that will not parse both resolve to null, which is a topdown
/// image on the board rather than an error anybody sees.
class _RiveCast {
  const _RiveCast._();

  static const asset = 'assets/sdk/players/smallcharacter.riv';

  static Future<rive.File?>? _opening;

  static Future<rive.File?> file() => _opening ??= _open();

  static Future<rive.File?> _open() async {
    // Same gate as the intro and the walking cast: on a platform where
    // `rive_native` takes the process down there is nothing to catch, so do
    // not even load. See [IntroAnimation.platformSupportsRive].
    if (!IntroAnimation.available) return null;
    try {
      return await rive.File.asset(
        asset,
        // The Flutter renderer, not Rive's: this is drawn into the game's own
        // canvas alongside everything else, not into a surface of its own.
        riveFactory: rive.Factory.flutter,
      );
    } on Object catch (e) {
      debugPrint('[player art] $asset did not load: $e');
      return null;
    }
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
