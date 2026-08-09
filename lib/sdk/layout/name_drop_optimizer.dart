import 'dart:math' as math;

import 'board_plan.dart';
import 'phone_spec.dart';

/// Post-processes a [BoardPlan] to reduce iOS NameDrop triggers.
///
/// NameDrop (iOS 17+) fires when the UWB antennas near the top edge of two
/// iPhones come within ~15 mm of each other. The only lever we have is
/// [PhonePlacement.turnDeg]: flipping a phone 180° moves its top edge to what
/// was its bottom, which may separate the danger corners.
///
/// The score to minimise is the count of (cornerA, cornerB) pairs — one corner
/// per phone — that are within [_kProximityMm] of each other. Each phone
/// contributes exactly two danger corners: the endpoints of its physical top
/// edge in board-mm space.
///
/// Algorithm:
/// - N ≤ 8: brute force all 2ᴺ flip combinations (≤256 states).
/// - N > 8: greedy — flip any phone whose individual flip lowers the score.
///
/// Tie-break: fewest flips from the original plan. If nothing helps the score,
/// the original plan is returned unchanged.
class NameDropOptimizer {
  const NameDropOptimizer._();

  static const double _kProximityMm = 15.0;

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

  static int _totalScore(List<PhonePlacement> placements, LobbyInfo lobby) {
    int score = 0;
    for (int i = 0; i < placements.length; i++) {
      final specA = lobby.byId(placements[i].phoneId);
      if (specA == null) continue;
      final cornersA = _dangerCorners(placements[i], specA);
      for (int j = i + 1; j < placements.length; j++) {
        final specB = lobby.byId(placements[j].phoneId);
        if (specB == null) continue;
        final cornersB = _dangerCorners(placements[j], specB);
        score += _pairScore(cornersA, cornersB);
      }
    }
    return score;
  }

  /// Count of corner pairs between phones A and B within the proximity threshold.
  static int _pairScore(
    List<(double, double)> cornersA,
    List<(double, double)> cornersB,
  ) {
    int count = 0;
    for (final a in cornersA) {
      for (final b in cornersB) {
        if (_dist(a, b) < _kProximityMm) count++;
      }
    }
    return count;
  }

  // ── geometry ─────────────────────────────────────────────────────────────────

  /// The two endpoints of the physical top edge in board-mm coordinates.
  ///
  /// In local (portrait, upright) coordinates the top edge runs from
  /// (−w/2, −h/2) to (+w/2, −h/2). Rotating CW by θ radians:
  ///   x' = lx·cosθ − ly·sinθ + cx
  ///   y' = lx·sinθ + ly·cosθ + cy
  static List<(double, double)> _dangerCorners(
    PhonePlacement p,
    PhoneSpec spec,
  ) {
    final hw = spec.widthMm / 2;
    final hh = spec.heightMm / 2;
    final theta = p.turnRadians;
    final cos = math.cos(theta);
    final sin = math.sin(theta);

    (double, double) rotate(double lx, double ly) => (
      lx * cos - ly * sin + p.xMm,
      lx * sin + ly * cos + p.yMm,
    );

    return [rotate(-hw, -hh), rotate(hw, -hh)];
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
