/// Tunables for the Arena fighter game.
class ArenaConfig {
  const ArenaConfig._();

  // -- movement ---------------------------------------------------------------
  static const double moveSpeed = 8.0; // cm/s (world units/s)
  static const double characterRadius = 0.6; // cm

  // -- lives ------------------------------------------------------------------
  /// Three hits and you are out, shown as three dots rather than a bar. A bar
  /// asks to be read; three dots are counted without looking.
  static const int maxLives = 3;

  // -- the sword --------------------------------------------------------------
  /// The blade, measured from the hilt.
  ///
  /// Shorter than the arm that holds it: a long blade growing straight out of
  /// a body reads as a spike, and the gap below is what makes it a sword being
  /// held rather than one stuck on.
  static const double swordLength = 1.80; // cm

  static const double swordWidth = 0.22; // cm

  /// How far the hilt sits from the body's centre — the fist at the end of a
  /// bent arm, close enough that the sword is plainly being *held*.
  ///
  /// Chosen against [swordLength] so that the two still add up to the reach
  /// this game was tuned around: every time the hand has moved, the blade has
  /// been given the difference back, and nobody's range has changed.
  static const double swordGrip = 0.85; // cm

  /// How far a blade can reach from the body's centre. Derived, never tuned:
  /// it is the geometry above, and it exists so nothing has to recompute it.
  static const double attackRange = swordGrip + swordLength;

  /// Where the blade rests, as an angle off the way the fighter is facing:
  /// straight ahead, so a fighter's reach is visible to everybody.
  static const double swordIdleAngle = 0.0;

  /// Blocking: the blade turned across the line of the body and held out in
  /// front, so it covers what is coming rather than pointing at it. A bar
  /// between you and the other sword, which is what a guard looks like.
  static const double swordBlockTilt = 1.5708; // rad, a quarter turn

  /// How far in front of the body the middle of that bar sits.
  static const double swordBlockReach = swordGrip; // cm

  /// How fast the hilt travels when the pose moves it — raising a guard slides
  /// the hand across, and a hand that jumps is the same fault as a blade that
  /// jumps.
  static const double swordReachSlew = 9.0; // cm/s

  /// Stunned: the arm drops and the blade trails behind.
  static const double swordStunAngle = 2.5; // rad

  /// How fast the blade travels between resting, blocking and stunned.
  ///
  /// The whole point of a slew rather than an assignment: a sword that
  /// teleports between poses reads as a bug, and the swing below is only
  /// legible because every *other* move is continuous too.
  static const double swordSlew = 11.0; // rad/s

  // -- attack -----------------------------------------------------------------
  /// The slash, as two angles off the fighter's facing: drawn back to one
  /// side and cut across to the other, passing straight through where they are
  /// looking.
  ///
  /// Seventy degrees each way rather than the ninety-odd it used to be. A
  /// blade that starts square across the body is winding up *behind* the
  /// shoulder, which reads as a wind-mill; a slash that starts and ends inside
  /// the shoulders is a cut.
  static const double attackWindup = 1.2217; // rad, 70 degrees
  static const double attackFollow = -1.2217; // rad, -70 degrees

  /// How fast the blade travels while slashing.
  ///
  /// A speed rather than a duration, so that the cut is the same cut whatever
  /// the blade was doing a moment before. Everything else about the timing
  /// follows from it.
  static const double swingSpeed = 13.0; // rad/s

  /// How long the slash itself takes: the whole 140 degrees, at [swingSpeed].
  ///
  /// Derived, and deliberately *only* the slash. Getting the blade to
  /// [attackWindup] in the first place is a move between poses like any other
  /// and takes as long as it takes — it is not part of the cut, it does not
  /// cut anybody, and it does not eat into this.
  static const double attackSwing =
      (attackWindup - attackFollow) / swingSpeed; // seconds

  /// Halved, now that nothing counts it down on screen. A second between
  /// swings is long enough that a player checks a number to know when they may
  /// go again; half of one is short enough that they just go.
  static const double attackCooldown = 0.5; // seconds

  /// Grace after losing a life, so one exchange cannot take two.
  static const double hitInvincibility = 0.9; // seconds

  /// The blade's colour with its guard spent: plain grey.
  static const int swordColor = 0xFFA8ACB6;

  /// How far the charged part of the blade is pulled towards its owner's own
  /// colour. The rest of the way it stays steel.
  ///
  /// The block cooldown is read off the blade rather than off a number in the
  /// corner. It is the one cooldown worth showing — an attack that is not
  /// ready simply does not come out, while a guard that is not ready gets
  /// somebody hit — and the sword is where a player is already looking.
  ///
  /// In the player's colour rather than one fixed blue, because on a table of
  /// six swords the glow is also *whose* sword: a green fighter's guard coming
  /// back lights green, and nobody has to work out which blade they were
  /// watching. Kept short of the colour itself so it still reads as metal.
  static const double swordChargeTint = 0.62;

  /// How much of the charge is spent before the blade starts to glow. Below
  /// this it only changes colour; the glow is the part that says *ready*.
  static const double swordGlowFrom = 0.55;

  // -- block ------------------------------------------------------------------
  static const double blockCooldown = 2.0; // seconds
  static const double blockMaxDuration = 1.5; // seconds

  // -- status effects ---------------------------------------------------------
  static const double stunDuration = 1.5; // seconds
  static const double spawnInvincibility = 2.0; // seconds

  // -- falling ----------------------------------------------------------------
  /// How long the round waits after the last fighter falls before it ends.
  ///
  /// The round is decided the instant it happens, and a decided round used to
  /// cut to the score in the same frame — so the burst that says *how* it was
  /// decided played to nobody. A second is long enough to watch somebody come
  /// apart and short enough that nobody taps the screen wondering.
  static const double deathShowSeconds = 1.0;

  /// The burst itself: a ring of round bits of the player's own colour, thrown
  /// outwards and slowing as they fade.
  static const int deathParticles = 16;
  static const double deathBurstSeconds = 1.0;

  /// How fast the fastest bits leave, in world units per second.
  static const double deathBurstSpeed = 7.0;

  /// The size of a bit, as a fraction of the body it came out of.
  static const double deathParticleScale = 0.22;

  // -- being hit --------------------------------------------------------------
  /// A blow that lands throws the same burst at seven tenths of the size.
  ///
  /// Written as a fraction of the death burst rather than as numbers of its
  /// own, because proportion is the whole point: a hit and a death are the
  /// same event at two strengths, and a player should read how much trouble
  /// somebody is in from the corner of their eye without counting anything.
  ///
  /// It started at a third and could not be seen across a table. A burst the
  /// eye misses is the same as no burst at all — and this one is the only
  /// thing that says a blow landed at all.
  static const double hitBurstScale = 0.7;

  static const int hitParticles = (deathParticles * hitBurstScale) ~/ 1;
  static const double hitBurstSeconds = deathBurstSeconds * hitBurstScale;
  static const double hitBurstSpeed = deathBurstSpeed * hitBurstScale;

  /// A blow that was turned away throws white ones instead of the player's
  /// colour — sparks off a guard, and the one thing on the floor that belongs
  /// to neither fighter.
  static const int parryColor = 0xFFFFFFFF;

  // -- scoring ----------------------------------------------------------------
  /// Paid the instant a fighter is cut down, to whoever did it.
  static const int pointsPerKill = 10;

  /// What surviving the longest is worth, on the shared placement ladder.
  ///
  /// Below the usual 100 because the kills pay out part of the prize on top,
  /// and a bigger table has more of them to go round.
  static int placementMax(int players) => 100 - 5 * players;

  // -- getting started --------------------------------------------------------
  /// The three lines of the briefing, and how long each one holds the screen.
  ///
  /// Long enough to read a line and watch the fighter do it, short enough that
  /// nobody who already knows how to play is kept waiting — the whole thing is
  /// over in the time the old countdown alone used to take twice.
  static const List<String> briefingLines = [
    'Drag to move',
    'Tap to attack',
    'Hold to block',
  ];

  static const double briefingStepSeconds = 1.8;
  static const double briefingSeconds = briefingStepSeconds * 3; // one per line

  /// When in a step the fighters demonstrate. Not at nought: the line wants a
  /// moment to be read before the thing it names happens.
  static const double briefingDemoAt = 0.45; // seconds into the step

  /// The whole count: three digits of a second each, then GO.
  ///
  /// The round starts when GO *leaves*, which is what the extra [goSeconds] on
  /// the end buys. Counting straight to zero meant the last thing on screen
  /// was a nought — held for the handful of frames between the clock running
  /// out and the phase changing, which reads as a stutter rather than a start.
  static const double countdownSeconds = 3.6;

  /// How long GO holds the screen at the end of the count.
  static const double goSeconds = 0.6;

  // -- gesture thresholds -----------------------------------------------------
  static const double minMoveDistance = 0.8; // cm
  static const int tapMaxMs = 250;
  static const int blockHoldMs = 350;

  // -- joystick ---------------------------------------------------------------
  /// Full tilt: the distance from the anchor at which the fighter runs at
  /// [moveSpeed], and where the drawn knob stops following the finger. Pushing
  /// further still steers — it just cannot go faster or look more pushed.
  static const double joystickRadius = 1.65; // cm

  static const double joystickKnobRadius = 0.56; // cm

  /// Faint throughout: the stick sits under the finger, over a floor somebody
  /// may be fighting on, and it is feedback rather than furniture.
  static const int joystickWellAlpha = 24;
  static const int joystickRingAlpha = 70;
  static const int joystickDeadZoneAlpha = 45;
  static const int joystickKnobAlpha = 130;

  /// How hard the stick is pushed, from a finger [distance] out of the anchor:
  /// 0 inside the dead zone, 1 at [joystickRadius] and beyond.
  ///
  /// The ramp starts where the dead zone ends rather than at the anchor, so
  /// the first distance that moves a fighter at all moves them slowly. A jump
  /// straight to half speed the instant the dead zone is crossed is the thing
  /// that makes an analogue stick feel like a digital one.
  static double moveScaleFor(double distance) {
    if (distance <= minMoveDistance) return 0;
    final span = joystickRadius - minMoveDistance;
    if (span <= 0) return 1;
    final t = (distance - minMoveDistance) / span;
    return t < 1 ? t : 1;
  }

  // -- player colours (ARGB ints) ---------------------------------------------
  static const List<int> playerColors = [
    0xFFE63946, // red
    0xFF457B9D, // blue
    0xFF2A9D8F, // teal
    0xFFE9C46A, // yellow
    0xFFF4A261, // orange
    0xFF6A0572, // purple
    0xFF1D3557, // navy
    0xFF8AC926, // lime
  ];
}
