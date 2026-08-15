import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'echo_sim.dart';

/// Echo's look: the default orbs, plus a HUD line for what to do right now.
class EchoView extends ShapeView {
  EchoView() : super(grid: false, playfield: const Color(0xFF0F1424));

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final phase = frame.sharedState['phase'];
    if (phase is! String) return null;

    final eliminated = frame.sharedState['eliminated'];
    final amOut =
        eliminated is List && eliminated.contains(frame.phoneId);

    String label;
    if (amOut) {
      label = 'You broke the sequence — watching the rest';
    } else if (phase == EchoPhase.reveal) {
      label = frame.sharedState['litSeat'] == frame.phoneId
          ? 'Your seat — remember this!'
          : 'Watch the ring…';
    } else {
      final idx = (frame.sharedState['recallIndex'] as int?) ?? 0;
      final total = (frame.sharedState['sequenceLength'] as int?) ?? 0;
      label = 'Repeat it — step ${idx + 1} of $total';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Round ${frame.sharedState['round']} · $label',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF7F1E5),
        ),
      ),
    );
  }
}
