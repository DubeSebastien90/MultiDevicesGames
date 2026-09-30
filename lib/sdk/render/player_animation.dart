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

/// What a character is doing, and so which file draws it.
enum PlayerMotion {
  /// Running, seen from above: the walk round the boards.
  run,

  /// Facing the reader and cheering: whoever won, on the podium.
  win,

  /// Facing the reader and not cheering: everybody else on the podium.
  lose,
}

/// One looping `.riv` for the whole cast, and how to colour it.
///
/// Per file rather than one set of names every file has to match: each was
/// drawn on its own, and the swatch is `skinOne` in one and `NormalColor` in
/// the next. Renaming a property is a trip back to the editor; mapping it is a
/// line here.
class _Rig {
  const _Rig({
    required this.asset,
    required this.stateMachine,
    required this.shades,
    required this.facing,
    required this.still,
  });

  final String asset;

  /// The looping machine. Named rather than default: a file may grow a second
  /// state machine, and picking whichever one happens to be first is how a
  /// character quietly starts playing the wrong thing.
  final String stateMachine;

  /// The view model properties that take [PlayerColor.value],
  /// [PlayerColor.skinLight] and [PlayerColor.skinDark].
  final ({String value, String light, String dark}) shades;

  /// Which way the character is drawn, in the same convention as an entity's
  /// angle: 0 is +x, `pi / 2` is down the screen. Everything is rotated by the
  /// difference between where the player is heading and this.
  final double facing;

  /// The picture drawn instead when the file cannot be — the same view, so a
  /// phone without Rive still shows the podium facing the reader.
  final PlayerArtSlot still;

  static _Rig of(PlayerMotion motion) => switch (motion) {
    PlayerMotion.run => run,
    PlayerMotion.win => win,
    PlayerMotion.lose => lose,
  };

  /// Drawn heading down the screen.
  static const run = _Rig(
    asset: 'assets/sdk/animations/running_man.riv',
    stateMachine: 'UpView_SM',
    shades: (value: 'skinOne', light: 'SkinLight', dark: 'SkinDark'),
    facing: 1.5707963267948966, // pi / 2
    still: PlayerArtSlot.topdown,
  );

  /// Drawn upright, so an angle of 0 leaves it standing — the same as the
  /// portrait in [PlayerArtSlot.face] it falls back to.
  static const win = _Rig(
    asset: 'assets/sdk/players/win.riv',
    stateMachine: 'WinVM',
    shades: (value: 'NormalColor', light: 'LightColor', dark: 'DarkColor'),
    facing: 0,
    still: PlayerArtSlot.face,
  );

  /// The same rig as [win], a different performance.
  static const lose = _Rig(
    asset: 'assets/sdk/players/lose.riv',
    stateMachine: 'LoseVM',
    shades: (value: 'NormalColor', light: 'LightColor', dark: 'DarkColor'),
    facing: 0,
    still: PlayerArtSlot.face,
  );
}

/// One player's character, doing one [PlayerMotion].
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
  static const PlayerAnimations none = _ShapeAnimations(PlayerArtSlot.topdown);

  /// Nothing loaded, for [motion]: [none] for running, and for the podium the
  /// same still portrait facing the reader that a failed load comes back as.
  static PlayerAnimations noneFor(PlayerMotion motion) =>
      _ShapeAnimations(_Rig.of(motion).still);

  /// Load the cast for [colors], doing [motion].
  ///
  /// Awaited during placement — dead time, people are pushing phones together
  /// — so the file is decoded before the first frame. **Never throws and never
  /// hangs on a bad file**: anything that goes wrong resolves to [noneFor],
  /// which draws the same pictures the games drew before any of this existed.
  static Future<PlayerAnimations> load(
    Iterable<PlayerColor> colors, {
    PlayerMotion motion = PlayerMotion.run,
  }) async {
    final rig = _Rig.of(motion);
    // Same gate as the intro: on a platform where `rive_native` takes the
    // process down there is nothing to catch, so do not even load. See
    // [IntroAnimation.platformSupportsRive].
    if (!IntroAnimation.available) return noneFor(motion);
    try {
      final file = await rive.File.asset(
        rig.asset,
        // The Flutter renderer, not Rive's: this is drawn into the game's own
        // canvas alongside everything else, not into a surface of its own.
        riveFactory: rive.Factory.flutter,
      );
      if (file == null) throw StateError('not found');
      return _RiveAnimations(file, rig);
    } on Object catch (e) {
      debugPrint('[player animation] ${rig.asset} did not load: $e');
      return noneFor(motion);
    }
  }
}

/// The fallback cast: [PlayerArt]'s picture, which does not move.
///
/// A complete implementation rather than a stub — [start] and [stop] are
/// honest no-ops on a picture with one frame — so a game written against this
/// API works identically on a phone with no animation.
class _ShapeAnimations implements PlayerAnimations {
  const _ShapeAnimations(this.slot);

  final PlayerArtSlot slot;

  @override
  PlayerAnimation of(PlayerColor color) => _ShapeAnimation(color, slot);

  @override
  void dispose() {}
}

class _ShapeAnimation implements PlayerAnimation {
  const _ShapeAnimation(this.color, this.slot);

  final PlayerColor color;
  final PlayerArtSlot slot;

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
    PlayerArt.of(color, slot).draw(
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
  _RiveAnimations(this._file, this._rig);

  final rive.File _file;
  final _Rig _rig;
  final _characters = <String, PlayerAnimation>{};

  /// Everything bound to an artboard here, held for as long as the artboard
  /// is. Each is a native object with a finalizer: left for the GC, it frees
  /// what the artboard still draws with, and the next draw reads freed memory.
  final _keepAlive = <Object>[];

  @override
  PlayerAnimation of(PlayerColor color) =>
      _characters[color.id] ??=
          _make(color) ?? _ShapeAnimation(color, _rig.still);

  /// One artboard, coloured, ready to play — or null, and this colour spends
  /// the round as a still picture.
  _RiveAnimation? _make(PlayerColor color) {
    try {
      // `frameOrigin: true` puts the artboard's top-left at (0, 0). The
      // centring is done by hand in `draw`, which is the only version of it
      // that behaves the same on every runtime.
      final artboard = _file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final machine = artboard.stateMachine(_rig.stateMachine) ??
          artboard.defaultStateMachine();
      _paint(artboard, machine, color);
      // Once, so the artboard holds the first frame of the loop rather than
      // whatever pose it was exported in.
      machine?.advanceAndApply(0);
      return _RiveAnimation(artboard, machine, _rig.facing);
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
      debugPrint('[player animation] ${_rig.asset} has no view model — '
          'characters keep the colour they were drawn');
      return;
    }
    _keepAlive.addAll([viewModel, instance]);
    artboard.bindViewModelInstance(instance);
    machine?.bindViewModelInstance(instance);
    final shades = {
      _rig.shades.value: color.value,
      _rig.shades.light: color.skinLight,
      _rig.shades.dark: color.skinDark,
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
  _RiveAnimation(this.artboard, this.machine, this.facing);

  final rive.Artboard artboard;
  final rive.StateMachine? machine;

  /// See [_Rig.facing].
  final double facing;

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
    // Standing still is not a state these files have — each machine is one
    // looping animation with no inputs — so it is the machine not being
    // advanced. It holds the frame it stopped on, which is what standing looks
    // like.
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
