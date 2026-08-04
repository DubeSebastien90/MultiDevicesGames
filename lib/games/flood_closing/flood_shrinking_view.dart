import 'dart:ui';

import '../../sdk/contract/view.dart';
import '../../sdk/model/world_rect.dart';
import '../flood_common/flood_sim.dart';
import '../flood_common/flood_view.dart';

/// Option B's look: the shared flood, plus the narrowing contested band that is
/// the whole point of the variant.
///
/// The band is the still-undecided ground — the part of the board a lead could
/// still be overturned in. It starts as the full playfield and closes toward
/// the waterline as the round runs, and it is drawn as a hatched, pulsing strip
/// so it reads as *pressure* rather than decoration.
///
/// This is deliberately the only countdown in the game. The README asks for the
/// narrowing to be legible without a timer or any UI text, and a band you can
/// watch closing does that better than a number nobody has time to read while
/// mashing.
class FloodShrinkingView extends FloodView {
  FloodShrinkingView(super.context);

  final _band = Paint();
  final _hatch = Paint()..style = PaintingStyle.stroke;

  @override
  void renderContested(
    Canvas canvas,
    Frame frame,
    WorldRect band,
    double waterY,
  ) {
    final scale =
        (frame.sharedState[FloodState.rangeScale] as num?)?.toDouble() ?? 1.0;

    // The contested window: the ground a lead could still be overturned in,
    // which is `scale` of the axis either side of the boundary. Expressed in
    // axis units and mapped through [waterlineY] rather than measured off the
    // board directly, so it follows the seam and each row's own depth exactly
    // as the waterline does — on mismatched rows the two halves are not the
    // same number of world units.
    final boundary =
        (frame.sharedState[FloodState.boundary] as num?)?.toDouble() ?? 0.0;
    final closedTop =
        waterlineY(frame, (boundary - scale).clamp(-1.0, 1.0));
    final closedBottom =
        waterlineY(frame, (boundary + scale).clamp(-1.0, 1.0));

    final window = WorldRect(
      band.left,
      closedTop,
      band.width,
      closedBottom - closedTop,
    ).intersect(band);
    if (window == null) return;

    final clip =
        Rect.fromLTRB(window.left, window.top, window.right, window.bottom);

    // A wash to lift the undecided ground out of the settled colour either
    // side of it, brightening as it narrows.
    final urgency = (1 - scale).clamp(0.0, 1.0);
    _band.color = Color.lerp(
      const Color(0x14FFFFFF),
      const Color(0x3DFFFFFF),
      urgency,
    )!;
    canvas.drawRect(clip, _band);

    canvas.save();
    canvas.clipRect(clip);

    // Diagonal hatching, in world units so every phone's stripes line up
    // across the seam exactly like everything else in this project.
    _hatch
      ..color = Color.lerp(
        const Color(0x22FFFFFF),
        const Color(0x66FFFFFF),
        urgency,
      )!
      ..strokeWidth = frame.onePixel * 1.5;
    const spacing = 1.2;
    final start = (clip.left - clip.height).floorToDouble();
    for (var x = start; x <= clip.right; x += spacing) {
      canvas.drawLine(
        Offset(x, clip.bottom),
        Offset(x + clip.height, clip.top),
        _hatch,
      );
    }
    canvas.restore();

    // The two closing edges, drawn hard so the movement is unmistakable.
    //
    // Only where the window was cut short by the *shrink*, never where it
    // simply ran off this screen: an edge drawn at a viewport border would be
    // a line one phone can see and its neighbour cannot, which is the one thing
    // this project does not allow itself.
    _hatch
      ..color = Color.lerp(
        const Color(0x66FFFFFF),
        const Color(0xE6FFFFFF),
        urgency,
      )!
      ..strokeWidth = frame.onePixel * 2;
    if (closedTop >= window.top) {
      canvas.drawLine(
        Offset(window.left, closedTop),
        Offset(window.right, closedTop),
        _hatch,
      );
    }
    if (closedBottom <= window.bottom) {
      canvas.drawLine(
        Offset(window.left, closedBottom),
        Offset(window.right, closedBottom),
        _hatch,
      );
    }
  }
}
