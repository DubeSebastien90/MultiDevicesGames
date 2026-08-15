import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// The default shapes — the ball, and the red ground line drawn as an
/// ordinary entity — plus a HUD showing the countdown and the save count.
class BeachBallView extends ShapeView {
  BeachBallView();

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final secondsLeft = frame.sharedState['secondsLeft'];
    final saves = frame.sharedState['saves'];
    if (secondsLeft is! int || saves is! int) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x80000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$secondsLeft s left  •  $saves saved',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFFFFD166),
        ),
      ),
    );
  }
}
