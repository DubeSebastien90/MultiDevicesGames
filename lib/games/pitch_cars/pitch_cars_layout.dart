import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../sdk/layout/board_links.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/phone_spec.dart';
import '../../sdk/platform_config.dart';

/// One phone placed by the motif builder, in board millimetres.
///
/// [spec] is null only for the synthetic seed anchor that starts the very
/// first motif — it is never included in a finished board, only used to
/// give that first motif something to attach to, mirroring how the real
/// first phone in a chain has no predecessor of its own.
class _MotifPhone {
  const _MotifPhone(
    this.spec,
    this.cx,
    this.cy,
    this.sideways,
    this.halfW,
    this.halfH, {
    this.arrivedBy = -1,
    this.flushRight,
  });

  factory _MotifPhone.of(
    PhoneSpec spec,
    double cx,
    double cy,
    bool sideways, {
    int arrivedBy = -1,
    bool? flushRight,
  }) => _MotifPhone(
    spec,
    cx,
    cy,
    sideways,
    (sideways ? spec.heightMm : spec.widthMm) / 2,
    (sideways ? spec.widthMm : spec.heightMm) / 2,
    arrivedBy: arrivedBy,
    flushRight: flushRight,
  );

  factory _MotifPhone.seed(bool sideways) =>
      _MotifPhone(null, 0, 0, sideways, 0, 0, arrivedBy: sideways ? 0 : 1);

  final PhoneSpec? spec;
  final double cx;
  final double cy;
  final bool sideways;
  final double halfW;
  final double halfH;

  final int arrivedBy;

  /// Which flank of its own anchor this phone flushed against, if it was
  /// placed by a turn (null for the seed and for straight-placed phones
  /// that never made that choice themselves). The next turn off of this
  /// phone reads it to flush the *opposite* way — see [_placeTurn].
  final bool? flushRight;

  double get left => cx - halfW;
  double get right => cx + halfW;
  double get top => cy - halfH;
  double get bottom => cy + halfH;

  bool overlaps(_MotifPhone o) {
    const skin = 0.01;
    return left < o.right - skin &&
        o.left < right - skin &&
        top < o.bottom - skin &&
        o.top < bottom - skin;
  }

  @visibleForTesting
  bool overlapsForTest(_MotifPhone o) => overlaps(o);
}

@visibleForTesting
_MotifPhone seedPhoneForTest({required bool sideways}) =>
    _MotifPhone.seed(sideways);

int _headingOf(_MotifPhone anchor) =>
    anchor.arrivedBy >= 0 ? anchor.arrivedBy : (anchor.sideways ? 0 : 1);

bool _isVertical(int heading) => heading == 1 || heading == 3;

({double x, double y}) _unitOf(int heading) => switch (heading) {
  0 => (x: 1.0, y: 0.0),
  1 => (x: 0.0, y: 1.0),
  2 => (x: -1.0, y: 0.0),
  _ => (x: 0.0, y: -1.0),
};

double _gapMm(_MotifPhone anchor, PhoneSpec spec) =>
    (anchor.spec?.bezelMm ?? 0) + spec.bezelMm;

_MotifPhone _placeStraight(_MotifPhone anchor, PhoneSpec spec) {
  final ahead = _headingOf(anchor);
  final sideways = anchor.sideways;
  final a = _unitOf(ahead);
  final halfAlongAnchor = _isVertical(ahead) ? anchor.halfH : anchor.halfW;
  final candidate = _MotifPhone.of(spec, 0, 0, sideways);
  final halfAlongNew = _isVertical(ahead) ? candidate.halfH : candidate.halfW;
  final along = halfAlongAnchor + _gapMm(anchor, spec) + halfAlongNew;
  return _MotifPhone.of(
    spec,
    anchor.cx + a.x * along,
    anchor.cy + a.y * along,
    sideways,
    arrivedBy: ahead,
    flushRight: anchor.flushRight,
  );
}

_MotifPhone _placeTurn(
  _MotifPhone anchor,
  PhoneSpec spec, {
  required bool turnRight,
}) {
  final ahead = _headingOf(anchor);
  final newHeading = turnRight ? (ahead + 1) % 4 : (ahead + 3) % 4;
  final sideways = !anchor.sideways;
  final a = _unitOf(ahead);
  final c = _unitOf((ahead + 3) % 4);
  final halfAlongAnchor = _isVertical(ahead) ? anchor.halfH : anchor.halfW;
  final acrossAnchor = _isVertical(ahead) ? anchor.halfW : anchor.halfH;
  final candidate = _MotifPhone.of(spec, 0, 0, sideways);
  final halfAlongNew = _isVertical(ahead) ? candidate.halfH : candidate.halfW;
  final halfAcrossNew = _isVertical(ahead) ? candidate.halfW : candidate.halfH;
  final along = halfAlongAnchor + _gapMm(anchor, spec) + halfAlongNew;
  // The anchor's own flush side, opposed — not `turnRight` — so that a
  // second turn (or a turn after a straight hand-off from an earlier one)
  // lands on the *opposite* flank instead of the same one, spreading a
  // chain's seams across each phone's full diagonal instead of clustering
  // them into one corner. `turnRight` still decides the heading alone, so
  // the anti-spiral alternation between motifs is untouched. Only the very
  // first turn off the seed has no prior side to oppose, and falls back to
  // `turnRight` as before.
  final flush = anchor.flushRight == null ? turnRight : !anchor.flushRight!;
  final across = flush
      ? (halfAcrossNew - acrossAnchor)
      : (acrossAnchor - halfAcrossNew);
  return _MotifPhone.of(
    spec,
    anchor.cx + a.x * along + c.x * across,
    anchor.cy + a.y * along + c.y * across,
    sideways,
    arrivedBy: newHeading,
    flushRight: flush,
  );
}

/// The 2-phone motif: a straight phone into a single quarter turn.
List<_MotifPhone> _placeL(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) {
  final p1 = _placeStraight(anchor, specs[0]);
  final p2 = _placeTurn(p1, specs[1], turnRight: mirror);
  return [p1, p2];
}

@visibleForTesting
List<_MotifPhone> placeLForTest(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) => _placeL(anchor, specs, mirror: mirror);

List<_MotifPhone> _placeStaircase(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) {
  final p1 = _placeStraight(anchor, specs[0]);
  final p2 = _placeTurn(p1, specs[1], turnRight: mirror);
  final provisional = _placeTurn(p2, specs[2], turnRight: !mirror);

  final vertical = _isVertical(p1.arrivedBy);
  final rawGap = vertical ? provisional.cy - p1.cy : provisional.cx - p1.cx;
  final halfExtentP1 = vertical ? p1.halfH : p1.halfW;
  final halfExtentP3 = vertical ? provisional.halfH : provisional.halfW;
  const clearanceMarginMm = 5.0;
  final extra = math.max(
    0.0,
    halfExtentP1 + halfExtentP3 + clearanceMarginMm - rawGap.abs(),
  );

  if (extra == 0.0) return [p1, p2, provisional];

  final push = rawGap.sign * extra;
  final p3 = _MotifPhone.of(
    specs[2],
    provisional.cx + (vertical ? 0.0 : push),
    provisional.cy + (vertical ? push : 0.0),
    provisional.sideways,
    arrivedBy: provisional.arrivedBy,
  );
  return [p1, p2, p3];
}

@visibleForTesting
List<_MotifPhone> placeStaircaseForTest(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) => _placeStaircase(anchor, specs, mirror: mirror);

List<int> _partSizes(int n, math.Random rng) {
  final options = <List<int>>[];
  for (var threes = 0; threes * 3 <= n; threes++) {
    final remainder = n - threes * 3;
    if (remainder % 2 == 0) {
      final twos = remainder ~/ 2;
      options.add([...List.filled(twos, 2), ...List.filled(threes, 3)]);
    }
  }
  final chosen = List.of(options[rng.nextInt(options.length)]);
  chosen.shuffle(rng);
  return chosen;
}

@visibleForTesting
List<int> partSizesForTest(int n, math.Random rng) => _partSizes(n, rng);

bool _wouldJoin(_MotifPhone a, _MotifPhone b) {
  final reachMm = BoardLinks.maxJoinGap / PlatformConfig.mmToWorld;
  final vOverlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (vOverlap > 0) {
    final gap = math.max(b.left - a.right, a.left - b.right);
    if (gap <= reachMm) return true;
  }
  final hOverlap = math.min(a.right, b.right) - math.max(a.left, b.left);
  if (hOverlap > 0) {
    final gap = math.max(b.top - a.bottom, a.top - b.bottom);
    if (gap <= reachMm) return true;
  }
  return false;
}

bool _fits(
  List<_MotifPhone> candidates,
  List<_MotifPhone> placedSoFar,
  _MotifPhone anchor,
) {
  for (var i = 0; i < candidates.length; i++) {
    final candidate = candidates[i];
    for (final existing in placedSoFar) {
      if (candidate.overlaps(existing)) return false;
      final isIntendedLink = i == 0 && identical(existing, anchor);
      if (!isIntendedLink && _wouldJoin(candidate, existing)) return false;
    }
    for (var j = i + 1; j < candidates.length; j++) {
      final isAdjacent = j == i + 1;
      if (!isAdjacent && _wouldJoin(candidate, candidates[j])) return false;
    }
  }
  return true;
}

List<_MotifPhone>? _pushedClear(
  _MotifPhone anchor,
  List<_MotifPhone> candidates,
  List<_MotifPhone> placedSoFar,
) {
  final ahead = _headingOf(anchor);
  final unit = _unitOf(ahead);
  final reachMm = BoardLinks.maxJoinGap / PlatformConfig.mmToWorld;
  const marginMm = 5.0;
  final budget = reachMm - _gapMm(anchor, candidates[0].spec!) - marginMm;
  if (budget <= 0) return null;

  final shifted = [
    for (final p in candidates)
      _MotifPhone.of(
        p.spec!,
        p.cx + unit.x * budget,
        p.cy + unit.y * budget,
        p.sideways,
        arrivedBy: p.arrivedBy,
        flushRight: p.flushRight,
      ),
  ];
  return _fits(shifted, placedSoFar, anchor) ? shifted : null;
}

List<_MotifPhone>? _placeSlot(
  _MotifPhone anchor,
  List<PhoneSpec> specs,
  List<_MotifPhone> placedSoFar,
  math.Random rng,
) {
  final mirrors = [true, false]..shuffle(rng);

  if (specs.length == 2) {
    for (final mirror in mirrors) {
      final candidate = _placeL(anchor, specs, mirror: mirror);
      if (_fits(candidate, placedSoFar, anchor)) return candidate;
      final pushed = _pushedClear(anchor, candidate, placedSoFar);
      if (pushed != null) return pushed;
    }
    return null;
  }

  for (final mirror in mirrors) {
    final candidate = _placeStaircase(anchor, specs, mirror: mirror);
    if (_fits(candidate, placedSoFar, anchor)) return candidate;
    final pushed = _pushedClear(anchor, candidate, placedSoFar);
    if (pushed != null) return pushed;
  }
  return null;
}

@visibleForTesting
List<_MotifPhone>? placeSlotForTest(
  _MotifPhone anchor,
  List<PhoneSpec> specs,
  List<_MotifPhone> placedSoFar,
  math.Random rng,
) => _placeSlot(anchor, specs, placedSoFar, rng);

@visibleForTesting
bool fitsForTest(
  List<_MotifPhone> candidates,
  List<_MotifPhone> placedSoFar,
  _MotifPhone anchor,
) => _fits(candidates, placedSoFar, anchor);

@visibleForTesting
_MotifPhone motifPhoneForTest({
  required double cx,
  required double cy,
  required bool sideways,
  required double halfW,
  required double halfH,
}) => _MotifPhone(null, cx, cy, sideways, halfW, halfH);

List<PhonePlacement>? _tryBuild(List<PhoneSpec> ordered, math.Random rng) {
  final shuffled = List.of(ordered)..shuffle(rng);
  final parts = _partSizes(shuffled.length, rng);
  final seedSideways = rng.nextBool();
  var cursor = _MotifPhone.seed(seedSideways);
  final placed = <_MotifPhone>[];
  var index = 0;

  for (final size in parts) {
    final specs = shuffled.sublist(index, index + size);
    index += size;
    final result = _placeSlot(cursor, specs, placed, rng);
    if (result == null) return null;
    placed.addAll(result);
    cursor = result.last;
  }

  final minX = placed.map((p) => p.left).reduce(math.min);
  final minY = placed.map((p) => p.top).reduce(math.min);
  return [
    for (final p in placed)
      PhonePlacement(
        p.spec!.phoneId,
        xMm: p.cx - minX,
        yMm: p.cy - minY,
        turnDeg: p.sideways ? 90 : 0,
      ),
  ];
}

class PitchCarsLayout {
  const PitchCarsLayout._();

  static BoardPlan motifChain(
    List<PhoneSpec> phones, {
    math.Random? random,
    String? instruction,
  }) {
    if (phones.length < 2) {
      throw const BoardPlanError('a motif chain needs at least two phones');
    }
    final rng = random ?? math.Random();
    const maxAttempts = 50;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final result = _tryBuild(phones, rng);
      if (result != null) {
        return BoardPlan(
          result,
          instruction:
              instruction ??
              'Lay the phones out to match the coloured edges — the track '
                  'winds along it, start to finish.',
        );
      }
    }
    throw const BoardPlanError(
      'could not place phones into a motif chain without overlap',
    );
  }
}
