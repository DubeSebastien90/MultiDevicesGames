import '../../sdk/audio/sound_cue.dart';

class HungryHipposConfig {
  const HungryHipposConfig._();

  static const int marbleCount = 36;

  static const double marbleRadius = 0.34;

  static const double spawnInnerFraction = 0.3;
  static const double spawnOuterFraction = 0.75;

  static const double spawnSpeedJitter = 0.35;

  static const double bowlPull = 3.0;

  static const double marbleDamping = 0.8;

  static const double swirlRingFraction = 0.55;

  static const double marbleRestitution = 0.55;

  static const double playerMarginWorld = 1.6;

  static const double hippoClearance = 0.9;

  static const double hippoRadius = 0.85;

  static const double hippoRestitution = 0.7;

  static const double mouthRadius = 1.5;

  static const double hippoInset = 1.4;

  static const double chargeFullSeconds = 0.7;

  static const double chargeMaxHoldSeconds = 1.5;

  static const double lungeFractionTap = 0.35;
  static const double lungeFractionFull = 0.93;

  static const double lungeOutSecondsTap = 0.12;
  static const double lungeOutSecondsFull = 0.24;
  static const double lungeBackSecondsTap = 0.2;
  static const double lungeBackSecondsFull = 0.32;

  static const double recoverSecondsTap = 0.25;
  static const double recoverSecondsFull = 0.7;

  static const double mouthOpenFraction = 0.35;

  static const double chargeRecoil = 0.35;

  static const double chargeShake = 0.06;

  static const double pushRadius = 3.2;

  static const double pushSpeedTap = 5;
  static const double pushSpeedFull = 11;

  static const double missStunSeconds = 0.9;

  static const double maxRoundSeconds = 60;

  static const double endDelaySeconds = 1;

  static const int colorMarble = 0xFFF4F6FB;
  static const int colorBowl = 0x99FFFFFF;

  static const int colorWater = 0xFF7DDAD0;
  static const int colorWaterEdge = 0xFF62C9BE;
  static const int colorRipple = 0xFF92E3DA;
  static const int colorHippoFallback = 0xFF9AA6C8;
  static const int colorPush = 0x88FFFFFF;
  static const int colorCharge = 0xCCFFFFFF;

  static const hold = SoundCue.asset('assets/games/hungryhippos/hold.wav');
  static const holdFadeOut = Duration(milliseconds: 120);

  static const shot = SoundCue.asset('assets/games/hungryhippos/shot.wav');
}
