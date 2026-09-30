/// The wipe between a finished round and its result.
///
/// Balls drop in one after another, bouncing, until they have covered the
/// screen completely; the screen underneath is swapped from the game to the
/// score, and then they fall away again. Nobody sees the swap, which is the
/// entire point: a round should not end by the game vanishing mid-frame.
///
/// **Every ball lands on a fixed grid.** Each one falls from above the screen
/// to its own cell — the bottom rows first, loosely shuffled — with a bounce
/// and a size of its own, and is drawn wide enough to cover that cell corner
/// to corner — so once the last one has settled there is no gap anywhere,
/// whatever the screen's shape. The swap waits for that moment. Only the
/// order, the bounce, the size and the colour are random: scattering *positions* and hoping would leave holes on some phones
/// and not others, and the one frame that matters is the frame the game is
/// supposed to be hidden. On the way out the whole grid slides down together.
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
    this.cover = const Duration(milliseconds: 2500),
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

  /// How long the balls take to drop in. The last one has settled when this
  /// is up, and that is when [onCovered] is called.
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

  /// A ball's first fall, as a fraction of the cover, rolled per ball between
  /// these two.
  static const _fallMin = 0.09;
  static const _fallMax = 0.12;

  /// How much of its speed a ball keeps on each bounce, rolled per ball.
  static const _bounceMin = 0.30;
  static const _bounceMax = 0.50;

  /// Two or three bounces, then it sits still.
  static const _bouncesMax = 3;

  /// The longest a ball can take from first moving to sitting still, as a
  /// fraction of the cover: the first fall, then two flights per bounce, each
  /// shorter than the last by the bounce factor. The drops are spread over
  /// what is left, so the last ball has settled exactly when the cover ends.
  static final double _dropMax = () {
    var d = _fallMax;
    var e = 1.0;
    for (var i = 0; i < _bouncesMax; i++) {
      e *= _bounceMax;
      d += 2 * _fallMax * e;
    }
    return d;
  }();

  /// How far a ball may sit from the middle of its cell, as a fraction of one.
  ///
  /// Rolled per ball and per wipe, so the pattern is never quite the same twice
  /// and the grid stops reading as a grid.
  static const _jitter = 0.10;

  /// How wide a ball is drawn, as a fraction of its cell — rolled per ball
  /// between these two, so the balls come in different sizes.
  ///
  /// **The smallest is a guarantee, not a look.** A circle that covers a
  /// square of side c needs a diameter of at least c·√2 — and once the ball
  /// may be up to [_jitter] out of place in both directions, the square it has
  /// to reach the corners of is effectively (1 + 2·jitter) wide. That puts the
  /// floor at 1.697; the rest is margin so antialiased edges never show a
  /// seam. Only ever larger than that, so every size still covers its cell.
  ///
  /// Shrink [_spreadMin] or grow [_jitter] without redoing that arithmetic and
  /// the wipe develops holes — on some screen sizes and not others, for one
  /// frame, which is the frame the finished game is meant to be hidden behind.
  static const _spreadMin = 1.76;
  static const _spreadMax = 2.35;

  /// How many rows the drop order may reach across. Zero would drop the
  /// screen strictly row by row from the bottom; this lets a ball from the
  /// row above slip in ahead of a few from the row below, so it fills from the
  /// bottom up without looking like a printer.
  static const _rowMix = 1.5;

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
    // A row past the bottom, so the jittered grid always reaches the last
    // pixel of the screen.
    final rows = (size.height / cell).ceil() + 1;
    // The biggest a ball can be: what a cull has to allow for.
    final most = cell * _spreadMax;

    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium;

    void draw(double x, double y, double side, int index) {
      final image = images[index];
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(center: Offset(x, y), width: side, height: side),
        paint,
      );
    }

    // On the way out the grid moves as one piece, down and off the bottom.
    // Until then it sits where it lands.
    final offset = t < revealBegins
        ? 0.0
        : _ease((t - revealBegins) / (1 - revealBegins)) * (size.height + most);

    // Every cell, with its landing spot, size, colour and place in the order.
    //
    // The order fills the screen **from the bottom up**, loosely: by row, with
    // a hashed nudge of up to [_rowMix] rows so neighbouring rows interleave.
    // It comes from the cell and this wipe's seed, so it differs every time the
    // animation plays and is identical on every frame of one.
    //
    // **Depth is separate from the order.** Each ball has its own hashed layer,
    // so a late ball may fall in front of the ones already down or slip in
    // behind them. The layer is the same in the drop and the slide, so nothing
    // visibly swaps places when one turns into the other.
    //
    // About forty balls on a phone screen, so collecting and sorting them each
    // frame costs nothing worth measuring.
    final cells = <_Ball>[];
    for (var row = 0; row < rows; row++) {
      final y = (row + 0.5) * cell;
      for (var col = 0; col < columns; col++) {
        final side = cell * _lerp(_spreadMin, _spreadMax, _unit(col, row, 9));
        final ty = y + _signed(col, row, 4) * _jitter * cell;
        // A cell whose ball would not reach the screen once landed has no
        // part in covering it, and dropping it would only leave a gap in the
        // rhythm where nothing seems to fall.
        if (ty - side / 2 > size.height) continue;
        cells.add(
          _Ball(
            x: (col + 0.5) * cell + _signed(col, row, 3) * _jitter * cell,
            y: ty,
            side: side,
            image: _hash(col, row, 1) % images.length,
            order: (rows - 1 - row) + _unit(col, row, 2) * _rowMix,
            depth: _hash(col, row, 10),
            col: col,
            row: row,
          ),
        );
      }
    }
    // Timing is read off the drop order; drawing goes back to front by depth.
    cells.sort((a, b) => a.order.compareTo(b.order));
    final begins = <_Ball, double>{
      for (final (i, ball) in cells.indexed)
        ball: cells.length > 1 ? i / (cells.length - 1) * (1 - _dropMax) : 0.0,
    };
    cells.sort((a, b) => a.depth.compareTo(b.depth));

    if (t >= coverEnds) {
      for (final ball in cells) {
        final at = ball.y + offset;
        if (at < -most || at > size.height + most) continue;
        draw(ball.x, at, ball.side, ball.image);
      }
      return;
    }

    // Dropping in: one ball after another, each starting a little after the
    // one before it, falling from just above the screen and bouncing to a stop
    // on its cell.
    final u = t / coverEnds;
    for (final ball in cells) {
      final since = u - begins[ball]!;
      if (since < 0) continue;

      final col = ball.col;
      final row = ball.row;
      final fall = _lerp(_fallMin, _fallMax, _unit(col, row, 5));
      final bounce = _lerp(_bounceMin, _bounceMax, _unit(col, row, 6));
      final bounces = 2 + _hash(col, row, 7) % (_bouncesMax - 1);
      // Out of sight when it starts, from a little higher for some than
      // others, so they do not all arrive on the same arc.
      final from = -ball.side / 2 - _unit(col, row, 8) * cell;

      draw(
        ball.x,
        _dropY(since, fall, bounce, bounces, from, ball.y),
        ball.side,
        ball.image,
      );
    }
  }

  /// Where a ball dropped from [from] onto [to] is, [since] after it let go.
  ///
  /// Real enough to read as a bounce: constant gravity, chosen so the first
  /// fall takes exactly [fall]; each bounce leaves the ground at [bounce] times
  /// the speed it arrived with; after [bounces] of them it stays put.
  static double _dropY(
    double since,
    double fall,
    double bounce,
    int bounces,
    double from,
    double to,
  ) {
    final height = to - from;
    final g = 2 * height / (fall * fall);
    if (since < fall) return from + 0.5 * g * since * since;

    var tau = since - fall;
    var speed = g * fall;
    for (var i = 0; i < bounces; i++) {
      speed *= bounce;
      final flight = 2 * speed / g;
      if (tau < flight) return to - (speed * tau - 0.5 * g * tau * tau);
      tau -= flight;
    }
    return to;
  }

  /// A hashed value in 0..1.
  double _unit(int col, int row, int salt) =>
      (_hash(col, row, salt) % 1000) / 999;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Slows as it arrives, so the grid settles rather than snapping into place.
  static double _ease(double p) => 1 - math.pow(1 - p, 3).toDouble();

  @override
  bool shouldRepaint(_WipePainter old) => old.t != t || old.seed != seed;
}

/// One ball of the wipe: where it lands, how big it is, which picture, and
/// its place in the drop order.
class _Ball {
  const _Ball({
    required this.x,
    required this.y,
    required this.side,
    required this.image,
    required this.order,
    required this.depth,
    required this.col,
    required this.row,
  });

  final double x;
  final double y;
  final double side;
  final int image;

  /// When it drops, bottom rows first.
  final double order;

  /// Which layer it is drawn on, independent of when it drops.
  final int depth;
  final int col;
  final int row;
}
