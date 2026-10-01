import 'dart:math' as math;

class PhonePlacement {
  const PhonePlacement(
    this.phoneId, {
    required this.xMm,
    required this.yMm,
    this.turnDeg = 0,
    this.hint,
  });

  final String phoneId;

  final double xMm;
  final double yMm;

  final double turnDeg;

  double get turnRadians => turnDeg * math.pi / 180;

  final String? hint;

  PhonePlacement copyWith({double? xMm, double? yMm, double? turnDeg}) =>
      PhonePlacement(
        phoneId,
        xMm: xMm ?? this.xMm,
        yMm: yMm ?? this.yMm,
        turnDeg: turnDeg ?? this.turnDeg,
        hint: hint,
      );
}

class BoardBoundsMm {
  const BoardBoundsMm({
    required this.leftMm,
    required this.topMm,
    required this.widthMm,
    required this.heightMm,
  });

  final double leftMm;
  final double topMm;
  final double widthMm;
  final double heightMm;
}

class BoardPlan {
  const BoardPlan(
    this.placements, {
    this.instruction,
    this.bounds,
    this.allowGaps = false,
  });

  final List<PhonePlacement> placements;

  final String? instruction;

  final BoardBoundsMm? bounds;

  final bool allowGaps;

  PhonePlacement? forPhone(String phoneId) {
    for (final p in placements) {
      if (p.phoneId == phoneId) return p;
    }
    return null;
  }

  BoardPlan withPlacement(PhonePlacement placement) => BoardPlan(
    [
      for (final p in placements)
        if (p.phoneId == placement.phoneId) placement else p,
    ],
    instruction: instruction,
    allowGaps: allowGaps,
    bounds: null,
  );
}

class BoardPlanError implements Exception {
  const BoardPlanError(this.message);
  final String message;

  @override
  String toString() => 'Bad board plan: $message';
}
