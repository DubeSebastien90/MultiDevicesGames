import 'dart:math' as math;

import 'pitch_cars_config.dart';

/// How big the race is drawn, and how far a shot goes, for a table of this
/// many phones.
///
/// ## The problem
///
/// A Pitch Cars board is a chain, so the road grows with the table: eight
/// phones is four times the tarmac of two. Nothing else grew with it. Every
/// car was the same size, every flick went the same distance, so a big table
/// simply meant everybody taking four times as many shots. The race did not
/// get grander, it got longer.
///
/// ## Two knobs, deliberately not one
///
/// **[size]** is how much of a phone the road takes up. Small tables get a
/// narrow ribbon with room to wander across the screen; big tables get a wide
/// one that runs straight through. This is the "zoom": the camera cannot move
/// — `ViewportGame` pins it so a world unit is its true physical size, which
/// is the whole reason the seam lines up — so what changes is the road, not
/// the lens. A wider road with a bigger car on it fills the phone exactly as
/// zooming in would, and every screen stays in agreement.
///
/// **[reach]** is how far a flick travels. It is *not* tied to [size], and the
/// separation is the point: how much of a phone the road covers is bounded by
/// the phone — past about two thirds of the width there is no room left for
/// the track to bend at all — while how far a car flies is bounded by nothing.
/// Tying them together would cap the only lever that actually shortens a race
/// at the same ceiling as the one that sets the look.
///
/// ## What this cannot do
///
/// It does not make a big table play in the same time as a small one, and it
/// is not tuned to. The number of shots in a race is roughly
///
///     phones × road-per-phone × wander ÷ reach
///
/// and the leading term is the table itself. Flattening that completely would
/// need a flick that crosses most of the board, which is not a game of skill
/// any more — it is one shot and a coast. What the numbers below aim at is
/// taking the difference from around fourfold to something nearer half again,
/// and leaving a big table feeling like a bigger race rather than a slog.
///
/// The values are a considered starting point, not a derivation. Anything that
/// claims to know how long a flick game *feels* without anybody having played
/// it is guessing with decimal places. Tune [_sizeAt], [_reachAt] and
/// [_wanderAt] against a real table; the shape of the system is what matters.
class PitchCarsScale {
  const PitchCarsScale._({
    required this.players,
    required this.size,
    required this.reach,
    required this.wander,
    required this.bendsPerPhone,
  });

  /// Everything the road and the cars are measured in, relative to the tuning
  /// in [PitchCarsConfig].
  final double size;

  /// How far a flick carries, relative to the same.
  final double reach;

  /// How far the road is allowed to stray from the straight line between the
  /// points where it enters and leaves a phone.
  final double wander;

  /// Interior control points the generator puts on each phone: two for an
  /// S through the screen, one for a single lazy bend, none at all for a
  /// straight run seam to seam.
  final int bendsPerPhone;

  final int players;

  /// The whole table's worth of tuning, derived once.
  factory PitchCarsScale.forPlayers(int players) {
    final n = players.clamp(_fewest, _most).toDouble();
    // 0 at the smallest table this game accepts, 1 at the largest.
    final t = (n - _fewest) / (_most - _fewest);
    return PitchCarsScale._(
      players: players,
      size: _lerp(_sizeAt.$1, _sizeAt.$2, t),
      reach: _lerp(_reachAt.$1, _reachAt.$2, t),
      wander: _lerp(_wanderAt.$1, _wanderAt.$2, t),
      bendsPerPhone: _bendsFor(players),
    );
  }

  // `PitchCarsGame.manifest.players` — the ends this interpolates between.
  static const _fewest = 2;
  static const _most = 8;

  /// Narrow enough at two phones to leave the road somewhere to wander, wide
  /// enough at eight to fill the screen. The upper end is held well under the
  /// phone's own width: a road that spans the whole screen has nowhere left to
  /// bend, and the generator's clamps would quietly flatten it anyway.
  static const _sizeAt = (0.75, 1.45);

  /// The lever that actually shortens a long race. Grows faster than [size]
  /// because it can: a car that flies further is not constrained by the phone
  /// it flies across.
  static const _reachAt = (0.85, 2.4);

  /// A small table has to make its own interest, so the road wanders. A big
  /// one already has corners — the phones give it one at every seam — and
  /// wandering on top of that only adds distance nobody enjoys driving.
  static const _wanderAt = (1.25, 0.4);

  /// Two bends is an S across the phone, and it is the small table's whole
  /// answer to being short. By six the seams are supplying the corners, and
  /// by seven the road is better off going straight and letting them.
  static int _bendsFor(int players) {
    if (players <= 4) return 2;
    if (players <= 6) return 1;
    return 0;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  // ── what the rest of the game reads ─────────────────────────────────────────

  double get trackWidthWorld => PitchCarsConfig.trackWidthWorld * size;

  double get carRadius => PitchCarsConfig.carRadius * size;
  double get carVisualRadius => PitchCarsConfig.carVisualRadius * size;

  /// How near a finger has to land to pick the car up. Scales with the car so
  /// the grab stays the same gesture on any table.
  double get grabSlack => PitchCarsConfig.grabSlack * size;

  /// The draw is a distance on the screen, so it follows [size].
  double get maxPull => PitchCarsConfig.maxPull * size;

  /// The impulse that draw buys, worked back from how far the car should end
  /// up going.
  ///
  /// Not simply `× reach`, because two things move underneath it. An impulse
  /// buys velocity as `J / m`, and the car's mass goes with the square of its
  /// radius — so a car scaled up by [size] is `size²` heavier — while the draw
  /// that produces the impulse has itself grown by [size]. Distance under
  /// linear damping is proportional to that velocity, so
  ///
  ///     distance  ∝  maxPull × impulsePerPull / carRadius²
  ///               ∝  size × impulsePerPull / size²
  ///
  /// which leaves `impulsePerPull ∝ reach × size` as the thing that makes
  /// distance come out proportional to [reach] and nothing else. Getting this
  /// backwards is easy and quiet: `reach / size` reads just as plausibly and
  /// makes the big table's cars *slower* than the small one's.
  double get impulsePerPull => PitchCarsConfig.impulsePerPull * reach * size;

  double get startLaneOffsetWorld =>
      PitchCarsConfig.startLaneOffsetWorld * size;
  double get startRowSpacingWorld =>
      PitchCarsConfig.startRowSpacingWorld * size;

  /// Wander is measured in track widths rather than centimetres, so a narrow
  /// road on a small table gets room to move without the amplitude having to
  /// be re-tuned alongside [size].
  double get lineAmplitudeWorld =>
      PitchCarsConfig.lineAmplitudeWorld * wander * size;
  double get cornerAmplitudeWorld =>
      PitchCarsConfig.cornerAmplitudeWorld * wander * size;

  /// Cars must not spawn on top of each other whatever the table.
  double get minCarGap => carRadius * 2 + 1e-4;

  /// How much road a car loses for being shoved into the void. Measured in
  /// track widths, so it is the same bite out of a lap on any table.
  double get knockBackWorld =>
      trackWidthWorld * PitchCarsConfig.knockBackWidths;

  /// The stall watchdog's threshold, which is a distance and so scales.
  double get stallDisplacement => PitchCarsConfig.stallDisplacement * size;

  /// A car is at rest when it is slower than this. Follows [reach] rather than
  /// [size]: it is a speed, and speeds on a big table are larger throughout.
  double get restSpeed => PitchCarsConfig.restSpeed * math.max(reach, 0.1);
}
