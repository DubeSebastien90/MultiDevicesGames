import 'dart:ui';

import '../../sdk/contract/view.dart';
import '../../sdk/model/world_rect.dart';
import '../flood_common/flood_sim.dart';
import '../flood_common/flood_view.dart';

class FloodGrowingView extends FloodView {
  FloodGrowingView(super.context);

  final _foam = Paint();

  @override
  void renderContested(
    Canvas canvas,
    Frame frame,
    WorldRect band,
    double waterY,
  ) {
    final power =
        (frame.sharedState[FloodState.power] as num?)?.toDouble() ?? 1.0;
    if (power <= 1.01) return;

    final intensity = ((power - 1) / 2).clamp(0.0, 1.0);
    final reach = 0.4 + intensity * 1.8;

    _foam.shader = Gradient.linear(
      Offset(0, waterY - reach),
      Offset(0, waterY + reach),
      [
        const Color(0x00FFFFFF),
        Color.lerp(
          const Color(0x33FFFFFF),
          const Color(0x99FFE9B0),
          intensity,
        )!,
        const Color(0x00FFFFFF),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(band.left, waterY - reach, band.right, waterY + reach),
      _foam,
    );
  }
}
