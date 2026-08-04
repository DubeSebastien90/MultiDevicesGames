import '../platform_config.dart';
import '../model/coverage_map.dart';
import '../model/phone_layout.dart';
import '../model/world_rect.dart';
import '../contract/sim.dart';
import '../score/scoreboard.dart';
import 'board_plan.dart';
import 'phone_spec.dart';

/// The compiled board: what the platform runs on, built from a game's plan.
class BoardLayout {
  const BoardLayout({
    required this.phones,
    required this.coverage,
    required this.mmToWorld,
    required this.slices,
    required this.instruction,
  });

  final List<PhoneLayout> phones;
  final CoverageMap coverage;
  final double mmToWorld;

  /// Named screen rectangles, in board order. The compiled truth about where
  /// every phone ended up — what a sim asks "whose screen is this?" against,
  /// and what the placement diagram is drawn from.
  final List<PhoneSlice> slices;

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

  /// Overlap is judged in millimetres with this much slack, so that two edges
  /// meant to be flush are not called an overlap by a rounding error.
  static const double _epsilonMm = 0.01;

  BoardLayout compile(BoardPlan plan, LobbyInfo lobby) {
    _validate(plan, lobby);

    // Normalise: whatever coordinates the game chose, the board's top-left
    // corner is the world origin. When the plan declares its playfield, that
    // is the origin; otherwise it is the top-left screen.
    var minX = double.infinity;
    var minY = double.infinity;
    for (final placement in plan.placements) {
      minX = placement.xMm < minX ? placement.xMm : minX;
      minY = placement.yMm < minY ? placement.yMm : minY;
    }
    final declared = plan.bounds;
    if (declared != null) {
      minX = declared.leftMm;
      minY = declared.topMm;
    }

    // Ordered by position, then, so "phone 1" means the first one you reach
    // reading the board the way it is laid out.
    final ordered = List.of(plan.placements)
      ..sort((a, b) {
        final byY = a.yMm.compareTo(b.yMm);
        if (byY != 0 && (a.yMm - b.yMm).abs() > _epsilonMm) return byY;
        return a.xMm.compareTo(b.xMm);
      });

    final double boardWidthMm;
    final double boardHeightMm;
    if (declared != null) {
      boardWidthMm = declared.widthMm;
      boardHeightMm = declared.heightMm;
    } else {
      // No declared playfield: the box around every screen.
      var maxX = -double.infinity;
      var maxY = -double.infinity;
      for (final placement in ordered) {
        final spec = lobby.byId(placement.phoneId)!;
        final right = placement.xMm -
            minX +
            spec.footprintWidthMm(placement.quarterTurns);
        final bottom = placement.yMm -
            minY +
            spec.footprintHeightMm(placement.quarterTurns);
        maxX = right > maxX ? right : maxX;
        maxY = bottom > maxY ? bottom : maxY;
      }
      boardWidthMm = maxX;
      boardHeightMm = maxY;
    }

    if (boardWidthMm <= 0 || boardHeightMm <= 0) {
      throw const BoardPlanError('the playfield has no area');
    }

    final board =
        WorldRect(0, 0, boardWidthMm * mmToWorld, boardHeightMm * mmToWorld);

    final layouts = <PhoneLayout>[];
    final liveRects = <WorldRect>[];
    final slices = <PhoneSlice>[];
    for (var i = 0; i < ordered.length; i++) {
      final placement = ordered[i];
      final spec = lobby.byId(placement.phoneId)!;
      final layout = PhoneLayout(
        phoneId: spec.phoneId,
        index: i,
        total: ordered.length,
        worldOffsetX: (placement.xMm - minX) * mmToWorld,
        worldOffsetY: (placement.yMm - minY) * mmToWorld,
        mmToWorld: mmToWorld,
        dpi: spec.dpi,
        devicePixelRatio: spec.devicePixelRatio,
        activePxWidth: spec.footprintPxWidth(placement.quarterTurns),
        activePxHeight: spec.footprintPxHeight(placement.quarterTurns),
        quarterTurns: placement.quarterTurns,
        board: board,
        placement: placement.hint ?? _defaultHint(i, ordered.length),
      );
      layouts.add(layout);
      liveRects.add(layout.viewport);
      slices.add(
        PhoneSlice(
          spec.phoneId,
          layout.viewport,
          label: spec.label,
          color: spec.color,
        ),
      );
    }

    return BoardLayout(
      phones: layouts,
      coverage: CoverageMap(liveRects: liveRects, board: board),
      mmToWorld: mmToWorld,
      slices: slices,
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
        throw BoardPlanError(
          'places unknown phone "${placement.phoneId}"',
        );
      }
      if (!placed.add(placement.phoneId)) {
        throw BoardPlanError('places ${placement.phoneId} more than once');
      }
      if (!placement.xMm.isFinite || !placement.yMm.isFinite) {
        throw BoardPlanError(
          '${placement.phoneId} has a non-finite position',
        );
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

    _rejectOverlaps(plan, lobby);
    _requireConnected(plan, lobby);
  }

  /// Two screens claiming the same world coordinates is not a layout, it is a
  /// bug that would present as a rendering glitch.
  void _rejectOverlaps(BoardPlan plan, LobbyInfo lobby) {
    for (var i = 0; i < plan.placements.length; i++) {
      for (var j = i + 1; j < plan.placements.length; j++) {
        final a = plan.placements[i];
        final b = plan.placements[j];
        final sa = lobby.byId(a.phoneId)!;
        final sb = lobby.byId(b.phoneId)!;

        final aw = sa.footprintWidthMm(a.quarterTurns);
        final ah = sa.footprintHeightMm(a.quarterTurns);
        final bw = sb.footprintWidthMm(b.quarterTurns);
        final bh = sb.footprintHeightMm(b.quarterTurns);

        final overlapX = a.xMm < b.xMm + bw - _epsilonMm &&
            b.xMm < a.xMm + aw - _epsilonMm;
        final overlapY = a.yMm < b.yMm + bh - _epsilonMm &&
            b.yMm < a.yMm + ah - _epsilonMm;

        if (overlapX && overlapY) {
          throw BoardPlanError(
            '${a.phoneId} and ${b.phoneId} overlap — two screens cannot show '
            'the same part of the board',
          );
        }
      }
    }
  }

  /// A phone floating on its own would be handed a slice of a world it has no
  /// physical connection to. Almost always a sign the plan's arithmetic is off.
  void _requireConnected(BoardPlan plan, LobbyInfo lobby) {
    if (plan.placements.length < 2) return;

    /// Two screens are neighbours when their rectangles are within a
    /// generous bezel's reach of each other.
    const reachMm = 40.0;

    bool touches(PhonePlacement a, PhonePlacement b) {
      final sa = lobby.byId(a.phoneId)!;
      final sb = lobby.byId(b.phoneId)!;
      final gapX = a.xMm > b.xMm
          ? a.xMm - (b.xMm + sb.footprintWidthMm(b.quarterTurns))
          : b.xMm - (a.xMm + sa.footprintWidthMm(a.quarterTurns));
      final gapY = a.yMm > b.yMm
          ? a.yMm - (b.yMm + sb.footprintHeightMm(b.quarterTurns))
          : b.yMm - (a.yMm + sa.footprintHeightMm(a.quarterTurns));
      return gapX <= reachMm && gapY <= reachMm;
    }

    // Flood fill from the first placement.
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
        'leaves $stranded disconnected from the rest of the board',
      );
    }
  }

  static String _defaultHint(int index, int total) {
    if (total == 1) return 'alone — the whole board is on this screen';
    return 'phone ${index + 1} of $total';
  }
}
