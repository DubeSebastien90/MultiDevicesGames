import '../../sdk/audio/sound_cue.dart';

class GuacamoleConfig {
  const GuacamoleConfig._();

  static const double roundSeconds = 60;

  static const int holesPerPhone = 4;

  static const double holeInset = 0.13;

  static const double moleRadiusFraction = 0.34;

  static const double visibleSecondsStart = 2.0;

  static const double visibleSecondsEnd = 0.75;

  static const double rampFraction = 0.6;

  static const double riseSeconds = 0.18;

  static const double sinkSeconds = 0.16;

  static const double squishSeconds = 0.42;

  static const double moleTargetPerPlayer = 0.5;

  static const double spawnGapStart = 0.75;
  static const double spawnGapEnd = 0.32;

  static int poolSize(int playerCount) => (playerCount * 3).clamp(6, 40);

  static const int colorBackground = 0xFF93D17F;
  static const int colorPlayfield = 0xFFBDEAA8;
  static const int colorLawnStripe = 0xFFB0E19A;
  static const int colorHole = 0xFF4A2F18;
  static const int colorHoleRim = 0xFF8B6038;

  static const int colorPit = 0xFF8B5E34;
  static const int colorPitHighlight = 0xFFA97A4E;
  static const int colorFlesh = 0xFFE8E4A0;

  static final voices = List<SoundCue>.unmodifiable([
    for (var i = 1; i <= 14; i++)
      SoundCue.asset('assets/games/guacamole/god$i.wav'),
  ]);
}
