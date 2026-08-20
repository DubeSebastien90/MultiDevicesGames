/// Tunables for Photo Finish.
///
/// Tuned for a runway the width of the whole row and only a phone's short
/// edge tall — plenty of room to run, not much room to fit lanes side by
/// side, which is why the player cap and [laneMargin] are conservative.
class PhotoFinishConfig {
  const PhotoFinishConfig._();

  /// Forward speed a single tap adds, world units/s.
  static const double boostPerTap = 3.2;

  /// Hard cap on how fast a runner can ever be moving.
  static const double maxSpeed = 9.0;

  /// Speed bled off every second without a tap. Tuned against [boostPerTap]
  /// so tapping a couple of times a second holds top speed and easing off
  /// coasts to a stop in a second and a half — a rhythm, not a single mash.
  static const double friction = 6.0;

  static const double runnerRadius = 0.35; // 7mm across

  /// How far in from each edge the start and finish lines sit.
  static const double startInset = 1.4;
  static const double finishInset = 1.4;

  /// Vertical margin every lane keeps clear of the board's own top and
  /// bottom edge.
  static const double laneMargin = 0.3;

  /// Points the winner banks on top of the race itself.
  static const int winBonus = 5;

  /// Nobody tapping forever should not hang a table: the round ends in a
  /// draw after this long with no runner across the line.
  static const double backstopSeconds = 40.0;
}
