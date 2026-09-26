/// A player's character, walking — as something you can draw rather than
/// something you have to load, rig and colour.
///
/// The sibling of [PlayerArt], and the same bargain: a game says *who* and
/// *where*, and whether they are moving. Everything else — which file, which
/// state machine, which view model property holds the skin colour, whether this
/// platform can render Rive at all, what to draw when it cannot — is the SDK's
/// business and will change again.
///
/// **One animation per colour.** There is one `.riv` for the whole cast; a
/// character *is* a colour, so an artboard per colour is an artboard per
/// player, which is exactly what independent walking needs: six people start
/// and stop on their own, and one shared artboard can only be walking or
/// frozen for everybody at once.
///
/// **It is never a reason a round does not start.** A missing file, an export
/// without its view model, a platform where the runtime is not safe — each of
/// those falls back to [PlayerArt]'s geometry, which is the same rule the art
/// layer already lives by. There is no `isLoaded` for a game to branch on.
library;

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../model/player_color.dart';
import '../ui/intro_animation.dart';
import 'player_art.dart';

/// One player's character, seen from above.
///
/// Playing and stopped are *states*, not calls: [start] and [stop] are
/// idempotent and cheap, so the natural thing — asking for one of them every
/// frame from whatever the game already knows about movement — is also the
/// correct thing.
abstract class PlayerAnimation {
  /// Walk. Does nothing if already walking, so this is safe every frame.
  void start();

  /// Stand still, holding whatever frame of the cycle they stopped on.
  void stop();

  bool get isPlaying;

  /// Paints the character centred on [center], its longest side filling
  /// [worldSize] world units, turned by [angle] radians — `0` faces +x, the
  /// same convention as an entity's angle.
  ///
  /// [dt] is the frame delta in seconds, and is what the animation advances by
  /// while it is playing. It is passed in rather than measured by a clock in
  /// here because the view is the only thing that knows how much of the game's
  /// time this frame was: a ticker of its own would keep walking through a
  /// pause, and would drift from the shared timeline everything else is drawn
  /// against.
  ///
  /// It is also the speed control, and deliberately the only one. A game whose
  /// world speeds up hands over `frame.dt * rate` and the legs keep up with it;
  /// there is no second knob to leave out of step with the first.
  ///
  /// [opacity] is here for the same reason it is on [PlayerArt.draw]: fading a
  /// player out is something games keep needing — knocked over, out of the
  /// round, not your turn — and the alternative is every caller wrapping this
  /// in a `saveLayer`.
  void draw(
    Canvas canvas,
    Offset center, {
    required double worldSize,
    required double dt,
    double angle = 0,
    double opacity = 1,
  });
}

/// Every player's character, for one round.
///
/// Owned by the platform and handed to the view on [ViewContext]: the artboards
/// are native memory and the playing state is per-round, so both are tied to
/// the life of the view rather than to a cache that outlives the table.
abstract class PlayerAnimations {
  /// The character for a colour. Cached, so a game may call this in a render
  /// loop and get the same walking body every frame.
  PlayerAnimation of(PlayerColor color);

  void dispose();

  /// Nothing loaded: everybody is [PlayerArt] geometry. The default on
  /// [ViewContext], and what a test gets without asking for anything.
  static const PlayerAnimations none = _ShapeAnimations();

  /// Load the cast for [colors].
  ///
  /// Awaited during placement — dead time, people are pushing phones together
  /// — so the file is decoded before the first frame. **Never throws and never
  /// hangs on a bad file**: anything that goes wrong resolves to [none], which
  /// draws the same circles the games drew before any of this existed.
  static Future<PlayerAnimations> load(Iterable<PlayerColor> colors) async {
    // Same gate as the intro: on a platform where `rive_native` takes the
    // process down there is nothing to catch, so do not even load. See
    // [IntroAnimation.platformSupportsRive].
    if (!IntroAnimation.available) return none;
    try {
      final file = await rive.File.asset(
        _RiveAnimations.asset,
        // The Flutter renderer, not Rive's: this is drawn into the game's own
        // canvas alongside everything else, not into a surface of its own.
        riveFactory: rive.Factory.flutter,
      );
      if (file == null) throw StateError('not found');
      return _RiveAnimations(file);
    } on Object catch (e) {
      debugPrint('[player animation] ${_RiveAnimations.asset} did not load: $e');
      return none;
    }
  }
}

/// The fallback cast: [PlayerArt]'s geometry, which does not move.
///
/// A complete implementation rather than a stub — [start] and [stop] are
/// honest no-ops on a picture with one frame — so a game written against this
/// API works identically on a phone with no animation.
class _ShapeAnimations implements PlayerAnimations {
  const _ShapeAnimations();

  @override
  PlayerAnimation of(PlayerColor color) => _ShapeAnimation(color);

  @override
  void dispose() {}
}

class _ShapeAnimation implements PlayerAnimation {
  const _ShapeAnimation(this.color);

  final PlayerColor color;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  bool get isPlaying => false;

  @override
  void draw(
    Canvas canvas,
    Offset center, {
    required double worldSize,
    required double dt,
    double angle = 0,
    double opacity = 1,
  }) {
    PlayerArt.of(color, PlayerArtSlot.topdown).draw(
      canvas,
      center,
      worldSize: worldSize,
      angle: angle,
      opacity: opacity,
    );
  }
}

/// The real cast: one Rive file, one artboard per colour.
class _RiveAnimations implements PlayerAnimations {
  _RiveAnimations(this._file);

  static const asset = 'assets/sdk/animations/running_man.riv';

  /// The looping walk. Named rather than default: the file may grow a second
  /// state machine, and picking whichever one happens to be first is how a
  /// character quietly starts playing the wrong thing.
  static const stateMachine = 'UpView_SM';

  final rive.File _file;
  final _characters = <String, PlayerAnimation>{};

  /// Everything bound to an artboard here, held for as long as the artboard
  /// is. Each is a native object with a finalizer: left for the GC, it frees
  /// what the artboard still draws with, and the next draw reads freed memory.
  final _keepAlive = <Object>[];

  @override
  PlayerAnimation of(PlayerColor color) =>
      _characters[color.id] ??= _make(color) ?? _ShapeAnimation(color);

  /// One artboard, coloured, ready to walk — or null, and this colour spends
  /// the round as geometry.
  _RiveAnimation? _make(PlayerColor color) {
    try {
      // `frameOrigin: true` puts the artboard's top-left at (0, 0). The
      // centring is done by hand in `draw`, which is the only version of it
      // that behaves the same on every runtime.
      final artboard = _file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final machine =
          artboard.stateMachine(stateMachine) ?? artboard.defaultStateMachine();
      _paint(artboard, machine, color);
      // Once, so the artboard holds the first frame of the walk rather than
      // whatever pose it was exported in.
      machine?.advanceAndApply(0);
      return _RiveAnimation(artboard, machine);
    } on Object catch (e) {
      debugPrint('[player animation] no character for ${color.id}: $e');
      return null;
    }
  }

  /// Put a player's three shades on their character.
  ///
  /// By name, because there are three of them and position in the list is not
  /// a contract — the same shades, off the same [PlayerColor], as the still
  /// character in [PlayerArt]. A property that is not there is said out loud
  /// and skipped: two shades on a character is worth more than none. Each
  /// artboard binds its *own* instance: a shared one would repaint every
  /// character on the table the colour of whoever was coloured last.
  void _paint(
    rive.Artboard artboard,
    rive.StateMachine? machine,
    PlayerColor color,
  ) {
    final viewModel = _file.defaultArtboardViewModel(artboard);
    final instance = viewModel?.createDefaultInstance();
    if (viewModel == null || instance == null) {
      debugPrint('[player animation] $asset has no view model — '
          'characters keep the colour they were drawn');
      return;
    }
    _keepAlive.addAll([viewModel, instance]);
    artboard.bindViewModelInstance(instance);
    machine?.bindViewModelInstance(instance);
    final shades = {
      'skinOne': color.value,
      'SkinLight': color.skinLight,
      'SkinDark': color.skinDark,
    };
    for (final MapEntry(key: name, value: shade) in shades.entries) {
      final property = instance.color(name);
      if (property == null) {
        debugPrint('[player animation] ${viewModel.name} has no $name');
        continue;
      }
      property.value = shade;
    }
  }

  @override
  void dispose() {
    _characters.clear();
    _keepAlive.clear();
    _file.dispose();
  }
}

class _RiveAnimation implements PlayerAnimation {
  _RiveAnimation(this.artboard, this.machine);

  /// Which way the character is drawn, in the same convention as an entity's
  /// angle: 0 is +x, `pi / 2` is down the screen — which is how this one is
  /// drawn. Everything is rotated by the difference between where the player is
  /// heading and this.
  static const facing = 1.5707963267948966; // pi / 2

  final rive.Artboard artboard;
  final rive.StateMachine? machine;

  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  void start() => _playing = true;

  @override
  void stop() => _playing = false;

  @override
  void draw(
    Canvas canvas,
    Offset center, {
    required double worldSize,
    required double dt,
    double angle = 0,
    double opacity = 1,
  }) {
    // Standing still is not a state this file has — `UpView_SM` is one looping
    // `Walk` with no inputs — so it is the machine not being advanced. It holds
    // the frame it stopped on, which is what standing looks like.
    if (_playing && dt > 0) machine?.advanceAndApply(dt);

    final bounds = artboard.bounds;
    final longest =
        bounds.width > bounds.height ? bounds.width : bounds.height;
    if (longest == 0) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle - facing);
    canvas.scale(worldSize / longest);
    // The artboard draws from its top-left, so pull it back by half its size:
    // [center] is then the middle of the character, and the rotation above
    // turns about that same point.
    canvas.translate(-bounds.width / 2, -bounds.height / 2);
    // A fresh renderer each frame, so the modulation starts from full and does
    // not accumulate over a fade.
    final renderer = rive.Renderer.make(canvas);
    try {
      if (opacity < 1) renderer.modulateOpacity(opacity);
      artboard.draw(renderer);
    } finally {
      // Now, not whenever the GC gets round to it: one of these is made every
      // frame.
      renderer.dispose();
    }
    canvas.restore();
  }
}
