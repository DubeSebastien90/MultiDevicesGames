/// The handful of seconds between a round ending and its result.
///
/// Balls in every colour of the palette pour down the screen and out of the
/// bottom — and the result is underneath them the whole time. That last part is
/// the important one: this is painted *over* the results, never instead of
/// them. A phone whose animation misbehaves is a phone showing the result a
/// moment early, which is the mildest failure this file could have.
///
/// The balls are the artist's `.svg` files, rasterised once per colour and then
/// drawn as images. Rasterising per frame would be work for nothing: they never
/// change shape, only position.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../model/player_color.dart';

/// One ball's flight: where it starts, how fast, how it spins.
///
/// Positions are fractions of the screen, so the same numbers describe the
/// same picture on a small phone and a large one.
class _Ball {
  _Ball(math.Random rng, this.image)
    : x = rng.nextDouble(),
      size = 0.07 + rng.nextDouble() * 0.07,
      delay = rng.nextDouble() * 0.5,
      speed = 1.4 + rng.nextDouble() * 0.9,
      spin = (rng.nextDouble() - 0.5) * 5,
      phase = rng.nextDouble() * math.pi * 2;

  final ui.Image image;

  /// Across the screen, as a fraction of its width. Fixed: these fall, they do
  /// not wander.
  final double x;

  final double size;

  /// How far into the animation this one starts, as a fraction of it. What
  /// turns two hundred balls into a shower rather than a curtain dropping in
  /// one piece.
  final double delay;

  /// Screen heights per second.
  final double speed;

  final double spin;

  /// Where its rotation starts, so identical balls do not fall in lockstep.
  final double phase;

  /// Where this ball is at [t], as a fraction of the screen height.
  ///
  /// Read from the clock rather than accumulated frame by frame. A ball is
  /// therefore in the same place at the same instant whatever the frame rate
  /// did, and a stutter cannot leave one hanging halfway down or push another
  /// off course.
  double yAt(double t, double seconds) => -0.2 + (t - delay) * speed * seconds;

  double angleAt(double t, double seconds) => phase + spin * t * seconds;
}

class BallDrop extends StatefulWidget {
  const BallDrop({
    super.key,
    required this.child,
    this.colors = PlayerPalette.all,
    this.onDone,
    this.duration = const Duration(milliseconds: 2200),
  });

  /// Which balls to drop. The whole palette by default: the shower belongs to
  /// the game, not to this table, so it looks the same however many people
  /// happened to be playing.
  final List<PlayerColor> colors;

  /// How many of each colour. Two hundred and forty balls in total, which is a
  /// downpour rather than a sprinkle.
  static const perColor = 30;

  /// The result, sitting underneath from the first frame.
  final Widget child;

  /// Called when the last ball has gone. Optional: nothing depends on it.
  final VoidCallback? onDone;

  final Duration duration;

  /// Where the artist's balls live. One per palette colour, by French name —
  /// the names on the files, kept rather than renamed so that replacing a ball
  /// is a matter of overwriting the file it came from.
  static const _file = <String, String>{
    'green': 'Vert',
    'yellow': 'Jaune',
    'purple': 'Mauve',
    'brown': 'Brun',
    'pink': 'Rose',
    'red': 'Rouge',
    'orange': 'Orange',
    'blue': 'Bleu',
  };

  static String? assetFor(PlayerColor color) {
    final name = _file[color.id];
    return name == null ? null : 'assets/sdk/animations/$name.svg';
  }

  /// Every ball, for a preloader or a test that wants to walk them.
  static Iterable<String> get assets =>
      _file.values.map((n) => 'assets/sdk/animations/$n.svg');

  @override
  State<BallDrop> createState() => _BallDropState();
}

class _BallDropState extends State<BallDrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// Grouped by image from the start, because that is how they are drawn.
  final _byImage = <ui.Image, List<_Ball>>{};
  final _rasterised = <String, ui.Image>{};

  @override
  void initState() {
    super.initState();
    _clock
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone?.call();
      })
      ..forward();
    _load();
  }

  /// Rasterise each colour once, then make the balls.
  ///
  /// Not awaited by anything. If it fails or arrives late the screen simply
  /// shows the result with fewer balls, or none — the same rule the rest of the
  /// SDK's artwork follows.
  Future<void> _load() async {
    final rng = math.Random();
    for (final color in widget.colors) {
      final asset = BallDrop.assetFor(color);
      if (asset == null) continue;
      try {
        final image = _rasterised[asset] ??= await _rasterise(asset);
        final group = _byImage.putIfAbsent(image, () => <_Ball>[]);
        for (var i = 0; i < BallDrop.perColor; i++) {
          group.add(_Ball(rng, image));
        }
      } on Object catch (e) {
        debugPrint('[balls] $asset did not load: $e');
      }
    }
    if (mounted) setState(() {});
  }

  static Future<ui.Image> _rasterise(String asset) async {
    final picture = await vg.loadPicture(SvgAssetLoader(asset), null);
    // Generous enough for the largest a ball is ever drawn, and rasterised
    // once for the whole animation rather than once per frame.
    const side = 256;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = picture.size;
    canvas.scale(side / size.width, side / size.height);
    canvas.drawPicture(picture.picture);
    final flattened = recorder.endRecording();
    final image = await flattened.toImage(side, side);
    flattened.dispose();
    picture.picture.dispose();
    return image;
  }

  @override
  void dispose() {
    _clock.dispose();
    for (final image in _rasterised.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The result, from the first frame. Nothing here can prevent it being
        // seen — the balls only ever cover it for a moment.
        widget.child,
        if (_byImage.isNotEmpty)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _clock,
              builder: (context, _) => CustomPaint(
                painter: _BallPainter(
                  _byImage,
                  _clock.value,
                  widget.duration.inMilliseconds / 1000,
                ),
                size: Size.infinite,
              ),
            ),
          ),
      ],
    );
  }
}

/// Draws every ball, batched by colour.
///
/// One `drawAtlas` per image rather than a `drawImageRect` per ball: at two
/// hundred and forty balls the difference is eight draw calls a frame against
/// two hundred and forty, each with its own matrix push and pop.
class _BallPainter extends CustomPainter {
  _BallPainter(this.byImage, this.t, this.seconds);

  /// Balls grouped by the image they are drawn from, so each group is one call.
  final Map<ui.Image, List<_Ball>> byImage;

  /// 0..1 through the animation.
  final double t;

  /// How long the whole animation lasts, in seconds.
  final double seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;

    for (final entry in byImage.entries) {
      final image = entry.key;
      final source = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );

      final transforms = <RSTransform>[];
      final rects = <Rect>[];
      for (final ball in entry.value) {
        final y = ball.yAt(t, seconds);
        // Not arrived, or gone out of the bottom. Either way, nothing to draw.
        if (y < -0.3 || y > 1.3) continue;

        final side = ball.size * size.width;
        transforms.add(
          RSTransform.fromComponents(
            rotation: ball.angleAt(t, seconds),
            scale: side / image.width,
            // Anchored at the middle of the source, so it spins about its own
            // centre rather than its corner.
            anchorX: image.width / 2,
            anchorY: image.height / 2,
            translateX: ball.x * size.width,
            translateY: y * size.height,
          ),
        );
        rects.add(source);
      }
      if (rects.isEmpty) continue;
      canvas.drawAtlas(image, transforms, rects, null, null, null, paint);
    }
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.t != t;
}
