import '../../sdk/audio/sound_cue.dart';

/// Tunables for Chomp Chase. World units are centimetres.
class ChompChaseConfig {
  const ChompChaseConfig._();

  // -- the maze ---------------------------------------------------------------
  /// Roughly how wide a corridor is. The board is cut into as many whole tiles
  /// of about this size as fit, then stretched a hair to fill it exactly.
  /// At 9mm the corridors were too fine to follow at arm's length.
  static const double targetTile = 1.3;

  /// Never fewer tiles than this either way, however small the table.
  static const int minTiles = 5;

  // -- moving -----------------------------------------------------------------
  /// Tiles a second. The same for both sides: the ghosts win by cornering,
  /// not by being faster.
  static const double chomperSpeed = 4.0;
  static const double ghostSpeed = 4.0;

  /// How far a finger has to travel on the glass to count as a swipe.
  static const double swipeThreshold = 0.6;

  /// A ghost this close to a chomper — as a fraction of a tile — has caught
  /// them.
  static const double catchReach = 0.6;

  /// A chomper this close to a dot's tile centre, in tiles, eats it.
  static const double eatReach = 0.3;

  // -- a half -----------------------------------------------------------------
  /// Who is who, before the count: each phone told its role.
  static const double roleSeconds = 2.4;

  /// 3, 2, 1, then GO, which holds for [goSeconds].
  static const double countdownSeconds = 3.6;
  static const double goSeconds = 0.6;

  /// The longest a half can run, in case the ghosts never close in.
  static const double halfSeconds = 45;

  /// The last seconds of a half, counted down on every phone.
  static const int finalCountdown = 5;

  /// How long ROUND OVER holds the table when the clock ends a half, before
  /// the swap or the score.
  static const double timeUpSeconds = 1.3;

  /// The pause after a half: the last catch plays out, then the roles swap.
  static const double switchSeconds = 3.2;

  /// The pause after the second half, before the results.
  static const double overSeconds = 2.6;

  // -- being caught -----------------------------------------------------------
  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;
  static const double deathBurstSpeed = 5.0;
  static const double deathParticleScale = 0.25;

  // -- sound ------------------------------------------------------------------
  //
  // Leveled copies of audio-src/originals/games/chompchase/. A dot eaten is the
  // SDK's own boup; a catch is heard where it happened, and in both players'
  // own voices on their own phones.

  static const explosion = SoundCue.asset(
    'assets/games/chompchase/chomp_explosion.wav',
  );

  // -- paint ------------------------------------------------------------------
  /// The walls, and everything off the maze: a bigger phone's spare glass is
  /// wall, so the maze is exactly the rectangle every screen can show.
  static const int colorWall = 0xFF2F3CC8;
  static const int colorWallGlow = 0xFF5D6BFF;
  static const int colorFloor = 0xFF07081A;
  static const int colorDot = 0xFFFFD9B0;
  static const int colorText = 0xFFFFFFFF;

  /// For a seat nobody is sitting in yet.
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
