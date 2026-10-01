import 'dart:math' as math;

import '../platform_config.dart';
import 'board_links.dart';
import 'board_plan.dart';
import 'phone_spec.dart';

class PhoneSort {
  const PhoneSort(this.compare, this.description);

  final Comparator<PhoneSpec> compare;

  final String description;

  static const joinOrder = PhoneSort(_noop, 'in the order you joined');

  static const smallestFirst = PhoneSort(
    _bySizeAscending,
    'smallest screen first',
  );
  static const largestFirst = PhoneSort(
    _bySizeDescending,
    'largest screen first',
  );
  static const smallestLast = PhoneSort(
    _bySizeDescending,
    'smallest screen last',
  );
  static const largestLast = PhoneSort(_bySizeAscending, 'largest screen last');

  static PhoneSort by(Comparator<PhoneSpec> compare, {String? description}) =>
      PhoneSort(compare, description ?? 'in a custom order');

  static int _noop(PhoneSpec a, PhoneSpec b) => 0;
  static int _bySizeAscending(PhoneSpec a, PhoneSpec b) =>
      a.areaMm2.compareTo(b.areaMm2);
  static int _bySizeDescending(PhoneSpec a, PhoneSpec b) =>
      b.areaMm2.compareTo(a.areaMm2);
}

class Gaps {
  const Gaps._(this._mmBetween, this.description);

  final double Function(PhoneSpec before, PhoneSpec after) _mmBetween;
  final String description;

  double between(PhoneSpec before, PhoneSpec after) =>
      _mmBetween(before, after);

  static const casingsTouching = Gaps._(_bothBezels, 'casings touching');

  static const flush = Gaps._(_zero, 'screens flush');

  static Gaps of(double mm) =>
      Gaps._((_, _) => mm, '${mm.toStringAsFixed(0)}mm apart');

  static double _bothBezels(PhoneSpec a, PhoneSpec b) => a.bezelMm + b.bezelMm;
  static double _zero(PhoneSpec a, PhoneSpec b) => 0;
}

enum PhoneOrientation { sideways, upright }

extension PhoneOrientationTurn on PhoneOrientation {
  double get turnDeg => this == PhoneOrientation.sideways ? 90 : 0;
}

enum CrossAlign { start, center, end }

enum RingFacing { tangential, radial }

class Layouts {
  const Layouts._();

  static BoardPlan row(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    CrossAlign align = CrossAlign.start,
    PhoneOrientation orientation = PhoneOrientation.sideways,
    String? instruction,
  }) => _pack(
    phones,
    horizontal: true,
    sort: sort,
    gap: gap,
    align: align,
    orientation: orientation,
    instruction: instruction ?? _instructionFor(true, orientation, align),
  );

  static BoardPlan column(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    CrossAlign align = CrossAlign.start,
    PhoneOrientation orientation = PhoneOrientation.sideways,
    String? instruction,
  }) => _pack(
    phones,
    horizontal: false,
    sort: sort,
    gap: gap,
    align: align,
    orientation: orientation,
    instruction: instruction ?? _instructionFor(false, orientation, align),
  );

  static BoardPlan circle(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,
    RingFacing facing = RingFacing.tangential,
    double spacing = 0.6,
    double? radiusMm,
    String? instruction,
  }) {
    if (phones.length < 3) {
      throw const BoardPlanError(
        'a circle needs at least 3 phones — with two you are just facing each '
        'other',
      );
    }

    final ordered = List.of(phones)..sort(sort.compare);
    final count = ordered.length;

    final tangential = facing == RingFacing.tangential;
    final alongRim = ordered
        .map((p) => tangential ? p.heightMm : p.widthMm)
        .reduce(math.max);
    final acrossRim = ordered
        .map((p) => tangential ? p.widthMm : p.heightMm)
        .reduce(math.max);
    final neededChord = alongRim * (1 + spacing);

    final fitted = neededChord / (2 * math.sin(math.pi / count));

    final radius = radiusMm ?? math.max(fitted, acrossRim * 1.2);

    final placements = <PhonePlacement>[];
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i) / count;
      placements.add(
        PhonePlacement(
          ordered[i].phoneId,
          xMm: radius * math.cos(angle),
          yMm: radius * math.sin(angle),
          turnDeg: angle * 180 / math.pi + (tangential ? 180 : 90),
          hint: _ringHint(i, count),
        ),
      );
    }

    return BoardPlan(
      placements,
      allowGaps: true,
      instruction:
          instruction ??
          'Sit in a circle and put your phone on the table in front of you, '
              'screen facing you. $count phones, evenly spaced.',
    );
  }

  static String _ringHint(int index, int count) {
    if (index == 0) return 'at the top of the circle';
    final oClock = (index * 12 / count).round() % 12;
    return '${oClock == 0 ? 12 : oClock} o\'clock in the circle';
  }

  static BoardPlan grid(
    List<PhoneSpec> phones, {
    required int rows,
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    PhoneOrientation orientation = PhoneOrientation.upright,
    bool seamAlign = true,
    String? instruction,
  }) {
    if (phones.isEmpty) {
      throw const BoardPlanError('no phones to place');
    }
    if (rows < 1) {
      throw BoardPlanError('a grid needs at least one row, not $rows');
    }
    if (phones.length % rows != 0) {
      throw BoardPlanError(
        'a grid of $rows rows needs a multiple of $rows phones, '
        'not ${phones.length}',
      );
    }

    final ordered = List.of(phones)..sort(sort.compare);
    final columns = ordered.length ~/ rows;
    final turn = orientation.turnDeg;
    final sideways = orientation == PhoneOrientation.sideways;

    double widthOf(PhoneSpec p) => sideways ? p.heightMm : p.widthMm;
    double heightOf(PhoneSpec p) => sideways ? p.widthMm : p.heightMm;

    PhoneSpec at(int row, int column) => ordered[row * columns + column];

    final rowDepths = [
      for (var r = 0; r < rows; r++)
        [for (var c = 0; c < columns; c++) heightOf(at(r, c))].reduce(math.max),
    ];

    final rowGaps = [
      for (var r = 0; r < rows - 1; r++)
        [
          for (var c = 0; c < columns; c++) gap.between(at(r, c), at(r + 1, c)),
        ].reduce(math.max),
    ];

    final rowTops = <double>[];
    var y = 0.0;
    for (var r = 0; r < rows; r++) {
      rowTops.add(y);
      y += rowDepths[r];
      if (r < rows - 1) y += rowGaps[r];
    }
    final totalDepth = y;

    final rowLefts = <List<double>>[];
    for (var r = 0; r < rows; r++) {
      final lefts = <double>[];
      var x = 0.0;
      for (var c = 0; c < columns; c++) {
        lefts.add(x);
        x += widthOf(at(r, c));
        if (c < columns - 1) x += gap.between(at(r, c), at(r, c + 1));
      }
      rowLefts.add(lefts);
    }

    double seamOf(int r, int k) =>
        (rowLefts[r][k] + widthOf(at(r, k)) + rowLefts[r][k + 1]) / 2;

    if (columns > 1) {
      final reference = [
        for (var k = 0; k < columns - 1; k++)
          [
                for (var r = 0; r < rows; r++) seamOf(r, k),
              ].fold<double>(0, (sum, v) => sum + v) /
              rows,
      ];

      for (var r = 0; r < rows; r++) {
        var drift = 0.0;
        for (var k = 0; k < columns - 1; k++) {
          drift += reference[k] - seamOf(r, k);
        }
        final shift = drift / (columns - 1);
        for (var c = 0; c < columns; c++) {
          rowLefts[r][c] += shift;
        }
      }
    } else {
      final widest = [
        for (var r = 0; r < rows; r++) widthOf(at(r, 0)),
      ].reduce(math.max);
      for (var r = 0; r < rows; r++) {
        rowLefts[r][0] = (widest - widthOf(at(r, 0))) / 2;
      }
    }

    final placements = <PhonePlacement>[];

    var playLeft = double.negativeInfinity;
    var playRight = double.infinity;

    for (var c = 0; c < columns; c++) {
      for (var r = 0; r < rows; r++) {
        final spec = at(r, c);
        final w = widthOf(spec);
        final h = heightOf(spec);
        final left = rowLefts[r][c];

        final double top;
        if (!seamAlign || rows == 1) {
          top = rowTops[r];
        } else if (r == 0) {
          top = rowTops[r] + (rowDepths[r] - h);
        } else if (r == rows - 1) {
          top = rowTops[r];
        } else {
          top = rowTops[r] + (rowDepths[r] - h) / 2;
        }

        placements.add(
          PhonePlacement(
            spec.phoneId,
            xMm: left + w / 2,
            yMm: top + h / 2,
            turnDeg: turn,
            hint: _gridHint(r, c, rows, columns),
          ),
        );

        if (c == 0 && left > playLeft) playLeft = left;
        if (c == columns - 1 && left + w < playRight) playRight = left + w;
      }
    }

    return BoardPlan(
      placements,
      instruction: instruction ?? _gridInstruction(rows, columns, orientation),
      bounds: BoardBoundsMm(
        leftMm: playLeft,
        topMm: 0,
        widthMm: playRight - playLeft,
        heightMm: totalDepth,
      ),
    );
  }

  static BoardPlan brick(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    PhoneOrientation orientation = PhoneOrientation.sideways,
    String? instruction,
  }) {
    if (phones.length < 2) {
      throw BoardPlanError(
        'a brick layout needs at least two phones, not ${phones.length}',
      );
    }

    final ordered = List.of(phones)..sort(sort.compare);
    final topCount = (ordered.length + 1) ~/ 2;
    final rows = [ordered.sublist(0, topCount), ordered.sublist(topCount)];
    final turn = orientation.turnDeg;
    final sideways = orientation == PhoneOrientation.sideways;

    double widthOf(PhoneSpec p) => sideways ? p.heightMm : p.widthMm;
    double heightOf(PhoneSpec p) => sideways ? p.widthMm : p.heightMm;

    double rowWidth(List<PhoneSpec> row) {
      var w = 0.0;
      for (var i = 0; i < row.length; i++) {
        w += widthOf(row[i]);
        if (i < row.length - 1) w += gap.between(row[i], row[i + 1]);
      }
      return w;
    }

    final widths = [for (final row in rows) rowWidth(row)];
    final widest = math.max(widths[0], widths[1]);
    final topDepth = rows[0].map(heightOf).reduce(math.max);

    final lefts = <List<double>>[];
    for (var r = 0; r < 2; r++) {
      final row = <double>[];
      var x = (widest - widths[r]) / 2;
      for (var c = 0; c < rows[r].length; c++) {
        row.add(x);
        x += widthOf(rows[r][c]);
        if (c < rows[r].length - 1) {
          x += gap.between(rows[r][c], rows[r][c + 1]);
        }
      }
      lefts.add(row);
    }
    var seam = 0.0;
    for (var a = 0; a < rows[0].length; a++) {
      for (var b = 0; b < rows[1].length; b++) {
        final aLeft = lefts[0][a];
        final bLeft = lefts[1][b];
        final overlap =
            math.min(aLeft + widthOf(rows[0][a]), bLeft + widthOf(rows[1][b])) -
            math.max(aLeft, bLeft);
        if (overlap > 0) {
          seam = math.max(seam, gap.between(rows[0][a], rows[1][b]));
        }
      }
    }

    final placements = <PhonePlacement>[];
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final spec = rows[r][c];
        final w = widthOf(spec);
        final h = heightOf(spec);

        final top = r == 0 ? topDepth - h : topDepth + seam;
        placements.add(
          PhonePlacement(
            spec.phoneId,
            xMm: lefts[r][c] + w / 2,
            yMm: top + h / 2,
            turnDeg: turn,
            hint: _brickHint(r, c, rows[0].length, rows[1].length),
          ),
        );
      }
    }

    return BoardPlan(
      placements,
      instruction:
          instruction ??
          _brickInstruction(rows[0].length, rows[1].length, orientation),
    );
  }

  static List<PhoneSpec> shortestLast(List<PhoneSpec> phones) {
    if (phones.isEmpty) return const [];
    var shortest = 0;
    for (var i = 1; i < phones.length; i++) {
      if (phones[i].heightMm < phones[shortest].heightMm) shortest = i;
    }
    return [
      for (var i = 0; i < phones.length; i++)
        if (i != shortest) phones[i],
      phones[shortest],
    ];
  }

  static String _brickHint(int row, int column, int top, int bottom) {
    if (row == 0) {
      if (top == 1) return 'top row';
      return 'top row, ${column + 1} of $top from the left';
    }

    if (top == bottom + 1) {
      return 'bottom row, centred across the join of phones '
          '${column + 1} and ${column + 2}';
    }
    if (bottom == 1) return 'bottom row, centred';
    return 'bottom row, ${column + 1} of $bottom from the left';
  }

  static String _brickInstruction(
    int top,
    int bottom,
    PhoneOrientation orientation,
  ) {
    final pose = orientation == PhoneOrientation.sideways
        ? 'on their sides'
        : 'upright';
    return 'Two rows $pose, $top on top and $bottom below, long edges '
        'touching — each phone below centred across a join above.';
  }

  static String _gridHint(int row, int column, int rows, int columns) {
    final rowWord = rows == 2
        ? (row == 0 ? 'top row' : 'bottom row')
        : 'row ${row + 1} of $rows';
    if (columns == 1) return rowWord;
    return '$rowWord, ${column + 1} of $columns from the left';
  }

  static String _gridInstruction(
    int rows,
    int columns,
    PhoneOrientation orientation,
  ) {
    final pose = orientation == PhoneOrientation.sideways
        ? 'on their sides'
        : 'upright';
    if (rows == 2) {
      return 'Two rows facing each other, $pose, long edges touching — '
          '$columns phone(s) per row.';
    }
    return 'A block $columns wide and $rows deep, $pose, edges touching.';
  }

  static BoardPlan path(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    math.Random? random,
    String? instruction,
  }) {
    if (phones.isEmpty) {
      throw const BoardPlanError('no phones to place');
    }

    final rng = random ?? math.Random();
    final ordered = List.of(phones)..sort(sort.compare);

    List<_LaidPhone>? laid;
    for (var attempt = 0; attempt < _pathAttempts && laid == null; attempt++) {
      laid = _walkPath(ordered, rng, gap);
    }
    if (laid == null) {
      throw BoardPlanError(
        'could not lay ${ordered.length} phones into a path where each one '
        'meets only the phone before it',
      );
    }

    final minX = laid.map((l) => l.left).reduce(math.min);
    final minY = laid.map((l) => l.top).reduce(math.min);

    return BoardPlan(
      [
        for (var i = 0; i < laid.length; i++)
          PhonePlacement(
            laid[i].spec.phoneId,
            xMm: laid[i].cx - minX,
            yMm: laid[i].cy - minY,
            turnDeg: laid[i].sideways ? 90 : 0,
            hint: i == 0 ? 'the start of the path' : 'against phone $i',
          ),
      ],
      instruction:
          instruction ??
          'Lay the phones out in a path, each against the last — '
              'match the coloured edges.',
    );
  }

  static const int _pathAttempts = 60;

  static List<_LaidPhone>? _walkPath(
    List<PhoneSpec> ordered,
    math.Random rng,
    Gaps gap,
  ) {
    final laid = <_LaidPhone>[_LaidPhone(ordered.first, 0, 0, rng.nextBool())];

    for (var i = 1; i < ordered.length; i++) {
      final next = _attach(ordered[i], laid, rng, gap);
      if (next == null) return null;
      laid.add(next);
    }
    return laid;
  }

  static _LaidPhone? _attach(
    PhoneSpec spec,
    List<_LaidPhone> laid,
    math.Random rng,
    Gaps gap,
  ) {
    {
      final anchor = laid.last;
      final options = _sevenWays(anchor, spec, gap)..shuffle(rng);

      for (final candidate in options) {
        if (laid.any(candidate.overlaps)) continue;

        if (laid.any((other) => _sharesAWholeLength(candidate, other))) {
          continue;
        }

        if (laid.any(
          (other) => !identical(other, anchor) && candidate.touches(other),
        )) {
          continue;
        }
        return candidate;
      }
    }
    return null;
  }

  static List<_LaidPhone> _sevenWays(
    _LaidPhone anchor,
    PhoneSpec spec,
    Gaps gap,
  ) {
    final ahead = anchor.arrivedBy >= 0
        ? anchor.arrivedBy
        : (anchor.sideways ? 0 : 1);
    final left = (ahead + 3) % 4;
    final right = (ahead + 1) % 4;

    final between = gap.between(anchor.spec, spec);
    final straight = _LaidPhone(spec, 0, 0, anchor.sideways);
    final turned = _LaidPhone(spec, 0, 0, !anchor.sideways);

    _LaidPhone at(_LaidPhone shape, double along, double across, int heading) {
      final a = _unitOf(ahead);
      final c = _unitOf((ahead + 3) % 4);
      return _LaidPhone(
        spec,
        anchor.cx + a.x * along + c.x * across,
        anchor.cy + a.y * along + c.y * across,
        shape.sideways,
        arrivedBy: heading,
      );
    }

    double halfAlong(_LaidPhone p) => _isVertical(ahead) ? p.halfH : p.halfW;
    double halfAcross(_LaidPhone p) => _isVertical(ahead) ? p.halfW : p.halfH;

    final aAlong = halfAlong(anchor);
    final aAcross = halfAcross(anchor);

    final endAlong = aAlong + between;

    final sideAcross = aAcross + between;

    return [
      at(
        straight,
        endAlong + halfAlong(straight),
        aAcross - halfAcross(straight),
        ahead,
      ),
      at(
        straight,
        endAlong + halfAlong(straight),
        halfAcross(straight) - aAcross,
        ahead,
      ),
      at(
        turned,
        endAlong + halfAlong(turned),
        aAcross - halfAcross(turned),
        right,
      ),
      at(
        turned,
        endAlong + halfAlong(turned),
        halfAcross(turned) - aAcross,
        left,
      ),
      at(
        turned,
        aAlong - halfAlong(turned),
        sideAcross + halfAcross(turned),
        left,
      ),
      at(
        turned,
        aAlong - halfAlong(turned),
        -sideAcross - halfAcross(turned),
        right,
      ),
      at(straight, aAlong, sideAcross + halfAcross(straight), ahead),
      at(straight, aAlong, -sideAcross - halfAcross(straight), ahead),
    ];
  }

  static bool _sharesAWholeLength(_LaidPhone a, _LaidPhone b) {
    const skin = 0.5;

    final apart = math.max(b.left - a.right, a.left - b.right);
    final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (apart.abs() < skin && overlap > skin) {
      return overlap > math.max(a.longEdge, b.longEdge) - skin;
    }

    final apartY = math.max(b.top - a.bottom, a.top - b.bottom);
    final overlapX = math.min(a.right, b.right) - math.max(a.left, b.left);
    if (apartY.abs() < skin && overlapX > skin) {
      return overlapX > math.max(a.longEdge, b.longEdge) - skin;
    }
    return false;
  }

  static bool _isVertical(int side) => side == 1 || side == 3;

  static ({double x, double y}) _unitOf(int side) => switch (side) {
    0 => (x: 1.0, y: 0.0),
    1 => (x: 0.0, y: 1.0),
    2 => (x: -1.0, y: 0.0),
    _ => (x: 0.0, y: -1.0),
  };

  static BoardPlan _pack(
    List<PhoneSpec> phones, {
    required bool horizontal,
    required PhoneSort sort,
    required Gaps gap,
    required CrossAlign align,
    required PhoneOrientation orientation,
    required String instruction,
  }) {
    if (phones.isEmpty) {
      throw const BoardPlanError('no phones to place');
    }

    final ordered = List.of(phones)..sort(sort.compare);
    final turn = orientation.turnDeg;
    final sideways = orientation == PhoneOrientation.sideways;

    double footprintAlong(PhoneSpec p) => horizontal
        ? (sideways ? p.heightMm : p.widthMm)
        : (sideways ? p.widthMm : p.heightMm);
    double footprintAcross(PhoneSpec p) => horizontal
        ? (sideways ? p.widthMm : p.heightMm)
        : (sideways ? p.heightMm : p.widthMm);

    final lane = ordered.map(footprintAcross).reduce(math.max);

    double offsetFor(double size) => switch (align) {
      CrossAlign.start => 0.0,
      CrossAlign.center => (lane - size) / 2,
      CrossAlign.end => lane - size,
    };

    final placements = <PhonePlacement>[];
    var cursor = 0.0;

    var bandStart = double.negativeInfinity;
    var bandEnd = double.infinity;

    for (var i = 0; i < ordered.length; i++) {
      final p = ordered[i];
      final across = footprintAcross(p);
      final along = footprintAlong(p);
      final offset = offsetFor(across);

      if (offset > bandStart) bandStart = offset;
      if (offset + across < bandEnd) bandEnd = offset + across;

      placements.add(
        PhonePlacement(
          p.phoneId,
          xMm: horizontal ? cursor + along / 2 : offset + across / 2,
          yMm: horizontal ? offset + across / 2 : cursor + along / 2,
          turnDeg: turn,
          hint: _hintFor(i, ordered.length, horizontal),
        ),
      );

      cursor += along;
      if (i < ordered.length - 1) {
        cursor += gap.between(p, ordered[i + 1]);
      }
    }

    final depth = bandEnd - bandStart;
    return BoardPlan(
      placements,
      instruction: instruction,
      bounds: BoardBoundsMm(
        leftMm: horizontal ? 0 : bandStart,
        topMm: horizontal ? bandStart : 0,
        widthMm: horizontal ? cursor : depth,
        heightMm: horizontal ? depth : cursor,
      ),
    );
  }

  static String _hintFor(int index, int total, bool horizontal) {
    if (total == 1) return 'alone — the whole board is on this screen';
    if (horizontal) {
      if (index == 0) return 'leftmost — everyone else goes to your right';
      return 'right of phone $index, top edges aligned';
    }
    if (index == 0) return 'top — everyone else goes below you';
    return 'below phone $index, left edges aligned';
  }

  static String _instructionFor(
    bool horizontal,
    PhoneOrientation orientation,
    CrossAlign align,
  ) {
    final sideways = orientation == PhoneOrientation.sideways;
    final touching = (horizontal == sideways) ? 'short' : 'long';
    final pose = sideways ? 'on their sides' : 'upright';
    final verb = horizontal
        ? 'Lay the phones $pose side by side in a row'
        : 'Stack the phones $pose one above the other';
    return '$verb, $touching edges touching, '
        '${_alignWord(align, horizontal)}.';
  }

  static String _alignWord(CrossAlign align, bool horizontal) =>
      switch ((align, horizontal)) {
        (CrossAlign.start, true) => 'top edges flush',
        (CrossAlign.end, true) => 'bottom edges flush',
        (CrossAlign.start, false) => 'left edges flush',
        (CrossAlign.end, false) => 'right edges flush',
        (CrossAlign.center, _) => 'centred on each other',
      };
}

class _LaidPhone {
  const _LaidPhone(
    this.spec,
    this.cx,
    this.cy,
    this.sideways, {
    this.arrivedBy = -1,
  });

  final PhoneSpec spec;
  final double cx;
  final double cy;
  final bool sideways;

  final int arrivedBy;

  double get halfW => (sideways ? spec.heightMm : spec.widthMm) / 2;
  double get halfH => (sideways ? spec.widthMm : spec.heightMm) / 2;

  double get longEdge => math.max(spec.widthMm, spec.heightMm);

  double get left => cx - halfW;
  double get right => cx + halfW;
  double get top => cy - halfH;
  double get bottom => cy + halfH;

  bool touches(_LaidPhone o) {
    final apartX = math.max(o.left - right, left - o.right);
    final apartY = math.max(o.top - bottom, top - o.bottom);
    const within = BoardLinks.maxJoinGap / PlatformConfig.mmToWorld;

    final sideBySide = apartX <= within && apartY < 0;
    final stacked = apartY <= within && apartX < 0;
    return sideBySide || stacked;
  }

  bool overlaps(_LaidPhone o) {
    const skin = 0.01;
    return left < o.right - skin &&
        o.left < right - skin &&
        top < o.bottom - skin &&
        o.top < bottom - skin;
  }
}
