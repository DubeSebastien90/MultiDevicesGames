import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';

/// Pitch Cars' look: the default shapes for cars and track segments, plus a
/// turn/progress readout.
class PitchCarsView extends ShapeView {
  PitchCarsView({required this.phoneId})
      : super(grid: false, playfield: const Color(0xFF141C33));

  final String phoneId;

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final winner = frame.sharedState['winner'];
    if (winner is String) {
      final mine = winner == phoneId;
      return _pill(mine ? 'You win!' : 'Race over', highlight: mine);
    }

    final currentTurn = frame.sharedState['currentTurn'];
    if (currentTurn is! String) return null;
    final mine = currentTurn == phoneId;

    final progress = frame.sharedState['progress_$phoneId'];
    final pct = progress is num ? (progress * 100).round() : 0;

    return _pill(
      mine ? 'YOUR TURN — $pct%' : "waiting — $pct%",
      highlight: mine,
    );
  }

  Widget _pill(String label, {required bool highlight}) => Container(
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
            color: highlight ? const Color(0xFFFFD166) : const Color(0xFFFFFFFF),
          ),
        ),
      );
}
