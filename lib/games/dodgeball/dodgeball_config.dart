import '../../sdk/audio/sound_cue.dart';

class DodgeballConfig {
  const DodgeballConfig._();

  static const double moveSpeed = 8.0;
  static const double characterRadius = 0.5;

  static const double dashSpeed = 28.0;
  static const double dashDuration = 0.15;
  static const double dashCooldown = 2.5;
  static const double dashInvincibility = 0.2;

  static const double ballRadius = 0.3;
  static const double ballBaseSpeed = 5.0;
  static const double ballSpeedIncrement = 0.4;
  static const double ballMaxSpeed = 20.0;
  static const double ballSpawnInterval = 3.0;
  static const double ballSpawnIntervalMin = 1.0;
  static const double ballSpawnIntervalDecay = 0.92;
  static const int ballMaxCount = 20;

  static const double deathShowSeconds = 1.0;

  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;

  static const double deathBurstSpeed = 7.0;

  static const double deathParticleScale = 0.22;

  static const woosh = SoundCue.asset('assets/games/dodgeball/woosh.wav');
  static const boing = SoundCue.asset('assets/games/dodgeball/boing.wav');

  static const double boingVolume = 0.6;

  static const List<String> briefingLines = [
    'Drag to move',
    'Tap to dash',
    'Do NOT get hit',
  ];

  static const double briefingStepSeconds = 2.2;
  static const double briefingSeconds = briefingStepSeconds * 3;

  static const double briefingDemoAt = 0.5;

  static const double demoBallTravel = 1.0;
  static const double demoDashAt = 0.62;

  static const double demoBallDistance = 9.0;

  static const double demoFadeIn = 0.22;
  static const double demoFadeOut = 0.3;

  static const double homeTurnSpeed = 6.0;

  static const double countdownSeconds = 3.6;

  static const double goSeconds = 0.6;

  static const double minMoveDistance = 0.8;
  static const int tapMaxMs = 250;

  static const double joystickRadius = 1.65;

  static const double joystickKnobRadius = 0.56;

  static const int joystickWellAlpha = 24;
  static const int joystickRingAlpha = 70;
  static const int joystickDeadZoneAlpha = 45;
  static const int joystickKnobAlpha = 130;

  static double moveScaleFor(double distance) {
    if (distance <= minMoveDistance) return 0;
    final span = joystickRadius - minMoveDistance;
    if (span <= 0) return 1;
    final t = (distance - minMoveDistance) / span;
    return t < 1 ? t : 1;
  }

  static const List<int> playerColors = [
    0xFFE63946,
    0xFF457B9D,
    0xFF2A9D8F,
    0xFFE9C46A,
    0xFFF4A261,
    0xFF6A0572,
    0xFF1D3557,
    0xFF8AC926,
  ];
}
