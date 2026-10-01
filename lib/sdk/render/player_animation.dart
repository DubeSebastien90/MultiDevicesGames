library;

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../model/player_color.dart';
import '../ui/intro_animation.dart';
import 'player_art.dart';

enum PlayerMotion { run, win, lose }

class _Rig {
  const _Rig({
    required this.asset,
    required this.stateMachine,
    required this.shades,
    required this.facing,
    required this.still,
  });

  final String asset;

  final String stateMachine;

  final ({String value, String light, String dark}) shades;

  final double facing;

  final PlayerArtSlot still;

  static _Rig of(PlayerMotion motion) => switch (motion) {
    PlayerMotion.run => run,
    PlayerMotion.win => win,
    PlayerMotion.lose => lose,
  };

  static const run = _Rig(
    asset: 'assets/sdk/animations/running_man.riv',
    stateMachine: 'UpView_SM',
    shades: (value: 'skinOne', light: 'SkinLight', dark: 'SkinDark'),
    facing: 1.5707963267948966,
    still: PlayerArtSlot.topdown,
  );

  static const win = _Rig(
    asset: 'assets/sdk/players/win.riv',
    stateMachine: 'WinVM',
    shades: (value: 'NormalColor', light: 'LightColor', dark: 'DarkColor'),
    facing: 0,
    still: PlayerArtSlot.face,
  );

  static const lose = _Rig(
    asset: 'assets/sdk/players/lose.riv',
    stateMachine: 'LoseVM',
    shades: (value: 'NormalColor', light: 'LightColor', dark: 'DarkColor'),
    facing: 0,
    still: PlayerArtSlot.face,
  );
}

abstract class PlayerAnimation {
  void start();

  void stop();

  bool get isPlaying;

  void draw(
    Canvas canvas,
    Offset center, {
    required double worldSize,
    required double dt,
    double angle = 0,
    double opacity = 1,
  });
}

abstract class PlayerAnimations {
  PlayerAnimation of(PlayerColor color);

  void dispose();

  static const PlayerAnimations none = _ShapeAnimations(PlayerArtSlot.topdown);

  static PlayerAnimations noneFor(PlayerMotion motion) =>
      _ShapeAnimations(_Rig.of(motion).still);

  static Future<PlayerAnimations> load(
    Iterable<PlayerColor> colors, {
    PlayerMotion motion = PlayerMotion.run,
  }) async {
    final rig = _Rig.of(motion);

    if (!IntroAnimation.available) return noneFor(motion);
    try {
      final file = await rive.File.asset(
        rig.asset,
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

class _RiveAnimations implements PlayerAnimations {
  _RiveAnimations(this._file, this._rig);

  final rive.File _file;
  final _Rig _rig;
  final _characters = <String, PlayerAnimation>{};

  final _keepAlive = <Object>[];

  @override
  PlayerAnimation of(PlayerColor color) => _characters[color.id] ??=
      _make(color) ?? _ShapeAnimation(color, _rig.still);

  _RiveAnimation? _make(PlayerColor color) {
    try {
      final artboard = _file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final machine =
          artboard.stateMachine(_rig.stateMachine) ??
          artboard.defaultStateMachine();
      _paint(artboard, machine, color);

      machine?.advanceAndApply(0);
      return _RiveAnimation(artboard, machine, _rig.facing);
    } on Object catch (e) {
      debugPrint('[player animation] no character for ${color.id}: $e');
      return null;
    }
  }

  void _paint(
    rive.Artboard artboard,
    rive.StateMachine? machine,
    PlayerColor color,
  ) {
    final viewModel = _file.defaultArtboardViewModel(artboard);
    final instance = viewModel?.createDefaultInstance();
    if (viewModel == null || instance == null) {
      debugPrint(
        '[player animation] ${_rig.asset} has no view model — '
        'characters keep the colour they were drawn',
      );
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
    if (_playing && dt > 0) machine?.advanceAndApply(dt);

    final bounds = artboard.bounds;
    final longest = bounds.width > bounds.height ? bounds.width : bounds.height;
    if (longest == 0) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle - facing);
    canvas.scale(worldSize / longest);

    canvas.translate(-bounds.width / 2, -bounds.height / 2);

    final renderer = rive.Renderer.make(canvas);
    try {
      if (opacity < 1) renderer.modulateOpacity(opacity);
      artboard.draw(renderer);
    } finally {
      renderer.dispose();
    }
    canvas.restore();
  }
}
