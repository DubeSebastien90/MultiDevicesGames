import '../../sdk/score/scoreboard.dart';

/// Tunables for Hot Potato.
class HotPotatoConfig {
  const HotPotatoConfig._();

  /// How long the fuse burns, in seconds of *sim* time — so every screen counts
  /// down together regardless of frame rate.
  static const double fuseSeconds = 15;

  /// What getting through the round clear of the blast is worth: first place
  /// on the shared ladder. Holding it when it goes off is worth nothing.
  static const int clearOfBlastPoints = Scoreboard.pointsPerGame;

  /// What sitting next to the holder when it goes off is worth — half, the
  /// other half lost to the blast. Only at four phones and up: at three, both
  /// the others are next to the holder, and the blast takes out the holder
  /// alone.
  static const int caughtInBlastPoints = Scoreboard.pointsPerGame ~/ 2;

  /// World units across, before it starts swelling.
  static const double potatoRadius = 1.2;

  /// How much bigger it gets by the time the fuse runs out.
  static const double swellAtZero = 0.6;

  /// The bang, as a multiple of the resting radius.
  static const double blastScale = 4.0;

  /// How long the bang stays on screen before the round is called, so the
  /// table gets to watch it go off rather than cutting straight to results.
  static const double blastHoldSeconds = 2;

  /// Bits of potato thrown out by the bang.
  static const int blastChunks = 36;

  /// How fast it travels between seats, in world units per second. Fast enough
  /// to feel thrown, slow enough that you watch it cross the table.
  static const double passSpeed = 55;

  /// A finger has to travel this far, in world units, to count as a throw
  /// rather than a tap. 1.5 units is 15mm of real glass.
  static const double minSwipeWorld = 1.5;

  // ------------------------------------------------------------- juggling

  /// One hop from hand to hand, fresh and at the very end. It gets frantic:
  /// nobody holds a potato that hot for long.
  static const double hopSecondsCalm = 0.55;
  static const double hopSecondsFrantic = 0.26;

  /// How high a hop goes, in world units. Lower as it heats up — quick little
  /// flicks rather than lazy tosses.
  static const double hopArcCalm = 2.2;
  static const double hopArcFrantic = 1.2;

  /// How high a throw to a neighbour goes at the top of its arc.
  static const double throwArc = 4.5;

  /// A top-down camera cannot show height, so height is faked twice: the
  /// potato is drawn this fraction of its height *toward the middle of the
  /// table* — away from the player, which reads as "up" — and it is drawn
  /// bigger. The shadow stays on the ground.
  static const double heightShown = 0.5;
  static const double heightGrowth = 0.09;

  /// Radians per second. The spin is the other half of the heat read.
  static const double spinCalm = 3;
  static const double spinFrantic = 24;

  // ----------------------------------------------------------------- arms

  /// How far past the edge of the screen an arm starts, in world units. The
  /// arm is scaled to reach from there to the hand, so this also sets how big
  /// the hands are drawn — and it has to be enough to keep the slanted cut at
  /// the end of the forearm off the glass.
  static const double shoulderOffscreen = 0.6;

  /// Arm props: the phone it belongs to, and whether it is that player's left.
  static const String propSeat = 'seat';
  static const String propLeft = 'left';

  /// How far a hand bobs when it throws or catches.
  static const double handBob = 0.7;

  // ----------------------------------------------------------------- heat

  /// Below this much of the fuse gone, no smoke yet.
  static const double smokeFrom = 0.15;

  /// Puffs per second with the fuse at zero.
  static const double smokeMaxPerSecond = 45;

  static const int colorPotato = 0xFFD98A34;
  static const int colorHot = 0xFFFF2A12;
  static const int colorBlast = 0xFFFF4D4D;
}
