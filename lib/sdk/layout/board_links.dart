import 'dart:math' as math;

import '../contract/sim.dart' show PhoneSlice;

/// A coloured stripe along part of one screen's edge, marking where that screen
/// meets — or faces — another.
///
/// Two phones sharing a join get two markers with the same [colorIndex], one on
/// each of their touching edges. Put the phones down so the matching colours
/// line up and the board is correct.
///
/// The segment covers only the **overlap** with the neighbour, not the whole
/// edge. A deep phone beside a shallow one marks just the shallow one's extent,
/// which is exactly the length you are trying to align.
class EdgeMarker {
  const EdgeMarker({
    required this.phoneId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.colorIndex,
    this.partnerId,
  });

  final String phoneId;

  /// The segment, in world coordinates.
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Which colour to use. An index rather than a colour because picking colours
  /// is the renderer's business, not the geometry's.
  final int colorIndex;

  /// The phone on the other side. Null for a ring marker, where nothing is
  /// touching and the stripe only says "the middle is this way".
  final String? partnerId;

  bool get isJoin => partnerId != null;

  Map<String, dynamic> toJson() => {
    'phoneId': phoneId,
    'x1': x1,
    'y1': y1,
    'x2': x2,
    'y2': y2,
    'c': colorIndex,
    if (partnerId != null) 'with': partnerId,
  };

  static EdgeMarker fromJson(Map<String, dynamic> j) => EdgeMarker(
    phoneId: j['phoneId'] as String,
    x1: (j['x1'] as num).toDouble(),
    y1: (j['y1'] as num).toDouble(),
    x2: (j['x2'] as num).toDouble(),
    y2: (j['y2'] as num).toDouble(),
    colorIndex: (j['c'] as num).toInt(),
    partnerId: j['with'] as String?,
  );
}

/// Why one pair of screens was, or was not, treated as joined.
///
/// Every pair produces one of these, joined or not. The markers are *derived*
/// from these verdicts rather than computed separately, so there is exactly one
/// decision path — which means a stripe cannot exist that no verdict explains,
/// and a board that looks wrong can be interrogated instead of reverse
/// engineered from a screenshot.
class LinkVerdict {
  const LinkVerdict({
    required this.aId,
    required this.bId,
    required this.axis,
    required this.overlap,
    required this.gap,
    required this.joined,
    required this.reason,
  });

  final String aId;
  final String bId;

  /// 'sideBySide', 'stacked', or 'neither'.
  final String axis;

  /// How much edge the two screens share, in world units. The length a stripe
  /// would be.
  final double overlap;

  /// The clear distance between them along the axis they are separated on.
  /// Double.infinity when they are not separated on either axis.
  final double gap;

  final bool joined;

  /// Plain English: 'joined', 'gap 4.20 exceeds 4.00', 'no shared edge on
  /// either axis', 'p2 is turned 72.0°'.
  final String reason;

  Map<String, dynamic> toJson() => {
    'a': aId,
    'b': bId,
    'axis': axis,
    'overlap': double.parse(overlap.toStringAsFixed(3)),
    'gap': gap.isFinite ? double.parse(gap.toStringAsFixed(3)) : null,
    'joined': joined,
    'reason': reason,
  };
}

/// Works out where every screen meets its neighbours.
///
/// **The single home for this.** It runs once, on the host, inside the board
/// compiler, and the result travels with the layout — so two phones can never
/// disagree about which edge is red. No game participates: it falls out of the
/// compiled geometry alone, which is also why one rule covers rows, columns,
/// grids and rings without naming any of them.
class BoardLinks {
  const BoardLinks._();

  /// Screens further apart than this are not joined. A join is a gap you could
  /// close by pushing two phones together — two bezels' worth — not a span of
  /// open table.
  ///
  /// **The single definition of "neighbouring".** `BoardCompiler` derives its
  /// connectivity check from this exact number, and that matters: the two used
  /// to disagree (30mm here, 40mm there), which left a window where a board
  /// passed validation but produced no joins at all. Every phone then fell
  /// through to an inward stripe and the whole table came out one colour —
  /// silently, with nothing to indicate anything had gone wrong.
  ///
  /// 4.0 world units is 40mm: generous enough for two chunky bezels, and
  /// anything wider is now a loud validation error rather than a quiet
  /// mis-colouring.
  static const double maxJoinGap = 4.0;

  static const double _epsilon = 1e-6;

  /// Every pair, judged. The source of truth; [of] is derived from it.
  static List<LinkVerdict> explain(List<PhoneSlice> slices) {
    final verdicts = <LinkVerdict>[];
    for (var i = 0; i < slices.length; i++) {
      for (var j = i + 1; j < slices.length; j++) {
        verdicts.add(_judge(slices[i], slices[j]));
      }
    }
    return verdicts;
  }

  static List<EdgeMarker> of(List<PhoneSlice> slices) {
    final markers = <EdgeMarker>[];
    final joined = <String>{};
    var colorIndex = 0;

    // Verdicts come in board order, so the same board always produces the same
    // colours.
    for (final verdict in explain(slices)) {
      if (!verdict.joined) continue;
      final a = slices.firstWhere((s) => s.phoneId == verdict.aId);
      final b = slices.firstWhere((s) => s.phoneId == verdict.bId);
      markers.addAll(_markersFor(a, b, verdict, colorIndex));
      joined
        ..add(verdict.aId)
        ..add(verdict.bId);
      colorIndex++;
    }

    // Anything touching nothing — a ring of phones around a table — gets a
    // single stripe on the edge facing the middle. There is no partner to match
    // colours with, so they all share one.
    final orphans = slices.where((s) => !joined.contains(s.phoneId)).toList();
    if (orphans.length > 1) {
      final midX =
          slices.map((s) => s.screen.centerX).reduce((a, b) => a + b) /
              slices.length;
      final midY =
          slices.map((s) => s.screen.centerY).reduce((a, b) => a + b) /
              slices.length;
      for (final slice in orphans) {
        markers.add(_inwardEdge(slice, midX, midY));
      }
    }

    return markers;
  }

  /// The one place a pair's fate is decided.
  static LinkVerdict _judge(PhoneSlice a, PhoneSlice b) {
    LinkVerdict no(String axis, double overlap, double gap, String reason) =>
        LinkVerdict(
          aId: a.phoneId,
          bId: b.phoneId,
          axis: axis,
          overlap: overlap,
          gap: gap,
          joined: false,
          reason: reason,
        );

    // A join only exists between screens square to each other; for those the
    // bounding box *is* the screen.
    for (final s in [a, b]) {
      if (s.screen.isTurned && !_isQuarterTurn(s.screen.turnRadians)) {
        final deg = s.screen.turnRadians * 180 / math.pi;
        return no('neither', 0, double.infinity,
            '${s.phoneId} is turned ${deg.toStringAsFixed(1)}°');
      }
    }

    final ra = a.viewport;
    final rb = b.viewport;

    // Side by side: the shared run is the vertical overlap.
    final vOverlap = math.min(ra.bottom, rb.bottom) - math.max(ra.top, rb.top);
    if (vOverlap > _epsilon) {
      final gap = separation(ra.left, ra.right, rb.left, rb.right);
      if (gap >= -_epsilon && gap <= maxJoinGap) {
        return LinkVerdict(
          aId: a.phoneId, bId: b.phoneId, axis: 'sideBySide',
          overlap: vOverlap, gap: gap, joined: true, reason: 'joined',
        );
      }
      return no('sideBySide', vOverlap, gap,
          'gap ${gap.toStringAsFixed(2)} exceeds '
          '${maxJoinGap.toStringAsFixed(2)}');
    }

    // Stacked: the shared run is the horizontal overlap.
    final hOverlap = math.min(ra.right, rb.right) - math.max(ra.left, rb.left);
    if (hOverlap > _epsilon) {
      final gap = separation(ra.top, ra.bottom, rb.top, rb.bottom);
      if (gap >= -_epsilon && gap <= maxJoinGap) {
        return LinkVerdict(
          aId: a.phoneId, bId: b.phoneId, axis: 'stacked',
          overlap: hOverlap, gap: gap, joined: true, reason: 'joined',
        );
      }
      return no('stacked', hOverlap, gap,
          'gap ${gap.toStringAsFixed(2)} exceeds '
          '${maxJoinGap.toStringAsFixed(2)}');
    }

    return no('neither', 0, double.infinity, 'no shared edge on either axis');
  }

  /// Clear distance between two intervals on one axis. Positive when apart,
  /// negative by the depth when they overlap. Unit-agnostic, so the compiler
  /// uses it on millimetres and [_judge] on world units.
  ///
  /// Deliberately branch-free. This used to ask "is A before B?" and subtract
  /// accordingly, which is correct right up until the two edges are *equal* —
  /// exactly what happens when both phones report a 0mm bezel and the compiler
  /// lays them flush. Then a rounding error in the last bit of a double decided
  /// the branch, and losing that coin flip subtracted the far edges instead of
  /// the near ones: a gap of 0 came out as -23.6, wildly "exceeding" the limit,
  /// and two touching phones were declared strangers. Taking the larger of both
  /// differences needs no such decision — for separated intervals only one is
  /// positive, and for touching ones both agree on zero.
  static double separation(
    double aLow,
    double aHigh,
    double bLow,
    double bHigh,
  ) =>
      math.max(bLow - aHigh, aLow - bHigh);

  /// The two stripes for a joined pair, on their facing edges.
  static List<EdgeMarker> _markersFor(
    PhoneSlice a,
    PhoneSlice b,
    LinkVerdict verdict,
    int colorIndex,
  ) {
    final ra = a.viewport;
    final rb = b.viewport;

    if (verdict.axis == 'sideBySide') {
      final top = math.max(ra.top, rb.top);
      final bottom = math.min(ra.bottom, rb.bottom);
      // Centres, not edges: for flush phones the facing edges are equal and a
      // comparison between them is a coin flip, which would paint the stripe on
      // the far side of one phone. Centres are unambiguous whenever the two are
      // separated on this axis at all — which, on this branch, they are.
      final aIsLeft = ra.centerX <= rb.centerX;
      final left = aIsLeft ? ra : rb;
      final right = aIsLeft ? rb : ra;
      return [
        EdgeMarker(
          phoneId: aIsLeft ? a.phoneId : b.phoneId,
          x1: left.right, y1: top, x2: left.right, y2: bottom,
          colorIndex: colorIndex,
          partnerId: aIsLeft ? b.phoneId : a.phoneId,
        ),
        EdgeMarker(
          phoneId: aIsLeft ? b.phoneId : a.phoneId,
          x1: right.left, y1: top, x2: right.left, y2: bottom,
          colorIndex: colorIndex,
          partnerId: aIsLeft ? a.phoneId : b.phoneId,
        ),
      ];
    }

    final leftEdge = math.max(ra.left, rb.left);
    final rightEdge = math.min(ra.right, rb.right);
    final aIsUpper = ra.centerY <= rb.centerY;
    final upper = aIsUpper ? ra : rb;
    final lower = aIsUpper ? rb : ra;
    return [
      EdgeMarker(
        phoneId: aIsUpper ? a.phoneId : b.phoneId,
        x1: leftEdge, y1: upper.bottom, x2: rightEdge, y2: upper.bottom,
        colorIndex: colorIndex,
        partnerId: aIsUpper ? b.phoneId : a.phoneId,
      ),
      EdgeMarker(
        phoneId: aIsUpper ? b.phoneId : a.phoneId,
        x1: leftEdge, y1: lower.top, x2: rightEdge, y2: lower.top,
        colorIndex: colorIndex,
        partnerId: aIsUpper ? a.phoneId : b.phoneId,
      ),
    ];
  }

  /// The edge of [slice] facing (midX, midY), as a world segment. Works at any
  /// angle: the screen's own axes are projected onto the direction of the
  /// middle, and whichever points at it more strongly names the edge.
  static EdgeMarker _inwardEdge(PhoneSlice slice, double midX, double midY) {
    final s = slice.screen;
    final cos = math.cos(s.turnRadians);
    final sin = math.sin(s.turnRadians);
    final ux = cos, uy = sin;
    final vx = -sin, vy = cos;

    final alongU = (midX - s.centerX) * ux + (midY - s.centerY) * uy;
    final alongV = (midX - s.centerX) * vx + (midY - s.centerY) * vy;

    final hw = s.width / 2;
    final hh = s.height / 2;

    final double outX, outY, runX, runY, runHalf;
    if (alongU.abs() >= alongV.abs()) {
      final sign = alongU >= 0 ? 1.0 : -1.0;
      outX = ux * hw * sign;
      outY = uy * hw * sign;
      runX = vx;
      runY = vy;
      runHalf = hh;
    } else {
      final sign = alongV >= 0 ? 1.0 : -1.0;
      outX = vx * hh * sign;
      outY = vy * hh * sign;
      runX = ux;
      runY = uy;
      runHalf = hw;
    }

    return EdgeMarker(
      phoneId: slice.phoneId,
      x1: s.centerX + outX - runX * runHalf,
      y1: s.centerY + outY - runY * runHalf,
      x2: s.centerX + outX + runX * runHalf,
      y2: s.centerY + outY + runY * runHalf,
      colorIndex: 0,
    );
  }

  static bool _isQuarterTurn(double radians) {
    final quarters = radians / (math.pi / 2);
    return (quarters - quarters.roundToDouble()).abs() < 1e-6;
  }
}
