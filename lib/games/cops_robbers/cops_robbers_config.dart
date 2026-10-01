import '../../sdk/audio/sound_cue.dart';

class CopsRobbersConfig {
  const CopsRobbersConfig._();

  static const double targetTile = 1.65;

  static const int minTiles = 5;

  static const double robberSpeed = 3.15;
  static const double copSpeed = 3.15;

  static const double copBoostOneOnOne = 1.10;

  static double copSpeedFor(int players) =>
      players == 2 ? copSpeed * copBoostOneOnOne : copSpeed;

  static const double swipeThreshold = 0.6;

  static const double catchReach = 0.6;

  static const double eatReach = 0.3;

  static const double roleSeconds = 2.4;

  static const double countdownSeconds = 3.6;
  static const double goSeconds = 0.6;

  static const double halfSeconds = 45;

  static const int finalCountdown = 5;

  static const double timeUpSeconds = 1.3;

  static const double switchSeconds = 3.2;

  static const double overSeconds = 2.6;

  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;
  static const double deathBurstSpeed = 5.0;
  static const double deathParticleScale = 0.25;

  static const caught = SoundCue.asset('assets/games/copsrobbers/caught.wav');

  static const int colorCity = 0xFFB9BEC8;

  static const int colorStreet = 0xFF4A505C;
  static const int colorLane = 0x99F3EBD3;

  static const double blockThickness = 0.34;
  static const List<int> roofColors = [
    0xFFC9C3B8,
    0xFFB9A89A,
    0xFFA9B4C2,
    0xFFBFC9A6,
  ];

  static const double characterTiles = 0.85;

  static const int colorCoin = 0xFFF5C542;
  static const int colorCoinRim = 0xFFB8860B;
  static const int colorSack = 0xFF9C6B3A;
  static const int colorSackShade = 0x66000000;

  static const int colorSirenRed = 0xFFFF3B3B;
  static const int colorSirenBlue = 0xFF3B7BFF;
  static const double sirenPeriodMs = 260;

  static const int colorText = 0xFFFFFFFF;

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
