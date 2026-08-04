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
/// put on the table. Both shipped games use [sideways], because a runway and a
/// falling well both want the long edge running left-to-right.
enum PhoneOrientation {
  /// Long edge horizontal — the phone on its side. One quarter turn.
  sideways,

  /// Long edge vertical — the phone as you normally hold it. No turn, so
  /// nothing is rotated when drawing either.
  upright,
}

extension PhoneOrientationTurns on PhoneOrientation {
  int get quarterTurns => this == PhoneOrientation.sideways ? 1 : 0;
}

/// How phones line up across the packing axis.
enum CrossAlign {
  /// Top edges flush in a row, left edges flush in a column.
  start,

  /// Centres line up.
  center,

  /// Bottom edges flush in a row, right edges flush in a column.
  end,
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
  }) =>
      _pack(
        phones,
        horizontal: true,
        sort: sort,
        gap: gap,
        align: align,
        orientation: orientation,
        instruction:
            instruction ?? _instructionFor(true, orientation, align),
      );

  /// Top to bottom. A narrow, tall board — falling things, towers, ladders.
  static BoardPlan column(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    CrossAlign align = CrossAlign.start,
    PhoneOrientation orientation = PhoneOrientation.sideways,
    String? instruction,
  }) =>
      _pack(
        phones,
        horizontal: false,
        sort: sort,
        gap: gap,
        align: align,
        orientation: orientation,
        instruction:
            instruction ?? _instructionFor(false, orientation, align),
      );

  /// A squarish block. Phones fill rows left to right, top to bottom.
  ///
  /// The arrangement for a game where everyone has to *reach* everyone: a strip
  /// of six phones is two metres of table and the far end is unplayable, while
  /// the same six in a 3x2 block are all within arm's length of every seat.
  ///
  /// Unlike [row] and [column] this asks for uniform phones and says so. A grid
  /// of mismatched screens has no honest answer — a short phone in the top row
  /// leaves a hole that is not a bezel gap and not playfield either, and every
  /// choice about it is wrong in some game. Cells are therefore sized to the
  /// *largest* footprint and smaller screens are centred in theirs, which keeps
  /// the grid square and confines the error to a visible margin rather than
  /// smearing it across the board.
  ///
  /// [columns] defaults to `ceil(sqrt(n))`, which is the squarest block for any
  /// count: 4 phones make 2x2, 6 make 3x2, 9 make 3x3. A short final row is
  /// centred, because a lone phone hanging off one end looks like a mistake.
  static BoardPlan grid(
    List<PhoneSpec> phones, {
    int? columns,
    PhoneSort sort = PhoneSort.joinOrder,
    Gaps gap = Gaps.casingsTouching,
    PhoneOrientation orientation = PhoneOrientation.upright,
    String? instruction,
  }) {
    if (phones.isEmpty) {
      throw const BoardPlanError('no phones to place');
    }

    final ordered = List.of(phones)..sort(sort.compare);
    final turns = orientation.quarterTurns;
    final n = ordered.length;

    final cols = columns ?? math.max(1, math.sqrt(n).ceil());
    if (cols < 1) {
      throw const BoardPlanError('a grid needs at least one column');
    }
    final rows = (n / cols).ceil();

    // One cell size for the whole grid, or the rows would not line up.
    var cellW = 0.0;
    var cellH = 0.0;
    for (final p in ordered) {
      final w = p.footprintWidthMm(turns);
      final h = p.footprintHeightMm(turns);
      if (w > cellW) cellW = w;
      if (h > cellH) cellH = h;
    }

    // Gaps between neighbours vary with which two phones meet, but a grid needs
    // one pitch. Take the largest so no two casings are asked to overlap.
    var gapX = 0.0;
    var gapY = 0.0;
    for (final a in ordered) {
      for (final b in ordered) {
        if (identical(a, b)) continue;
        final g = gap.between(a, b);
        if (g > gapX) gapX = g;
        if (g > gapY) gapY = g;
      }
    }
    // A single phone has no neighbour to measure against.
    if (n == 1) gapX = gapY = 0;

    final pitchX = cellW + gapX;
    final pitchY = cellH + gapY;

    final placements = <PhonePlacement>[];
    for (var i = 0; i < n; i++) {
      final p = ordered[i];
      final row = i ~/ cols;
      final col = i % cols;

      // Centre a short last row: with 5 phones in a 3-wide grid the pair below
      // sits under the middle of the three, which is what people do anyway.
      final inThisRow = math.min(cols, n - row * cols);
      final rowInsetMm = (cols - inThisRow) * pitchX / 2;

      // Centre each screen in its cell, so a smaller phone's margin is even
      // rather than all on one side.
      final dx = (cellW - p.footprintWidthMm(turns)) / 2;
      final dy = (cellH - p.footprintHeightMm(turns)) / 2;

      placements.add(PhonePlacement(
        p.phoneId,
        xMm: rowInsetMm + col * pitchX + dx,
        yMm: row * pitchY + dy,
        quarterTurns: turns,
        hint: _gridHint(row, col, rows, cols, inThisRow),
      ));
    }

    return BoardPlan(
      placements,
      instruction: instruction ??
          'Lay the phones in a $cols x $rows block, '
              '${orientation == PhoneOrientation.upright ? 'upright' : 'on their sides'}, '
              'casings touching — everyone should be able to reach the middle.',
      // Deliberately no declared bounds: every cell is backed by a screen, so
      // the bounding box *is* the playfield and the compiler's default is
      // already right. Hugging a band the way a row does would cut off rows.
    );
  }

  static String _gridHint(
    int row,
    int col,
    int rows,
    int cols,
    int inThisRow,
  ) {
    if (rows == 1) return _hintFor(col, cols, true);
    final vertical = row == 0
        ? 'top row'
        : row == rows - 1
            ? 'bottom row'
            : 'row ${row + 1}';
    if (inThisRow == 1) return '$vertical, on your own in the middle';
    final horizontal = col == 0
        ? 'far left'
        : col == inThisRow - 1
            ? 'far right'
            : 'position ${col + 1} from the left';
    return '$vertical, $horizontal';
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
    final turns = orientation.quarterTurns;

    // Footprints, not panels: a phone put on its side covers the board the
    // other way round, and every measurement below is about the board.
    double alongSize(PhoneSpec p) => horizontal
        ? p.footprintWidthMm(turns)
        : p.footprintHeightMm(turns);
    double acrossSize(PhoneSpec p) => horizontal
        ? p.footprintHeightMm(turns)
        : p.footprintWidthMm(turns);

    // Phones sit inside a lane as deep as the *largest* of them, so no screen
    // is ever placed at a negative offset.
    final lane = ordered.map(acrossSize).reduce((a, b) => a > b ? a : b);

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
      final offset = offsetFor(acrossSize(p));

      if (offset > bandStart) bandStart = offset;
      if (offset + acrossSize(p) < bandEnd) bandEnd = offset + acrossSize(p);

      placements.add(PhonePlacement(
        p.phoneId,
        xMm: horizontal ? cursor : offset,
        yMm: horizontal ? offset : cursor,
        quarterTurns: turns,
        hint: _hintFor(i, ordered.length, horizontal),
      ));

      cursor += alongSize(p);
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
    // In a row the touching edges run across the row, and vice versa.
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
