import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'carousel_config.dart';

/// Carousel's look: the default marker shape, plus a readout of the clock, the
/// current owner and how close each phone is to the target.
class CarouselView extends ShapeView {
  CarouselView() : super(grid: false, playfield: const Color(0xFF1B1233));

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final secondsLeft = frame.sharedState['secondsLeft'];
    if (secondsLeft is! num) return null;

    final owner = frame.sharedState['owner'];
    final moving = frame.sharedState['moving'] == true;
    final landings = frame.sharedState['landings'];
    final mine = landings is Map ? ((landings[frame.phoneId] as int?) ?? 0) : 0;
    final target = frame.sharedState['target'] ?? CarouselConfig.targetLandings;
    final mineHasIt = owner == frame.phoneId;

    final label = moving
        ? 'Spinning…'
        : mineHasIt
            ? "In your zone — don't tap!"
            : 'Tap to push it on';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '${secondsLeft}s  •  $mine / $target landings',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFFFFF),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: mineHasIt
                  ? const Color(CarouselConfig.colorMarkerSettled)
                  : const Color(0xFFFFD166),
            ),
          ),
        ],
      ),
    );
  }
}
