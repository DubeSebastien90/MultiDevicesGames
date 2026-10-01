library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rive/rive.dart' as rive;

import '../model/player_character.dart';
import '../model/player_color.dart';
import '../ui/intro_animation.dart';

enum PlayerArtSlot { topdown, face }

abstract class PlayerArt {
  factory PlayerArt.of(PlayerColor color, PlayerArtSlot slot) {
    final key = '${color.id}/${slot.name}';
    return _cache[key] ??= switch (slot) {
      PlayerArtSlot.topdown => _RiveArt(color, _RiveCharacter.topdown),
      PlayerArtSlot.face => _RiveArt(color, _RiveCharacter.front),
    };
  }

  static final _cache = <String, PlayerArt>{};

  static void preload(Iterable<PlayerColor> colors) {
    for (final color in colors) {
      for (final slot in PlayerArtSlot.values) {
        PlayerArt.of(color, slot).beginLoading();
      }
    }
  }

  void beginLoading();

  bool get isLoaded;

  void draw(
    Canvas canvas,
    Offset center, {
    required double worldSize,
    double angle = 0,
    double opacity = 1,
  });

  Widget widget({double size});
}

class _ShapeArt implements PlayerArt {
  _ShapeArt(this.color, this.slot);

  final PlayerColor color;
  final PlayerArtSlot slot;

  final _fill = Paint()..isAntiAlias = true;
  final _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  final _arrived = ValueNotifier<int>(0);

  ui.Image? _image;
  bool _started = false;

  @override
  bool get isLoaded => _image != null;

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
    beginLoading();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (angle != 0) canvas.rotate(angle);
    _paint(canvas, worldSize, opacity);
    canvas.restore();
  }

  void _paint(Canvas canvas, double size, [double opacity = 1]) {
    final image = _image;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: size, height: size),
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
      child: CustomPaint(painter: _ShapeArtPainter(this, _arrived)),
    );
  }
}

enum _Shade {
  main,
  light,
  dark;

  Color of(PlayerColor color) => switch (this) {
    _Shade.main => color.value,
    _Shade.light => color.skinLight,
    _Shade.dark => color.skinDark,
  };
}

class _RiveCharacter {
  const _RiveCharacter({
    required this.asset,
    required this.slot,
    required this.viewModel,
    required this.shades,
    required this.facing,
  });

  final String asset;

  final PlayerArtSlot slot;

  final String viewModel;

  final Map<String, _Shade> shades;

  final double facing;

  static const topdown = _RiveCharacter(
    asset: 'assets/sdk/players/smallcharacter.riv',
    slot: PlayerArtSlot.topdown,
    viewModel: 'SmallCharacter_VM',
    shades: {
      'SkinPrincipal': _Shade.main,
      'SkinLight': _Shade.light,
      'SkinDark': _Shade.dark,
    },
    facing: 1.5707963267948966,
  );

  static const front = _RiveCharacter(
    asset: 'assets/sdk/players/CharacterFrontView.riv',
    slot: PlayerArtSlot.face,
    viewModel: 'SkinVM',
    shades: {
      'NormalSkin': _Shade.main,
      'LightSkin': _Shade.light,
      'DarkSkin': _Shade.dark,
    },
    facing: 0,
  );
}

class _RiveArt implements PlayerArt {
  _RiveArt(this.color, this.character);

  final PlayerColor color;
  final _RiveCharacter character;

  late final _fallback = _ShapeArt(color, character.slot);

  final _arrived = ValueNotifier<int>(0);

  rive.Artboard? _artboard;
  bool _started = false;

  final _keepAlive = <Object>[];

  @override
  bool get isLoaded => _artboard != null || _fallback.isLoaded;

  @override
  void beginLoading() {
    _fallback.beginLoading();
    if (_started) return;
    _started = true;

    unawaited(_load());
  }

  Future<void> _load() async {
    final file = await _RiveCast.file(character.asset);
    if (file == null) return;
    try {
      final artboard = file.defaultArtboard(frameOrigin: true);
      if (artboard == null) throw StateError('no artboard');
      final machine = artboard.defaultStateMachine();
      if (machine != null) _keepAlive.add(machine);
      _bind(file, artboard, machine);

      machine?.advanceAndApply(0);
      _artboard = artboard;
      _arrived.value++;
    } on Object catch (e) {
      debugPrint(
        '[player art] no ${character.slot.name} character for ${color.id}: $e',
      );
    }
  }

  void _bind(
    rive.File file,
    rive.Artboard artboard,
    rive.StateMachine? machine,
  ) {
    final viewModel =
        file.defaultArtboardViewModel(artboard) ??
        file.viewModelByName(character.viewModel);
    final instance = viewModel?.createDefaultInstance();
    if (viewModel == null || instance == null) {
      debugPrint(
        '[player art] ${character.asset} has no view model — '
        'characters keep the colours they were drawn',
      );
      return;
    }

    _keepAlive.addAll([viewModel, instance]);
    artboard.bindViewModelInstance(instance);
    machine?.bindViewModelInstance(instance);
    for (final MapEntry(key: name, value: shade) in character.shades.entries) {
      final property = instance.color(name);
      if (property == null) {
        debugPrint(
          '[player art] ${viewModel.name} has no $name '
          '(expected the ${shade.name} shade)',
        );
        continue;
      }
      property.value = shade.of(color);
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
    beginLoading();

    final artboard = _artboard;
    if (artboard == null) {
      _fallback.draw(
        canvas,
        center,
        worldSize: worldSize,
        angle: angle,
        opacity: opacity,
      );
      return;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle - character.facing);
    _paint(canvas, artboard, worldSize, opacity);
    canvas.restore();
  }

  void _paint(
    Canvas canvas,
    rive.Artboard artboard,
    double size,
    double opacity,
  ) {
    final bounds = artboard.bounds;
    final longest = bounds.width > bounds.height ? bounds.width : bounds.height;
    if (longest == 0) return;

    canvas.save();
    canvas.scale(size / longest);

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

  @override
  Widget widget({double size = 48}) {
    beginLoading();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _RiveArtPainter(this, _arrived)),
    );
  }
}

class _RiveArtPainter extends CustomPainter {
  const _RiveArtPainter(this.art, Listenable repaint) : super(repaint: repaint);

  final _RiveArt art;

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
  bool shouldRepaint(_RiveArtPainter old) => !identical(old.art, art);
}

class _RiveCast {
  const _RiveCast._();

  static final _opening = <String, Future<rive.File?>>{};

  static Future<rive.File?> file(String asset) =>
      _opening[asset] ??= _open(asset);

  static Future<rive.File?> _open(String asset) async {
    if (!IntroAnimation.available) return null;
    try {
      return await rive.File.asset(asset, riveFactory: rive.Factory.flutter);
    } on Object catch (e) {
      debugPrint('[player art] $asset did not load: $e');
      return null;
    }
  }
}

class _ShapeArtPainter extends CustomPainter {
  const _ShapeArtPainter(this.art, Listenable repaint)
    : super(repaint: repaint);

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
