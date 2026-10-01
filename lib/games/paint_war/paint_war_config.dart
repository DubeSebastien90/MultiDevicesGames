import '../../sdk/audio/sound_cue.dart';

class PaintWarConfig {
  const PaintWarConfig._();

  static const double roundSeconds = 45;

  static const int finalCountdown = 5;

  static const double overSeconds = 1.4;

  static const double cellSize = 0.16;

  static const double spawnRadius = 1.3;

  static const double spawnMargin = 0.9;

  static const double spawnSearchStep = 0.5;

  static const double respawnSeconds = 1.6;

  static const double trailRadius = 0.3;

  static const double trailOpacity = 0.55;

  static const double trailBendRadians = 0.14;
  static const double trailMaxRun = 2.5;

  static const double moveSpeed = 8.0;
  static const double characterRadius = 0.5;

  static const double minMoveDistance = 0.8;
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

  static const List<String> briefingLines = [
    'Drag to move',
    'Expand your territory',
    'Do NOT get cut',
  ];

  static const double briefingStepSeconds = 2.4;
  static const double briefingSeconds = briefingStepSeconds * 3;

  static const double briefingDemoAt = 0.45;

  static const double demoStrollRadius = 0.6;

  static const double demoLoopAcross = 2.6;
  static const double demoLoopUp = 2.0;

  static const double demoTurnSpeed = 14;

  static const double countdownSeconds = 3.6;
  static const double goSeconds = 0.6;

  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;
  static const double deathBurstSpeed = 7.0;
  static const double deathParticleScale = 0.22;

  static const cutTrail = SoundCue.asset('assets/games/paintwar/cut_trail.wav');

  static const List<int> fallbackColors = [
    0xFF31B83C,
    0xFFF3C61A,
    0xFF8D13FF,
    0xFFBA6C24,
    0xFFFB48C4,
    0xFFD23131,
    0xFFFE7013,
    0xFF14AEEF,
  ];
}
