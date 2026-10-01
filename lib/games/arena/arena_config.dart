import '../../sdk/audio/sound_cue.dart';

class ArenaConfig {
  const ArenaConfig._();

  static const double moveSpeed = 8.0;
  static const double characterRadius = 0.6;

  static const int maxLives = 3;

  static const double swordLength = 1.80;

  static const double swordWidth = 0.22;

  static const double swordGrip = 0.85;

  static const double swordHandSide = 0.3;

  static const double attackRange = swordGrip + swordLength;

  static const double swordIdleAngle = 0.0;

  static const double swordBlockTilt = 1.5708;

  static const double swordBlockReach = swordGrip;

  static const double swordReachSlew = 9.0;

  static const double swordStunAngle = 2.5;

  static const double swordSlew = 11.0;

  static const double attackWindup = 1.2217;
  static const double attackFollow = -1.2217;

  static const double swingSpeed = 13.0;

  static const double attackSwing = (attackWindup - attackFollow) / swingSpeed;

  static const double attackCooldown = 0.5;

  static const double hitInvincibility = 0.9;

  static const int swordColor = 0xFFA8ACB6;

  static const double guardRingRadius = 1.45;
  static const double guardRingWidth = 0.16;

  static const double blockCooldown = 2.0;
  static const double blockMaxDuration = 1.5;

  static const double stunDuration = 1.5;
  static const double spawnInvincibility = 2.0;

  static const double deathShowSeconds = 1.0;

  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;

  static const double deathBurstSpeed = 7.0;

  static const double deathParticleScale = 0.22;

  static const double hitBurstScale = 0.7;

  static const int hitParticles = (deathParticles * hitBurstScale) ~/ 1;
  static const double hitBurstSeconds = deathBurstSeconds * hitBurstScale;
  static const double hitBurstSpeed = deathBurstSpeed * hitBurstScale;

  static const int parryColor = 0xFFFFFFFF;

  static const int pointsPerKill = 10;

  static int placementMax(int players) => 100 - 5 * players;

  static const List<String> briefingLines = [
    'Drag to move',
    'Tap to attack',
    'Hold to block',
  ];

  static const double briefingStepSeconds = 1.8;
  static const double briefingSeconds = briefingStepSeconds * 3;

  static const double briefingDemoAt = 0.45;

  static const double countdownSeconds = 3.6;

  static const double goSeconds = 0.6;

  static const double minMoveDistance = 0.8;
  static const int tapMaxMs = 250;
  static const int blockHoldMs = 350;

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

  static const saberOn = SoundCue.asset('assets/games/arena/lightsaber_on.wav');

  static const knockedOut = SoundCue.asset(
    'assets/games/arena/knocked_out.wav',
  );
  static const knockedOutFadeIn = Duration(milliseconds: 250);
  static const knockedOutFadeOut = Duration(milliseconds: 400);

  static const saberVoid = [
    SoundCue.asset('assets/games/arena/lightsaber_void_1.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_void_2.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_void_3.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_void_4.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_void_5.wav'),
  ];

  static const saberHit = [
    SoundCue.asset('assets/games/arena/lightsaber_hit_1.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_hit_2.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_hit_3.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_hit_4.wav'),
    SoundCue.asset('assets/games/arena/lightsaber_hit_5.wav'),
  ];

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
