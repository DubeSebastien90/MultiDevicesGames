import '../../sdk/audio/sound_cue.dart';

/// Hungry Hippos' tunables, all in one place.
///
/// World units are centimetres, so these numbers are readable as real sizes on
/// a real table: a marble is 5mm across, a hippo about a centimetre.
class HungryHipposConfig {
  const HungryHipposConfig._();

  // ------------------------------------------------------------- the bowl

  /// How many marbles are on the table.
  static const int marbleCount = 36;

  static const double marbleRadius = 0.34;

  /// Where the marbles are dealt at the whistle: a band between these two
  /// fractions of the dish radius, rather than a heap in the middle. They are
  /// dealt already circling (see [swirlRingFraction]), so the round starts
  /// moving instead of waiting for somebody to break the pile.
  static const double spawnInnerFraction = 0.3;
  static const double spawnOuterFraction = 0.75;

  /// Random spread on each marble's starting speed, as a fraction of it, so
  /// they do not all travel in lockstep.
  static const double spawnSpeedJitter = 0.35;

  /// The slope of the bowl, in world units per second squared per unit of
  /// distance from the middle.
  ///
  /// A slice of a very large sphere: the pull back is proportional to how far
  /// out a marble is. Lower is flatter, so a shoved marble travels further
  /// before the dish brings it home.
  static const double bowlPull = 3.0;

  /// Marbles lose speed to the felt.
  ///
  /// Low, so a marble that is hit actually goes somewhere. On its own that
  /// would leave marbles swinging through the middle forever; the swirl below
  /// is what keeps them in a readable lane instead.
  static const double marbleDamping = 0.8;

  /// The dish turns, like a slow carousel.
  ///
  /// A gentle push along the rim, the same for every marble. Against the bowl
  /// and the felt it settles every marble onto one ring at this fraction of the
  /// dish radius — the middle is no longer where everything ends up, and a
  /// marble comes round past each hippo at a steady, readable pace, which is
  /// what makes a charge something you can time.
  ///
  /// 0 turns it off, and the marbles drift back to the middle as a plain bowl.
  static const double swirlRingFraction = 0.55;

  /// Marbles bounce off each other and off the hippos.
  static const double marbleRestitution = 0.55;

  /// A strip of each player's own glass the dish keeps off, so there is
  /// somewhere to say whose phone this is.
  static const double playerMarginWorld = 1.6;

  /// Clear space between the rim of the dish and a resting hippo, so no hippo
  /// begins the round already standing in the bowl.
  static const double hippoClearance = 0.9;

  // ------------------------------------------------------------ the hippo

  /// The hippo's body.
  static const double hippoRadius = 0.85;

  /// How hard a hippo's body throws a marble it runs into. High: a lunge that
  /// clips the pack should scatter it.
  static const double hippoRestitution = 0.7;

  /// Anything this close to the middle of the hippo's head while its mouth is
  /// open is eaten. Wider than the head — near enough is the point.
  static const double mouthRadius = 1.5;

  /// How far the hippo sits inside its own screen edge when resting.
  static const double hippoInset = 1.4;

  // ------------------------------------------------------------ the charge

  /// Press and hold to charge, let go to lunge. A tap is a charge of 0.
  ///
  /// Everything below comes as a pair, *at no charge* and *at full charge*,
  /// and a lunge sits in between by how long the finger was down.
  static const double chargeFullSeconds = 0.7;

  /// Hold longer than this and the hippo goes on its own: nobody gets to sit
  /// on a full charge all round.
  static const double chargeMaxHoldSeconds = 1.5;

  /// How far the hippo lunges, as a fraction of its own distance to the middle.
  /// A full charge reaches the very middle, so nothing can be stranded there.
  static const double lungeFractionTap = 0.35;
  static const double lungeFractionFull = 0.93;

  /// Out fast, back slower — a snap and a chew. A long lunge takes longer.
  static const double lungeOutSecondsTap = 0.12;
  static const double lungeOutSecondsFull = 0.24;
  static const double lungeBackSecondsTap = 0.2;
  static const double lungeBackSecondsFull = 0.32;

  /// Time after returning before it can charge again.
  static const double recoverSecondsTap = 0.25;
  static const double recoverSecondsFull = 0.7;

  /// The mouth opens only for this last fraction of the way out. Timing, not
  /// sweeping: a marble has to be where the jaws end up, not merely somewhere
  /// along the path.
  static const double mouthOpenFraction = 0.35;

  /// How far the hippo draws back while charging, at full charge — the tell
  /// that tells everyone else what is coming.
  static const double chargeRecoil = 0.35;

  /// How much it trembles while charging, at full charge.
  static const double chargeShake = 0.06;

  // ------------------------------------------------------------ the shove

  /// At the end of every lunge, marbles just outside the mouth are thrown
  /// clear: anything within this distance of the mouth's centre that was not
  /// swallowed. Aimed at a marble heading for your neighbour, it steals it.
  static const double pushRadius = 3.2;

  /// How fast a shoved marble leaves, at no charge and at full charge.
  static const double pushSpeedTap = 5;
  static const double pushSpeedFull = 11;

  // ------------------------------------------------------------- the miss

  /// A lunge that ate nothing leaves the hippo dazed for this long on top of
  /// its usual recovery — shoving marbles aside does not count as a bite. This is what makes hammering the
  /// screen worse than waiting for a marble to come round.
  static const double missStunSeconds = 0.9;

  // ----------------------------------------------------------- the round

  /// A round ends when the marbles run out. This is the backstop.
  static const double maxRoundSeconds = 60;

  /// How long after the last marble is eaten the round is called, so the final
  /// bite is seen rather than cut off by the results.
  static const double endDelaySeconds = 1;

  // ------------------------------------------------------------- colours

  static const int colorMarble = 0xFFF4F6FB;
  static const int colorBowl = 0x99FFFFFF;

  /// The pond the hippos stand round: water in the lobby's cyan, deep enough
  /// that the white marbles still stand out on it.
  static const int colorWater = 0xFF7DDAD0;
  static const int colorWaterEdge = 0xFF62C9BE;
  static const int colorRipple = 0xFF92E3DA;
  static const int colorHippoFallback = 0xFF9AA6C8;
  static const int colorPush = 0x88FFFFFF;
  static const int colorCharge = 0xCCFFFFFF;

  // --------------------------------------------------------------- sound
  //
  // All on the hippo's own phone. Leveled copies of
  // audio-src/originals/games/hungryhippos/; the bite is the SDK's own boup.

  /// A charge building. Faded out the moment the hippo is let go — or plays on
  /// to the end, near enough, when it is held right up to
  /// [chargeMaxHoldSeconds].
  static const hold = SoundCue.asset('assets/games/hungryhippos/hold.wav');
  static const holdFadeOut = Duration(milliseconds: 120);

  /// The lunge, as the hippo is let go.
  static const shot = SoundCue.asset('assets/games/hungryhippos/shot.wav');
}
