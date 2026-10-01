import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/model/world_rect.dart';

class SubwaySkaterConfig {
  const SubwaySkaterConfig._();

  static const int lanes = 3;

  static const double roundSeconds = 45;

  static const double obstacleSpeed = 12.6;

  static const double endSpeed = 16.2;

  static const double peakWithSecondsLeft = 15;

  static const double rampSeconds = roundSeconds - peakWithSecondsLeft;

  static double speedAt(double elapsed) {
    final t = (elapsed / rampSeconds).clamp(0.0, 1.0);
    return obstacleSpeed + (endSpeed - obstacleSpeed) * t;
  }

  static double travelAt(double elapsed) {
    final winding = elapsed.clamp(0.0, rampSeconds);
    final ramped =
        obstacleSpeed * winding +
        (endSpeed - obstacleSpeed) * winding * winding / (2 * rampSeconds);
    final flatOut = elapsed > rampSeconds
        ? (elapsed - rampSeconds) * endSpeed
        : 0.0;
    return ramped + flatOut;
  }

  static const double firstSpawnGap = 1.9;
  static const double lastSpawnGap = 0.85;

  static const double firstDoubleChance = 0.1;
  static const double lastDoubleChance = 0.55;

  static const double leadInSeconds = 1.6;

  static const double skaterRadius = 0.85;

  static const double obstacleLength = 3.2;
  static const double obstacleLaneFraction = 0.7;

  static const int carModels = 2;

  static const double standFraction = 3 / 5;

  static const double swipeThreshold = 0.8;

  static const double laneChangeSpeed = 20;

  static const double climbSpeed = 48;

  static const double facingAngle = math.pi;

  static const double rightingSpeed = 12;

  static const double minTumbleSeconds = 0.4;

  static const double maxTumbleSeconds = 8;

  static const double graceSeconds = 0.8;

  static const double chargeSeconds = 1.0;

  static const int obstaclePool = 32;

  static const double burstSeconds = 0.35;

  static const int burstPool = 12;

  static double laneCenter(WorldRect board, int lane) =>
      board.top + board.height * (lane + 0.5) / lanes;

  static double laneHeight(WorldRect board) => board.height / lanes;

  static int laneAt(WorldRect board, double y) {
    final t = (y - board.top) / board.height * lanes;
    return t.floor().clamp(0, lanes - 1);
  }

  static const woosh = SoundCue.asset('assets/games/subway_skater/woosh.wav');

  static const honk = SoundCue.asset('assets/games/subway_skater/honk.wav');

  static const int honkOneIn = 7;

  static const crash = SoundCue.asset('assets/games/subway_skater/crash.wav');

  static const knockedDown = SoundCue.asset(
    'assets/games/subway_skater/potato_explosion.wav',
  );
}
