/// A player's arm and hand, reaching in from the edge of their screen.
///
/// One `.riv` for the whole cast, like the piece on the board: the same drawing
/// eight times over, with only the fill changing. That fill is `HandColor` on
/// the artboard's `HandVM`, fed [PlayerColor.value]. There is only a right hand
/// in the file — the left is the same artboard mirrored.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../model/player_color.dart';
import '../ui/intro_animation.dart';

/// One colour's hand. Cached and shared, so a view may ask for it every frame.
///
/// **[draw] always paints something**, by the same rule as `PlayerArt`: until
/// the artboard has loaded — or for good, on a platform without Rive — it is a
/// rounded bar in the player's colour, the shape the arms had before the art.
class PlayerHand {
  PlayerHand._(this.color);

  factory PlayerHand.of(PlayerColor color) =>
      _cache[color.id] ??= PlayerHand._(color);

  static final _cache = <String, PlayerHand>{};

  /// Start loading these colours' hands, and hand control straight back.
  /// Nothing awaits it; until it lands, the bar is what gets painted.
  static void preload(Iterable<PlayerColor> colors) {
    for (final color in colors) {
      PlayerHand.of(color).beginLoading();
    }
  }

  final PlayerColor color;

  rive.Artboard? _artboard;
  bool _started = false;

  bool get isLoaded => _artboard != null;

  // Where things are on the artboard, in its own units (500 x 500, top-left
  // origin). Read off the drawing, so they move if it is redrawn.

  /// The middle of the cut at the end of the forearm, bottom left.
  static const _cut = Offset(105.5, 490);

  /// The middle of the palm, where the fingers meet: what catches the potato.
  static const _palm = Offset(285, 205);

  /// The forearm's width at the cut, across the arm.
  static const _cutWidth = 112.0;

  /// From the cut to the palm: the direction the arm reaches in the drawing,
  /// and how long it is.
  static final _reachAngle = math.atan2(_palm.dy - _cut.dy, _palm.dx - _cut.dx);
  static final _reachLength = (_palm - _cut).distance;

  void beginLoading() {
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final file = await _HandFile.file();
    if (file == null) return;
    try {
      final artboard = file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final machine = artboard.defaultStateMachine();
      _bind(file, artboard, machine);
      // Once: this is a still, and advancing by zero is what applies the
      // binding.
      machine?.advanceAndApply(0);
      _artboard = artboard;
    } on Object catch (e) {
      debugPrint('[player hand] no hand for ${color.id}: $e');
    }
  }

  void _bind(
    rive.File file,
    rive.Artboard artboard,
    rive.StateMachine? machine,
  ) {
    final viewModel = file.defaultArtboardViewModel(artboard);
    final instance = viewModel?.createDefaultInstance();
    if (viewModel == null || instance == null) {
      debugPrint(
        '[player hand] ${_HandFile.asset} has no view model — '
        'hands keep the colour they were drawn',
      );
      return;
    }
    // Each colour binds its own instance, or every hand at the table would be
    // whoever was coloured last.
    artboard.bindViewModelInstance(instance);
    machine?.bindViewModelInstance(instance);
    final property = instance.color('HandColor');
    if (property == null) {
      debugPrint('[player hand] ${viewModel.name} has no HandColor');
      return;
    }
    property.value = color.value;
  }

  /// Paints the arm with the palm on [palm], reaching along [angle] — the
  /// direction from the shoulder to the hand, in the same convention as an
  /// entity's angle.
  ///
  /// [length] is how far back from the palm the arm goes before it is cut off,
  /// in world units, and it sets the size: the whole drawing scales so its
  /// forearm is that long. Put the far end past the edge of the screen and
  /// the cut is never seen.
  ///
  /// [left] mirrors it across the arm. The drawing is a right hand seen from
  /// above, thumb toward the body.
  void draw(
    Canvas canvas,
    Offset palm, {
    required double angle,
    required double length,
    bool left = false,
    double opacity = 1,
  }) {
    beginLoading();
    if (length <= 0) return;
    final scale = length / _reachLength;

    canvas
      ..save()
      ..translate(palm.dx, palm.dy)
      ..rotate(angle);
    // In here the arm runs along +x, from the shoulder at -length to the palm
    // at the origin. Flipping y mirrors the hand across its own arm.
    if (left) canvas.scale(1, -1);

    final artboard = _artboard;
    if (artboard == null) {
      _drawFallback(canvas, length, _cutWidth * scale, opacity);
    } else {
      canvas
        ..rotate(-_reachAngle)
        ..scale(scale)
        ..translate(-_palm.dx, -_palm.dy);
      final renderer = rive.Renderer.make(canvas);
      if (opacity < 1) renderer.modulateOpacity(opacity);
      artboard.draw(renderer);
    }
    canvas.restore();
  }

  final _fill = Paint()..isAntiAlias = true;

  void _drawFallback(
    Canvas canvas,
    double length,
    double width,
    double opacity,
  ) {
    _fill.color = color.value.withValues(alpha: opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-length, -width / 2, width / 2, width / 2),
        Radius.circular(width * 0.35),
      ),
      _fill,
    );
  }
}

/// The hand file, opened once for the whole app. Resolves to null rather than
/// throwing — on a platform that cannot render Rive, or a file that will not
/// parse — and null is the bar.
class _HandFile {
  const _HandFile._();

  static const asset = 'assets/sdk/players/hand.riv';

  static Future<rive.File?>? _opening;

  static Future<rive.File?> file() => _opening ??= _open();

  static Future<rive.File?> _open() async {
    // Same gate as every other Rive file: see
    // [IntroAnimation.platformSupportsRive].
    if (!IntroAnimation.available) return null;
    try {
      return await rive.File.asset(asset, riveFactory: rive.Factory.flutter);
    } on Object catch (e) {
      debugPrint('[player hand] $asset did not load: $e');
      return null;
    }
  }
}
