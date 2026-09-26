import 'dart:math' as math;

import '../platform_config.dart';
import 'board_links.dart';
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
    ///
    /// Only about depth. Across, phones are always packed against each other —
    /// there is no arrangement in which a hole along a row is wanted.
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

    // A row is as deep as its deepest phone. There is deliberately no matching
    // idea of a column width — see the packing below.
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

    // Each row is packed **edge to edge** and then centred, rather than laid
    // into columns as wide as their widest phone.
    //
    // Columns were the obvious shape and the wrong one. A column is only as
    // wide as its biggest screen, so a smaller phone sharing that column sat
    // centred in it with a hole on either side — touching nobody. Pulling it to
    // one seam fixed the two-column case, because there each phone has a single
    // neighbour to reach for; it cannot fix a middle column, where a phone has
    // one on each side and centring is the least-bad compromise. Grouping
    // similar widths into the same column would narrow the hole without ever
    // closing it, and would take away the game's say in who sits where —
    // Flood picks its order deliberately.
    //
    // Packing the row instead makes the hole impossible rather than small:
    // every phone is placed against the one before it, so the only space left
    // anywhere on a row is the bezels between two casings, whatever sizes turn
    // up and however many are playing. What is given up is columns lining up
    // exactly between rows, which nothing depends on — screens are joined by
    // where they actually are, not by a grid index.
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

    // Then slide each row so the seams *between* columns line up down the
    // board.
    //
    // Centring each row on its own was the obvious way to place them and it
    // staggered the grid: rows of different total width drifted apart, columns
    // stopped standing over each other, and a phone ended up joined to the one
    // diagonally opposite it. The seams are what has to line up — they are
    // where two screens meet, and a straight one is the difference between a
    // block of phones and a pile of them.
    //
    // With two columns there is one seam per row and it lines up exactly. With
    // more, no single slide can align them all unless the widths match, so each
    // row takes the shift that puts its seams closest to where the others have
    // theirs — the average error, which is the best one number can do.
    double seamOf(int r, int k) =>
        (rowLefts[r][k] + widthOf(at(r, k)) + rowLefts[r][k + 1]) / 2;

    if (columns > 1) {
      final reference = [
        for (var k = 0; k < columns - 1; k++)
          [for (var r = 0; r < rows; r++) seamOf(r, k)]
                  .fold<double>(0, (sum, v) => sum + v) /
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
      // One column: no seam to line up on, so centre the rows on each other.
      final widest = [
        for (var r = 0; r < rows; r++) widthOf(at(r, 0)),
      ].reduce(math.max);
      for (var r = 0; r < rows; r++) {
        rowLefts[r][0] = (widest - widthOf(at(r, 0))) / 2;
      }
    }

    final placements = <PhonePlacement>[];

    // The playfield across is the strip *every* row covers: a row that is
    // shorter than the widest leaves ground at each end with no screen under
    // it, and calling that playfield would invent a dead zone.
    var playLeft = double.negativeInfinity;
    var playRight = double.infinity;

    for (var c = 0; c < columns; c++) {
      for (var r = 0; r < rows; r++) {
        final spec = at(r, c);
        final w = widthOf(spec);
        final h = heightOf(spec);
        final left = rowLefts[r][c];

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

  /// Two rows laid like bricks: the top row one phone longer than the bottom,
  /// both centred, so every phone below sits across a join above it.
  ///
  /// ```
  ///   three phones            five phones
  ///  ┌────┬────┐            ┌────┬────┬────┐
  ///  │ 1  │ 2  │            │ 1  │ 2  │ 3  │
  ///  └─┬──┴──┬─┘            └─┬──┴─┬──┴─┬──┘
  ///    │  3  │                │ 4  │ 5  │
  ///    └─────┘                └────┴────┘
  /// ```
  ///
  /// What an odd table does instead of a grid: it stays a block of phones
  /// facing each other across one seam rather than stretching into a line.
  /// Filled row by row in [sort] order, so the first `(n + 1) ~/ 2` phones are
  /// the top row. With an even count the rows come out equal and centred.
  ///
  /// The rows meet the way a grid's do — the top row sits on its bottom edge,
  /// the bottom row hangs from its top — so screens are flush at the seam
  /// whatever their depth.
  ///
  /// The box around the rows is not all screen: beyond the ends of the
  /// shorter row there is open table. No bounds are declared, so the board
  /// is that whole box, and a game that keeps things on the screens (see
  /// `PlayArea`) walls those corners off on its own.
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

    // Every phone above that has a phone below it somewhere along its length
    // is touching across the seam, so the widest such bezel pair sets it.
    final lefts = <List<double>>[];
    for (var r = 0; r < 2; r++) {
      final row = <double>[];
      var x = (widest - widths[r]) / 2;
      for (var c = 0; c < rows[r].length; c++) {
        row.add(x);
        x += widthOf(rows[r][c]);
        if (c < rows[r].length - 1) x += gap.between(rows[r][c], rows[r][c + 1]);
      }
      lefts.add(row);
    }
    var seam = 0.0;
    for (var a = 0; a < rows[0].length; a++) {
      for (var b = 0; b < rows[1].length; b++) {
        final aLeft = lefts[0][a];
        final bLeft = lefts[1][b];
        final overlap = math.min(aLeft + widthOf(rows[0][a]),
                bLeft + widthOf(rows[1][b])) -
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
        // Toward the seam: the top row on its bottom edge, the bottom row on
        // its top.
        final top = r == 0 ? topDepth - h : topDepth + seam;
        placements.add(PhonePlacement(
          spec.phoneId,
          xMm: lefts[r][c] + w / 2,
          yMm: top + h / 2,
          turnDeg: turn,
          hint: _brickHint(r, c, rows[0].length, rows[1].length),
        ));
      }
    }

    return BoardPlan(
      placements,
      instruction: instruction ??
          _brickInstruction(rows[0].length, rows[1].length, orientation),
    );
  }

  /// [phones] with the one whose long edge is shortest moved to the end, the
  /// rest left in the order they came.
  ///
  /// For a three-phone [brick]: the phone below lies across the join of the
  /// two above, so giving it the shortest long edge is what lets all of it
  /// rest against them. Not a [PhoneSort] because only one phone moves, and a
  /// comparator cannot say that without leaning on a stable sort.
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
    // Numbered in reading order, so the phones above this one are the
    // column'th and the one after it.
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

  /// A winding path: each phone laid against an edge of the one before,
  /// turning wherever it likes.
  ///
  /// The only helper here that is **different every time it is called**, which
  /// is the point of it — a board nobody can lay out from memory. Pass a seeded
  /// [random] to pin one down; the platform calls `planBoard` once per round, so
  /// the shape holds for that round and is rebuilt for the next.
  ///
  /// Every phone still shares a real edge with its neighbour, so the seam and
  /// the connector stripes work exactly as they do in a row — the stripes mark
  /// the *overlapping* part of the two edges, which is the length there is to
  /// line up when a portrait phone meets a sideways one.
  ///
  /// Two phones always meet **corner to corner**, flush at one end of the edge
  /// they share, so the join is the whole of the shorter of the two edges — the
  /// most connection there can be between them. Nothing is offset by a random
  /// amount: half an edge against half an edge is both harder to place and
  /// leaves less to line up.
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

    // A path paints itself into a corner sometimes: it curls round, and the
    // only places left for the next phone all brush against something it was
    // never attached to. There is nothing to repair at that point — the
    // mistake was several phones ago — so the whole thing is thrown away and
    // walked again from a different first turn.
    //
    // Cheap: laying eight phones is a handful of arithmetic, and each attempt
    // is independent, so the chance of every one of them failing falls away
    // fast. Deliberately *not* a search — no backtracking, no scoring — since
    // rolling again is both simpler to follow and produces the variety this
    // layout exists for.
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

    // Shift so the board starts at the origin, as every other helper does.
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
      instruction: instruction ??
          'Lay the phones out in a path, each against the last — '
              'match the coloured edges.',
    );
  }

  /// How many times to lay the whole path out before giving up.
  static const int _pathAttempts = 60;

  /// One go at laying every phone down, or null if it got stuck.
  static List<_LaidPhone>? _walkPath(
    List<PhoneSpec> ordered,
    math.Random rng,
    Gaps gap,
  ) {
    final laid = <_LaidPhone>[
      _LaidPhone(ordered.first, 0, 0, rng.nextBool()),
    ];

    for (var i = 1; i < ordered.length; i++) {
      final next = _attach(ordered[i], laid, rng, gap);
      if (next == null) return null;
      laid.add(next);
    }
    return laid;
  }

  /// Against the head of the path, and only the head.
  ///
  /// It used to fall back to earlier phones when the head had no room, which
  /// kept a crowded board from failing — and quietly built a fork every time it
  /// did, because the phone it reached back to then had three neighbours. Now
  /// that a stuck path is simply walked again, that fallback buys nothing and
  /// costs the one guarantee this layout is for: phone *i* meets phone *i-1*
  /// and nothing else, so the board is a chain from one end to the other.
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
        // A join running the whole length of a phone is the one thing this
        // layout will not have — see [_sharesAWholeLength].
        if (laid.any((other) => _sharesAWholeLength(candidate, other))) {
          continue;
        }
        // And it must meet its anchor and nothing else.
        //
        // A path is allowed to wind, and winding brings it back alongside
        // phones it was never attached to. Those brush past close enough to
        // count as neighbours, and the board stops being a chain and becomes a
        // web: every extra join is a fork, and anything walking the board end
        // to end has to guess which way to go. A game reading the board as a
        // route then drops whatever the walk it picked did not reach — which
        // on a table means somebody watching a blank screen for the round.
        //
        // Cheaper to refuse the placement than to describe the tangle
        // afterwards: there are seven ways to carry on and the next one is
        // usually fine.
        if (laid.any((other) =>
            !identical(other, anchor) && candidate.touches(other))) {
          continue;
        }
        return candidate;
      }
    }
    return null;
  }

  /// Every way the next phone may be laid against this one. There are seven.
  ///
  /// Take the anchor as a phone with the path running *along* it. Three of its
  /// four edges are free — the fourth is where the path came from — and each
  /// offers a way to carry on:
  ///
  /// - **at the end**: straight on, or turned a quarter each way (3)
  /// - **on each side**: turned a quarter, or alongside (2 + 2)
  ///
  /// Eight entries come back rather than seven: carrying straight on can be
  /// flush with either flank, and those are the same place only when the two
  /// phones are the same width.
  ///
  /// Everything is flush at a corner except the last pair. Two phones laid
  /// alongside each other *flush* would share one whole long edge, and a join
  /// running the entire length of a phone is what this layout exists to avoid:
  /// it stops being a path and becomes a slab. So a phone laid alongside is
  /// pushed half a length along, and the join is half an edge.
  static List<_LaidPhone> _sevenWays(
    _LaidPhone anchor,
    PhoneSpec spec,
    Gaps gap,
  ) {
    // Where the path is heading, and the two ways off it.
    //
    // Every phone lies *along* the path — that is the premise the seven ways
    // are counted from, so the very first one sets the direction from the way
    // it is lying rather than the other way round.
    final ahead = anchor.arrivedBy >= 0
        ? anchor.arrivedBy
        : (anchor.sideways ? 0 : 1);
    final left = (ahead + 3) % 4;
    final right = (ahead + 1) % 4;

    final between = gap.between(anchor.spec, spec);
    final straight = _LaidPhone(spec, 0, 0, anchor.sideways);
    final turned = _LaidPhone(spec, 0, 0, !anchor.sideways);

    /// [along] is measured in the direction of travel, [across] to its left.
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

    // Beyond the far edge: the end of the anchor.
    final endAlong = aAlong + between;
    // Beyond a side edge: past its flank.
    final sideAcross = aAcross + between;

    return [
      // 1. Straight on, flush with one flank or the other.
      //
      // Two entries rather than one because the phones need not be the same
      // width. Centring the newcomer looked right — with matched phones it is
      // flush on both sides at once — and put a narrower phone in the middle of
      // its neighbour's end, overhanging equally at both flanks with no corner
      // meeting anywhere. That is not one of the ways this layout offers, and on
      // a real table it is the placement nobody can reproduce: there is nothing
      // to line the phone up against. With matched phones both entries land in
      // the same place, so nothing changes there.
      at(straight, endAlong + halfAlong(straight),
          aAcross - halfAcross(straight), ahead),
      at(straight, endAlong + halfAlong(straight),
          halfAcross(straight) - aAcross, ahead),

      // 2 and 3. A quarter turn at the end, flush with one flank or the other.
      //
      // The heading is the way the path leaves, which is the *opposite* of the
      // flank it is flush against — a phone flush with the anchor's left flank
      // reaches away to the right, so that is where the next one goes. These
      // two were the wrong way round, and the mistake did not show on the phone
      // being placed but on the one after it: the path believed it was heading
      // back toward the phone it had just come from, so it offered the next
      // placement against the half already spoken for, and two neighbours ended
      // up sharing a half with nothing on the other.
      at(turned, endAlong + halfAlong(turned),
          aAcross - halfAcross(turned), right),
      at(turned, endAlong + halfAlong(turned),
          halfAcross(turned) - aAcross, left),

      // 4 and 5. A quarter turn out to the side, flush with the far end.
      at(turned, aAlong - halfAlong(turned),
          sideAcross + halfAcross(turned), left),
      at(turned, aAlong - halfAlong(turned),
          -sideAcross - halfAcross(turned), right),

      // 6 and 7. Alongside, pushed half a length on so the two do not share a
      // whole edge. The heading does not turn: this phone lies the same way as
      // the one it is beside, so the path has stepped sideways, not turned.
      at(straight, aAlong, sideAcross + halfAcross(straight), ahead),
      at(straight, aAlong, -sideAcross - halfAcross(straight), ahead),
    ];
  }

  /// Do these two meet along the entire long edge of either of them?
  ///
  /// The one arrangement this layout refuses. Two phones flush side by side
  /// share every millimetre of one edge each: the pair reads as a single fat
  /// screen rather than as two steps of a path, and the stripe marking it is a
  /// full-length bar that says nothing about which way to go next.
  static bool _sharesAWholeLength(_LaidPhone a, _LaidPhone b) {
    const skin = 0.5;

    final apart = math.max(b.left - a.right, a.left - b.right);
    final overlap =
        math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
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

  /// 0 right, 1 down, 2 left, 3 up.
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

/// One phone already on the table, as the path builder sees it.
///
/// Axis aligned by construction: a path only ever turns by quarters, which is
/// also what keeps the connector stripes computable.
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

  /// Which way the path was travelling when it arrived here — 0 right, 1 down,
  /// 2 left, 3 up, and -1 for the phone it started from. The next phone carries
  /// on or turns a quarter; it never goes back over this one.
  final int arrivedBy;

  double get halfW => (sideways ? spec.heightMm : spec.widthMm) / 2;
  double get halfH => (sideways ? spec.widthMm : spec.heightMm) / 2;

  /// The phone's own long side, whichever way it is lying.
  double get longEdge => math.max(spec.widthMm, spec.heightMm);

  double get left => cx - halfW;
  double get right => cx + halfW;
  double get top => cy - halfH;
  double get bottom => cy + halfH;

  /// Close enough that the platform would call these two neighbours.
  ///
  /// The same judgement [BoardLinks] makes — near on one axis while overlapping
  /// on the other — read from the same constant, so "the path thinks these
  /// touch" and "the board draws a connector between them" can never drift
  /// apart.
  bool touches(_LaidPhone o) {
    final apartX = math.max(o.left - right, left - o.right);
    final apartY = math.max(o.top - bottom, top - o.bottom);
    const within = BoardLinks.maxJoinGap / PlatformConfig.mmToWorld;

    final sideBySide = apartX <= within && apartY < 0;
    final stacked = apartY <= within && apartX < 0;
    return sideBySide || stacked;
  }

  /// Touching is fine — that is the whole idea. Sharing area is not.
  bool overlaps(_LaidPhone o) {
    const skin = 0.01;
    return left < o.right - skin &&
        o.left < right - skin &&
        top < o.bottom - skin &&
        o.top < bottom - skin;
  }
}
