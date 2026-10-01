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

  final Widget child;

  final VoidCallback onCovered;

  final VoidCallback? onDone;

  final int columns;

  final Duration cover;
  final Duration hold;
  final Duration reveal;

  Duration get total => cover + hold + reveal;

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

  static final Map<String, ui.Image> _cache = <String, ui.Image>{};

  static Future<void>? _loading;

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

  final _images = <ui.Image>[];

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

  void _watchForCovered() {
    if (_swapped || _clock.value < _coverEnds) return;
    _swapped = true;
    widget.onCovered();
  }

  Future<void> _load() async {
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
    if (!_swapped) {
      _swapped = true;
      widget.onCovered();
    }
    _clock.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
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

  final double t;

  final double coverEnds;
  final double revealBegins;

  static const _fallMin = 0.09;
  static const _fallMax = 0.12;

  static const _bounceMin = 0.30;
  static const _bounceMax = 0.50;

  static const _bouncesMax = 3;

  static final double _dropMax = () {
    var d = _fallMax;
    var e = 1.0;
    for (var i = 0; i < _bouncesMax; i++) {
      e *= _bounceMax;
      d += 2 * _fallMax * e;
    }
    return d;
  }();

  static const _jitter = 0.10;

  static const _spreadMin = 1.76;
  static const _spreadMax = 2.35;

  static const _rowMix = 1.5;

  int _hash(int col, int row, int salt) {
    var h =
        seed ^ (col * 0x1f1f1f1f) ^ (row * 0x85ebca6b) ^ (salt * 0x27d4eb2d);
    h ^= h >> 13;
    h = (h * 0x5bd1e995) & 0x3fffffff;
    return h ^ (h >> 15);
  }

  double _signed(int col, int row, int salt) =>
      (_hash(col, row, salt) % 2000) / 1000 - 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (images.isEmpty) return;

    final cell = size.width / columns;

    final rows = (size.height / cell).ceil() + 1;

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

    final offset = t < revealBegins
        ? 0.0
        : _ease((t - revealBegins) / (1 - revealBegins)) * (size.height + most);

    final cells = <_Ball>[];
    for (var row = 0; row < rows; row++) {
      final y = (row + 0.5) * cell;
      for (var col = 0; col < columns; col++) {
        final side = cell * _lerp(_spreadMin, _spreadMax, _unit(col, row, 9));
        final ty = y + _signed(col, row, 4) * _jitter * cell;

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

    final u = t / coverEnds;
    for (final ball in cells) {
      final since = u - begins[ball]!;
      if (since < 0) continue;

      final col = ball.col;
      final row = ball.row;
      final fall = _lerp(_fallMin, _fallMax, _unit(col, row, 5));
      final bounce = _lerp(_bounceMin, _bounceMax, _unit(col, row, 6));
      final bounces = 2 + _hash(col, row, 7) % (_bouncesMax - 1);

      final from = -ball.side / 2 - _unit(col, row, 8) * cell;

      draw(
        ball.x,
        _dropY(since, fall, bounce, bounces, from, ball.y),
        ball.side,
        ball.image,
      );
    }
  }

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

  double _unit(int col, int row, int salt) =>
      (_hash(col, row, salt) % 1000) / 999;

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _ease(double p) => 1 - math.pow(1 - p, 3).toDouble();

  @override
  bool shouldRepaint(_WipePainter old) => old.t != t || old.seed != seed;
}

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

  final double order;

  final int depth;
  final int col;
  final int row;
}
