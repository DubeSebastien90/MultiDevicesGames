/// Hungry Hippos' tunables, all in one place.
///
/// World units are centimetres, so these numbers are readable as real sizes on
/// a real table: a marble is 5mm across, a hippo about a centimetre.
class HungryHipposConfig {
  const HungryHipposConfig._();

  // ------------------------------------------------------------- the bowl

  /// How many marbles start in the middle.
  ///
  /// Enough to look like a heap, few enough to fit the dish without being
  /// stacked on top of each other at the whistle: `n` marbles need a dish of
  /// about `r * sqrt(n / 0.6)`, and the smallest board this game accepts is two
  /// phones.
  static const int marbleCount = 36;

  static const double marbleRadius = 0.34;

  /// How far from the middle the marbles are scattered at the start, as a
  /// fraction of the distance from the centre to the nearest hippo. Comfortably
  /// short of them, so nobody starts with a free mouthful.
  static const double scatterFraction = 0.42;

  /// The slope of the bowl, in world units per second squared per unit of
  /// distance from the middle.
  ///
  /// This is the whole trick of the real toy: a slice taken from a *very* large
  /// sphere. On a sphere of radius R the pull back toward the bottom is
  /// `g * r / R`, so a big R gives a gentle, almost-flat dish — marbles drift
  /// back to the middle and dawdle there instead of rolling like ball bearings
  /// in a saucer. Tune this rather than the marble's mass: it is the radius of
  /// the imaginary bowl, and everything else follows from it.
  static const double bowlPull = 5.5;

  /// Marbles lose speed to the felt.
  ///
  /// Near the critical value for this slope — `2 * sqrt(bowlPull)` — because a
  /// dish is not a pendulum. Much less and the marbles swing back and forth
  /// through the middle for the whole round, which is pretty and impossible to
  /// aim at.
  static const double marbleDamping = 3.2;

  /// Marbles bounce off each other, but not much: they are glass on cloth.
  static const double marbleRestitution = 0.22;

  /// A strip of each player's own glass the dish keeps off, so there is
  /// somewhere to say whose phone this is.
  ///
  /// Measured from the board's short side, which is where it is scarce: at four
  /// and six phones the dish is limited by the width, and at two the outer end
  /// of each phone would otherwise be entirely bowl.
  static const double playerMarginWorld = 1.6;

  /// Clear space between the rim of the dish and a resting hippo, so no hippo
  /// begins the round already standing in the bowl.
  static const double hippoClearance = 0.9;

  // ------------------------------------------------------------ the hippo

  /// The hippo's body, and the mouth that swallows.
  static const double hippoRadius = 0.85;

  /// Anything this close to the middle of the hippo's head while it is out is
  /// eaten. A shade wider than the head so a marble grazing the jaw counts —
  /// this is a party game and near enough is the point.
  static const double mouthRadius = 1.15;

  /// How far the hippo lunges, as a fraction of its own distance to the middle.
  ///
  /// A fraction rather than a distance: two phones make a small board and six
  /// make a large one, and a lunge measured in centimetres either falls short
  /// on one or sails past the marbles on the other.
  ///
  /// Deep enough that an open mouth covers the very middle of the dish. At 0.85
  /// it did not, and the bowl gathers stragglers into exactly that spot — so
  /// every round limped to its time limit with one or two marbles sitting in
  /// the centre that nobody could reach. Still short of 1: a hippo stops at the
  /// middle rather than charging through it.
  static const double lungeFraction = 0.93;

  /// Out fast, back slower — a snap and a chew.
  static const double lungeOutSeconds = 0.16;
  static const double lungeBackSeconds = 0.26;

  /// Time after returning before it can go again. Long enough that hammering
  /// the screen is worse than timing a lunge, short enough to feel frantic.
  static const double lungeCooldownSeconds = 0.1;

  /// How far the hippo sits inside its own screen edge when resting.
  static const double hippoInset = 1.4;

  // ----------------------------------------------------------- the round

  /// A round ends when the marbles run out. This is the backstop for the last
  /// one or two that nobody can corner.
  static const double maxRoundSeconds = 60;

  static const int pointsPerMarble = 1;

  // ------------------------------------------------------------- colours

  static const int colorMarble = 0xFFF4F6FB;
  static const int colorBowl = 0x22FFFFFF;
  static const int colorHippoFallback = 0xFF9AA6C8;
}
