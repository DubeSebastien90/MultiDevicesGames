import 'dart:math' as math;

import 'pitch_cars_config.dart';

class PitchCarsScale {
  const PitchCarsScale._({
    required this.players,
    required this.size,
    required this.reach,
    required this.wander,
    required this.bendsPerPhone,
  });

  final double size;

  final double reach;

  final double wander;

  final int bendsPerPhone;

  final int players;

  factory PitchCarsScale.forPlayers(int players) {
    final n = players.clamp(_fewest, _most).toDouble();

    final t = (n - _fewest) / (_most - _fewest);
    return PitchCarsScale._(
      players: players,
      size: _lerp(_sizeAt.$1, _sizeAt.$2, t),
      reach: _lerp(_reachAt.$1, _reachAt.$2, t),
      wander: _lerp(_wanderAt.$1, _wanderAt.$2, t),
      bendsPerPhone: _bendsFor(players),
    );
  }

  static const _fewest = 2;
  static const _most = 8;

  static const _sizeAt = (0.75, 1.45);

  static const _reachAt = (0.85, 2.4);

  static const _wanderAt = (1.25, 0.4);

  static int _bendsFor(int players) {
    if (players <= 4) return 2;
    if (players <= 6) return 1;
    return 0;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  double get trackWidthWorld => PitchCarsConfig.trackWidthWorld * size;

  double get carRadius => PitchCarsConfig.carRadius * size;
  double get carVisualRadius => PitchCarsConfig.carVisualRadius * size;

  double get grabSlack => PitchCarsConfig.grabSlack * size;

  double get maxPull => PitchCarsConfig.maxPull * size;

  double get impulsePerPull => PitchCarsConfig.impulsePerPull * reach * size;

  double get startLaneOffsetWorld =>
      PitchCarsConfig.startLaneOffsetWorld * size;
  double get startRowSpacingWorld =>
      PitchCarsConfig.startRowSpacingWorld * size;

  double get lineAmplitudeWorld =>
      PitchCarsConfig.lineAmplitudeWorld * wander * size;
  double get cornerAmplitudeWorld =>
      PitchCarsConfig.cornerAmplitudeWorld * wander * size;

  double get minCarGap => carRadius * 2 + 1e-4;

  double get knockBackWorld =>
      trackWidthWorld * PitchCarsConfig.knockBackWidths;

  double get stallDisplacement => PitchCarsConfig.stallDisplacement * size;

  double get restSpeed => PitchCarsConfig.restSpeed * math.max(reach, 0.1);

  double get brakeSpeed => restSpeed * PitchCarsConfig.brakeBelowRestSpeeds;

  double get brakeDecel => brakeSpeed / PitchCarsConfig.brakeSeconds;
}
