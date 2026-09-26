/// One `.riv` drawn in several colours.
///
/// For art that is the same drawing whatever it belongs to, with a single fill
/// that changes: the colour is a property on the artboard's default view
/// model, and each colour gets an artboard — and a view model instance — of its
/// own. A shared instance would repaint every copy on the table whatever colour
/// was set last.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../ui/intro_animation.dart';

class TintedRive {
  TintedRive(this.asset, {required this.property});

  /// The file, under `assets/`.
  final String asset;

  /// The colour property on the default view model.
  final String property;

  Future<rive.File?>? _opening;
  final _started = <int>{};
  final _artboards = <int, rive.Artboard>{};

  /// Everything bound to an artboard in [_artboards], held for as long as it
  /// is. Each is a native object with a finalizer: left for the GC, it frees
  /// what the artboard still draws with, and the next draw reads freed memory.
  final _keepAlive = <Object>[];

  /// The artboard in [color], or null until it has loaded — and for good on a
  /// platform without Rive, or if the file will not parse. The first ask
  /// starts the load; nothing awaits it.
  rive.Artboard? artboard(Color color) {
    final key = color.toARGB32();
    if (_started.add(key)) unawaited(_load(color, key));
    return _artboards[key];
  }

  /// Start loading these colours, and hand control straight back.
  void preload(Iterable<Color> colors) {
    for (final color in colors) {
      artboard(color);
    }
  }

  /// Draws [artboard] from its top-left, in its own units, onto [canvas] as it
  /// is currently transformed.
  static void paint(
    Canvas canvas,
    rive.Artboard artboard, {
    double opacity = 1,
  }) {
    // A fresh renderer each time, so the modulation starts from full and does
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
  }

  Future<void> _load(Color color, int key) async {
    final file = await (_opening ??= _open());
    if (file == null) return;
    try {
      final artboard = file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final machine = artboard.defaultStateMachine();
      if (machine != null) _keepAlive.add(machine);
      _bind(file, artboard, machine, color);
      // Once: these are stills. Advancing by zero applies the binding, and
      // whatever the first state sets.
      machine?.advanceAndApply(0);
      _artboards[key] = artboard;
    } on Object catch (e) {
      debugPrint('[tinted rive] $asset in $color: $e');
    }
  }

  void _bind(
    rive.File file,
    rive.Artboard artboard,
    rive.StateMachine? machine,
    Color color,
  ) {
    final viewModel = file.defaultArtboardViewModel(artboard);
    final instance = viewModel?.createDefaultInstance();
    if (viewModel == null || instance == null) {
      debugPrint(
        '[tinted rive] $asset has no view model — '
        'it keeps the colour it was drawn',
      );
      return;
    }
    _keepAlive.addAll([viewModel, instance]);
    artboard.bindViewModelInstance(instance);
    machine?.bindViewModelInstance(instance);
    final colour = instance.color(property);
    if (colour == null) {
      debugPrint('[tinted rive] ${viewModel.name} has no $property');
      return;
    }
    colour.value = color;
  }

  Future<rive.File?> _open() async {
    // Same gate as every other Rive file: on a platform where `rive_native`
    // takes the process down there is nothing to catch. See
    // [IntroAnimation.platformSupportsRive].
    if (!IntroAnimation.available) return null;
    try {
      return await rive.File.asset(
        asset,
        // Drawn into the game's own canvas, not a surface of its own.
        riveFactory: rive.Factory.flutter,
      );
    } on Object catch (e) {
      debugPrint('[tinted rive] $asset did not load: $e');
      return null;
    }
  }
}
