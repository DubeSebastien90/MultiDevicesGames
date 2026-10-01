library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../ui/intro_animation.dart';

class TintedRive {
  TintedRive(this.asset, {required this.property});

  final String asset;

  final String property;

  Future<rive.File?>? _opening;
  final _started = <int>{};
  final _artboards = <int, rive.Artboard>{};

  final _keepAlive = <Object>[];

  rive.Artboard? artboard(Color color) {
    final key = color.toARGB32();
    if (_started.add(key)) unawaited(_load(color, key));
    return _artboards[key];
  }

  void preload(Iterable<Color> colors) {
    for (final color in colors) {
      artboard(color);
    }
  }

  static void paint(
    Canvas canvas,
    rive.Artboard artboard, {
    double opacity = 1,
  }) {
    final renderer = rive.Renderer.make(canvas);
    try {
      if (opacity < 1) renderer.modulateOpacity(opacity);
      artboard.draw(renderer);
    } finally {
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
    if (!IntroAnimation.available) return null;
    try {
      return await rive.File.asset(asset, riveFactory: rive.Factory.flutter);
    } on Object catch (e) {
      debugPrint('[tinted rive] $asset did not load: $e');
      return null;
    }
  }
}
