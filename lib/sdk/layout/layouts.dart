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
  /// Every phone is turned so its top edge points *outward*, away from the
  /// middle — because the player it belongs to is sitting on the outside
  /// looking in. That needs arbitrary angles, not quarter turns: five phones
  /// sit 72° apart.
  ///
  /// Order runs clockwise from the top, and the game's own passing order is
  /// simply that order wrapping around.
  static BoardPlan circle(
    List<PhoneSpec> phones, {
    PhoneSort sort = PhoneSort.joinOrder,

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

    // Adjacent phones sit shoulder to shoulder around the ring, so what has to
    // fit in the chord between two centres is their widths, not their heights.
    final widest = ordered.map((p) => p.widthMm).reduce(math.max);
    final tallest = ordered.map((p) => p.heightMm).reduce(math.max);
    final neededChord = widest * (1 + spacing);

    // chord = 2 R sin(pi / n)
    final fitted = neededChord / (2 * math.sin(math.pi / count));
    // Keep a hole in the middle even when there are only three phones, so the
    // ring reads as a ring rather than a huddle.
    final radius = radiusMm ?? math.max(fitted, tallest * 0.9);

    final placements = <PhonePlacement>[];
    for (var i = 0; i < count; i++) {
      // Start at the top of the ring and work clockwise.
      final angle = -math.pi / 2 + (2 * math.pi * i) / count;
      placements.add(PhonePlacement(
        ordered[i].phoneId,
        xMm: radius * math.cos(angle),
        yMm: radius * math.sin(angle),
        // A phone's top edge points along its own radius, outward. Turn zero
        // already points "up", which is outward at the top of the ring, so the
        // turn is the angle plus a quarter.
        turnDeg: angle * 180 / math.pi + 90,
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
