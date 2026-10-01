import 'dart:math' as math;
import 'dart:typed_data';

import 'board_plan.dart';
import 'phone_spec.dart';

class NameDropOptimizer {
  const NameDropOptimizer._();

  static const double _kProximityMm = 20.0;

  static const double _kAntennaBandMm = 20.0;

  static BoardPlan optimize(BoardPlan plan, LobbyInfo lobby) {
    final placements = plan.placements;
    final n = placements.length;
    if (n == 0) return plan;

    final table = _buildTable(placements, lobby);
    final mask = n <= 8 ? _bruteForce(n, table) : _greedy(n, table);

    if (mask == 0) return plan;

    return BoardPlan(
      [
        for (int i = 0; i < n; i++)
          mask & (1 << i) != 0 ? _flip(placements[i]) : placements[i],
      ],
      instruction: plan.instruction,
      bounds: plan.bounds,
      allowGaps: plan.allowGaps,
    );
  }

  static Set<(String, String)> dangerousPairs(BoardPlan plan, LobbyInfo lobby) {
    final placements = plan.placements;
    final n = placements.length;

    final zones = <List<(double, double)>?>[];
    for (final p in placements) {
      final spec = lobby.byId(p.phoneId);
      zones.add(spec == null ? null : _dangerZone(p, spec));
    }

    final pairs = <(String, String)>{};
    for (int i = 0; i < n; i++) {
      final zonesI = zones[i];
      if (zonesI == null) continue;
      for (int j = i + 1; j < n; j++) {
        final zonesJ = zones[j];
        if (zonesJ == null) continue;
        if (_polygonDistance(zonesI, zonesJ) < _kProximityMm) {
          pairs.add(pairKey(placements[i].phoneId, placements[j].phoneId));
        }
      }
    }
    return pairs;
  }

  static (String, String) pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? (a, b) : (b, a);

  static Uint8List _buildTable(
    List<PhonePlacement> placements,
    LobbyInfo lobby,
  ) {
    final n = placements.length;
    final danger = Uint8List(n * n * 4);

    final zones = <List<List<(double, double)>>?>[];
    for (final p in placements) {
      final spec = lobby.byId(p.phoneId);
      zones.add(
        spec == null
            ? null
            : [_dangerZone(p, spec), _dangerZone(_flip(p), spec)],
      );
    }

    for (int i = 0; i < n; i++) {
      final zonesI = zones[i];
      if (zonesI == null) continue;
      for (int j = i + 1; j < n; j++) {
        final zonesJ = zones[j];
        if (zonesJ == null) continue;
        for (int a = 0; a < 2; a++) {
          for (int b = 0; b < 2; b++) {
            if (_polygonDistance(zonesI[a], zonesJ[b]) < _kProximityMm) {
              danger[((i * n + j) * 2 + a) * 2 + b] = 1;
            }
          }
        }
      }
    }
    return danger;
  }

  static int _scoreOf(int mask, int n, Uint8List table) {
    int score = 0;
    for (int i = 0; i < n; i++) {
      final a = (mask >> i) & 1;
      for (int j = i + 1; j < n; j++) {
        final b = (mask >> j) & 1;
        score += table[((i * n + j) * 2 + a) * 2 + b];
      }
    }
    return score;
  }

  static int _bruteForce(int n, Uint8List table) {
    int bestScore = _scoreOf(0, n, table);
    int bestFlips = 0;
    int best = 0;

    for (int mask = 1; mask < (1 << n); mask++) {
      final score = _scoreOf(mask, n, table);
      final flips = _popcount(mask);
      if (score < bestScore || (score == bestScore && flips < bestFlips)) {
        bestScore = score;
        bestFlips = flips;
        best = mask;
      }
    }
    return best;
  }

  static int _greedy(int n, Uint8List table) {
    var current = 0;
    var improved = true;
    while (improved) {
      improved = false;
      for (int i = 0; i < n; i++) {
        final candidate = current ^ (1 << i);
        if (_scoreOf(candidate, n, table) < _scoreOf(current, n, table)) {
          current = candidate;
          improved = true;
        }
      }
    }
    return current;
  }

  static List<(double, double)> _dangerZone(PhonePlacement p, PhoneSpec spec) {
    final hw = spec.widthMm / 2;
    final hh = spec.heightMm / 2;

    final depth = math.min(_kAntennaBandMm, spec.heightMm / 2);
    final theta = p.turnRadians;
    final cos = math.cos(theta);
    final sin = math.sin(theta);

    (double, double) rotate(double lx, double ly) =>
        (lx * cos - ly * sin + p.xMm, lx * sin + ly * cos + p.yMm);

    return [
      rotate(-hw, -hh),
      rotate(hw, -hh),
      rotate(hw, -hh + depth),
      rotate(-hw, -hh + depth),
    ];
  }

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

  static int _popcount(int n) {
    int count = 0;
    while (n != 0) {
      count += n & 1;
      n >>= 1;
    }
    return count;
  }
}
