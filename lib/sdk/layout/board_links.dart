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

    // Phones that touch nothing — a ring of them around a table.
    final orphans = slices.where((s) => !joined.contains(s.phoneId)).toList();
    if (orphans.length > 1) {
      final midX =
          slices.map((s) => s.screen.centerX).reduce((a, b) => a + b) /
              slices.length;
      final midY =
          slices.map((s) => s.screen.centerY).reduce((a, b) => a + b) /
              slices.length;

      // Which way to face. Never paired with anyone, so the renderer paints
      // these one neutral colour and they cannot be mistaken for a join.
      for (final slice in orphans) {
        markers.add(_edgeFacing(slice, midX, midY));
      }

      // And who is on your left and right. A stripe pointing at the middle says
      // where to stand but nothing about the order to stand in, which is the
      // one thing a circle of people actually has to agree on. Neighbours here
      // are *near*, not touching — the only difference from a join is the size
      // of the gap, so they earn matching colours the same way.
      for (final (a, b) in _ringPairs(orphans, midX, midY)) {
        markers
          ..add(_edgeAround(a, b, midX, midY, colorIndex, b.phoneId))
          ..add(_edgeAround(b, a, midX, midY, colorIndex, a.phoneId));
        colorIndex++;
      }
    }

    return markers;
  }

  /// The edge of [me] that faces [neighbour] *around* the ring rather than
  /// across it.
  ///
  /// Aiming straight at a neighbour's centre is not good enough, and the reason
  /// is worth keeping: on a circle of three, each neighbour sits only 30° off
  /// the direction of the middle, and on a circle of four, exactly 45°. Picking
  /// an edge by whichever screen axis points most strongly at the target then
  /// chooses the *same* edge for the middle and for both neighbours, and all
  /// three stripes land on top of each other — one visible line per phone,
  /// which is precisely what a real three-phone table showed.
  ///
  /// So the pull toward the middle is removed first, leaving only the part of
  /// the direction that runs along the ring. What is left can only point out of
  /// one of the two edges facing round the circle, whatever the player count.
  static EdgeMarker _edgeAround(
    PhoneSlice me,
    PhoneSlice neighbour,
    double midX,
    double midY,
    int colorIndex,
    String partnerId,
  ) {
    final s = me.screen;
    final toMid = _unit(midX - s.centerX, midY - s.centerY);
    final dx = neighbour.screen.centerX - s.centerX;
    final dy = neighbour.screen.centerY - s.centerY;

    // Strip the radial component; keep the tangential one.
    final radial = dx * toMid.x + dy * toMid.y;
    final aroundX = dx - radial * toMid.x;
    final aroundY = dy - radial * toMid.y;

    // Directly across the ring with nothing to either side — a degenerate
    // board rather than a circle. The plain direction is the best answer left.
    if (aroundX.abs() + aroundY.abs() < _epsilon) {
      return _edgeFacing(me, neighbour.screen.centerX, neighbour.screen.centerY,
          colorIndex: colorIndex, partnerId: partnerId);
    }

    return _edgeFacing(me, s.centerX + aroundX, s.centerY + aroundY,
        colorIndex: colorIndex, partnerId: partnerId);
  }

  static ({double x, double y}) _unit(double x, double y) {
    final len = math.sqrt(x * x + y * y);
    return len < _epsilon ? (x: 0.0, y: 0.0) : (x: x / len, y: y / len);
  }

  /// Consecutive phones around the ring, as pairs, wrapping at the end.
  ///
  /// Ordered by the angle of each screen from the middle of the board, which is
  /// what "sitting next to" means once nothing is touching. Deliberately not a
  /// special case asked for by the game: a circle is simply the arrangement in
  /// which this falls out, and any scattered board would be described the same
  /// way. Two phones facing each other across a table are one pair, not two —
  /// hence the wrap only above three.
  static List<(PhoneSlice, PhoneSlice)> _ringPairs(
    List<PhoneSlice> ring,
    double midX,
    double midY,
  ) {
    if (ring.length < 3) return const [];

    final byAngle = List.of(ring)
      ..sort((a, b) => math
          .atan2(a.screen.centerY - midY, a.screen.centerX - midX)
          .compareTo(
              math.atan2(b.screen.centerY - midY, b.screen.centerX - midX)));

    return [
      for (var i = 0; i < byAngle.length; i++)
        (byAngle[i], byAngle[(i + 1) % byAngle.length]),
    ];
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

  /// The edge of [slice] facing (targetX, targetY), as a world segment.
  ///
  /// Works at any angle: the screen's own axes are projected onto the direction
  /// of the target, and whichever points at it more strongly names the edge.
  /// With no [partnerId] this is the "middle is that way" hint; with one it is
  /// half of a pair, and the phone it points at carries the matching half.
  static EdgeMarker _edgeFacing(
    PhoneSlice slice,
    double targetX,
    double targetY, {
    int colorIndex = 0,
    String? partnerId,
  }) {
    final s = slice.screen;
    final cos = math.cos(s.turnRadians);
    final sin = math.sin(s.turnRadians);
    final ux = cos, uy = sin;
    final vx = -sin, vy = cos;

    final alongU = (targetX - s.centerX) * ux + (targetY - s.centerY) * uy;
    final alongV = (targetX - s.centerX) * vx + (targetY - s.centerY) * vy;

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
      colorIndex: colorIndex,
      partnerId: partnerId,
    );
  }

  static bool _isQuarterTurn(double radians) {
    final quarters = radians / (math.pi / 2);
    return (quarters - quarters.roundToDouble()).abs() < 1e-6;
  }
}
