import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// The default shapes — the ball, the spikes and the floor line, all drawn as
/// ordinary entities — plus a HUD showing how far down the shaft it has got.
class PlummetView extends ShapeView {
  PlummetView();

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final pct = frame.sharedState['progressPct'];
    if (pct is! int) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x80000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$pct% down the shaft',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6FE3C6),
        ),
      ),
    );
  }
}
