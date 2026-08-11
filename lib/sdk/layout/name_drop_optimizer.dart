import 'dart:math' as math;

import 'board_plan.dart';
import 'phone_spec.dart';

/// Post-processes a [BoardPlan] to reduce iOS NameDrop triggers.
///
/// NameDrop (iOS 17+) fires when the antennas near the **top** of two iPhones
/// are brought together, and puts a Share Contact sheet over the game. The only
/// lever we have is [PhonePlacement.turnDeg]: turning a phone 180° moves its top
/// to what was its bottom, which can put the two dangerous ends apart.
///
/// ## Why the danger zone is a band and not two corners
///
/// This used to score the two *endpoints* of each phone's top edge and count
/// pairs within 15 mm. That measures the wrong thing, and it fails on exactly
/// the tables this platform exists for — ones with mismatched phones.
///
/// Stack phones in a column lying sideways, as Ball Bin does. Each phone's top
/// edge is then a vertical segment down one side, and neighbours' segments are
/// collinear, end to end, separated by
///
///     sqrt(offset² + bezelGap²),   offset = (longSideB − longSideA) / 2
///
/// The bezel gap is a few millimetres and never changes. The offset grows with
/// the *size difference*, so the measured distance between two edges that are
/// physically just as adjacent depends only on how unlike the phones are:
///
///     60 mm + 66 mm phone →  9.0 mm  → caught
///     60 mm + 70 mm       → 12.6 mm  → caught
///     60 mm + 74 mm       → 16.7 mm  → missed
///     60 mm + 80 mm       → 23.0 mm  → missed
///
/// An SE beside a Pro Max is an ordinary pair of phones, and it sailed straight
/// through. Raising the threshold only moves that cliff: the offset has no upper
/// bound, so no radius catches a 60 mm phone next to a 95 mm one while still
/// meaning anything at all.
///
/// So each phone contributes a **band across the top of its body**
/// ([_kAntennaBandMm] deep, the full width of the phone) rather than two points,
/// and a pair is dangerous when the two bands come within [_kProximityMm]. Two
/// tops laid along the same line overlap in projection, so their bands sit the
/// bezel gap apart whatever the size difference. The measurement stops caring
/// how unlike the phones are, which was the bug.
///
/// The margin this leaves is wide rather than marginal: across the arrangements
/// the catalogue produces, dangerous pairs measure under 10 mm and safe ones
/// over 100 mm — a phone that is not top-to-top with its neighbour has a whole
/// phone length between the two bands.
///
/// ## Search
///
/// - N ≤ 8: brute force all 2ᴺ turn combinations (≤256 states).
/// - N > 8: greedy — turn any phone whose individual turn lowers the score.
///
/// The score is the number of dangerous pairs, tie-broken by fewest phones
/// turned from the original plan. If nothing helps, the original plan comes back
/// unchanged: this only ever asks somebody to turn a phone around when doing so
/// actually removes a trigger.
class NameDropOptimizer {
  const NameDropOptimizer._();

  /// How close two antenna bands may come before the pair counts as dangerous.
  ///
  /// Generous on purpose. Phones are put on a table by hand, and the distinction
  /// this has to draw is not a fine one: adjacent tops come out under 10 mm and
  /// everything else in these layouts is over 100 mm.
  static const double _kProximityMm = 20.0;

  /// How far into the body the antennas reach, in from the top edge.
  ///
  /// The NFC coil and the UWB chip sit in the top of the phone across most of
  /// its width, not at its two corners. 20 mm is a deliberately blunt stand-in
  /// for "the top of the phone": what matters is that the region is a band, not
  /// its exact depth.
  static const double _kAntennaBandMm = 20.0;

  static BoardPlan optimize(BoardPlan plan, LobbyInfo lobby) {
    final placements = plan.placements;
    final n = placements.length;
    if (n == 0) return plan;

    final best =
        n <= 8 ? _bruteForce(placements, lobby) : _greedy(placements, lobby);

    if (_listEqual(best, placements)) return plan;

    return BoardPlan(
      best,
      instruction: plan.instruction,
      bounds: plan.bounds,
      allowGaps: plan.allowGaps,
    );
  }

  // ── brute force ─────────────────────────────────────────────────────────────

  static List<PhonePlacement> _bruteForce(
    List<PhonePlacement> placements,
    LobbyInfo lobby,
  ) {
    final n = placements.length;
    int bestScore = _totalScore(placements, lobby);
    int bestFlips = 0;
    List<PhonePlacement> best = placements;

    for (int mask = 1; mask < (1 << n); mask++) {
      final candidate = [
        for (int i = 0; i < n; i++)
          mask & (1 << i) != 0 ? _flip(placements[i]) : placements[i],
      ];
      final score = _totalScore(candidate, lobby);
      final flips = _popcount(mask);
      if (score < bestScore || (score == bestScore && flips < bestFlips)) {
        bestScore = score;
        bestFlips = flips;
        best = candidate;
      }
    }
    return best;
  }

  // ── greedy ───────────────────────────────────────────────────────────────────

  static List<PhonePlacement> _greedy(
    List<PhonePlacement> placements,
    LobbyInfo lobby,
  ) {
    var current = List<PhonePlacement>.of(placements);
    var improved = true;
    while (improved) {
      improved = false;
      for (int i = 0; i < current.length; i++) {
        final candidate = List<PhonePlacement>.of(current);
        candidate[i] = _flip(candidate[i]);
        if (_totalScore(candidate, lobby) < _totalScore(current, lobby)) {
          current = candidate;
          improved = true;
        }
      }
    }
    return current;
  }

  // ── scoring ──────────────────────────────────────────────────────────────────

  /// How many pairs of phones have their tops together.
  ///
  /// One point per pair, not per corner: a pair is either a trigger or it is
  /// not, and counting the corners involved made a head-on pair look worse than
  /// a diagonal one for no physical reason.
  static int _totalScore(List<PhonePlacement> placements, LobbyInfo lobby) {
    int score = 0;
    for (int i = 0; i < placements.length; i++) {
      final specA = lobby.byId(placements[i].phoneId);
      if (specA == null) continue;
      final zoneA = _dangerZone(placements[i], specA);
      for (int j = i + 1; j < placements.length; j++) {
        final specB = lobby.byId(placements[j].phoneId);
        if (specB == null) continue;
        final zoneB = _dangerZone(placements[j], specB);
        if (_polygonDistance(zoneA, zoneB) < _kProximityMm) score++;
      }
    }
    return score;
  }

  // ── geometry ─────────────────────────────────────────────────────────────────

  /// The four corners of the antenna band, in board-mm coordinates.
  ///
  /// In local (portrait, upright) coordinates the band spans the full width and
  /// runs from the top edge at −h/2 inward by [_kAntennaBandMm]. Rotating CW by
  /// θ radians:
  ///   x' = lx·cosθ − ly·sinθ + cx
  ///   y' = lx·sinθ + ly·cosθ + cy
  static List<(double, double)> _dangerZone(
    PhonePlacement p,
    PhoneSpec spec,
  ) {
    final hw = spec.widthMm / 2;
    final hh = spec.heightMm / 2;
    // Never deeper than the phone is long, so a small device does not get a band
    // reaching out through its own far side.
    final depth = math.min(_kAntennaBandMm, spec.heightMm / 2);
    final theta = p.turnRadians;
    final cos = math.cos(theta);
    final sin = math.sin(theta);

    (double, double) rotate(double lx, double ly) => (
      lx * cos - ly * sin + p.xMm,
      lx * sin + ly * cos + p.yMm,
    );

    // Wound in order around the rectangle, so the result is a convex
    // quadrilateral whichever way the phone is turned.
    return [
      rotate(-hw, -hh),
      rotate(hw, -hh),
      rotate(hw, -hh + depth),
      rotate(-hw, -hh + depth),
    ];
  }

  /// Shortest distance between two convex polygons; 0 when they overlap.
  ///
  /// Vertex-to-edge in both directions covers every separated case. The
  /// containment check covers the one case it misses — one band entirely inside
  /// another, which a small phone's top lying within a much larger phone's would
  /// produce. Without it, that pair measures as far apart while sitting on top of
  /// each other.
  static double _polygonDistance(
    List<(double, double)> a,
    List<(double, double)> b,
  ) {
    if (_containsAny(a, b) || _containsAny(b, a)) return 0;

    var best = double.infinity;
    for (final pair in [(a, b), (b, a)]) {
      for (final v in pair.$1) {
        for (var i = 0; i < pair.$2.length; i++) {
          final p1 = pair.$2[i];
          final p2 = pair.$2[(i + 1) % pair.$2.length];
          best = math.min(best, _pointToSegment(v, p1, p2));
        }
      }
    }
    return best;
  }

  /// Whether any vertex of [inner] lies inside convex [outer].
  static bool _containsAny(
    List<(double, double)> outer,
    List<(double, double)> inner,
  ) {
    for (final p in inner) {
      var allLeft = true;
      var allRight = true;
      for (var i = 0; i < outer.length; i++) {
        final a = outer[i];
        final b = outer[(i + 1) % outer.length];
        final cross =
            (b.$1 - a.$1) * (p.$2 - a.$2) - (b.$2 - a.$2) * (p.$1 - a.$1);
        if (cross < 0) allLeft = false;
        if (cross > 0) allRight = false;
      }
      // On the same side of every edge. Checked both ways round so the winding
      // of the quadrilateral does not matter.
      if (allLeft || allRight) return true;
    }
    return false;
  }

  static double _pointToSegment(
    (double, double) p,
    (double, double) a,
    (double, double) b,
  ) {
    final dx = b.$1 - a.$1;
    final dy = b.$2 - a.$2;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq == 0) return _dist(p, a);
    var t = ((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    return _dist(p, (a.$1 + t * dx, a.$2 + t * dy));
  }

  static double _dist((double, double) a, (double, double) b) {
    final dx = a.$1 - b.$1;
    final dy = a.$2 - b.$2;
    return math.sqrt(dx * dx + dy * dy);
  }

  static PhonePlacement _flip(PhonePlacement p) =>
      p.copyWith(turnDeg: (p.turnDeg + 180) % 360);

  // ── helpers ──────────────────────────────────────────────────────────────────

  static bool _listEqual(
    List<PhonePlacement> a,
    List<PhonePlacement> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].turnDeg != b[i].turnDeg || a[i].phoneId != b[i].phoneId) {
        return false;
      }
    }
    return true;
  }

  static int _popcount(int n) {
    int count = 0;
    while (n != 0) {
      count += n & 1;
      n >>= 1;
    }
    return count;
  }
}
