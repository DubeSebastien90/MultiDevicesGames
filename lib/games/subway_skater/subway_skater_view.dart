import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import 'subway_skater_config.dart';

/// The corridor, drawn the same on every phone because every phone is drawing
/// the same world.
///
/// Nothing here is per-phone except the highlight on your own circle and the
/// HUD — the lane markings are computed from the shared board and the dashes
/// scroll on the shared clock, so the corridor runs unbroken across the seams
/// rather than restarting at each phone.
class SubwaySkaterView extends GameView {
  SubwaySkaterView(this.context);

  final ViewContext context;

  static const _void = Color(0xFF05070D);

  /// The asphalt under the tile, and the same grey the tile is painted on.
  ///
  /// Matched on purpose, twice over: it is what shows for the frame or two
  /// before the art lands, and it is what shows through any sub-pixel crack
  /// between two tiles laid end to end. Either one against the old navy floor
  /// would be a flash of a different corridor.
  static const _floor = Color(0xFF737373);
  static const _rail = Color(0xFF3D5A8A);

  /// Road paint. Worn rather than fresh — full-strength yellow on grey is
  /// brighter than the obstacles, and the thing a player has to see first is
  /// the block, not the lane it is in.
  static const _laneMark = Color(0xE6EFC03A);
  static const _hazard = Color(0xFFFF6B3D);
  static const _hazardCore = Color(0xFF7A2410);
  static const _charge = Color(0xFFFFD166);

  /// Lane markings, in physical pixels.
  ///
  /// In pixels and not world units because this is a line rather than an
  /// object: it wants to be the same weight to the eye on every phone at the
  /// table, not the same number of millimetres on the glass.
  static const _laneMarkPx = 2.5;

  final _paint = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  /// The floor art. Nothing waits on it and nothing checks it — see
  /// [_RasterSvg].
  ///
  /// Rasterised short of 4096, which is still the largest texture some of the
  /// phones at a table will take — a wider bitmap is re-tiled or dropped on
  /// exactly the devices least able to afford either. The art is authored at
  /// 4500, so this is a touch softer than native; it is flat asphalt and
  /// low-contrast scuffs, and everything with an edge on it is drawn over the
  /// top. Filtered low rather than medium on purpose: a tile is drawn at close
  /// to its own size, and mipmaps would blur across the seam where two of them
  /// meet.
  final _tile = _RasterSvg(
    'assets/corridor-tile-45x7cm@100px-cm.svg',
    rasterWidth: 3600,
    filterQuality: FilterQuality.low,
  );

  /// The traffic. Two cars, indexed by the `car` prop each obstacle spawns
  /// with — see the sim for why the choice rides in props rather than being
  /// worked out here.
  ///
  /// A car is about three centimetres of corridor and a phone runs near 180
  /// pixels to the centimetre, so it lands on screen at roughly 550 pixels
  /// wide. Rasterised above that and filtered down, which is the way round
  /// that stays sharp: the cars are the only thing in this corridor with a
  /// hard edge and a silhouette worth reading. Unlike the floor these are
  /// scaled down a long way and never tiled, so mipmaps cost nothing and save
  /// the shimmer.
  static const _carRasterWidth = 768;
  final _cars = [
    for (var i = 1; i <= SubwaySkaterConfig.carVariants; i++)
      _RasterSvg('assets/subway_skater/Car$i.svg',
          rasterWidth: _carRasterWidth),
  ];

  @override
  Future<void> load() async {
    // Together rather than one after another: three decodes on the same frame
    // budget, and the round is waiting on all of them.
    await Future.wait([_tile.load(), for (final car in _cars) car.load()]);
  }

  @override
  void dispose() {
    _tile.dispose();
    for (final car in _cars) {
      car.dispose();
    }
  }

  /// Who is mid-tumble and who is charging, unpacked from shared state only
  /// when it changes.
  ///
  /// The wire carries joined strings — see the sim for why they are not lists —
  /// and splitting them sixty times a second to answer questions whose answers
  /// change a handful of times a round would be work for nothing.
  String _tumblingRaw = '';
  Set<String> _tumbling = const {};
  String _chargingRaw = '';
  Set<String> _charging = const {};

  @override
  void render(Canvas canvas, Frame frame) {
    _readShared(frame);

    _drawCorridor(canvas, frame);
    for (final o in frame.ofKind('obstacle')) {
      _drawObstacle(canvas, frame, o);
    }
    for (final b in frame.ofKind('burst')) {
      _drawBurst(canvas, frame, b);
    }

    for (final s in frame.ofKind('skater')) {
      _drawSkater(canvas, frame, s);
    }
  }

  /// This phone's place in the line, and whose circle is standing in it.
  ///
  /// [owner] is null for a phone past the end of a line that has got shorter —
  /// nobody is standing there and nothing this screen is touched with moves.
  ///
  /// Read from the broadcast rather than from this device's own layout, and
  /// answered here for the canvas and the HUD both: those two disagreeing about
  /// which circle is yours is the one thing this game cannot survive, since the
  /// ring is the only thing telling a player which phone to reach for.
  static ({int place, String? owner}) postOf(
    String? phoneId,
    List<String> phones,
    List<String> order,
  ) {
    final place = phones.indexOf(phoneId ?? '');
    final standing = place >= 0 && place < order.length;
    return (place: place, owner: standing ? order[place] : null);
  }

  void _readShared(Frame frame) {
    final tumbling = frame.sharedState['tumbling'] as String? ?? '';
    if (tumbling != _tumblingRaw) {
      _tumblingRaw = tumbling;
      _tumbling = tumbling.isEmpty ? const {} : tumbling.split(',').toSet();
    }

    final charging = frame.sharedState['charging'] as String? ?? '';
    if (charging != _chargingRaw) {
      _chargingRaw = charging;
      _charging = charging.isEmpty ? const {} : charging.split(',').toSet();
    }
  }

  /// Floor, rails and lane markings, clipped to what this screen can see.
  void _drawCorridor(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2);
    final board = frame.board;

    _paint.color = _void;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _paint,
    );

    final left = math.max(view.left, board.left);
    final right = math.min(view.right, board.right);
    if (right <= left) return;

    _paint.color = _floor;
    canvas.drawRect(
      Rect.fromLTRB(left, board.top, right, board.bottom),
      _paint,
    );
    _drawFloorTiles(canvas, frame, left, right);

    _stroke
      ..color = _rail
      ..strokeWidth = frame.onePixel * 2;
    canvas.drawLine(
      Offset(left, board.top),
      Offset(right, board.top),
      _stroke,
    );
    canvas.drawLine(
      Offset(left, board.bottom),
      Offset(right, board.bottom),
      _stroke,
    );

    _drawLaneDashes(canvas, frame, left, right);
  }

  /// The floor itself, laid end to end along the corridor.
  ///
  /// Phased exactly as the lane markings are — on `frame.timeMs` through
  /// [SubwaySkaterConfig.travelAt] — because the two are the same surface. A
  /// background on any other clock, or at any other rate, would slide
  /// underneath the dashes and read as the floor coming apart.
  ///
  /// At three phone-lengths a tile, a phone sees at most two of these, so the
  /// loop is a couple of draws whatever the table is doing.
  void _drawFloorTiles(Canvas canvas, Frame frame, double left, double right) {
    final image = _tile.image;
    if (image == null) return;

    const len = SubwaySkaterConfig.floorTileLength;
    final phase = SubwaySkaterConfig.travelAt(frame.timeMs / 1000) % len;
    final board = frame.board;

    canvas
      ..save()
      // Clipped, because a tile is laid on a grid of its own and the one
      // straddling the end of the board would otherwise paint corridor out into
      // the void beside it.
      ..clipRect(Rect.fromLTRB(left, board.top, right, board.bottom));

    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    // Start at the first tile at or before the visible left edge, so which tile
    // lands where depends only on world position and never on which phone is
    // asking — the same reasoning as the dashes below.
    var x = (left / len).floorToDouble() * len + phase - len;
    while (x < right) {
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTRB(x, board.top, x + len, board.bottom),
        _tile.paint,
      );
      x += len;
    }

    canvas.restore();
  }

  /// Dashes between the lanes, sliding down the corridor at the speed the
  /// obstacles travel — so the floor visibly winds up as the round does.
  ///
  /// Phased on `frame.timeMs`, which is the host's clock and identical on every
  /// phone: a local clock here would have the dashes step across each seam. And
  /// on [SubwaySkaterConfig.travelAt] rather than on a running total, for the
  /// same reason — a sum of per-frame steps is a different number on a phone
  /// that dropped a frame.
  void _drawLaneDashes(Canvas canvas, Frame frame, double left, double right) {
    const period = 3.0;
    const dash = 1.6;

    final phase = SubwaySkaterConfig.travelAt(frame.timeMs / 1000) % period;
    final board = frame.board;

    _stroke
      ..color = _laneMark
      ..strokeWidth = frame.onePixel * _laneMarkPx;

    for (var lane = 1; lane < SubwaySkaterConfig.lanes; lane++) {
      final y = board.top + board.height * lane / SubwaySkaterConfig.lanes;
      // Start at the first dash at or before the visible left edge, so what is
      // drawn depends only on world position and never on where this screen is.
      var x = (left / period).floorToDouble() * period + phase - period;
      while (x < right) {
        final a = math.max(x, left);
        final b = math.min(x + dash, right);
        if (b > a) canvas.drawLine(Offset(a, y), Offset(b, y), _stroke);
        x += period;
      }
    }
  }

  /// A car, coming at you nose first.
  ///
  /// Drawn unrotated, and that is the art's doing rather than luck: the cars
  /// are authored pointing `+x`, which is the way the corridor runs, so the end
  /// of the picture with the mirrors on it is the end that reaches a player
  /// first. Obstacles carry no angle for the same reason — nothing in this
  /// corridor is ever turned except a skater mid-tumble.
  void _drawObstacle(Canvas canvas, Frame frame, RenderEntity o) {
    final w = o.propDouble('w', SubwaySkaterConfig.obstacleLength(frame.board));
    final h = o.propDouble('h', SubwaySkaterConfig.obstacleHeight(frame.board));
    final rect =
        Rect.fromCenter(center: Offset(o.x, o.y), width: w, height: h);

    // Which car, decided when this one spawned and the same on every phone it
    // crosses. Wrapped rather than trusted: a prop that outlived the art it
    // indexes should put a car on the road, not take the round down.
    final car = _cars[o.propInt('car').abs() % _cars.length];
    final image = car.image;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        car.paint,
      );
      return;
    }

    // No art on this phone. The painted block the cars replaced is still a
    // complete drawing of an obstacle — the right length, in the right lane,
    // at the right moment — so this corridor is playable rather than pretty.
    final rounded = RRect.fromRectXY(rect, h * 0.25, h * 0.25);
    _paint.color = _hazard;
    canvas.drawRRect(rounded, _paint);

    // A dark core, so a block reads as solid rather than as a glowing pill —
    // and so the leading edge, which is the part you are timing, is the
    // brightest thing on it.
    _paint.color = _hazardCore;
    canvas.drawRRect(
      RRect.fromRectXY(rect.deflate(h * 0.22), h * 0.12, h * 0.12),
      _paint,
    );
  }

  /// What a flattened block leaves behind: a ring going out and five shards
  /// going with it, both fading.
  ///
  /// Timed from the birth stamp in the entity's own props against the shared
  /// clock, so the shatter plays at the same instant on every screen that can
  /// see it — and, on a burst straddling a seam, at the same instant on both
  /// halves of itself.
  void _drawBurst(Canvas canvas, Frame frame, RenderEntity b) {
    final life = SubwaySkaterConfig.burstSeconds * 1000;
    final t = ((frame.timeMs - b.propDouble('born')) / life).clamp(0.0, 1.0);
    if (t >= 1) return;

    final size = b.propDouble('size', 1);
    // Out fast and then easing off, which is what a thing coming apart does.
    final spread = 1 - (1 - t) * (1 - t);
    final fade = 1 - t;

    _stroke
      ..color = _charge.withValues(alpha: 0.8 * fade)
      ..strokeWidth = frame.onePixel * 2;
    canvas.drawCircle(Offset(b.x, b.y), size * (0.3 + 1.5 * spread), _stroke);

    _paint.color = _hazard.withValues(alpha: fade);
    final shard = size * 0.26 * fade;
    for (var i = 0; i < 5; i++) {
      // Tilted per burst, so five of them in a row do not look like one sprite
      // played five times.
      final a = b.angle + i * 2 * math.pi / 5;
      final at = Offset(b.x, b.y) +
          Offset(math.cos(a), math.sin(a)) * (size * (0.2 + 1.7 * spread));
      canvas.drawRect(
        Rect.fromCenter(center: at, width: shard * 2, height: shard * 2),
        _paint,
      );
    }
  }

  void _drawSkater(Canvas canvas, Frame frame, RenderEntity s) {
    final r = s.propDouble('r', SubwaySkaterConfig.skaterRadius);
    final phoneId = s.props['phone'] as String?;
    final down = phoneId != null && _tumbling.contains(phoneId);
    final charged = phoneId != null && _charging.contains(phoneId);

    final player = phoneId == null ? null : context.roster.byPhone(phoneId);
    final color = player?.color.value ?? const Color(0xFFF2F4F8);
    final center = Offset(s.x, s.y);

    // Fresh off a promotion: a halo, because for the next second this circle
    // goes through blocks instead of being stopped by them, and everybody at
    // the table needs to be able to see that from where they are sitting.
    if (charged) {
      _paint.color = _charge.withValues(alpha: 0.28);
      canvas.drawCircle(center, r * 2.1, _paint);
      _paint.color = _charge.withValues(alpha: 0.5);
      canvas.drawCircle(center, r * 1.5, _paint);
    }

    // The skater is whoever is riding it, drawn by the SDK — the walking
    // character in their colour, or the circle this game drew by hand until the
    // roster arrived, on a phone where the animation could not load.
    //
    // Nobody in this corridor ever stands still: the floor is moving under all
    // of them for the whole round, so the legs never stop. They keep up with
    // it, too — the stride runs at the corridor's own speed, so the ramp from
    // [SubwaySkaterConfig.obstacleSpeed] to [SubwaySkaterConfig.endSpeed] is
    // something you can read off the players and not only off the blocks going
    // past. `dt` is the only speed control there is, which is why the rate goes
    // through it rather than through a setting of its own.
    if (player != null) {
      final speed =
          SubwaySkaterConfig.speedAt(frame.timeMs / 1000) /
              SubwaySkaterConfig.obstacleSpeed;
      final character = context.characters.of(player.color);
      character.start();
      character.draw(
        canvas,
        center,
        worldSize: r * 2,
        // The same clock the corridor scrolls on, so the legs and the floor
        // cannot drift apart.
        dt: frame.dt * speed,
        angle: s.angle,
        // Carried away: still theirs, and visibly not in control of it.
        opacity: down ? 0.55 : 1,
      );
    } else {
      // A skater with no seat on the roster. Should not happen — the sim builds
      // them from the same slices — so this is the belt to that braces.
      _paint.color = down ? color.withValues(alpha: 0.55) : color;
      canvas.drawCircle(center, r, _paint);
    }

  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    if (frame.sharedState['over'] == true) return null;

    List<String> read(String key) => (frame.sharedState[key] as String? ?? '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList();

    final order = read('order');
    final post = postOf(frame.phoneId, read('phones'), order);

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (post.owner != null)
            Text(
              // This phone's place in the line, which is fixed — the leftmost
              // phone is always the front. What changes is who is standing at
              // it, and that is worth saying out loud, because the number is
              // also what the place is paying whoever is there.
              '${_ordinal(post.place + 1)} of ${order.length}',
              style: TextStyle(
                color: post.place == 0
                    ? const Color(0xFFFFD166)
                    : const Color(0xCCFFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            const Text(
              // A phone past the end of a line that has got shorter. Nobody is
              // standing here, so nothing this screen is touched with moves.
              'out of the line',
              style: TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
            ),
          const SizedBox(width: 10),
          Text(
            '${frame.sharedState['secondsLeft']} s',
            style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}

/// A piece of this game's art: a vector on disk, a bitmap by the time anyone
/// looks at it.
///
/// Rasterised once during placement rather than replayed per frame, because
/// each of these is laid down several times a frame on every phone at the table
/// and the paths in them never change shape — only where they sit. A corridor
/// with a dozen cars in flight is a dozen `drawImageRect`s either way; the
/// difference is whether it is also a dozen path tessellations.
///
/// **A failure here is a plainer corridor, never a round that will not start.**
/// The client turns a throw out of `GameView.load` into "Could not load Subway
/// Skater" on somebody's screen, so this swallows its own and every caller has
/// something to draw without it — flat grey for the floor, the old painted
/// blocks for the cars. Artwork does not get to decide whether people can play.
class _RasterSvg {
  _RasterSvg(
    this.asset, {
    required this.rasterWidth,
    FilterQuality filterQuality = FilterQuality.medium,
  }) : paint = Paint()
          ..isAntiAlias = true
          ..filterQuality = filterQuality;

  final String asset;

  /// How wide the art is rasterised, in pixels. Its height follows from the
  /// viewBox, so the bitmap is never a different shape from the drawing.
  final int rasterWidth;

  /// The alpha is what modulates an image; the colour is ignored.
  final Paint paint;

  ui.Image? _image;
  bool _started = false;

  ui.Image? get image => _image;

  Future<void> load() async {
    if (_started) return;
    _started = true;
    try {
      final picture = await vg.loadPicture(SvgAssetLoader(asset), null);
      final size = picture.size;
      final height = (rasterWidth * size.height / size.width).round();

      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(rasterWidth / size.width, height / size.height)
        ..drawPicture(picture.picture);
      final flattened = recorder.endRecording();

      _image = await flattened.toImage(rasterWidth, height);
      flattened.dispose();
      picture.picture.dispose();
    } on Object catch (e) {
      debugPrint('[subway skater] $asset did not load: $e');
    }
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}
