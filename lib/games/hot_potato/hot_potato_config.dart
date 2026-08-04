/// Tunables for Hot Potato.
class HotPotatoConfig {
  const HotPotatoConfig._();

  /// How long the fuse burns, in seconds of *sim* time — so every screen counts
  /// down together regardless of frame rate.
  static const double fuseSeconds = 15;

  /// What holding it when it goes off costs you.
  static const int explosionPenalty = 10;

  /// World units across, before it starts swelling.
  static const double potatoRadius = 1.2;

  /// How much bigger it gets by the time the fuse runs out.
  static const double swellAtZero = 0.6;

  /// The bang, as a multiple of the resting radius.
  static const double blastScale = 4.0;

  /// How fast it travels between seats, in world units per second. Fast enough
  /// to feel thrown, slow enough that you watch it cross the table.
  static const double passSpeed = 55;

  /// A finger has to travel this far, in world units, to count as a throw
  /// rather than a tap. 1.5 units is 15mm of real glass.
  static const double minSwipeWorld = 1.5;

  static const int colorPotato = 0xFFD98A34;
  static const int colorBlast = 0xFFFF4D4D;
}
