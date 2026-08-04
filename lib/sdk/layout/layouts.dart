import 'dart:math' as math;

import 'board_plan.dart';
import 'phone_spec.dart';

/// How to order phones along the packing axis.
///
/// Ordering is a game decision, not a platform one: only the game knows whether
/// the big phone belongs at the bottom of a well or on the left of a runway.
class PhoneSort {
  const PhoneSort(this.compare, this.description);

  final Comparator<PhoneSpec> compare;

  /// Shown on the arrangement diagram, so people know why they are being asked
  /// to put the little phone first.
  final String description;

  /// However they happened to connect.
  static const joinOrder = PhoneSort(_noop, 'in the order you joined');

  static const smallestFirst =
      PhoneSort(_bySizeAscending, 'smallest screen first');
  static const largestFirst =
      PhoneSort(_bySizeDescending, 'largest screen first');
  static const smallestLast =
      PhoneSort(_bySizeDescending, 'smallest screen last');
  static const largestLast =
      PhoneSort(_bySizeAscending, 'largest screen last');

  /// Anything else.
  static PhoneSort by(Comparator<PhoneSpec> compare, {String? description}) =>
      PhoneSort(compare, description ?? 'in a custom order');

  static int _noop(PhoneSpec a, PhoneSpec b) => 0;
  static int _bySizeAscending(PhoneSpec a, PhoneSpec b) =>
      a.areaMm2.compareTo(b.areaMm2);
  static int _bySizeDescending(PhoneSpec a, PhoneSpec b) =>
      b.areaMm2.compareTo(a.areaMm2);
}

/// The space left between two neighbouring lit areas.
class Gaps {
  const Gaps._(this._mmBetween, this.description);

  final double Function(PhoneSpec before, PhoneSpec after) _mmBetween;
  final String description;

  double between(PhoneSpec before, PhoneSpec after) =>
      _mmBetween(before, after);

  /// Phones physically touching: the gap is both bezels. Real space, which the
  /// simulation runs through — this is the seam.
  static const casingsTouching = Gaps._(_bothBezels, 'casings touching');

  /// Lit areas edge to edge, as if the phones had no bezels. Only honest on a
  /// desktop test board.
  static const flush = Gaps._(_zero, 'screens flush');

  /// A deliberate space, for a game that wants the board spread out.
  static Gaps of(double mm) =>
      Gaps._((_, _) => mm, '${mm.toStringAsFixed(0)}mm apart');

  static double _bothBezels(PhoneSpec a, PhoneSpec b) => a.bezelMm + b.bezelMm;
  static double _zero(PhoneSpec a, PhoneSpec b) => 0;
}

/// Which way up the phones lie within the board.
///
/// The app itself is always portrait; this is purely about how the devices are
/// put on the table. The row and column helpers use [sideways], because a
/// runway and a falling well both want the long edge running left-to-right.
enum PhoneOrientation {
  /// Long edge horizontal — the phone on its side. A quarter turn.
  sideways,

  /// Long edge vertical — the phone as you normally hold it. No turn.
  upright,
}

extension PhoneOrientationTurn on PhoneOrientation {
  double get turnDeg => this == PhoneOrientation.sideways ? 90 : 0;
}

/// How phones line up across the packing axis.
enum CrossAlign { start, center, end }

/// Which way a phone lies in a ring.
enum RingFacing {
  /// Long edge along the rim, at right angles to the radius — phones laid like
  /// tiles around a wheel. The circumference is spent on long edges, so more
  /// phones fit and the ring reads as a ring.
  tangential,

  /// Long edge pointing at the middle, like spokes. Each phone's own top edge
  /// then points outward at its player, which reads more naturally on the
  /// device but wastes rim.
  radial,
}

/// Ready-made plans for the arrangements most games want.
///
/// Every one of these returns an ordinary [BoardPlan], so a game can call a
/// helper and then move one phone by hand. Nothing here is privileged.
class Layouts {
  const Layouts._();

  /// Left to right. A wide, short board — runways, side-scrollers, pong.
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

  /// Top to bottom. A narrow, tall board — falling things, towers, ladders.
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

  /// A ring of phones around a table, each turned to face its own player.
  ///
  /// Unlike a row or a column, nothing touches: the phones are islands with
  /// space between them, and a game passing something around the ring sends it
  /// across that space. So the plan declares [BoardPlan.allowGaps] and the
  /// compiler stops treating the distance as a mistake.
  ///
  /// By default each phone lies [RingFacing.tangential]: its long edge along
  /// the rim, at right angles to its own radius, like tiles around a wheel.
  /// That spends the circumference on long edges, so more phones fit and the
  /// ring actually looks like one.
  ///
  /// Either way this needs arbitrary angles rather than quarter turns — five
  /// phones sit 72° apart.
  ///
  /// Order runs clockwise from the top, and the game's own passing order is
  /// simply that order wrapping around.
  static BoardPlan circle(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,
    RingFacing facing = RingFacing.tangential,

    /// Clear space between neighbouring screens, as a fraction of the widest
    /// phone. Enough that nobody's elbows collide.
    double spacing = 0.6,

    /// Force a particular ring size instead of the smallest that fits.
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

    // What has to fit in the chord between two neighbours is whichever edge
    // runs along the rim — the long one when the phones lie tangentially.
    final tangential = facing == RingFacing.tangential;
    final alongRim = ordered
        .map((p) => tangential ? p.heightMm : p.widthMm)
        .reduce(math.max);
    final acrossRim = ordered
        .map((p) => tangential ? p.widthMm : p.heightMm)
        .reduce(math.max);
    final neededChord = alongRim * (1 + spacing);

    // chord = 2 R sin(pi / n)
    final fitted = neededChord / (2 * math.sin(math.pi / count));
    // Keep a hole in the middle even when there are only three phones, so the
    // ring reads as a ring rather than a huddle.
    final radius = radiusMm ?? math.max(fitted, acrossRim * 1.2);

    final placements = <PhonePlacement>[];
    for (var i = 0; i < count; i++) {
      // Start at the top of the ring and work clockwise.
      final angle = -math.pi / 2 + (2 * math.pi * i) / count;
      placements.add(PhonePlacement(
        ordered[i].phoneId,
        xMm: radius * math.cos(angle),
        yMm: radius * math.sin(angle),
        // Radial puts the phone's top edge along its own radius, pointing
        // outward — turn zero already points "up", which is outward at the top
        // of the ring, hence the extra quarter. Tangential adds another
        // quarter, swinging the long edge round onto the rim.
        turnDeg: angle * 180 / math.pi + (tangential ? 180 : 90),
        hint: _ringHint(i, count),
      ));
    }

    return BoardPlan(
      placements,
      allowGaps: true,
      instruction: instruction ??
          'Sit in a circle and put your phone on the table in front of you, '
              'screen facing you. $count phones, evenly spaced.',
    );
  }

  static String _ringHint(int index, int count) {
    if (index == 0) return 'at the top of the circle';
    final oClock = (index * 12 / count).round() % 12;
    return '${oClock == 0 ? 12 : oClock} o\'clock in the circle';
  }

  /// A block of phones, [rows] deep and as many columns as it takes.
  ///
  /// The two-axis helper. `row` and `column` pack along one axis and stop; this
  /// fills a rectangle, which is what a game wants when players face each other
  /// across a table rather than sitting in a line or a ring:
  ///
  /// ```
  ///   rows: 2, four phones      rows: 2, six phones
  ///  ┌────┬────┐               ┌────┬────┬────┐
  ///  │ 1  │ 2  │               │ 1  │ 2  │ 3  │
  ///  ├────┼────┤               ├────┼────┼────┤
  ///  │ 3  │ 4  │               │ 4  │ 5  │ 6  │
  ///  └────┴────┘               └────┴────┴────┘
  /// ```
  ///
  /// Filled row by row, so the first `columns` phones are the top row. A game
  /// wanting two teams asks for `rows: 2` and reads the rows off the compiled
  /// board — the top half is one side, the bottom half the other.
  ///
  /// Mismatched phones are handled the way a table handles them: a column is as
  /// wide as its widest phone and every screen in it is centred, a row is as
  /// deep as its deepest. With [seamAlign] on, each row is then pushed *toward*
  /// the seam it shares with its neighbour, so a shallower phone gives up its
  /// far edge rather than its front line — which matters when the game happens
  /// at the seam, and is why this is not simply nested `row` calls.
  ///
  /// The playfield hugs what every facing pair can actually see: within a
  /// column it is the narrower phone's width, and across columns those bands
  /// join up. Treating a wider phone's overhang as playfield would invent a
  /// dead zone that is not a real gap between screens.
  static BoardPlan grid(
    List<PhoneSpec> phones, {
    required int rows,
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    PhoneOrientation orientation = PhoneOrientation.upright,

    /// Pull each row toward the seam it shares with the next, so screens meet
    /// edge to edge there whatever their depth. Off, rows are top-aligned.
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

    // Footprints, not panels: a phone put on its side covers the board the
    // other way round, and every measurement below is about the board.
    double widthOf(PhoneSpec p) => sideways ? p.heightMm : p.widthMm;
    double heightOf(PhoneSpec p) => sideways ? p.widthMm : p.heightMm;

    /// The phone at (row, column), reading row by row.
    PhoneSpec at(int row, int column) => ordered[row * columns + column];

    // A column is as wide as its widest phone; a row as deep as its deepest.
    final columnWidths = [
      for (var c = 0; c < columns; c++)
        [for (var r = 0; r < rows; r++) widthOf(at(r, c))].reduce(math.max),
    ];
    final rowDepths = [
      for (var r = 0; r < rows; r++)
        [for (var c = 0; c < columns; c++) heightOf(at(r, c))].reduce(math.max),
    ];

    // Every column shares one seam line between two rows, so the widest bezel
    // pair across that seam sets it — that is the phones physically touching.
    final rowGaps = [
      for (var r = 0; r < rows - 1; r++)
        [
          for (var c = 0; c < columns; c++)
            gap.between(at(r, c), at(r + 1, c)),
        ].reduce(math.max),
    ];

    // Where each row's band starts, walking down through depths and seams.
    final rowTops = <double>[];
    var y = 0.0;
    for (var r = 0; r < rows; r++) {
      rowTops.add(y);
      y += rowDepths[r];
      if (r < rows - 1) y += rowGaps[r];
    }
    final totalDepth = y;

    // Column x positions, and the same for the horizontal gaps.
    final columnLefts = <double>[];
    var x = 0.0;
    for (var c = 0; c < columns; c++) {
      columnLefts.add(x);
      x += columnWidths[c];
      if (c < columns - 1) {
        x += [
          for (var r = 0; r < rows; r++) gap.between(at(r, c), at(r, c + 1)),
        ].reduce(math.max);
      }
    }

    final placements = <PhonePlacement>[];
    var playLeft = double.infinity;
    var playRight = double.negativeInfinity;

    for (var c = 0; c < columns; c++) {
      // Within a column, the playfield is the narrowest phone's band: the strip
      // every row can see.
      var columnLeft = double.negativeInfinity;
      var columnRight = double.infinity;

      for (var r = 0; r < rows; r++) {
        final spec = at(r, c);
        final w = widthOf(spec);
        final h = heightOf(spec);
        final left = columnLefts[c] + (columnWidths[c] - w) / 2;

        // Toward the seam: the top row sits on its bottom edge, the bottom row
        // on its top, and a middle row cannot favour both so it centres.
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

        placements.add(PhonePlacement(
          spec.phoneId,
          // Placements are the centre of the lit area, not a corner.
          xMm: left + w / 2,
          yMm: top + h / 2,
          turnDeg: turn,
          hint: _gridHint(r, c, rows, columns),
        ));

        if (left > columnLeft) columnLeft = left;
        if (left + w < columnRight) columnRight = left + w;
      }

      // Columns sit side by side, so each one adds ground.
      if (columnLeft < playLeft) playLeft = columnLeft;
      if (columnRight > playRight) playRight = columnRight;
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

    // Footprints, not panels: a phone put on its side covers the board the
    // other way round, and every measurement below is about the board.
    double footprintAlong(PhoneSpec p) => horizontal
        ? (sideways ? p.heightMm : p.widthMm)
        : (sideways ? p.widthMm : p.heightMm);
    double footprintAcross(PhoneSpec p) => horizontal
        ? (sideways ? p.widthMm : p.heightMm)
        : (sideways ? p.heightMm : p.widthMm);

    // Phones sit inside a lane as deep as the largest of them, so no screen is
    // ever placed at a negative offset.
    final lane = ordered.map(footprintAcross).reduce(math.max);

    double offsetFor(double size) => switch (align) {
      CrossAlign.start => 0.0,
      CrossAlign.center => (lane - size) / 2,
      CrossAlign.end => lane - size,
    };

    final placements = <PhonePlacement>[];
    var cursor = 0.0;

    // The playfield is the band every screen covers — the intersection, not the
    // union. With matched phones that is the whole lane; with a tall phone and a
    // short one it is the short one's depth, so the only dead zones left are
    // real gaps between screens.
    var bandStart = double.negativeInfinity;
    var bandEnd = double.infinity;

    for (var i = 0; i < ordered.length; i++) {
      final p = ordered[i];
      final across = footprintAcross(p);
      final along = footprintAlong(p);
      final offset = offsetFor(across);

      if (offset > bandStart) bandStart = offset;
      if (offset + across < bandEnd) bandEnd = offset + across;

      // Centre, not corner.
      placements.add(PhonePlacement(
        p.phoneId,
        xMm: horizontal ? cursor + along / 2 : offset + across / 2,
        yMm: horizontal ? offset + across / 2 : cursor + along / 2,
        turnDeg: turn,
        hint: _hintFor(i, ordered.length, horizontal),
      ));

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

  /// The line everyone reads before moving a phone.
  ///
  /// Which edges end up touching depends on both the packing axis *and* which
  /// way up the phones lie: a row of phones on their sides meets at the short
  /// edges, the same row standing upright meets at the long ones.
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
