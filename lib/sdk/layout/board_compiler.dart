import 'dart:math' as math;

import '../contract/sim.dart';
import '../model/coverage_map.dart';
import '../model/phone_layout.dart';
import '../model/world_rect.dart';
import '../platform_config.dart';
import '../score/scoreboard.dart';
import 'board_links.dart';
import 'board_plan.dart';
import 'phone_spec.dart';

/// The compiled board: what the platform runs on, built from a game's plan.
class BoardLayout {
  const BoardLayout({
    required this.phones,
    required this.coverage,
    required this.mmToWorld,
    required this.slices,
    required this.links,
    required this.instruction,
  });

  final List<PhoneLayout> phones;
  final CoverageMap coverage;
  final double mmToWorld;

  /// Named screen rectangles, in board order. The compiled truth about where
  /// every phone ended up — what a sim asks "whose screen is this?" against,
  /// and what the placement diagram is drawn from.
  final List<PhoneSlice> slices;

  /// Where each screen meets its neighbours, as coloured edge stripes. Computed
  /// once here so no two phones can disagree about which edge is red.
  final List<EdgeMarker> links;

  /// The game's one-line "put your phones like this".
  final String instruction;

  WorldRect get board => coverage.board;

  PhoneLayout? forPhone(String id) {
    for (final p in phones) {
      if (p.phoneId == id) return p;
    }
    return null;
  }

  /// Everything a [GameSim] needs to be built against this board.
  BoardContext contextFor(Scoreboard scores) => BoardContext(
    board: board,
    coverage: coverage,
    scores: scores,
    slices: slices,
  );
}

/// Turns a game's [BoardPlan] into a [BoardLayout], or refuses.
///
/// Validation is deliberately strict and deliberately early: this runs before a
/// single phone is told anything, so a game with a broken `planBoard` fails on
/// the host's own screen rather than sending everyone to rearrange a table for
/// a round that cannot start.
class BoardCompiler {
  const BoardCompiler({this.mmToWorld = PlatformConfig.mmToWorld});

  final double mmToWorld;

  /// Overlap is judged with this much slack, so two edges meant to be flush are
  /// not called an overlap by a rounding error.
  static const double _epsilonMm = 0.01;

  /// How far apart two screens may be before a board is considered broken —
  /// unless the plan says it means it (see [BoardPlan.allowGaps]).
  ///
  /// Derived from [BoardLinks.maxJoinGap] rather than chosen separately, so
  /// "close enough to be connected" and "close enough to be joined" are the
  /// same judgement. When they were two numbers, a gap between them passed
  /// validation and then produced no connectors.
  double get _reachMm => BoardLinks.maxJoinGap / mmToWorld;

  BoardLayout compile(BoardPlan plan, LobbyInfo lobby) {
    _validate(plan, lobby);

    // Every screen's axis-aligned extent, turn included. Used to frame the
    // board and to order the phones.
    final boxes = <String, _Box>{
      for (final p in plan.placements)
        p.phoneId: _Box.of(p, lobby.byId(p.phoneId)!),
    };

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final box in boxes.values) {
      minX = math.min(minX, box.left);
      minY = math.min(minY, box.top);
      maxX = math.max(maxX, box.right);
      maxY = math.max(maxY, box.bottom);
    }

    final declared = plan.bounds;
    if (declared != null) {
      minX = declared.leftMm;
      minY = declared.topMm;
    }

    // Reading order: down the board, then across it.
    final ordered = List.of(plan.placements)
      ..sort((a, b) {
        final byY = a.yMm.compareTo(b.yMm);
        if (byY != 0 && (a.yMm - b.yMm).abs() > _epsilonMm) return byY;
        return a.xMm.compareTo(b.xMm);
      });

    final boardWidthMm = declared?.widthMm ?? (maxX - minX);
    final boardHeightMm = declared?.heightMm ?? (maxY - minY);
    if (boardWidthMm <= 0 || boardHeightMm <= 0) {
      throw const BoardPlanError('the playfield has no area');
    }

    final board =
        WorldRect(0, 0, boardWidthMm * mmToWorld, boardHeightMm * mmToWorld);

    final layouts = <PhoneLayout>[];
    final slices = <PhoneSlice>[];
    for (var i = 0; i < ordered.length; i++) {
      final placement = ordered[i];
      final spec = lobby.byId(placement.phoneId)!;
      final layout = PhoneLayout(
        phoneId: spec.phoneId,
        index: i,
        total: ordered.length,
        worldCenterX: (placement.xMm - minX) * mmToWorld,
        worldCenterY: (placement.yMm - minY) * mmToWorld,
        mmToWorld: mmToWorld,
        dpi: spec.dpi,
        devicePixelRatio: spec.devicePixelRatio,
        activePxWidth: spec.activePxWidth,
        activePxHeight: spec.activePxHeight,
        turnRadians: placement.turnRadians,
        board: board,
        placement: placement.hint ?? _defaultHint(i, ordered.length),
      );
      layouts.add(layout);
      slices.add(PhoneSlice(
        spec.phoneId,
        _screenOf(layout),
        label: spec.label,
        color: spec.color,
      ));
    }

    return BoardLayout(
      phones: layouts,
      coverage: CoverageMap(
        screens: [for (final l in layouts) _screenOf(l)],
        board: board,
      ),
      mmToWorld: mmToWorld,
      slices: slices,
      links: BoardLinks.of(slices),
      instruction: plan.instruction ?? 'Arrange the phones as shown.',
    );
  }

  void _validate(BoardPlan plan, LobbyInfo lobby) {
    if (plan.placements.isEmpty) {
      throw const BoardPlanError('the plan places no phones');
    }

    final placed = <String>{};
    for (final placement in plan.placements) {
      if (lobby.byId(placement.phoneId) == null) {
        throw BoardPlanError('places unknown phone "${placement.phoneId}"');
      }
      if (!placed.add(placement.phoneId)) {
        throw BoardPlanError('places ${placement.phoneId} more than once');
      }
      if (!placement.xMm.isFinite ||
          !placement.yMm.isFinite ||
          !placement.turnDeg.isFinite) {
        throw BoardPlanError('${placement.phoneId} has a non-finite position');
      }
    }

    for (final phone in lobby.phones) {
      if (!placed.contains(phone.phoneId)) {
        throw BoardPlanError(
          'leaves ${phone.phoneId} (${phone.label}) unplaced — every '
          'connected phone needs somewhere to be',
        );
      }
    }

    _requireHonestScale(lobby);
    _rejectOverlaps(plan, lobby);
    if (!plan.allowGaps) _requireConnected(plan, lobby);
  }

  /// A screen's size in millimetres has to agree with its size in pixels.
  ///
  /// The compiler reserves each phone a slot of `widthMm` by `heightMm`, but
  /// what it hands back — the compiled screen, and the camera behind it — is
  /// the pixel count scaled by the density. Let those two drift and a phone is
  /// drawn to one size while given room for another: it reaches over its
  /// neighbour on the glass and on the placement diagram, while the plan
  /// validates cleanly, because overlap is checked against the slot and never
  /// against the screen.
  ///
  /// Pixels are square, so this is a real constraint and not a convention.
  /// Refusing here turns a whole class of quiet geometry corruption into one
  /// sentence naming the phone.
  void _requireHonestScale(LobbyInfo lobby) {
    for (final spec in lobby.phones) {
      if (spec.activePxWidth <= 0 || spec.widthMm <= 0) continue;
      final byPixels = spec.activePxHeight / spec.activePxWidth;
      final byMillimetres = spec.heightMm / spec.widthMm;
      // One per cent covers rounding and a ruler; nothing covers a wrong axis.
      if ((byPixels - byMillimetres).abs() <= byPixels * 0.01) continue;

      final impliedMm = spec.widthMm * byPixels;
      throw BoardPlanError(
        '${spec.phoneId} says it is ${spec.widthMm.toStringAsFixed(1)} by '
        '${spec.heightMm.toStringAsFixed(1)}mm, but its '
        '${spec.activePxWidth.round()}x${spec.activePxHeight.round()} pixels '
        'make that ${spec.widthMm.toStringAsFixed(1)} by '
        '${impliedMm.toStringAsFixed(1)}mm. Pixels are square, so one measured '
        'edge fixes the other — correct the width and let the height follow.',
      );
    }
  }

  /// Two screens claiming the same world coordinates is not a layout, it is a
  /// bug that would present as a rendering glitch.
  ///
  /// Turned screens are compared with the separating-axis test rather than by
  /// their bounding boxes: two phones at 45° in a ring have boxes that overlap
  /// while the screens themselves are comfortably apart.
  void _rejectOverlaps(BoardPlan plan, LobbyInfo lobby) {
    for (var i = 0; i < plan.placements.length; i++) {
      for (var j = i + 1; j < plan.placements.length; j++) {
        final a = plan.placements[i];
        final b = plan.placements[j];
        if (_overlaps(a, lobby.byId(a.phoneId)!, b, lobby.byId(b.phoneId)!)) {
          throw BoardPlanError(
            '${a.phoneId} and ${b.phoneId} overlap — two screens cannot show '
            'the same part of the board',
          );
        }
      }
    }
  }

  /// A phone floating on its own would be handed a slice of a world it has no
  /// physical connection to. Almost always a sign the plan's arithmetic is off
  /// — unless the plan says the spacing is deliberate.
  void _requireConnected(BoardPlan plan, LobbyInfo lobby) {
    if (plan.placements.length < 2) return;

    bool touches(PhonePlacement a, PhonePlacement b) {
      final ba = _Box.of(a, lobby.byId(a.phoneId)!);
      final bb = _Box.of(b, lobby.byId(b.phoneId)!);
      // Same measurement as the join test, from the same function — not a
      // second implementation that happens to agree today.
      final gapX = BoardLinks.separation(ba.left, ba.right, bb.left, bb.right);
      final gapY = BoardLinks.separation(ba.top, ba.bottom, bb.top, bb.bottom);
      return gapX <= _reachMm && gapY <= _reachMm;
    }

    final seen = <String>{plan.placements.first.phoneId};
    final queue = <PhonePlacement>[plan.placements.first];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final other in plan.placements) {
        if (seen.contains(other.phoneId)) continue;
        if (touches(current, other)) {
          seen.add(other.phoneId);
          queue.add(other);
        }
      }
    }

    if (seen.length != plan.placements.length) {
      final stranded = plan.placements
          .where((p) => !seen.contains(p.phoneId))
          .map((p) => p.phoneId)
          .join(', ');
      throw BoardPlanError(
        'leaves $stranded disconnected from the rest of the board — pass '
        'allowGaps if the space is deliberate',
      );
    }
  }

  /// Separating-axis test between two turned rectangles.
  static bool _overlaps(
    PhonePlacement a,
    PhoneSpec sa,
    PhonePlacement b,
    PhoneSpec sb,
  ) {
    final axes = <_Vec>[
      _Vec.unit(a.turnRadians),
      _Vec.unit(a.turnRadians + math.pi / 2),
      _Vec.unit(b.turnRadians),
      _Vec.unit(b.turnRadians + math.pi / 2),
    ];
    final dx = b.xMm - a.xMm;
    final dy = b.yMm - a.yMm;

    for (final axis in axes) {
      final centreGap = (dx * axis.x + dy * axis.y).abs();
      final reach = _project(sa, a.turnRadians, axis) +
          _project(sb, b.turnRadians, axis);
      // A single axis with daylight on it is enough to prove they are apart.
      if (centreGap > reach - _epsilonMm) return false;
    }
    return true;
  }

  /// Half the extent of a turned screen along [axis].
  static double _project(PhoneSpec spec, double turn, _Vec axis) {
    final u = _Vec.unit(turn);
    final v = _Vec.unit(turn + math.pi / 2);
    return (spec.widthMm / 2) * (u.x * axis.x + u.y * axis.y).abs() +
        (spec.heightMm / 2) * (v.x * axis.x + v.y * axis.y).abs();
  }

  static String _defaultHint(int index, int total) {
    if (total == 1) return 'alone — the whole board is on this screen';
    return 'phone ${index + 1} of $total';
  }
}

/// A compiled screen, as the coverage map and the diagram want it.
ScreenRect _screenOf(PhoneLayout l) => ScreenRect(
  centerX: l.worldCenterX,
  centerY: l.worldCenterY,
  width: l.halfWidth * 2,
  height: l.halfHeight * 2,
  turnRadians: l.turnRadians,
);

class _Vec {
  const _Vec(this.x, this.y);
  factory _Vec.unit(double radians) =>
      _Vec(math.cos(radians), math.sin(radians));
  final double x;
  final double y;
}

/// A screen's axis-aligned extent in plan millimetres, turn included.
class _Box {
  const _Box(this.left, this.top, this.right, this.bottom);

  factory _Box.of(PhonePlacement placement, PhoneSpec spec) {
    final c = math.cos(placement.turnRadians).abs();
    final s = math.sin(placement.turnRadians).abs();
    final hw = (spec.widthMm / 2) * c + (spec.heightMm / 2) * s;
    final hh = (spec.widthMm / 2) * s + (spec.heightMm / 2) * c;
    return _Box(
      placement.xMm - hw,
      placement.yMm - hh,
      placement.xMm + hw,
      placement.yMm + hh,
    );
  }

  final double left;
  final double top;
  final double right;
  final double bottom;
}
