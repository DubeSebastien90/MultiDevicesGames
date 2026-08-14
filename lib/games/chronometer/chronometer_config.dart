/// Chronometer's tunables, all in one place.
class ChronometerConfig {
  const ChronometerConfig._();

  // ------------------------------------------------------------- the target

  /// The target is drawn from this range, whole seconds.
  ///
  /// Never shorter than three: under that the count is a reaction rather than
  /// an estimate, and everybody is equally good at it. Never longer than
  /// fifteen: past there the spread between a good guess and a bad one stops
  /// growing and the round is just longer.
  static const int minTargetSeconds = 3;
  static const int maxTargetSeconds = 15;

  // -------------------------------------------------------------- the phases

  /// How long the target number is shown before the countdown starts.
  static const double revealSeconds = 2.6;

  /// The 3-2-1. One second a digit, and the last one hands straight over to
  /// the running clock — a pause after "1" would be a free head start for
  /// whoever noticed it.
  static const int countdownFrom = 3;
  static const double countdownSeconds = countdownFrom * 1.0;

  /// How long past the target the round stays open for stragglers.
  ///
  /// The round does not end when the target elapses — somebody guessing "about
  /// now" a beat late is playing the game correctly, and cutting them off at
  /// the exact second would score them as if they had never pressed. Five
  /// seconds is long enough to cover a genuine overestimate and short enough
  /// that one person staring at the ceiling cannot hold the table hostage.
  static const double graceSeconds = 5.0;

  /// A player who never pressed is scored at this error, in seconds. Equal to
  /// the grace window: not pressing is exactly as wrong as pressing at the
  /// last possible instant, and no worse — inventing a bigger number would
  /// punish a lost connection more than a bad guess.
  static const double noGuessErrorSeconds = graceSeconds;

  /// How long the results stay up before the platform is told the round is
  /// over, so everybody can read the marks before the screen changes.
  ///
  /// Has to outlast [winnerFlightMs] with room to spare, or the disc is still
  /// in the air when the platform tears the screen down — the flight is the
  /// part that explains the result, so being cut off mid-way is worse than not
  /// animating at all. There is a test pinning the two together.
  ///
  /// Nine seconds, not five: the screen now carries your time, how far off you
  /// were, your place in the field, the winner and everybody else's guess. Five
  /// was already brisk for a disc and a number, and it left the table reading
  /// aloud to each other and being cut off. Long enough to look up and say
  /// something is the point — this is the only moment in the round when anyone
  /// is allowed to talk.
  static const double resultsSeconds = 9.0;

  // ---------------------------------------------------------------- the dial

  /// The dial's radius, in world units — 1 unit is a centimetre.
  ///
  /// Sized against the *phone*, not the board: every screen draws its own dial
  /// centred on itself, so this is a fraction of the short side rather than a
  /// fixed measure that would overflow a small phone and swim on a large one.
  static const double dialFraction = 0.34;

  /// The pip marking a guess, as a fraction of the dial's radius.
  static const double pipFraction = 0.135;

  /// The winner's disc once it has flown to the middle, as a fraction of the
  /// dial's radius.
  ///
  /// Nearly the whole dial: this is the one moment the game has a hero, and a
  /// disc that merely grew a bit reads as a slightly larger dot rather than as
  /// a result. It also has to hold a time and a caption at a size legible from
  /// across the table.
  static const double winnerFraction = 0.92;

  /// The winner's bubble on the phones that did not win, as a fraction of the
  /// dial's radius.
  ///
  /// Roughly a third of the hero disc: big enough to read a time off from
  /// across the table, small enough that it never competes with your own
  /// result for the middle of your own screen.
  static const double sideBubbleFraction = 0.38;

  /// How long the winning pip takes to travel from its place on the rim into
  /// the centre.
  ///
  /// Slow enough to be *followed*: the flight is what explains the result, so
  /// an eye has to be able to track the mark from beside the notch into the
  /// middle. Any quicker and it reads as the disc simply appearing.
  static const double winnerFlightMs = 900;

  /// **One full turn of the dial is the target.** The circle is the time.
  ///
  /// So a guess of zero sits at twelve o'clock, half the target is at six, and
  /// a perfect guess comes all the way round to twelve again. Where a pip sits
  /// is *when* that player pressed, as a fraction of the round — which is what
  /// makes the dial a clock face rather than a scoreboard, and what lets two
  /// players compare their guesses by looking at the shape rather than reading
  /// two numbers.
  ///
  /// It used to divide by the target *plus* the grace window, which made the
  /// scale silently different every round: the same one-second error swept a
  /// wide arc on a three-second target and a sliver on a fifteen-second one, and
  /// the top of the dial marked nothing a player could point at. Anchoring the
  /// turn to the target is what makes twelve o'clock mean "bang on".
  ///
  /// Late guesses run past twelve into a second lap; [maxLapTurns] caps how far
  /// round they are allowed to go.
  static const double sweepTurns = 1.0;

  /// How far past a full turn a very late guess may travel, so the grace window
  /// cannot wrap a pip back onto the early side.
  ///
  /// A guess at target + grace would otherwise keep going and land next to
  /// somebody who pressed far too soon — the one reading the dial must never
  /// give. Past this the pip simply pins, which reads as "off the end" and is
  /// the truth.
  static const double maxLapTurns = 1.32;

  // -------------------------------------------------------------- the points

  /// Points for the closest guess, sliding to zero for the furthest.
  static const int bestScore = 30;

  /// Within this many seconds counts as a bullseye, worth a bonus and a ring.
  static const double bullseyeSeconds = 0.25;

  static const int bullseyeBonus = 10;

  // ------------------------------------------------------------- the effects

  /// How long a freshly-landed pip flares before settling.
  static const double pipFlashMs = 620;

  /// How long the confirmation pulse washes out from the middle when this
  /// phone's own guess registers.
  static const double pressPulseMs = 520;
}
