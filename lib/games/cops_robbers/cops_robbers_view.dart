import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player.dart';
import '../../sdk/model/world_rect.dart';
import '../../sdk/render/particle_burst.dart';
import '../../sdk/render/player_animation.dart';
import 'city_maze.dart';
import 'cops_robbers_config.dart';

/// A city from above: asphalt streets with a dashed line down the middle,
/// blocks of buildings between them, coins in the road — and everybody as
/// their own character from the lobby.
///
/// The cops wear a flashing light, red then blue, that washes the road round
/// them; the robbers carry a sack of loot. Same characters, told apart at a
/// glance by what they carry.
///
/// Everything off the streets is city: a bigger phone's spare glass is built
/// on, so the maze is exactly the rectangle every screen shows.
class CopsRobbersView extends GameView {
  CopsRobbersView({
    required this.phoneId,
    this.characters = PlayerAnimations.none,
    this.roster = Roster.empty,
  });

  final String phoneId;
  final PlayerAnimations characters;
  final Roster roster;

  static const _messageMargin = 0.06;

  /// World units a second below which a character counts as standing still.
  static const _walkingSpeed = 0.5;

  final _fill = Paint();
  final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// The city as last built: its blocks, one path per roof colour, and the
  /// dashes down the middle of its streets.
  String? _mazeRaw;
  CityMaze? _maze;
  List<Path> _blocks = const [];
  Path _blockOutline = Path();
  Path _dashes = Path();

  /// The blocks that stand on a seam, as filled rectangles rather than
  /// strokes: one path per roof colour, like [_blocks].
  List<Path> _seamBlocks = const [];
  Path _seamOutline = Path();

  final _burstAt = <String, double>{};
  final _lastSeen = <String, Offset>{};

  @override
  void render(Canvas canvas, Frame frame) {
    final state = frame.sharedState;
    final view = frame.visible;

    // The city past the streets: whatever of this phone the maze does not
    // reach is built on.
    _fill.color = const Color(CopsRobbersConfig.colorCity);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );

    final ox = (state['ox'] as num?)?.toDouble() ?? 0;
    final oy = (state['oy'] as num?)?.toDouble() ?? 0;
    final tw = (state['tw'] as num?)?.toDouble() ?? 1;
    final th = (state['th'] as num?)?.toDouble() ?? 1;
    final raw = state['maze'] as String?;
    if (raw == null) return;
    if (raw != _mazeRaw) {
      _mazeRaw = raw;
      final maze = _maze = CityMaze.decode(raw);
      _build(maze, ox, oy, tw, th, frame.coverage.seamRects());
    }
    final maze = _maze!;
    final tile = math.min(tw, th);

    // The streets.
    _fill.color = const Color(CopsRobbersConfig.colorStreet);
    canvas.drawRect(
      Rect.fromLTWH(ox, oy, maze.cols * tw, maze.rows * th),
      _fill,
    );
    _line
      ..strokeCap = StrokeCap.butt
      ..color = const Color(CopsRobbersConfig.colorLane)
      ..strokeWidth = tile * 0.05;
    canvas.drawPath(_dashes, _line);
    _line.strokeCap = StrokeCap.round;

    // The blocks: a shadow on the road, the roofs, and a lighter rim.
    final wall = tile * CopsRobbersConfig.blockThickness;
    canvas.save();
    canvas.translate(tile * 0.05, tile * 0.07);
    _line
      ..color = const Color(0x55000000)
      ..strokeWidth = wall;
    canvas.drawPath(_blockOutline, _line);
    _fill.color = const Color(0x55000000);
    canvas.drawPath(_seamOutline, _fill);
    canvas.restore();
    for (var k = 0; k < _blocks.length; k++) {
      _line
        ..color = Color(CopsRobbersConfig.roofColors[k])
        ..strokeWidth = wall;
      canvas.drawPath(_blocks[k], _line);
      _fill.color = Color(CopsRobbersConfig.roofColors[k]);
      canvas.drawPath(_seamBlocks[k], _fill);
    }
    _line
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = wall * 0.3;
    canvas.drawPath(_blockOutline, _line);

    _drawCoins(canvas, state['dots'] as String?, maze, ox, oy, tw, th, tile);
    _drawDeaths(canvas, frame, tile);

    // The cops' lights first, on the road, so the characters stand in them.
    for (final e in frame.ofKind('cop')) {
      _drawSirenGlow(canvas, frame, e, tile);
    }
    for (final e in frame.ofKind('robber')) {
      _drawCharacter(canvas, frame, e, tile);
      // Over the character, slung off its back, so it shows round the body.
      _drawLoot(canvas, e, tile);
    }
    for (final e in frame.ofKind('cop')) {
      _drawCharacter(canvas, frame, e, tile);
      _drawSiren(canvas, frame, e, tile);
    }

    _drawWords(canvas, frame);
  }

  /// The city from the maze: each closed side between two tiles is a stretch
  /// of building, roofed in one of a few colours picked by where it is — so
  /// the same maze is the same city on every phone.
  ///
  /// A block standing on a seam is built out across it instead, far enough to
  /// show on both screens — see [seamBlock].
  void _build(
    CityMaze maze,
    double ox,
    double oy,
    double tw,
    double th,
    List<WorldRect> seams,
  ) {
    final roofs = [
      for (var k = 0; k < CopsRobbersConfig.roofColors.length; k++) Path(),
    ];
    final seamRoofs = [
      for (var k = 0; k < CopsRobbersConfig.roofColors.length; k++) Path(),
    ];
    final outline = Path();
    final seamOutline = Path();
    final dashes = Path();
    final thickness = math.min(tw, th) * CopsRobbersConfig.blockThickness;

    void wall(double x0, double y0, double x1, double y1, int c, int r) {
      // Neighbouring stretches share a roof often enough to read as blocks
      // rather than confetti: the colour follows a coarse patch of the grid.
      final patch = ((c ~/ 3) * 7 + (r ~/ 2) * 3) % roofs.length;
      final onSeam = seamBlock(x0, y0, x1, y1, thickness, seams);
      if (onSeam != null) {
        final rect = Rect.fromLTRB(
          onSeam.left,
          onSeam.top,
          onSeam.right,
          onSeam.bottom,
        );
        seamRoofs[patch].addRect(rect);
        seamOutline.addRect(rect);
        return;
      }
      roofs[patch]
        ..moveTo(x0, y0)
        ..lineTo(x1, y1);
      outline
        ..moveTo(x0, y0)
        ..lineTo(x1, y1);
    }

    for (var r = 0; r < maze.rows; r++) {
      for (var c = 0; c < maze.cols; c++) {
        final x = ox + c * tw;
        final y = oy + r * th;
        if (!maze.open(c, r, 1, 0)) wall(x + tw, y, x + tw, y + th, c, r);
        if (!maze.open(c, r, 0, 1)) wall(x, y + th, x + tw, y + th, c, r);
        if (c == 0) wall(x, y, x, y + th, c, r);
        if (r == 0) wall(x, y, x + tw, y, c, r);

        // A dash down the middle of every street, between two tile centres.
        final cx = x + tw / 2;
        final cy = y + th / 2;
        if (maze.open(c, r, 1, 0)) {
          dashes
            ..moveTo(cx + tw * 0.3, cy)
            ..lineTo(cx + tw * 0.7, cy);
        }
        if (maze.open(c, r, 0, 1)) {
          dashes
            ..moveTo(cx, cy + th * 0.3)
            ..lineTo(cx, cy + th * 0.7);
        }
      }
    }
    _blocks = roofs;
    _blockOutline = outline;
    _seamBlocks = seamRoofs;
    _seamOutline = seamOutline;
    _dashes = dashes;
  }

  /// The block to draw for the wall from ([x0], [y0]) to ([x1], [y1]) if it
  /// stands on one of [seams]; null if it does not.
  ///
  /// The maze is mirrored, so its middle wall lies on the middle of the board —
  /// which is where two rows of phones meet — and a block [thickness] thick is
  /// thinner than two bezels. Drawn as it is, it vanishes into the dead glass,
  /// and the way across looks open where it is not. So a block along a seam is
  /// built out across the whole of it and [seamPeek] of a block onto each
  /// screen: the maze is untouched, only what shows of it.
  static WorldRect? seamBlock(
    double x0,
    double y0,
    double x1,
    double y1,
    double thickness,
    List<WorldRect> seams,
  ) {
    final half = thickness / 2;
    final peek = thickness * seamPeek;
    final horizontal = y0 == y1;
    final midX = (x0 + x1) / 2;
    final midY = (y0 + y1) / 2;
    for (final seam in seams) {
      // Only a wall running along the seam: one across it shows on both sides
      // already.
      final along = seam.width > seam.height;
      if (along != horizontal) continue;
      if (horizontal) {
        if (midX < seam.left || midX > seam.right) continue;
        if (y0 + half < seam.top || y0 - half > seam.bottom) continue;
        final top = math.min(seam.top - peek, y0 - half);
        final bottom = math.max(seam.bottom + peek, y0 + half);
        final left = math.min(x0, x1) - half;
        final right = math.max(x0, x1) + half;
        return WorldRect(left, top, right - left, bottom - top);
      }
      if (midY < seam.top || midY > seam.bottom) continue;
      if (x0 + half < seam.left || x0 - half > seam.right) continue;
      final left = math.min(seam.left - peek, x0 - half);
      final right = math.max(seam.right + peek, x0 + half);
      final top = math.min(y0, y1) - half;
      final bottom = math.max(y0, y1) + half;
      return WorldRect(left, top, right - left, bottom - top);
    }
    return null;
  }

  /// How much of a seam block shows on each screen, as a share of a block's
  /// thickness: half, so each side sees about as much roof as it would of an
  /// ordinary block on its own glass.
  static const double seamPeek = 0.5;

  void _drawCoins(
    Canvas canvas,
    String? hex,
    CityMaze maze,
    double ox,
    double oy,
    double tw,
    double th,
    double tile,
  ) {
    if (hex == null) return;
    final r = tile * 0.12;
    for (var d = 0; d < hex.length; d++) {
      final v = int.parse(hex[d], radix: 16);
      if (v == 0) continue;
      for (var b = 0; b < 4; b++) {
        if (v & (1 << b) == 0) continue;
        final k = d * 4 + b;
        if (k >= maze.tiles) break;
        final at = Offset(
          ox + (k % maze.cols + 0.5) * tw,
          oy + (k ~/ maze.cols + 0.5) * th,
        );
        _fill.color = const Color(CopsRobbersConfig.colorCoinRim);
        canvas.drawCircle(at, r, _fill);
        _fill.color = const Color(CopsRobbersConfig.colorCoin);
        canvas.drawCircle(at, r * 0.78, _fill);
        _fill.color = const Color(0xAAFFFFFF);
        canvas.drawCircle(at + Offset(-r * 0.3, -r * 0.3), r * 0.22, _fill);
      }
    }
  }

  // -- the players ------------------------------------------------------------

  Color _colourOf(Frame frame, String key) {
    final phone = frame.sharedState['phoneId_$key'] as String? ?? '';
    return roster.byPhone(phone)?.color.value ??
        Color((frame.sharedState['color_$key'] as num?)?.toInt() ?? 0xFFFFFFFF);
  }

  /// Their own character from the lobby, walking while they move.
  void _drawCharacter(Canvas canvas, Frame frame, RenderEntity e, double tile) {
    final here = Offset(e.x, e.y);
    final before = _lastSeen[e.id];
    _lastSeen[e.id] = here;
    final moving =
        before != null &&
        frame.dt > 0 &&
        (here - before).distance / frame.dt > _walkingSpeed;

    final phone = e.props['phoneId'] as String? ?? '';
    final seated = roster.byPhone(phone);
    if (seated == null) {
      _fill.color = _colourOf(frame, 'p${e.propInt('index')}');
      canvas.drawCircle(here, tile * 0.3, _fill);
      return;
    }
    final character = characters.of(seated.color);
    moving ? character.start() : character.stop();
    character.draw(
      canvas,
      here,
      worldSize: tile * CopsRobbersConfig.characterTiles,
      dt: frame.dt,
      angle: e.angle,
    );
  }

  /// Which half of the siren is lit: red, then blue.
  static bool _redPhase(Frame frame) =>
      (frame.timeMs / CopsRobbersConfig.sirenPeriodMs).floor().isEven;

  /// The light a siren throws on the road round a cop.
  void _drawSirenGlow(Canvas canvas, Frame frame, RenderEntity e, double tile) {
    final colour = Color(
      _redPhase(frame)
          ? CopsRobbersConfig.colorSirenRed
          : CopsRobbersConfig.colorSirenBlue,
    );
    final at = Offset(e.x, e.y);
    final reach = tile * 0.95;
    _fill.shader = ui.Gradient.radial(
      at,
      reach,
      [
        colour.withValues(alpha: 0.75),
        colour.withValues(alpha: 0.35),
        colour.withValues(alpha: 0),
      ],
      [0, 0.5, 1],
    );
    canvas.drawCircle(at, reach, _fill);
    _fill.shader = null;
  }

  /// The light bar itself, across the cop's head: one half lit, the other dim,
  /// swapping.
  void _drawSiren(Canvas canvas, Frame frame, RenderEntity e, double tile) {
    final red = _redPhase(frame);
    final w = tile * 0.5;
    final h = tile * 0.16;
    canvas.save();
    canvas.translate(e.x, e.y);
    canvas.rotate(e.angle + math.pi / 2);
    for (final (side, lit, colour) in [
      (-1, red, CopsRobbersConfig.colorSirenRed),
      (1, !red, CopsRobbersConfig.colorSirenBlue),
    ]) {
      final rect = Rect.fromLTWH(side < 0 ? -w / 2 : 0, -h / 2, w / 2, h);
      final c = Color(colour);
      if (lit) {
        _fill.color = c.withValues(alpha: 0.55);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(h * 0.6), Radius.circular(h)),
          _fill,
        );
      }
      _fill.color = lit ? c : Color.lerp(c, const Color(0xFF000000), 0.55)!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(h / 2)),
        _fill,
      );
    }
    canvas.restore();
  }

  /// A sack of loot, slung behind a robber.
  void _drawLoot(Canvas canvas, RenderEntity e, double tile) {
    final back = Offset(
      e.x - math.cos(e.angle) * tile * 0.4,
      e.y - math.sin(e.angle) * tile * 0.4,
    );
    final r = tile * 0.2;
    _fill.color = const Color(CopsRobbersConfig.colorSackShade);
    canvas.drawCircle(back + Offset(r * 0.12, r * 0.15), r, _fill);
    _fill.color = const Color(CopsRobbersConfig.colorSack);
    canvas.drawCircle(back, r, _fill);
    _fill.color = const Color(CopsRobbersConfig.colorCoin);
    canvas.drawCircle(back, r * 0.38, _fill);
  }

  void _drawDeaths(Canvas canvas, Frame frame, double tile) {
    for (var i = 0; i < 8; i++) {
      final key = 'p$i';
      if (frame.sharedState['phoneId_$key'] == null) break;
      if (frame.sharedState['caught_$key'] != true) {
        _burstAt.remove(key);
        continue;
      }
      final started = _burstAt[key] ??= frame.timeMs;
      final t =
          (frame.timeMs - started) / 1000 / CopsRobbersConfig.deathBurstSeconds;
      if (t < 0 || t >= 1) continue;
      final x = double.tryParse('${frame.sharedState['deadX_$key']}');
      final y = double.tryParse('${frame.sharedState['deadY_$key']}');
      if (x == null || y == null) continue;
      drawParticleBurst(
        canvas,
        _fill,
        Offset(x, y),
        _colourOf(frame, key),
        t,
        count: CopsRobbersConfig.deathParticles,
        speed: CopsRobbersConfig.deathBurstSpeed,
        seconds: CopsRobbersConfig.deathBurstSeconds,
        particleRadius: tile * CopsRobbersConfig.deathParticleScale,
      );
    }
  }

  // -- words ------------------------------------------------------------------

  /// This phone's team, or null on a phone nobody is playing at.
  int? _myTeam(Map<String, Object?> state) {
    for (var i = 0; i < 8; i++) {
      if (state['phoneId_p$i'] == phoneId) {
        return (state['team_p$i'] as num?)?.toInt();
      }
    }
    return null;
  }

  void _drawWords(Canvas canvas, Frame frame) {
    final state = frame.sharedState;
    final size = frame.me.halfWidth * 2;
    final team = _myTeam(state);
    final robbing = (state['robbing'] as num?)?.toInt() ?? 0;
    final eaten0 = (state['eaten0'] as num?)?.toInt() ?? 0;
    final eaten1 = (state['eaten1'] as num?)?.toInt() ?? 0;
    final mine = team == 1 ? eaten1 : eaten0;
    final theirs = team == 1 ? eaten0 : eaten1;

    switch (state['phase']) {
      case 'role':
        final text = team == null
            ? ''
            : team == robbing
            ? 'ROBBER! Grab the cash'
            : 'COP! Catch them';
        _drawCentered(canvas, frame, text, size * 0.08);
      case 'playing':
        final left = (state['left'] as num?)?.toInt() ?? 0;
        if (left > 0 && left <= CopsRobbersConfig.finalCountdown) {
          _drawCentered(canvas, frame, '$left', size * 0.26);
        }
      case _ when state['timeUp'] == true:
        _drawCentered(canvas, frame, 'ROUND OVER', size * 0.12);
      case 'countdown':
        final cd = (state['countdown'] as num?)?.toDouble() ?? 0;
        final go = cd <= CopsRobbersConfig.goSeconds;
        _drawCentered(
          canvas,
          frame,
          go ? 'GO' : (cd - CopsRobbersConfig.goSeconds).ceil().toString(),
          size * (go ? 0.2 : 0.26),
        );
      case 'switch':
        _drawCentered(
          canvas,
          frame,
          switchLine(wasRobbing: team == robbing, grabbed: mine),
          size * 0.08,
        );
      case 'over' || 'finished':
        _drawCentered(canvas, frame, '$mine — $theirs', size * 0.14);
    }
  }

  /// What a phone says at half time. What was grabbed only for the side that
  /// was robbing: the cops never had the chance, and 'you grabbed 0' reads as
  /// a failure that was not one.
  static String switchLine({required bool wasRobbing, required int grabbed}) =>
      wasRobbing ? 'SWITCH! You grabbed $grabbed' : 'SWITCH!';

  /// One line across this phone's own glass, turned to its slot so it reads
  /// upright for whoever is holding it.
  void _drawCentered(Canvas canvas, Frame frame, String text, double size) {
    if (text.isEmpty) return;
    final me = frame.me;
    final width = me.halfWidth * 2;
    // Laid out in logical pixels, at the size it is actually seen, and drawn
    // with the canvas scaled back down to world units — Flood's way. Laid out
    // in world units the line was a sub-point font magnified fifty-fold by the
    // camera: Skia redraws glyphs at the final size, but Impeller on iOS
    // rasterises them near the laid-out size and stretches the result, which
    // is what made every briefing blurry on an iPhone.
    final px = me.logicalPxPerWorldUnit;
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: size * px),
          )
          ..pushStyle(
            ui.TextStyle(
              color: const Color(CopsRobbersConfig.colorText),
              fontWeight: FontWeight.w900,
              shadows: const [Shadow(color: Color(0xFF000000), blurRadius: 6)],
            ),
          )
          ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: width * px));
    final half = paragraph.height / px / 2;
    final margin = me.halfHeight * _messageMargin;
    var centre = 0.0;
    final lowest = me.halfHeight - margin - half;
    final highest = -me.halfHeight + margin + half;
    if (centre > lowest) centre = lowest;
    if (centre < highest) centre = highest;

    canvas.save();
    canvas.translate(me.worldCenterX, me.worldCenterY);
    canvas.rotate(me.turnRadians);
    canvas.scale(1 / px);
    canvas.drawParagraph(
      paragraph,
      Offset(-width / 2 * px, (centre - half) * px),
    );
    canvas.restore();
  }
}
