import 'dart:math' as math;

import '../../sdk/model/world_rect.dart';

/// Subway Skater's tunables, all in one place.
///
/// World units are centimetres, so every distance here can be checked against a
/// real table with a ruler.
class SubwaySkaterConfig {
  const SubwaySkaterConfig._();

  /// Lanes across the corridor. Three is the number the whole design rests on:
  /// with two, a blocked lane leaves exactly one answer and there is nothing to
  /// decide; with four, a wave that leaves one lane open is unfair to whoever is
  /// standing at the far side of the corridor.
  static const int lanes = 3;

  /// One minute.
  static const double roundSeconds = 60;

  /// How fast the corridor comes at you at the start, in world units per
  /// second.
  ///
  /// This sets the reaction window together with the phone size and
  /// [standFraction]: three fifths of a 15cm phone at this speed is about two
  /// thirds of a second between an obstacle appearing at the top of your screen
  /// and reaching you. From [peakWithSecondsLeft] onward it is nearer a half —
  /// see [endSpeed].
  static const double obstacleSpeed = 14;

  /// The fastest the corridor ever runs.
  ///
  /// It applies to everything in flight at once rather than fixing each block's
  /// speed when it spawns: the corridor is one moving thing, and blocks
  /// travelling at different speeds would slide through each other and turn a
  /// wave with a gap in it into a wall without one.
  ///
  /// ## Why the band is narrow
  ///
  /// This used to run 12 → 22, nearly double, and on a real table the closing
  /// stretch was not hard so much as arbitrary. The arithmetic says why: at 22
  /// the reaction window is about four tenths of a second, and by the time a
  /// person has seen a block, decided a lane and got a thumb moving, most of
  /// that is gone. Everyone died at roughly the same rate whatever they did,
  /// which reads as the game stopping rather than as a climax.
  ///
  /// So the two ends were brought toward each other — the top down, and the
  /// opening up to keep the first twenty seconds from feeling slack next to it.
  /// Half a second at the peak is still fast, and it is enough to act on.
  ///
  /// The round does not lose its build for this. Most of the pressure was never
  /// in the speed: [firstSpawnGap] to [lastSpawnGap] more than halves the room
  /// between waves, and [firstDoubleChance] to [lastDoubleChance] takes
  /// two-lane waves from rare to better than even. Those keep tightening
  /// through the plateau, and they tighten what a player has to *decide* rather
  /// than how fast they have to twitch.
  static const double endSpeed = 18;

  /// The corridor hits [endSpeed] with this long still to run, and holds it
  /// there to the finish.
  ///
  /// The wind-up is the first two thirds and the last third is flat out. A ramp
  /// that only arrived at full speed on the final second would mean nobody ever
  /// played at it: the top speed would be a number in a config file rather than
  /// twenty seconds everybody remembers. The waves keep tightening through the
  /// plateau, so the closing stretch still builds — on spacing rather than on
  /// pace, which is a different kind of pressure and lands after players have
  /// had time to find the rhythm of the fast corridor.
  static const double peakWithSecondsLeft = 20;

  /// How long the wind-up lasts.
  static const double rampSeconds = roundSeconds - peakWithSecondsLeft;

  /// How fast the corridor is running [elapsed] seconds in.
  static double speedAt(double elapsed) {
    final t = (elapsed / rampSeconds).clamp(0.0, 1.0);
    return obstacleSpeed + (endSpeed - obstacleSpeed) * t;
  }

  /// How far the corridor has travelled by [elapsed] — the integral of
  /// [speedAt], and the only reason it exists in closed form: the lane markings
  /// scroll by this, and a view that added up [speedAt] frame by frame would
  /// drift out of step with the phone beside it.
  static double travelAt(double elapsed) {
    final winding = elapsed.clamp(0.0, rampSeconds);
    final ramped =
        obstacleSpeed * winding +
        (endSpeed - obstacleSpeed) * winding * winding / (2 * rampSeconds);
    final flatOut = elapsed > rampSeconds
        ? (elapsed - rampSeconds) * endSpeed
        : 0.0;
    return ramped + flatOut;
  }

  /// Seconds between waves, at the start of the round and at the end of it.
  /// It tightens all the way through, so the last ten seconds are the ones that
  /// scramble the order.
  static const double firstSpawnGap = 1.9;
  static const double lastSpawnGap = 0.85;

  /// How likely a wave blocks two lanes rather than one, start and end.
  /// Never three: a wave you cannot dodge is not a wave, it is a tax.
  static const double firstDoubleChance = 0.1;
  static const double lastDoubleChance = 0.55;

  /// Quiet at the start, so the table can find its own circle before the first
  /// thing comes at it.
  static const double leadInSeconds = 1.6;

  /// The skater's circle.
  static const double skaterRadius = 0.85;

  /// The obstacle, along the corridor and across a lane.
  static const double obstacleLength = 1.8;
  static const double obstacleLaneFraction = 0.7;

  /// Where a skater stands on its own phone, measured from the top of the
  /// corridor — the edge obstacles arrive at — as a fraction of that phone.
  ///
  /// Three fifths down, so a bit more than half the screen is runway: an
  /// obstacle appears at the top of the phone and has that much to cross before
  /// it reaches the person standing on it. The same fraction of the same phone
  /// for everybody, which is what makes the warning equal wherever in the line
  /// you happen to be — and the remaining two fifths is the room the tumble
  /// needs to read as a tumble rather than as a circle vanishing off the edge.
  static const double standFraction = 3 / 5;

  /// How far a finger has to travel across the corridor to move a lane. Each
  /// further stride of this much in the same drag moves another.
  static const double swipeThreshold = 0.8;

  /// How fast a skater slides across to the lane it has committed to. Fast
  /// enough that the swipe and the dodge read as one action; slow enough that
  /// the hop can still be seen from the far end of the table.
  static const double laneChangeSpeed = 20;

  /// How fast the line closes up when somebody ahead is knocked out — a whole
  /// phone in about a third of a second.
  static const double climbSpeed = 48;

  /// Which way is up the corridor, as an entity angle.
  ///
  /// Obstacles travel towards `+x` and the front of the line is the low end, so
  /// facing the way you are going means facing `-x`. Everybody stands like this
  /// for the whole round; the only time an angle is anything else is mid-tumble.
  static const double facingAngle = math.pi;

  /// How fast a skater turns back to [facingAngle] once a tumble lets go —
  /// about half a turn in a quarter of a second.
  ///
  /// A spin that simply stopped left the character looking at a wall for the
  /// rest of the round, and one that snapped back on the frame it landed threw
  /// away the end of the tumble. This finishes the spin the way it was going,
  /// only decelerating into forward.
  static const double rightingSpeed = 12;

  /// A tumble lasts until the obstacle carrying it passes the back of the line,
  /// but never less than this. Without a floor, the player already *at* the back
  /// would be knocked and released on the same tick and taken straight out by
  /// the rest of the same wave.
  static const double minTumbleSeconds = 0.4;

  /// And never more than this, whatever the arithmetic says.
  static const double maxTumbleSeconds = 8;

  /// Untouchable for this long after landing, so a wave cannot pick somebody off
  /// twice on the way past.
  static const double graceSeconds = 0.8;

  /// What a player gets for climbing a place: this long untouchable, and
  /// smashing anything they run into for the same second.
  ///
  /// Longer than the climb itself, deliberately. The climb alone was already
  /// safe — you cannot be hit off your post while you are not on it — so an
  /// immunity that ended on arrival would have been worth nothing. This one
  /// outlasts the sprint and arrives with you, which is what makes moving up
  /// the line feel like being handed something rather than merely surviving.
  static const double chargeSeconds = 1.0;

  /// Obstacles in the pool. An eight-phone corridor is 120cm long and holds
  /// about a dozen in flight; the rest is headroom.
  static const int obstaclePool = 32;

  /// How long the shatter left behind by a flattened block lasts.
  ///
  /// Short: it is a punctuation mark on a hit that already happened, and
  /// anything longer would still be on screen when the next block arrives.
  static const double burstSeconds = 0.35;

  /// Shatters in flight at once. Smashes come at most a few a second across the
  /// whole table and each lasts a third of one.
  static const int burstPool = 12;

  /// The middle of [lane], in world units.
  static double laneCenter(WorldRect board, int lane) =>
      board.top + board.height * (lane + 0.5) / lanes;

  static double laneHeight(WorldRect board) => board.height / lanes;

  /// Which lane a world position falls in.
  static int laneAt(WorldRect board, double y) {
    final t = (y - board.top) / board.height * lanes;
    return t.floor().clamp(0, lanes - 1);
  }
}
