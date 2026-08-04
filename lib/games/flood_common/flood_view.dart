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

  /// The countdown number, and afterwards nothing at all.
  ///
  /// A HUD rather than canvas text: it is Flutter widgets, it only changes a
  /// few times a round, and it therefore never touches the render loop.
  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final phase = frame.sharedState[FloodState.phase] as String?;
    final teams = frame.sharedState[FloodState.teams];
    final myTeam = teams is Map ? teams[frame.phoneId] as String? : null;

    if (phase == FloodPhase.countdown) {
      final remaining =
          (frame.sharedState[FloodState.countdown] as num?)?.toInt() ?? 0;
      return _CountdownPill(
        text: remaining > 0 ? '$remaining' : 'GO',
        team: myTeam,
      );
    }

    // Once the round is live the screen says everything: your colour is
    // advancing or it is not. A number would only be something else to look at.
    return null;
  }
}

class _CountdownPill extends StatelessWidget {
  const _CountdownPill({required this.text, required this.team});

  final String text;
  final String? team;

  @override
  Widget build(BuildContext context) {
    final color = team == FloodConfig.blue
        ? const Color(FloodConfig.colorBlue)
        : team == FloodConfig.red
            ? const Color(FloodConfig.colorRed)
            : const Color(0xFFFFFFFF);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFFFFFF),
          ),
        ),
        if (team != null)
          Text(
            'tap anywhere for ${team!.toUpperCase()}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
      ],
    );
  }
}
