/// Reaction Time's tunables, all in one place.
class ReactionConfig {
  const ReactionConfig._();

  /// How long a round lasts.
  static const double roundSeconds = 30;

  /// The dark gap before a screen lights, picked at random inside this range.
  ///
  /// Never fixed, and never shorter than a person's own reaction: a predictable
  /// rhythm turns the game into counting rather than reacting, and everybody
  /// scores the same.
  static const double minDarkSeconds = 0.7;
  static const double maxDarkSeconds = 2.4;

  /// A prompt nobody answers is given up on after this, and counts as a miss
  /// worth exactly this long. Otherwise a player who puts their phone down
  /// stalls the round for everyone else.
  static const double maxWaitSeconds = 2.0;

  /// Tapping a black screen costs you a sample of this length.
  ///
  /// Without it the winning strategy is to hammer the glass: one of those taps
  /// lands the instant the colour appears and reads as a superhuman two
  /// milliseconds. Jumping the gun has to be worse than waiting, so it scores
  /// as the slowest possible answer.
  static const double falseStartSeconds = maxWaitSeconds;

  /// The dot's radius in world units — 1 unit is a centimetre.
  ///
  /// Big enough to hit without aiming, small enough that it has to be *found*:
  /// a whole screen changing colour is noticed with the corner of an eye, a
  /// spot somewhere on it has to be looked at.
  static const double dotRadiusWorld = 1.2;

  /// Fingers are wider than the pixel they land on, so the target is forgiving
  /// by a margin. Missing should mean missing, not grazing.
  static const double hitTolerance = 1.35;

  /// How long the red wash lasts after a mistake, swell and ebb together.
  static const double faultFlashMs = 700;

  /// How far in from each edge the wash reaches, as a fraction of the screen's
  /// short side. Wide enough to be unmistakable in the corner of the eye,
  /// short of the middle where the dot appears.
  static const double faultEdgeFraction = 0.28;

  /// Points for the fastest average, sliding to zero for the slowest.
  static const int bestScore = 30;

  /// Left dark for a moment after each answer, so the next prompt cannot land
  /// under a finger that has not lifted yet.
  static const double settleSeconds = 0.35;
}
