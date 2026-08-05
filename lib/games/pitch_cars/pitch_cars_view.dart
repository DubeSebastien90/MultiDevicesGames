import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'pitch_cars_config.dart';

/// Pitch Cars' look: the default shapes for cars and track segments, plus a
/// turn/progress readout.
class PitchCarsView extends ShapeView {
  PitchCarsView({required this.phoneId})
      : super(grid: false, playfield: const Color(0xFF141C33));

  final String phoneId;

  final _aim = Paint()..style = PaintingStyle.stroke;

  /// Pool cue, not slingshot: the car itself never moves while aiming
  /// (`PitchCarsSim` holds it at its pre-turn position throughout the
  /// pull). This draws the only visual feedback the player gets instead —
  /// an arrow from the car, in the direction it is actually about to
  /// launch (opposite the pull, same as the physics impulse), scaled by
  /// how far back the pull has gone.
  @override
  void renderForeground(Canvas canvas, Frame frame) {
    final currentTurn = frame.sharedState['currentTurn'] as String?;
    final pullX = frame.sharedState['pullX'] as double?;
    final pullY = frame.sharedState['pullY'] as double?;
    if (currentTurn == null || pullX == null || pullY == null) return;

    final car = frame.byId(currentTurn);
    if (car == null) return;

    final origin = Offset(car.x, car.y);
    final pullVector = Offset(pullX, pullY) - origin;
    final pulled = pullVector.distance;
    if (pulled < 0.05) return; // not enough to read as a real pull yet

    final strength = (pulled / PitchCarsConfig.maxPull).clamp(0.0, 1.0);
    final direction = -pullVector / pulled; // opposite the pull = the shot

    final shaftLen =
        PitchCarsConfig.carRadius * 1.5 + strength * PitchCarsConfig.maxPull * 1.5;
    final tip = origin + direction * shaftLen;

    final px = frame.onePixel;
    _aim
      ..color = Color.lerp(
        const Color(0xFF7FD1C4),
        const Color(0xFFFF4D4D),
        strength,
      )!
      ..strokeWidth = (2.0 + strength * 2.0) * px;

    canvas.drawLine(origin, tip, _aim);

    // Arrowhead: two short strokes angled back from the tip.
    const headAngle = 0.5; // radians either side of the shaft
    final headLen = 0.3 + strength * 0.2;
    final dirAngle = math.atan2(direction.dy, direction.dx);
    for (final sign in [-1, 1]) {
      final wingAngle = dirAngle + math.pi - sign * headAngle;
      final wing = tip + Offset(math.cos(wingAngle), math.sin(wingAngle)) * headLen;
      canvas.drawLine(tip, wing, _aim);
    }
  }

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
