import '../../sdk/audio/sound_cue.dart';

class PitchCarsConfig {
  const PitchCarsConfig._();
  static const double trackWidthWorld = 3.0;

  static const double lineAmplitudeWorld = 3.0;

  static const double cornerAmplitudeWorld = 1.8;

  static const int splineSamplesPerSegment = 8;

  static const double carRadius = 0.25;

  static const double carVisualRadius = 0.25;

  static const double startLaneOffsetWorld = 0.65;

  static const double startRowSpacingWorld = 1.4;

  static const double carDensity = 4.0;
  static const double carRestitution = 0.5;
  static const double carFriction = 0.3;

  static const double carLinearDamping = 1.0;

  static const double carAngularDamping = 2.0;

  static const double stallDisplacement = 0.1;
  static const Duration stallTimeout = Duration(seconds: 2);

  static const double grabSlack = 1.0;

  static const double fallSeconds = 2.0;

  static const double fallSpinTurnsPerSecond = 1.2;

  static const double fallVisualLagSeconds = 0.08;

  static const double fallVisualMarginSeconds = 0.05;

  static const double knockBackWidths = 1.2;

  static const double maxPull = 3.0;

  static const double cancelPullFraction = 0.12;

  static const double impulsePerPull = 5.5;
  static const double restSpeed = 0.3;
  static const Duration restDelay = Duration(milliseconds: 600);

  static const double brakeBelowRestSpeeds = 3;
  static const double brakeSeconds = 0.15;
  static const Duration maxFlightTime = Duration(seconds: 6);
  static const Duration hitGraceWindow = Duration(milliseconds: 250);

  static const int colorTrack = 0xFF2E4057;

  static const String ribbonKind = 'trackRibbon';

  static const String ribbonPoints = 'pts';

  static const String ribbonWidth = 'ribbonW';
  static const String ribbonColor = 'ribbonColor';

  static const String wallKind = 'trackWall';

  static const double wallThicknessFraction = 0.14;

  static const int colorWall = 0xFFE8B04B;

  static const double wallRestitution = 0.45;

  static const double wallFriction = 0.05;

  static const int finishLineCols = 6;
  static const int finishLineRows = 4;
  static const int finishLineColorA = 0xFF000000;
  static const int finishLineColorB = 0xFFFFFFFF;

  static const String finishTileKind = 'finishTile';

  static const String finishClip = 'clip';

  static const hold = SoundCue.asset('assets/games/pitch_cars/hold.wav');
  static const holdFadeOut = Duration(milliseconds: 120);

  static const shot = SoundCue.asset('assets/games/pitch_cars/shot.wav');

  static const falling = SoundCue.asset('assets/games/pitch_cars/falling.wav');

  static const crash = SoundCue.asset('assets/games/pitch_cars/crash.wav');

  static const double crashSpeedFactor = 5.0;

  static const double crashVolume = 0.35;

  static const double crashCooldownSeconds = 0.1;
}
