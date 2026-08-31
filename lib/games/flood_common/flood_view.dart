import 'dart:math' as math;
// `flutter/widgets.dart` re-exports a *widget* named Gradient, which shadows
// the painting one this file needs. Aliasing keeps both reachable.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/world_rect.dart';
import 'flood_config.dart';
import 'flood_sim.dart';

/// The flood itself: blue pouring down from the top, red up from the bottom,
/// and the waterline between them at the shared boundary.
///
/// Every phone draws the same world with the same boundary, so the waterline
/// runs unbroken across the seam — which is the whole reason this game is on
/// this platform rather than being two phones showing two pictures.
///
/// Not a [ShapeView] subclass: there are no entities to draw. The world is one
/// float, and what it paints is two rectangles and the water between them.
abstract class FloodView extends GameView {
  FloodView(this.context);

  final ViewContext context;

  final _fill = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;
  final _foam = Paint();

  /// Laid out once per distinct string and kept. There are only ever a handful
  /// — the counts, "GO", and the briefing — and shaping text is far too much
  /// work to redo sixty times a second for a digit that changes once.
  final _text = <String, TextPainter>{};

  /// The whole of how Flood is played, which is little enough to fit on the
  /// screen and be read in the three seconds before the count starts.
  static const _briefing =
      'Tap as fast as you can on the screen to flood the other team!';

  /// How much the briefing swells at the top of its breath, and how long one
  /// breath takes. Small and slow on purpose: it is there to pull an eye that
  /// has not looked up yet, not to be an animation.
  static const double _briefingPulse = 0.07;
  static const double _briefingPulseSeconds = 1.6;

  /// How much of the screen's width the message may use before it wraps.
  static const double _briefingWidthFraction = 0.82;

  /// The air between the count and the message, in logical pixels.
  ///
  /// Generous, and it buys two things at once. The count is enormous and the
  /// message is small, so a tight gap has the sentence hanging off the bottom
  /// of the digit as if it were part of it; and because the pair is centred as
  /// one block, every pixel of gap also settles the message half a pixel
  /// further down the screen, which is where a line of instructions reads best.
  static const double _briefingGap = 40.0;

  /// The overlap of two world rectangles, or null when they do not meet.
  ///
  /// Flood fills *regions* rather than drawing objects, which is why it needs
  /// this and the other games do not: `ShapeView` culls an entity with a
  /// boolean "is this circle off-screen?", whereas "blue from the top of the
  /// board down to the waterline" is a rectangle that has to be cut to what
  /// this phone can actually see, in both axes. Doing that with four
  /// hand-written min/max calls per drawing site is easy to get subtly wrong
  /// in one axis, and a mistake there shows up as a seam artefact.
  static WorldRect? overlap(WorldRect a, WorldRect b) {
    final l = a.left > b.left ? a.left : b.left;
    final t = a.top > b.top ? a.top : b.top;
    final r = a.right < b.right ? a.right : b.right;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    if (r <= l || bottom <= t) return null;
    return WorldRect(l, t, r - l, bottom - t);
  }

  /// Maps the game's `[-1, +1]` axis onto the board's vertical extent.
  ///
  /// **The axis runs opposite to the screen.** Blue sits along the top and taps
  /// its boundary *negative*, and `-1` is total blue victory — blue's colour
  /// filling both rows. So `-1` has to land at the **bottom** of the board, the
  /// far edge of red's last phone: a team pushes its own colour forward onto
  /// the opponent's glass, it does not pull the line back toward itself.
  ///
  /// Getting this backwards is invisible in the sim and obvious on a table, so
  /// the sign lives here, once, rather than in each variant's rendering.
  ///
  /// **0 is the seam, not the board's centre.** Those differ whenever the two
  /// rows have different depths — a big phone facing a small one, or two
  /// desktop windows of different sizes. Anchoring on the board's middle would
  /// start the round with the waterline already inside one team's territory,
  /// and each half is therefore scaled to its own row's depth.
  double waterlineY(Frame frame, double boundary) {
    final board = frame.board;
    final seam = (frame.sharedState[FloodState.seamY] as num?)?.toDouble() ??
        board.centerY;
    return boundary < 0
        ? seam - boundary * (board.bottom - seam)
        : seam - boundary * (seam - board.top);
  }

  /// What a variant draws between the two territories, clipped to [band] —
  /// the part of the playfield this screen can actually see.
  ///
  /// Option A leaves it to the waterline alone; option B draws the narrowing
  /// contested band that is its signature. Handing the band down means neither
  /// subclass re-derives the board-against-viewport intersection.
  void renderContested(
    Canvas canvas,
    Frame frame,
    WorldRect band,
    double waterY,
  ) {}

  @override
  void render(Canvas canvas, Frame frame) {
    final boundary =
        (frame.sharedState[FloodState.boundary] as num?)?.toDouble() ?? 0.0;
    final phase = frame.sharedState[FloodState.phase] as String?;
    final view = frame.visible;
    final waterY = waterlineY(frame, boundary);

    // Outside the board — the strip of screen beyond the playfield, if any.
    _fill.color = const Color(FloodConfig.colorNeutral);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );

    // Blue from the top of the board down to the waterline, red from there to
    // the bottom. Drawn in *board* coordinates and cut to what this screen can
    // see, so each phone shows its own slice of one continuous picture.
    final band = overlap(frame.board, view);
    if (band != null) {
      _fill.color = const Color(FloodConfig.colorBlue);
      final blueBottom = math.min(waterY, band.bottom);
      if (blueBottom > band.top) {
        canvas.drawRect(
          Rect.fromLTRB(band.left, band.top, band.right, blueBottom),
          _fill,
        );
      }

      _fill.color = const Color(FloodConfig.colorRed);
      final redTop = math.max(waterY, band.top);
      if (redTop < band.bottom) {
        canvas.drawRect(
          Rect.fromLTRB(band.left, redTop, band.right, band.bottom),
          _fill,
        );
      }

      renderContested(canvas, frame, band, waterY);
      _renderWaterline(canvas, frame, waterY, band.left, band.right);
    }

    if (phase == FloodPhase.countdown) {
      _renderCountdownWash(canvas, frame);
      _renderCountdown(canvas, frame);
    }
  }

  /// A soft edge rather than a ruler line — it reads better on camera, and it
  /// hides the fact that the boundary moves in discrete steps.
  void _renderWaterline(
    Canvas canvas,
    Frame frame,
    double waterY,
    double left,
    double right,
  ) {
    final bluePulse =
        (frame.sharedState[FloodState.bluePulse] as num?)?.toDouble() ?? 0;
    final redPulse =
        (frame.sharedState[FloodState.redPulse] as num?)?.toDouble() ?? 0;

    // The foam band swells when either side lands a tap, so mashing has a
    // visible pressure to it even while the line is barely moving.
    final swell = 0.35 + 0.5 * math.max(bluePulse, redPulse);

    final gradient = ui.Gradient.linear(
      Offset(0, waterY - swell),
      Offset(0, waterY + swell),
      [
        const Color(0x00FFFFFF),
        Color.lerp(
          const Color(0x66FFFFFF),
          const Color(0xCCFFFFFF),
          math.max(bluePulse, redPulse),
        )!,
        const Color(0x00FFFFFF),
      ],
      [0.0, 0.5, 1.0],
    );
    _foam.shader = gradient;
    canvas.drawRect(
      Rect.fromLTRB(left, waterY - swell, right, waterY + swell),
      _foam,
    );

    _stroke
      ..color = const Color(0xE6FFFFFF)
      ..strokeWidth = frame.onePixel * 2;
    canvas.drawLine(Offset(left, waterY), Offset(right, waterY), _stroke);
  }

  /// Dim everything while the countdown runs, so the board reads as "not yet".
  void _renderCountdownWash(Canvas canvas, Frame frame) {
    final view = frame.visible;
    _fill.color = const Color(0x99000000);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
  }

  /// The briefing, and — once it has been up long enough to read — the count.
  /// Both in the middle of this phone's own screen.
  ///
  /// On the canvas rather than in a HUD widget, which is where the number used
  /// to live. The platform gathers every game's HUD into the badge row in the
  /// top-left corner — right for a score or a status pill, wrong for the one
  /// thing on screen during the one moment when there is nothing else to look
  /// at. A "get ready" belongs in the middle, next to the wash it is already
  /// darkening the board with, and the canvas is the only place a view can put
  /// something there.
  ///
  /// Centred on this phone's own screen, so every player reads it in their own
  /// middle rather than all of them deferring to one point on the shared
  /// board. The wash is per-screen for the same reason: this is the game
  /// talking to each player, not the game drawing the world.
  ///
  /// The message does not move when the count appears above it: the count's
  /// space is part of the layout from the first frame, occupied or not.
  void _renderCountdown(Canvas canvas, Frame frame) {
    // Null while the briefing has the screen to itself — see
    // `FloodState.countdown`. Not the same as zero.
    final count = (frame.sharedState[FloodState.countdown] as num?)?.toInt();

    // The canvas is in world units, so a size in logical pixels has to be
    // converted or the text comes out either microscopic or the size of the
    // table.
    final px = frame.onePixel;
    final me = frame.me;

    // Measured off this phone's real screen rather than `frame.visible`: that
    // is the axis-aligned *bounding box* of a turned phone, which is wider
    // than the glass, and wrapping text to it would run the message off both
    // edges. The centre is the same either way; the width is not.
    final maxWidth = me.halfWidth * 2 * _briefingWidthFraction;

    // White, like the count. It used to carry the player's team colour, which
    // was worth it back when the line named the team — it does not any more,
    // and a saturated blue sentence on a blue board is the one place on this
    // screen where legibility is the whole job.
    final message = _painterFor(
      _briefing,
      size: 30 * px,
      weight: FontWeight.w700,
      color: const Color(0xFFFFFFFF),
      lineHeight: 1.3,
      maxWidth: maxWidth,
    );
    // Laid out even while there is no count to show, because its *slot* is
    // reserved either way — see [blockHeight]. Painted only when there is one.
    final number = _painterFor(
      count == null
          ? '0'
          : count > 0
          ? '$count'
          : 'GO',
      size: 72 * px,
      weight: FontWeight.w800,
      color: const Color(0xFFFFFFFF),
    );

    // Breathing, phased off [Frame.timeMs] — the host's clock, identical on
    // every phone — so the whole table swells and settles as one. A local
    // clock would have six phones pulsing out of step, which reads as six
    // screens rather than one board.
    final pulse =
        1 +
        _briefingPulse *
            math.sin(frame.timeMs / 1000 * 2 * math.pi / _briefingPulseSeconds);

    final gap = _briefingGap * px;
    // The count's height is in here whether or not there is a count yet, so
    // the message holds one position from the first frame of the briefing to
    // the last of the countdown. Sized to the block that will exist rather
    // than the one that does, because a message that jumps when the number
    // arrives is a message somebody has to find again mid-sentence.
    //
    // Built from the *unpulsed* height for the same reason: the message swells
    // about its own middle rather than shoving the block around as it breathes.
    final blockHeight = number.height + gap + message.height;

    canvas.save();
    // Undo the camera's turn. A phone laid sideways has the world rotated to
    // meet it, which is exactly right for the board and exactly wrong for a
    // word: this is being read by the one person holding this screen, so it
    // wants to be upright on the glass, not square to the table.
    canvas
      ..translate(me.worldCenterX, me.worldCenterY)
      ..rotate(me.turnRadians);

    final top = -blockHeight / 2;
    if (count != null) {
      number.paint(canvas, Offset(-number.width / 2, top));
    }

    final messageTop = top + number.height + gap;
    final middle = messageTop + message.height / 2;
    canvas
      ..save()
      ..translate(0, middle)
      ..scale(pulse)
      ..translate(0, -middle);
    message.paint(canvas, Offset(-message.width / 2, messageTop));
    canvas
      ..restore()
      ..restore();
  }

  /// One laid-out string, from the cache.
  ///
  /// Scaling is left to the canvas rather than done by laying out at a new
  /// font size: a pulse that changed the size would be a fresh shaping pass on
  /// every frame and a new cache entry for every size it passed through.
  TextPainter _painterFor(
    String value, {
    required double size,
    required FontWeight weight,
    required Color color,
    double lineHeight = 1.0,
    double? maxWidth,
  }) {
    // Everything baked into the span or fixed at layout belongs in the key.
    final key =
        '$value|${size.toStringAsFixed(3)}|$weight|${color.toARGB32()}'
        '|$lineHeight|${maxWidth?.toStringAsFixed(2)}';
    return _text.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            height: lineHeight,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: maxWidth ?? double.infinity),
    );
  }

  @override
  void dispose() {
    for (final p in _text.values) {
      p.dispose();
    }
    _text.clear();
    super.dispose();
  }
}
