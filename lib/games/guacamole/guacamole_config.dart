import '../../sdk/audio/sound_cue.dart';

/// Tunables for Guac-a-Mole.
///
/// Almost everything here is about *time*, because this is the first game on
/// the platform where the difficulty is entirely a schedule rather than a
/// physics constant. Numbers are first guesses meant to be argued with on a
/// real table — the whole point of keeping them in one file.
class GuacamoleConfig {
  const GuacamoleConfig._();

  /// A round, in seconds. Short on purpose: the game is frantic, and it is
  /// nicer to want another one than to be relieved it is over.
  static const double roundSeconds = 60;

  /// Holes per phone. Four, in a 2x2 — the number is baked into the game's
  /// name and into how the quarters are laid out, so it is not really a knob.
  static const int holesPerPhone = 4;

  /// How much of a screen's short and long edge the hole grid uses, leaving a
  /// margin so no hole sits under the curve of a case or a rounded corner.
  static const double holeInset = 0.13;

  /// A mole's radius, as a fraction of the smaller cell dimension. Big enough
  /// to be an easy target at arm's length, small enough that four fit clearly.
  static const double moleRadiusFraction = 0.34;

  // ---------------------------------------------------------------- timing

  /// How long a mole stays up, at the start of the round.
  static const double visibleSecondsStart = 2.0;

  /// ...and at the end. The floor, not an average.
  static const double visibleSecondsEnd = 0.75;

  /// Fraction of the round after which moles are at [visibleSecondsEnd].
  ///
  /// Well before the end, so the last third is played entirely at full speed —
  /// a difficulty curve that is still ramping when the whistle goes never
  /// actually delivers the fast part.
  static const double rampFraction = 0.6;

  /// Rising, in seconds. Part of [visibleSecondsStart], not on top of it: a
  /// mole is tappable from the moment it starts coming up.
  static const double riseSeconds = 0.18;

  /// Sinking, in seconds — quick, and all the way down into the hole. A mole
  /// on its way down is already gone: it cannot be squished.
  static const double sinkSeconds = 0.16;

  /// How long a squished mole stays on screen, flattened and fading.
  static const double squishSeconds = 0.42;

  // --------------------------------------------------------------- density

  /// Live moles at once, per player. 0.5 means a four-phone table averages two
  /// moles up at any instant — busy enough to always have something to look
  /// at, calm enough to read a colour before committing a finger.
  static const double moleTargetPerPlayer = 0.5;

  /// Gap between spawn attempts, at the start of the round and at the end.
  static const double spawnGapStart = 0.75;
  static const double spawnGapEnd = 0.32;

  /// The pool: the most moles that can exist at once, live or squished. Sized
  /// so a full table never runs dry mid-round.
  static int poolSize(int playerCount) => (playerCount * 3).clamp(6, 40);

  // ----------------------------------------------------------------- paint

  static const int colorBackground = 0xFF93D17F;
  static const int colorPlayfield = 0xFFBDEAA8;
  static const int colorLawnStripe = 0xFFB0E19A;
  static const int colorHole = 0xFF4A2F18;
  static const int colorHoleRim = 0xFF8B6038;

  /// The avocado's pit, and the flesh ring just inside the skin. The skin
  /// itself is the owner's colour — that is the thing you have to read.
  static const int colorPit = 0xFF8B5E34;
  static const int colorPitHighlight = 0xFFA97A4E;
  static const int colorFlesh = 0xFFE8E4A0;

  // ----------------------------------------------------------------- sound
  //
  // Each on the phone the avocado is on. Leveled copies of
  // audio-src/originals/games/guacamole/; the squish is the SDK's own boup.

  /// One of these, at random, as an avocado pops up.
  static final voices = List<SoundCue>.unmodifiable([
    for (var i = 1; i <= 14; i++)
      SoundCue.asset('assets/games/guacamole/god$i.wav'),
  ]);
}
