/// Tunables for Pitch Cars, kept as plain data next to the game that uses
/// them — none of this is the platform's business.
class PitchCarsConfig {
  const PitchCarsConfig._();

  /// The drivable ribbon's width, in world units (1 unit = 1cm). Wide enough
  /// for a car to have real room to aim within, narrow enough that a bad
  /// shot genuinely risks the dead space at the edges.
  static const double trackWidthWorld = 3.0;

  /// How far a "line" track's centerline swings from the board's vertical
  /// centre, before jitter. Forces the curvature that keeps the track from
  /// ever reading as straight.
  static const double lineAmplitudeWorld = 3.0;

  static const double carRadius = 0.5;

  /// How far each of the two starting lanes sits either side of the
  /// centerline. Two lanes rather than one row of N: at 3-4 players a single
  /// row across a 3-unit ribbon cannot fit cars a full diameter apart without
  /// putting the outer ones on the track's edge, where they have no room to
  /// aim (and, before the staggered grid, spawned overlapping).
  static const double startLaneOffsetWorld = 0.65;

  /// Distance along the centerline between successive rows of the starting
  /// grid. Progress is cumulative distance travelled, not absolute arclength
  /// (see `PitchCarsSim._updateProgress`), so a car further up the grid gets
  /// no head start — only elbow room.
  static const double startRowSpacingWorld = 1.4;
  static const double carDensity = 1.0;
  static const double carRestitution = 0.5;
  static const double carFriction = 0.3;

  /// Cars scrub to a stop on their own, unlike a bird in flight. High on
  /// purpose: the real board game's felt track kills speed abruptly, which
  /// is what makes a shot hard to read.
  ///
  /// A first attempt at "faster" (0.6 → 1.5 here, 0.8 → 1.0 on
  /// [impulsePerPull]) hit a hard ceiling well short of "fast": with no
  /// physical rail, a car's launch speed alone set how far it travelled in
  /// a near-straight line before curvature had any chance to bend it back
  /// onto a curved track — push speed higher and it exits the ribbon
  /// before the curve ever catches it, no matter how fast it decelerates
  /// afterward. [wallThickness] and friends exist to remove that ceiling:
  /// with a real edge to bounce off, a fast, well-aimed shot ricochets
  /// back onto the track instead of being judged off it, and speed is
  /// limited by chaos and pacing, not by geometry. Both this and
  /// [impulsePerPull] moved again once the walls existed.
  static const double carLinearDamping = 1.0;

  /// Unlike linear motion, nothing was slowing rotation on its own — a car
  /// that picked up spin (an off-centre hit, a glancing collision) could
  /// keep spinning indefinitely, and contact friction from that spin could
  /// keep re-injecting just enough linear velocity to stay above [restSpeed]
  /// forever, hanging the turn. This decays spin on its own regardless of
  /// contact.
  static const double carAngularDamping = 2.0;

  /// Independent safety net for the same failure, in case some contact
  /// pattern still slips past the damping above (e.g. two cars locked in
  /// repeated contact, or a car stuck oscillating on and off the track):
  /// if the current turn's car hasn't meaningfully *translated* — spin
  /// alone doesn't count — in this long, the turn ends wherever the car is,
  /// no matter what its velocity currently reads.
  static const double stallDisplacement = 0.1;
  static const Duration stallTimeout = Duration(seconds: 2);

  /// How far past a car's edge a grab still counts (fingers are wide).
  static const double grabSlack = 1.0;

  /// Maximum pull distance from the car's rest position.
  static const double maxPull = 3.0;

  /// Impulse magnitude per world unit of pull. See [carLinearDamping] — with
  /// track-edge walls now catching a fast car instead of the geometry
  /// having to, this is tuned so a full-power pull covers roughly one
  /// phone's length in the open, not the couple of world units it managed
  /// before the walls existed.
  static const double impulsePerPull = 5.5;

  /// Track-edge bumpers a fast car ricochets off (see [carLinearDamping]).
  /// Thin and low-friction, high restitution — meant to read as a sharp
  /// carom, not a sticky bump.
  static const double wallThickness = 0.3;
  static const double wallFriction = 0.1;
  static const double wallRestitution = 0.75;

  /// Auto-advance-the-turn triggers, once a flick has been launched.
  static const double restSpeed = 0.3;
  static const Duration restDelay = Duration(milliseconds: 600);
  static const Duration maxFlightTime = Duration(seconds: 6);

  /// A collision only excuses a car from the self-fault penalty if the car
  /// left the track within this long of being hit — a graze early in a turn,
  /// followed by the player's own reckless momentum carrying it off-track much
  /// later, still counts as self-fault.
  static const Duration hitGraceWindow = Duration(milliseconds: 250);

  /// Colours are chosen host-side so every screen agrees exactly.
  static const List<int> carColors = [
    0xFFFF6B4A,
    0xFF4ECDC4,
    0xFFFFD166,
    0xFFB388FF,
  ];
  static const int colorTrack = 0xFF2E4057;
}
