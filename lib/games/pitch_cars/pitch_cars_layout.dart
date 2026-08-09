import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../sdk/layout/board_links.dart';
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
  });

  factory _MotifPhone.of(
    PhoneSpec spec,
    double cx,
    double cy,
    bool sideways, {
    int arrivedBy = -1,
  }) =>
      _MotifPhone(
        spec,
        cx,
        cy,
        sideways,
        (sideways ? spec.heightMm : spec.widthMm) / 2,
        (sideways ? spec.widthMm : spec.heightMm) / 2,
        arrivedBy: arrivedBy,
      );

  /// A zero-size phantom anchor for the very first phone of the chain —
  /// heading 0 (right) if it starts sideways, 1 (down) if upright, the same
  /// convention `Layouts.path` falls back to for a phone with no
  /// predecessor.
  factory _MotifPhone.seed(bool sideways) =>
      _MotifPhone(null, 0, 0, sideways, 0, 0, arrivedBy: sideways ? 0 : 1);

  final PhoneSpec? spec;
  final double cx;
  final double cy;
  final bool sideways;
  final double halfW;
  final double halfH;

  /// Which way the chain was travelling when it arrived here — 0 right, 1
  /// down, 2 left, 3 up.
  final int arrivedBy;

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

/// Casings touching: the same gap `Gaps.casingsTouching` computes, kept
/// local rather than imported so this file has no dependency on
/// `layouts.dart` at all. `anchor.spec` is null only for the seed phantom,
/// which has no real casing.
double _gapMm(_MotifPhone anchor, PhoneSpec spec) =>
    (anchor.spec?.bezelMm ?? 0) + spec.bezelMm;

/// Continues straight ahead from [anchor]: same orientation, flush against
/// its far edge, centered on its own line.
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
  );
}

/// A quarter turn off [anchor]'s far end, flush with one of its flanks —
/// [turnRight] picks which. Orientation flips: turning necessarily swaps
/// which of the phone's own edges faces the direction of travel.
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
  final across =
      turnRight ? (halfAcrossNew - acrossAnchor) : (acrossAnchor - halfAcrossNew);
  return _MotifPhone.of(
    spec,
    anchor.cx + a.x * along + c.x * across,
    anchor.cy + a.y * along + c.y * across,
    sideways,
    arrivedBy: newHeading,
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
}) =>
    _placeL(anchor, specs, mirror: mirror);

/// The 3-phone zigzag motif: a straight phone, then two quarter turns in
/// *alternating* directions — two turns the same way would spiral a long
/// chain of staircases back over itself; alternating keeps it a staircase.
List<_MotifPhone> _placeStaircase(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) {
  final p1 = _placeStraight(anchor, specs[0]);
  final p2 = _placeTurn(p1, specs[1], turnRight: mirror);
  final p3 = _placeTurn(p2, specs[2], turnRight: !mirror);
  return [p1, p2, p3];
}

@visibleForTesting
List<_MotifPhone> placeStaircaseForTest(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) =>
    _placeStaircase(anchor, specs, mirror: mirror);

/// A partition of [n] into parts of size 2 or 3, in random order.
///
/// Every count from 2 has at least one such partition (2 = [2], 3 = [3],
/// and every larger n by induction), so this never returns an empty list
/// for `n >= 2`. When more than one partition exists (e.g. n=6: three 2s,
/// or two 3s), one is picked uniformly at random.
List<int> _partSizes(int n, math.Random rng) {
  final options = <List<int>>[];
  for (var threes = 0; threes * 3 <= n; threes++) {
    final remainder = n - threes * 3;
    if (remainder % 2 == 0) {
      final twos = remainder ~/ 2;
      options.add([
        ...List.filled(twos, 2),
        ...List.filled(threes, 3),
      ]);
    }
  }
  final chosen = List.of(options[rng.nextInt(options.length)]);
  chosen.shuffle(rng);
  return chosen;
}

/// Test-only access to [_partSizes] — kept private otherwise, since nothing
/// outside this file needs a partition on its own.
@visibleForTesting
List<int> partSizesForTest(int n, math.Random rng) => _partSizes(n, rng);

/// The 3-phone bridge motif: a straight phone, a gap, another straight
/// phone continuing the same line — with a third phone turned 90° and
/// offset sideways, wide enough to touch both outer phones across the gap
/// without them ever touching each other. This is the shared mechanic
/// behind both the "n-shape" and "T-shape" patterns from the design sketch:
/// which one it looks like falls out of the *incoming heading* alone (legs
/// vertical with a horizontal bridge, or legs horizontal with a vertical
/// one) — there is only one placement function.
///
/// Returns null if the middle phone isn't wide enough, in its short
/// dimension, to keep the outer phones' gap safely past
/// `BoardLinks.maxJoinGap` while still overlapping both of them — an
/// unusually narrow real device, not expected in practice but not asserted
/// away either.
List<_MotifPhone>? _placeBridge(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) {
  final ahead = _headingOf(anchor);
  final vertical = _isVertical(ahead);
  final sideways = anchor.sideways;
  final a = _unitOf(ahead);
  final c = _unitOf((ahead + 3) % 4);

  final specA = specs[0];
  final specB = specs[1];
  final specC = specs[2];
  final legA = _MotifPhone.of(specA, 0, 0, sideways);
  final legC = _MotifPhone.of(specC, 0, 0, sideways);
  final bridge = _MotifPhone.of(specB, 0, 0, !sideways);

  final halfAlongAnchor = vertical ? anchor.halfH : anchor.halfW;
  final halfAlongA = vertical ? legA.halfH : legA.halfW;
  final halfAcrossA = vertical ? legA.halfW : legA.halfH;
  final halfAlongC = vertical ? legC.halfH : legC.halfW;
  final halfAcrossC = vertical ? legC.halfW : legC.halfH;
  final halfAlongB = vertical ? bridge.halfH : bridge.halfW;
  final halfAcrossB = vertical ? bridge.halfW : bridge.halfH;

  // The gap between the two outer phones must clear the join-distance
  // threshold (so BoardLinks never calls them joined), and the middle
  // phone's own width must comfortably span that gap with real overlap on
  // each side (not just a touch), or a "stacked"/"sideBySide" join between
  // it and either outer phone would never register at all.
  const overlapMm = 5.0;
  final reachMm = BoardLinks.maxJoinGap / PlatformConfig.mmToWorld;
  final gapAC = reachMm + 2 * overlapMm;
  if (halfAlongB < gapAC / 2 + overlapMm) return null;

  final alongA = halfAlongAnchor + _gapMm(anchor, specA) + halfAlongA;
  final alongB = alongA + halfAlongA + gapAC / 2;
  final alongC = alongA + halfAlongA + gapAC + halfAlongC;

  final acrossExtent = math.max(halfAcrossA, halfAcrossC);
  final side = mirror ? 1.0 : -1.0;
  final acrossB = side * (acrossExtent + _gapMm(anchor, specB) + halfAcrossB);

  _MotifPhone at(double along, double across, PhoneSpec spec, bool sw) =>
      _MotifPhone.of(
        spec,
        anchor.cx + a.x * along + c.x * across,
        anchor.cy + a.y * along + c.y * across,
        sw,
        arrivedBy: ahead,
      );

  return [
    at(alongA, 0, specA, sideways),
    at(alongB, acrossB, specB, !sideways),
    at(alongC, 0, specC, sideways),
  ];
}

@visibleForTesting
List<_MotifPhone>? placeBridgeForTest(
  _MotifPhone anchor,
  List<PhoneSpec> specs, {
  required bool mirror,
}) =>
    _placeBridge(anchor, specs, mirror: mirror);
