import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'hot_potato_config.dart';

/// Hot Potato's look: the default shapes for the potato, plus a fuse readout.
class HotPotatoView extends ShapeView {
  HotPotatoView({required this.phoneId})
    : super(grid: false, playfield: const Color(0xFF141C33));

  final String phoneId;

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final left = frame.sharedState['secondsLeft'];
    if (left is! num) return null;

    final exploded = frame.sharedState['exploded'] == true;
    final mine = frame.sharedState['holder'] == phoneId;

    final label = exploded
        ? (mine ? 'It went off in your hands' : 'Boom — not your problem')
        : mine
            ? 'YOU HAVE IT — swipe it away!'
            : '${left.toStringAsFixed(1)}s';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: exploded || mine
              ? const Color(HotPotatoConfig.colorBlast)
              : const Color(0xFFFFD166),
        ),
      ),
    );
  }
}
