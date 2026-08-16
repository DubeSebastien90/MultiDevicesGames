import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// Ball Bin's look: the default shapes, plus a catch counter.
///
/// The other half of the worked example. Slingshot overrode [render] to add
/// something the generic renderer could not draw; this one leaves the pixels
/// entirely alone and only adds an overlay.
class BallBinView extends ShapeView {
  BallBinView();

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final caught = frame.sharedState['caught'];
    final goal = frame.sharedState['goal'];
    if (caught is! int || goal is! int) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x80000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$caught / $goal caught',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFFFFD166),
        ),
      ),
    );
  }
}
