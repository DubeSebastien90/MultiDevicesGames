import '../../sdk/audio/sound_cue.dart';

/// Tunables for Paint War. World units are centimetres, so these read as real
/// sizes on a real table.
class PaintWarConfig {
  const PaintWarConfig._();

  // -- the round --------------------------------------------------------------
  /// Forty-five seconds of painting, then the biggest territory wins.
  static const double roundSeconds = 45;

  /// The last seconds, counted down on every phone: 5, 4, 3, 2, 1, then OVER.
  static const int finalCountdown = 5;

  /// How long OVER holds the table before the results. Nobody moves during it:
  /// the territories on the glass are the ones being ranked.
  static const double overSeconds = 1.4;

  // -- the paint --------------------------------------------------------------
  /// One cell of the paint grid. Small enough that a territory's edge reads as
  /// a line rather than a staircase at arm's length — at 2.5mm the steps were
  /// plain to see on a phone — and big enough that filling an enclosure is
  /// instant on the host: eight phones is still only about 33,000 cells.
  static const double cellSize = 0.16;

  /// The circle of paint a player starts with, and comes back with.
  static const double spawnRadius = 1.3;

  /// How far from the edge of the glass a respawn circle wants to be, on top
  /// of its own radius — a player dropped against a wall has half the moves.
  static const double spawnMargin = 0.9;

  /// How far apart respawn candidates are tried, across the whole board.
  static const double spawnSearchStep = 0.5;

  /// How long a cut player is off the board before they paint again.
  static const double respawnSeconds = 1.6;

  /// Half the width of a trail. The trail is what can be cut, so it is laid
  /// wide enough that a player crossing it cannot slip between two cells.
  static const double trailRadius = 0.3;

  /// How opaque a trail is drawn. See-through, so it reads as paint still
  /// wet rather than as territory.
  static const double trailOpacity = 0.55;

  /// A trail is sent to the phones as its corners, not its every step: a new
  /// point only when the path bends by more than this, or has run straight for
  /// [trailMaxRun]. A straight run costs nothing on the wire.
  static const double trailBendRadians = 0.14;
  static const double trailMaxRun = 2.5;

  // -- movement ---------------------------------------------------------------
  static const double moveSpeed = 8.0; // cm/s
  static const double characterRadius = 0.5; // cm

  static const double minMoveDistance = 0.8; // cm, the stick's dead zone
  static const double joystickRadius = 1.65; // cm, full tilt
  static const double joystickKnobRadius = 0.56; // cm

  /// Faint throughout, as in Dodgeball: the stick sits under the finger, over
  /// paint somebody may be fighting over, and it is feedback, not furniture.
  static const int joystickWellAlpha = 24;
  static const int joystickRingAlpha = 70;
  static const int joystickDeadZoneAlpha = 45;
  static const int joystickKnobAlpha = 130;

  /// How hard the stick is pushed, from a finger [distance] out of where it
  /// came down: 0 inside the dead zone, 1 at [joystickRadius] and beyond.
  static double moveScaleFor(double distance) {
    if (distance <= minMoveDistance) return 0;
    final span = joystickRadius - minMoveDistance;
    if (span <= 0) return 1;
    final t = (distance - minMoveDistance) / span;
    return t < 1 ? t : 1;
  }

  // -- getting started --------------------------------------------------------
  /// The three lines of the briefing, one step each.
  static const List<String> briefingLines = [
    'Drag to move',
    'Expand your territory',
    'Do NOT get cut',
  ];

  static const double briefingStepSeconds = 2.4;
  static const double briefingSeconds = briefingStepSeconds * 3;

  /// When in a step the demonstration begins: the line wants reading first.
  static const double briefingDemoAt = 0.45;

  /// The first line's walk: a small ring inside the player's own paint, so it
  /// shows moving without painting anything.
  static const double demoStrollRadius = 0.6;

  /// The second line's loop, in the player's own screen axes from where they
  /// stand: out to the side, up, back across and down into their paint.
  static const double demoLoopAcross = 2.6;
  static const double demoLoopUp = 2.0;

  /// How fast a painter turns to face where a demonstration walks them, in
  /// radians a second. Turned rather than set: a body that snaps a quarter
  /// turn at every corner of the loop reads as a glitch.
  static const double demoTurnSpeed = 14;

  /// 3, 2, 1, then GO, which holds for [goSeconds].
  static const double countdownSeconds = 3.6;
  static const double goSeconds = 0.6;

  // -- being cut --------------------------------------------------------------
  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;
  static const double deathBurstSpeed = 7.0;
  static const double deathParticleScale = 0.22;

  // -- sound ------------------------------------------------------------------
  //
  // Leveled copies of audio-src/originals/games/paintwar/; the capture is the
  // SDK's own boup.

  /// A trail cut, and the player it belonged to wiped off the board.
  static const cutTrail = SoundCue.asset('assets/games/paintwar/cut_trail.wav');

  // -- fallbacks --------------------------------------------------------------
  /// For a seat nobody is sitting in yet, which has no platform colour.
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
