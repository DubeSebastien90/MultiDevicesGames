import 'dart:math' as math;

import '../game/game_config.dart';
import '../model/arrangement.dart';
import '../model/coverage_map.dart';
import '../model/device_metrics.dart';
import '../model/phone_layout.dart';
import '../model/world_rect.dart';

/// The host's mental model of the physical arrangement.
class BoardLayout {
  const BoardLayout({
    required this.phones,
    required this.coverage,
    required this.mmToWorld,
    required this.arrangement,
  });

  final List<PhoneLayout> phones;
  final CoverageMap coverage;
  final double mmToWorld;
  final Arrangement arrangement;

  WorldRect get board => coverage.board;

  PhoneLayout? forPhone(String id) {
    for (final p in phones) {
      if (p.phoneId == id) return p;
    }
    return null;
  }
}

/// One phone as calibration knows it.
class CalibratedPhone {
  const CalibratedPhone(this.phoneId, this.metrics);
  final String phoneId;
  final DeviceMetrics metrics;
}

/// Packs phones into the arrangement a minigame asked for: butted together
/// along one axis, flush along the other.
///
/// Freeform packing is explicitly out of scope. Phones may still differ in size
/// and density — that is absorbed entirely by the per-phone transform, which is
/// the part that actually needed proving. Adding [Arrangement.stack] on top of
/// the original strip needed no change to that transform at all: a phone's
/// offset was always a full (x, y), the second component just happened to be
/// zero every time.
class LayoutSolver {
  const LayoutSolver({this.mmToWorld = GameConfig.mmToWorld});

  final double mmToWorld;

  BoardLayout solve(
    List<CalibratedPhone> phones, {
    Arrangement arrangement = Arrangement.strip,
  }) {
    assert(phones.isNotEmpty, 'need at least one phone to build a board');
    final horizontal = arrangement.isHorizontal;

    // Pass 1: walk along the packing axis accumulating offsets.
    final offsets = <double>[];
    var cursor = 0.0;
    for (var i = 0; i < phones.length; i++) {
      offsets.add(cursor);
      final m = phones[i].metrics;
      cursor += (horizontal ? m.widthMm : m.heightMm) * mmToWorld;
      if (i < phones.length - 1) {
        // The gap between two active areas is the trailing bezel of one phone
        // plus the leading bezel of the next. Physically real space the bird or
        // ball must cross, so it belongs in the world, not hidden away.
        final gapMm = phones[i].metrics.bezelMm + phones[i + 1].metrics.bezelMm;
        cursor += gapMm * mmToWorld;
      }
    }

    // The playfield hugs the covered area: across the packing axis it is as
    // wide as the *smallest* screen, so the only dead zones left are real bezel
    // gaps and they all mean the same thing.
    final across = phones
        .map((p) =>
            (horizontal ? p.metrics.heightMm : p.metrics.widthMm) * mmToWorld)
        .reduce(math.min);

    final board = horizontal
        ? WorldRect(0, 0, cursor, across)
        : WorldRect(0, 0, across, cursor);

    // Pass 2: now that the board is known, build the per-phone layouts.
    final layouts = <PhoneLayout>[];
    final liveRects = <WorldRect>[];
    for (var i = 0; i < phones.length; i++) {
      final p = phones[i];
      final m = p.metrics;
      final layout = PhoneLayout(
        phoneId: p.phoneId,
        index: i,
        total: phones.length,
        // Flush along the off-axis by construction, hence the zero.
        worldOffsetX: horizontal ? offsets[i] : 0,
        worldOffsetY: horizontal ? 0 : offsets[i],
        mmToWorld: mmToWorld,
        dpi: m.dpi,
        devicePixelRatio: m.devicePixelRatio,
        activePxWidth: m.activePxWidth,
        activePxHeight: m.activePxHeight,
        board: board,
        placement: _placementFor(i, phones.length, arrangement),
      );
      layouts.add(layout);
      liveRects.add(layout.viewport);
    }

    return BoardLayout(
      phones: layouts,
      coverage: CoverageMap(
        liveRects: liveRects,
        board: board,
        arrangement: arrangement,
      ),
      mmToWorld: mmToWorld,
      arrangement: arrangement,
    );
  }

  static String _placementFor(int index, int total, Arrangement arrangement) {
    if (total == 1) return 'alone — the whole board is on this screen';
    if (arrangement.isHorizontal) {
      if (index == 0) return 'leftmost — everyone else goes to your right';
      return 'right of phone $index, top edges aligned';
    }
    if (index == 0) return 'top — everyone else goes below you';
    return 'below phone $index, left edges aligned';
  }
}
