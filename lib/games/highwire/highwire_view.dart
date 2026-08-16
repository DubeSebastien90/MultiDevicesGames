import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// The wire and the walker draw themselves from their shape props — this only
/// adds the HUD: the countdown, a balance bar, and a prompt telling whoever's
/// screen the walker is currently over that it is their turn to hold on.
class HighwireView extends ShapeView {
  HighwireView({required this.phoneId});

  final String phoneId;

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final balance = (frame.sharedState['balance'] as num?)?.toDouble() ?? 1;
    final holder = frame.sharedState['holder'] as String?;
    final secondsLeft = frame.sharedState['secondsLeft'] as int? ?? 0;
    final needsMe = holder == phoneId;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$secondsLeft s',
                  style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18),
                ),
                if (needsMe)
                  const Text(
                    'HOLD ON!',
                    style: TextStyle(
                      color: Color(0xFFFFD54A),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: const Color(0x33000000),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: balance.clamp(0, 1),
                  child: Container(
                    color: balance > 0.35
                        ? const Color(0xFF63E6A0)
                        : const Color(0xFFFF5C5C),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
