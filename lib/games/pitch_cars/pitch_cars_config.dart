import '../../sdk/audio/sound_cue.dart';

/// Tunables for Pitch Cars, kept as plain data next to the game that uses
/// them — none of this is the platform's business.
class PitchCarsConfig {
  const PitchCarsConfig._();
  static const double trackWidthWorld = 3.0;

  static const double lineAmplitudeWorld = 3.0;

  /// A deliberate, tuned hook rather than a subtle wiggle.
  ///
  /// `Layouts.path` joins two phones corner to corner and never along a whole
  /// edge, so a corner's geometry sits inside a known range rather than being
  /// anything at all — which is what lets this be generous instead of
  /// conservative.
  static const double cornerAmplitudeWorld = 1.8;

  /// How many points the Catmull-Rom spline is sampled at between each
  /// pair of control points — `PitchTrack.waypoints`'s density.
  static const int splineSamplesPerSegment = 8;

  static const double carRadius = 0.25;

  static const double carVisualRadius = 0.25;

  static const double startLaneOffsetWorld = 0.65;

  static const double startRowSpacingWorld = 1.4;

  static const double carDensity = 4.0;
  static const double carRestitution = 0.5;
  static const double carFriction = 0.3;

  static const double carLinearDamping = 1.0;

  static const double carAngularDamping = 2.0;

  static const double stallDisplacement = 0.1;
  static const Duration stallTimeout = Duration(seconds: 2);

  static const double grabSlack = 1.0;

  /// How long a car knocked off the road is left to sail into the void before
  /// it is put back.
  ///
  /// The reset used to be instant — off the edge and back on it in the same
  /// tick — which read as the car *stopping* at the edge rather than going
  /// over it. Nobody could see they had knocked anybody anywhere.
  ///
  /// As long as the [falling] sound, so the car comes back as the sound ends
  /// rather than reappearing on the road while it is still whistling down.
  /// Nothing waits on the sound itself — this is only the same length.
  static const double fallSeconds = 2.0;

  /// How fast a falling car spins, in turns per second: tumbling, not just
  /// shrinking.
  static const double fallSpinTurnsPerSecond = 1.2;

  /// How far behind the sim the fall's shrink-and-fade is played, to match
  /// the phones' own lag: they draw positions `SnapshotBuffer.interpDelayMs`
  /// in the past, but apply shared state the moment it lands. Unlagged, the
  /// fade ran ahead of the picture — and at the end the car came back at full
  /// size out in the void, 80 ms before it jumped home, which read as a slide.
  static const double fallVisualLagSeconds = 0.08;

  /// Kept invisible a little past the lag before being shown again, so a
  /// late snapshot cannot flash the car at its last spot in the void.
  static const double fallVisualMarginSeconds = 0.05;

  /// How far back down the road a knocked-off car returns, in track widths.
  ///
  /// In widths rather than centimetres so it costs the same fraction of a lap
  /// on any table — see [PitchCarsScale].
  ///
  /// This is the whole point of being able to shove somebody: before it, a car
  /// pushed off came back exactly where it had been standing, so a hit cost its
  /// victim nothing at all and there was no reason to aim at anyone.
  static const double knockBackWidths = 1.2;

  static const double maxPull = 3.0;

  /// A draw shorter than this fraction of [maxPull] is a tap, not a shot: the
  /// car stays put and the turn is not consumed.
  ///
  /// A fraction rather than a distance, so cancelling is the same *gesture* on
  /// a narrow table as on a wide one. Generous on purpose — a shot can now be
  /// aimed from anywhere on the board, and backing out of one you did not mean
  /// to start should not require the finger to come back to within a hair of
  /// where it landed. The view reads the same number, so the aim arrow appears
  /// exactly when the release would actually fire.
  static const double cancelPullFraction = 0.12;

  static const double impulsePerPull = 5.5;
  static const double restSpeed = 0.3;
  static const Duration restDelay = Duration(milliseconds: 600);

  /// Below this many times [restSpeed], a car stops coasting and brakes.
  ///
  /// Damping alone slows a car in proportion to its speed, so the last stretch
  /// is a long creep: a car that was all but stopped slid on for another
  /// second, and the turn waited on it. Under this, friction is replaced by a
  /// steady brake that takes it to a dead stop in [brakeSeconds].
  static const double brakeBelowRestSpeeds = 3;
  static const double brakeSeconds = 0.15;
  static const Duration maxFlightTime = Duration(seconds: 6);
  static const Duration hitGraceWindow = Duration(milliseconds: 250);

  static const int colorTrack = 0xFF2E4057;

  /// The road surface, as one entity carrying the whole centerline.
  ///
  /// Its props deliberately do **not** include `ShapeProps.shape`, so
  /// `ShapeView.renderEntities` skips it — a stroked polyline is this game's
  /// shape, not a platform primitive, and `PitchCarsView` is the only thing
  /// that knows how to draw it. That is the same door `EntityDescriptor.kind`
  /// already opens for game-defined entities.
  static const String ribbonKind = 'trackRibbon';

  /// The centerline as a flat `[x0,y0,x1,y1,…]`, in coordinates local to the
  /// entity — the same convention a radius or a width follows.
  static const String ribbonPoints = 'pts';

  /// Stroke width, which is the track's full width: half of it either side of
  /// the centerline is precisely what `PitchTrack.isOnTrack` allows.
  static const String ribbonWidth = 'ribbonW';
  static const String ribbonColor = 'ribbonColor';

  /// A barrier on the outside of a bend. Drawn exactly like [ribbonKind] — same
  /// props, same stroked polyline — because it *is* one, just thinner and
  /// brighter and with a physics chain behind it.
  static const String wallKind = 'trackWall';

  /// How thick a wall is drawn, as a fraction of the road's width. The physics
  /// chain has no thickness at all; this is only so the barrier reads as a kerb
  /// rather than as a hairline.
  static const double wallThicknessFraction = 0.14;

  static const int colorWall = 0xFFE8B04B;

  /// Bouncy enough to send a car back into the road rather than parking it
  /// against the kerb, short of the trampoline that full restitution makes of
  /// a corner.
  static const double wallRestitution = 0.45;

  /// Low, so a car that meets the wall at a shallow angle slides along it and
  /// carries on round the bend instead of stopping dead where it touched.
  static const double wallFriction = 0.05;

  static const int finishLineCols = 6;
  static const int finishLineRows = 4;
  static const int finishLineColorA = 0xFF000000;
  static const int finishLineColorB = 0xFFFFFFFF;

  /// One square of the finish checkerboard, as a filled quad whose four
  /// corners ride [ribbonPoints] — bent to follow the road rather than a box
  /// laid flat along a single tangent, which on a curved finish would stick
  /// out past the tarmac.
  static const String finishTileKind = 'finishTile';

  /// On a tile past the road's end, the round cap it must stay inside, as
  /// `[x, y, r]` in world coordinates: the tile is drawn clipped to that disc.
  static const String finishClip = 'clip';

  // -- sound ------------------------------------------------------------------
  //
  // Each plays on one phone only, the one where it happened. Leveled copies of
  // audio-src/originals/games/pitch_cars/.

  /// An aim begins, on the phone the finger came down on. Cut short with a
  /// quick fade if the finger lifts before it has finished.
  static const hold = SoundCue.asset('assets/games/pitch_cars/hold.wav');
  static const holdFadeOut = Duration(milliseconds: 120);

  /// A shot fired, on the phone it was aimed from. Not for a release inside
  /// the cancel zone, which fires nothing.
  static const shot = SoundCue.asset('assets/games/pitch_cars/shot.wav');

  /// A car going over the edge, on the phone it went over from.
  static const falling = SoundCue.asset('assets/games/pitch_cars/falling.wav');

  /// A car hitting a wall or another car, on the phone under the impact.
  static const crash = SoundCue.asset('assets/games/pitch_cars/crash.wav');

  /// How fast two things must be closing for their touch to be a crash, as a
  /// multiple of the rest speed. Below it is a car nudging a kerb or settling
  /// against a neighbour, and a crash sound for that would be constant.
  static const double crashSpeedFactor = 5.0;

  /// Well under the rest: it is the one sound here with a hard attack, and at
  /// full level it drowns everything else on that phone.
  static const double crashVolume = 0.35;

  /// After a crash, how long before another can sound. One impact is often a
  /// few contacts in quick succession — a car glancing off a kerb touches it,
  /// leaves, and touches again — and each would otherwise be its own bang.
  static const double crashCooldownSeconds = 0.1;
}
