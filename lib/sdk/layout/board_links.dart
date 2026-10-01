import 'dart:math' as math;

import '../contract/sim.dart' show PhoneSlice;

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

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  final int colorIndex;

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

  final String axis;

  final double overlap;

  final double gap;

  final bool joined;

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

class BoardLinks {
  const BoardLinks._();

  static const double maxJoinGap = 4.0;

  static const double _epsilon = 1e-6;

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

    final orphans = slices.where((s) => !joined.contains(s.phoneId)).toList();
    if (orphans.length > 1) {
      final midX =
          slices.map((s) => s.screen.centerX).reduce((a, b) => a + b) /
          slices.length;
      final midY =
          slices.map((s) => s.screen.centerY).reduce((a, b) => a + b) /
          slices.length;

      for (final slice in orphans) {
        markers.add(_edgeFacing(slice, midX, midY));
      }

      for (final (a, b) in _ringPairs(orphans, midX, midY)) {
        markers
          ..add(_edgeAround(a, b, midX, midY, colorIndex, b.phoneId))
          ..add(_edgeAround(b, a, midX, midY, colorIndex, a.phoneId));
        colorIndex++;
      }
    }

    return markers;
  }

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

    final radial = dx * toMid.x + dy * toMid.y;
    final aroundX = dx - radial * toMid.x;
    final aroundY = dy - radial * toMid.y;

    if (aroundX.abs() + aroundY.abs() < _epsilon) {
      return _edgeFacing(
        me,
        neighbour.screen.centerX,
        neighbour.screen.centerY,
        colorIndex: colorIndex,
        partnerId: partnerId,
      );
    }

    return _edgeFacing(
      me,
      s.centerX + aroundX,
      s.centerY + aroundY,
      colorIndex: colorIndex,
      partnerId: partnerId,
    );
  }

  static ({double x, double y}) _unit(double x, double y) {
    final len = math.sqrt(x * x + y * y);
    return len < _epsilon ? (x: 0.0, y: 0.0) : (x: x / len, y: y / len);
  }

  static List<(PhoneSlice, PhoneSlice)> _ringPairs(
    List<PhoneSlice> ring,
    double midX,
    double midY,
  ) {
    if (ring.length < 3) return const [];

    final byAngle = List.of(ring)
      ..sort(
        (a, b) => math
            .atan2(a.screen.centerY - midY, a.screen.centerX - midX)
            .compareTo(
              math.atan2(b.screen.centerY - midY, b.screen.centerX - midX),
            ),
      );

    return [
      for (var i = 0; i < byAngle.length; i++)
        (byAngle[i], byAngle[(i + 1) % byAngle.length]),
    ];
  }

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

    for (final s in [a, b]) {
      if (s.screen.isTurned && !_isQuarterTurn(s.screen.turnRadians)) {
        final deg = s.screen.turnRadians * 180 / math.pi;
        return no(
          'neither',
          0,
          double.infinity,
          '${s.phoneId} is turned ${deg.toStringAsFixed(1)}°',
        );
      }
    }

    final ra = a.viewport;
    final rb = b.viewport;

    final vOverlap = math.min(ra.bottom, rb.bottom) - math.max(ra.top, rb.top);
    if (vOverlap > _epsilon) {
      final gap = separation(ra.left, ra.right, rb.left, rb.right);
      if (gap >= -_epsilon && gap <= maxJoinGap) {
        return LinkVerdict(
          aId: a.phoneId,
          bId: b.phoneId,
          axis: 'sideBySide',
          overlap: vOverlap,
          gap: gap,
          joined: true,
          reason: 'joined',
        );
      }
      return no(
        'sideBySide',
        vOverlap,
        gap,
        'gap ${gap.toStringAsFixed(2)} exceeds '
            '${maxJoinGap.toStringAsFixed(2)}',
      );
    }

    final hOverlap = math.min(ra.right, rb.right) - math.max(ra.left, rb.left);
    if (hOverlap > _epsilon) {
      final gap = separation(ra.top, ra.bottom, rb.top, rb.bottom);
      if (gap >= -_epsilon && gap <= maxJoinGap) {
        return LinkVerdict(
          aId: a.phoneId,
          bId: b.phoneId,
          axis: 'stacked',
          overlap: hOverlap,
          gap: gap,
          joined: true,
          reason: 'joined',
        );
      }
      return no(
        'stacked',
        hOverlap,
        gap,
        'gap ${gap.toStringAsFixed(2)} exceeds '
            '${maxJoinGap.toStringAsFixed(2)}',
      );
    }

    return no('neither', 0, double.infinity, 'no shared edge on either axis');
  }

  static double separation(
    double aLow,
    double aHigh,
    double bLow,
    double bHigh,
  ) => math.max(bLow - aHigh, aLow - bHigh);

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

      final aIsLeft = ra.centerX <= rb.centerX;
      final left = aIsLeft ? ra : rb;
      final right = aIsLeft ? rb : ra;
      return [
        EdgeMarker(
          phoneId: aIsLeft ? a.phoneId : b.phoneId,
          x1: left.right,
          y1: top,
          x2: left.right,
          y2: bottom,
          colorIndex: colorIndex,
          partnerId: aIsLeft ? b.phoneId : a.phoneId,
        ),
        EdgeMarker(
          phoneId: aIsLeft ? b.phoneId : a.phoneId,
          x1: right.left,
          y1: top,
          x2: right.left,
          y2: bottom,
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
        x1: leftEdge,
        y1: upper.bottom,
        x2: rightEdge,
        y2: upper.bottom,
        colorIndex: colorIndex,
        partnerId: aIsUpper ? b.phoneId : a.phoneId,
      ),
      EdgeMarker(
        phoneId: aIsUpper ? b.phoneId : a.phoneId,
        x1: leftEdge,
        y1: lower.top,
        x2: rightEdge,
        y2: lower.top,
        colorIndex: colorIndex,
        partnerId: aIsUpper ? a.phoneId : b.phoneId,
      ),
    ];
  }

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
