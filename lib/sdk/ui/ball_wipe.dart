/// The wipe between a finished round and its result.
///
/// Balls pour down until they have covered the screen completely, the screen
/// underneath is swapped from the game to the score, and then they fall away
/// again. Nobody sees the swap, which is the entire point: a round should not
/// end by the game vanishing mid-frame.
///
/// **It is one grid sliding, not a screen filling in.** The balls are laid out
/// in a block taller than the screen, and the whole block travels down: in from
/// above, a beat with the screen hidden, then on out of the bottom. Each ball
/// is drawn wide enough to cover its own cell corner to corner, so there is no
/// gap anywhere at the moment it matters — whatever the screen's shape. Only
/// the *colour* is random. Scattering positions and hoping would leave holes on
/// some phones and not others, and the one frame that matters is the frame the
/// game is supposed to be hidden.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../model/player_color.dart';

class BallWipe extends StatefulWidget {
  const BallWipe({
    super.key,
    required this.child,
    required this.onCovered,
    this.onDone,
    this.columns = 4,
    this.cover = const Duration(milliseconds: 1100),
    this.hold = const Duration(milliseconds: 220),
    this.reveal = const Duration(milliseconds: 800),
  });

  /// What sits underneath: the finished game while the balls arrive, the score
  /// once [onCovered] has been answered.
  final Widget child;

  /// The screen is completely hidden — swap what is underneath now.
  ///
  /// Called exactly once, and the swap has a whole [hold] to happen in before
  /// anything is uncovered again.
  final VoidCallback onCovered;

  /// The last ball has gone.
  final VoidCallback? onDone;

  /// How many balls across. Fewer means bigger balls.
  final int columns;

  final Duration cover;
  final Duration hold;
  final Duration reveal;

  Duration get total => cover + hold + reveal;

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

  static Iterable<String> get assets =>
      _file.values.map((n) => 'assets/sdk/animations/$n.svg');

  /// The rasterised balls, shared by every wipe for the life of the app.
  ///
  /// Eight images at 256px is about two megabytes, held once. Rasterising them
  /// per round instead is what made the first wipe of a session stutter: the
  /// clock had already started, so by the time the vectors were done the
  /// animation jumped to wherever it had got to.
  static final Map<String, ui.Image> _cache = <String, ui.Image>{};

  static Future<void>? _loading;

  /// Rasterise every ball, once, ahead of time.
  ///
  /// Called from `main` so the first round to end finds them ready. Safe to
  /// call again — later calls wait on the first rather than redoing the work.
  static Future<void> preload() => _loading ??= _rasteriseAll();

  static Future<void> _rasteriseAll() async {
    for (final asset in assets) {
      if (_cache.containsKey(asset)) continue;
      try {
        _cache[asset] = await _rasterise(asset);
      } on Object catch (e) {
        debugPrint('[wipe] $asset did not load: $e');
      }
    }
  }

  static Future<ui.Image> _rasterise(String asset) async {
    final picture = await vg.loadPicture(SvgAssetLoader(asset), null);
    const side = 256;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(side / picture.size.width, side / picture.size.height);
    canvas.drawPicture(picture.picture);
    final flattened = recorder.endRecording();
    final image = await flattened.toImage(side, side);
    flattened.dispose();
    picture.picture.dispose();
    return image;
  }

  @override
  State<BallWipe> createState() => _BallWipeState();
}

class _BallWipeState extends State<BallWipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: widget.total,
  );

  /// The eight balls, in palette order. Rasterised once each: they never change
  /// shape, only position, so redoing the vector work per frame would be work
  /// for nothing.
  final _images = <ui.Image>[];

  /// Fixed for the life of this wipe, so a rebuild cannot reshuffle the colours
  /// halfway down the screen.
  final _seed = math.Random().nextInt(1 << 30);

  bool _swapped = false;

  double get _coverEnds =>
      widget.cover.inMilliseconds / widget.total.inMilliseconds;
  double get _revealBegins =>
      (widget.cover + widget.hold).inMilliseconds / widget.total.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _clock
      ..addListener(_watchForCovered)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone?.call();
      })
      ..forward();
    _load();
  }

  /// Swap what is underneath the instant the last cell is filled.
  void _watchForCovered() {
    if (_swapped || _clock.value < _coverEnds) return;
    _swapped = true;
    widget.onCovered();
  }

  Future<void> _load() async {
    // Usually already done — `preload` runs at launch. When it is, this
    // completes on the same turn and the first frame has its balls.
    await BallWipe.preload();
    if (!mounted) return;
    setState(() {
      for (final color in PlayerPalette.all) {
        final asset = BallWipe.assetFor(color);
        final image = asset == null ? null : BallWipe._cache[asset];
        if (image != null) _images.add(image);
      }
    });
  }

  @override
  void dispose() {
    // The swap has to happen even if this is torn down mid-wipe — otherwise the
    // round would end on the game screen, still hidden behind nothing.
    if (!_swapped) {
      _swapped = true;
      widget.onCovered();
    }
    _clock.dispose();
    // The images belong to the cache, not to this wipe. Disposing them here
    // would leave the next round with eight dead handles.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Nothing underneath is touchable while this is up, and deliberately
        // not conditional on the artwork: balls that failed to load would
        // otherwise leave a finished game fully playable. The round is over
        // either way.
        Positioned.fill(
          child: AbsorbPointer(
            child: _images.isEmpty
                ? const SizedBox.expand()
                : AnimatedBuilder(
                    animation: _clock,
                    builder: (context, _) => CustomPaint(
                      painter: _WipePainter(
                        images: _images,
                        seed: _seed,
                        columns: widget.columns,
                        t: _clock.value,
                        coverEnds: _coverEnds,
                        revealBegins: _revealBegins,
                      ),
                      size: Size.infinite,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _WipePainter extends CustomPainter {
  _WipePainter({
    required this.images,
    required this.seed,
    required this.columns,
    required this.t,
    required this.coverEnds,
    required this.revealBegins,
  });

  final List<ui.Image> images;
  final int seed;
  final int columns;

  /// 0..1 through the whole wipe.
  final double t;

  final double coverEnds;
  final double revealBegins;

  /// How far above the screen the grid waits, in screen heights, on top of its
  /// own height.
  ///
  /// Head start rather than decoration: the first stretch of the slide happens
  /// where nobody can see it, so a phone that is still finishing something —
  /// the last frame of a round, a decode — has somewhere to do it.
  static const _lead = 0.45;

  /// How far a ball may sit from the middle of its cell, as a fraction of one.
  ///
  /// Rolled per ball and per wipe, so the pattern is never quite the same twice
  /// and the grid stops reading as a grid.
  static const _jitter = 0.15;

  /// How wide a ball is drawn, as a fraction of its cell.
  ///
  /// **This is a guarantee, not a look.** A circle that covers a square of side
  /// c needs a diameter of at least c·√2 — and once the ball may be up to
  /// [_jitter] out of place in both directions, the square it has to reach the
  /// corners of is effectively (1 + 2·jitter) wide. That puts the floor at
  /// 1.838; the rest is margin so antialiased edges never show a seam.
  ///
  /// Shrink this or grow [_jitter] without redoing that arithmetic and the wipe
  /// develops holes — on some screen sizes and not others, for one frame, which
  /// is the frame the finished game is meant to be hidden behind.
  static const _spread = 1.90;

  /// Deterministic per cell, so a ball keeps its colour, its place and its
  /// turn in the stack on every frame — without storing a grid that would have
  /// to be rebuilt whenever the screen changed size.
  ///
  /// [salt] draws independent values from the same cell: one for the colour,
  /// one for the depth, one for each axis of the offset. Reusing a single
  /// number for all four would tie them together, and the colour would tell you
  /// where the ball had been nudged.
  int _hash(int col, int row, int salt) {
    var h =
        seed ^ (col * 0x1f1f1f1f) ^ (row * 0x85ebca6b) ^ (salt * 0x27d4eb2d);
    h ^= h >> 13;
    h = (h * 0x5bd1e995) & 0x3fffffff;
    return h ^ (h >> 15);
  }

  /// A hashed value in -1..1.
  double _signed(int col, int row, int salt) =>
      (_hash(col, row, salt) % 2000) / 1000 - 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (images.isEmpty) return;

    final cell = size.width / columns;
    // A row past the bottom, so the grid is always taller than the screen and
    // there is something to cover the last pixel with as it slides.
    final rows = (size.height / cell).ceil() + 1;
    final gridHeight = rows * cell;
    final side = cell * _spread;

    // Where the grid sits before it has entered.
    //
    // Not simply `-gridHeight`: that puts the bottom row's *centre* level with
    // the top edge, so a quarter of it was already on screen at rest — the
    // wipe began with a strip of balls visible, then jumped. A whole ball's
    // width clears that, and [_lead] on top of it buys the first frames
    // off-screen, which is where any remaining work belongs.
    final start = -(gridHeight + side + size.height * _lead);

    // The grid moves as one piece: down from above the screen until it covers
    // everything, a beat, then on down and out of the bottom. Nothing fills in
    // place — every ball keeps its neighbours for the whole slide.
    final double offset;
    if (t < coverEnds) {
      offset = start - _ease(t / coverEnds) * start;
    } else if (t < revealBegins) {
      offset = 0;
    } else {
      final p = _ease((t - revealBegins) / (1 - revealBegins));
      offset = p * (size.height + side);
    }

    // Collected first, then drawn in a shuffled order.
    //
    // The order is **hashed, not scanned**: it comes from the cell and this
    // wipe's seed, so it differs every time the animation plays and is
    // identical on every frame of one. That distinction is the whole lesson
    // here. An earlier version grouped balls by colour and drew a batch each,
    // so the order depended on which colour was met first while scanning — and
    // as rows scrolled past the cull that changed mid-slide, and overlapping
    // balls visibly swapped places. Random is fine. Random *per frame* is what
    // looked broken.
    //
    // About forty balls on a phone screen, so collecting and sorting them each
    // frame costs nothing worth measuring.
    final cells = <(double, double, int, int)>[];
    for (var row = 0; row < rows; row++) {
      final y = offset + (row + 0.5) * cell;
      if (y < -side || y > size.height + side) continue;

      for (var col = 0; col < columns; col++) {
        cells.add((
          (col + 0.5) * cell + _signed(col, row, 3) * _jitter * cell,
          y + _signed(col, row, 4) * _jitter * cell,
          _hash(col, row, 1) % images.length,
          _hash(col, row, 2),
        ));
      }
    }
    cells.sort((a, b) => a.$4.compareTo(b.$4));

    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;

    for (final (x, y, index, _) in cells) {
      final image = images[index];
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(center: Offset(x, y), width: side, height: side),
        paint,
      );
    }
  }

  /// Slows as it arrives, so the grid settles rather than snapping into place.
  static double _ease(double p) => 1 - math.pow(1 - p, 3).toDouble();

  @override
  bool shouldRepaint(_WipePainter old) => old.t != t || old.seed != seed;
}
