import '../../sdk/audio/sound_cue.dart';

/// Tunables for Cops & Robbers. World units are centimetres.
class CopsRobbersConfig {
  const CopsRobbersConfig._();

  // -- the maze ---------------------------------------------------------------
  /// Roughly how wide a corridor is. The board is cut into as many whole tiles
  /// of about this size as fit, then stretched a hair to fill it exactly.
  /// At 9mm the corridors were too fine to follow at arm's length, and at 13mm
  /// still fiddly on a small phone: this is about nine corridors along a phone
  /// on its side, and four across it.
  static const double targetTile = 1.65;

  /// Never fewer tiles than this either way, however small the table.
  static const int minTiles = 5;

  // -- moving -----------------------------------------------------------------
  /// Tiles a second. The same for both sides: the cops win by cornering,
  /// not by being faster. About 5.2cm a second on the glass — kept there when
  /// the corridors widened, rather than letting bigger tiles make everyone
  /// faster.
  static const double robberSpeed = 3.15;
  static const double copSpeed = 3.15;

  /// How much faster the cop runs in a game of two. One cop cannot corner
  /// anybody alone — every loop in the maze is a way round them — so at even
  /// speeds a lone robber is simply never caught. A tenth is enough to close
  /// a gap, not enough to run anyone down in a straight line.
  static const double copBoostOneOnOne = 1.10;

  /// The cops' speed for a table of [players].
  static double copSpeedFor(int players) =>
      players == 2 ? copSpeed * copBoostOneOnOne : copSpeed;

  /// How far a finger has to travel on the glass to count as a swipe.
  static const double swipeThreshold = 0.6;

  /// A cop this close to a robber — as a fraction of a tile — has caught
  /// them.
  static const double catchReach = 0.6;

  /// A robber this close to a dot's tile centre, in tiles, eats it.
  static const double eatReach = 0.3;

  // -- a half -----------------------------------------------------------------
  /// Who is who, before the count: each phone told its role.
  static const double roleSeconds = 2.4;

  /// 3, 2, 1, then GO, which holds for [goSeconds].
  static const double countdownSeconds = 3.6;
  static const double goSeconds = 0.6;

  /// The longest a half can run, in case the cops never close in.
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
  // Leveled copies of audio-src/originals/games/copsrobbers/. A coin grabbed is the
  // SDK's own boup; a catch is heard where it happened, and in both players'
  // own voices on their own phones.

  static const caught = SoundCue.asset(
    'assets/games/copsrobbers/caught.wav',
  );

  // -- paint ------------------------------------------------------------------
  /// A city from above. Muted on purpose: the players are the eight saturated
  /// colours of the palette, and a city in any of them would hide somebody.

  /// Everything off the streets — a bigger phone's spare glass is built on, so
  /// the maze is exactly the rectangle every screen can show.
  static const int colorCity = 0xFFB9BEC8;

  /// The streets, and the dashes down their middles.
  static const int colorStreet = 0xFF4A505C;
  static const int colorLane = 0x99F3EBD3;

  /// The blocks: a stretch of building between two streets, as thick as this
  /// share of a street, roofed in one of these.
  static const double blockThickness = 0.34;
  static const List<int> roofColors = [
    0xFFC9C3B8, // concrete
    0xFFB9A89A, // clay
    0xFFA9B4C2, // slate
    0xFFBFC9A6, // moss
  ];

  /// How big a character is drawn, in tiles.
  static const double characterTiles = 0.85;

  /// The coins in the road, and a robber's sack.
  static const int colorCoin = 0xFFF5C542;
  static const int colorCoinRim = 0xFFB8860B;
  static const int colorSack = 0xFF9C6B3A;
  static const int colorSackShade = 0x66000000;

  /// A cop's light: red, then blue, this long each.
  static const int colorSirenRed = 0xFFFF3B3B;
  static const int colorSirenBlue = 0xFF3B7BFF;
  static const double sirenPeriodMs = 260;

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
