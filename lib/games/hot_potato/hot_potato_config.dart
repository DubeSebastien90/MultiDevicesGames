import '../../sdk/audio/sound_cue.dart';
import '../../sdk/score/scoreboard.dart';

class HotPotatoConfig {
  const HotPotatoConfig._();

  static const double fuseSeconds = 15;

  static const int clearOfBlastPoints = Scoreboard.pointsPerGame;

  static const int caughtInBlastPoints = Scoreboard.pointsPerGame ~/ 2;

  static const double potatoRadius = 1.2;

  static const double swellAtZero = 0.6;

  static const double blastScale = 4.0;

  static const double blastHoldSeconds = 2;

  static const int blastChunks = 36;

  static const double passSpeed = 55;

  static const double minSwipeWorld = 1.5;

  static const double hopSecondsCalm = 0.55;
  static const double hopSecondsFrantic = 0.26;

  static const int hopsBeforePass = 2;

  static const double hopArcCalm = 2.2;
  static const double hopArcFrantic = 1.2;

  static const double throwArc = 4.5;

  static const double heightShown = 0.5;
  static const double heightGrowth = 0.09;

  static const double spinCalm = 3;
  static const double spinFrantic = 24;

  static const double shoulderOffscreen = 0.6;

  static const String propSeat = 'seat';
  static const String propLeft = 'left';

  static const double handBob = 0.7;

  static const double smokeFrom = 0.15;

  static const double smokeMaxPerSecond = 45;

  static const boing = SoundCue.asset('assets/games/hotpotato/boing.wav');

  static const woosh = SoundCue.asset('assets/games/hotpotato/woosh.wav');

  static const explosion = SoundCue.asset(
    'assets/games/hotpotato/potato_explosion.wav',
  );

  static const double kettleLowHz = 900;
  static const double kettleHighHz = 1800;

  static const double kettleVolumeCalm = 0.125;
  static const double kettleVolumeFrantic = 0.25;

  static const Duration kettleHandover = Duration(milliseconds: 60);

  static const double excitedFrom = 0.5;

  static const int colorPotato = 0xFFD98A34;
  static const int colorHot = 0xFFFF2A12;
  static const int colorBlast = 0xFFFF4D4D;
}
