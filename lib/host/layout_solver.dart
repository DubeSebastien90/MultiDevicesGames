import 'dart:math' as math;

import '../game/game_config.dart';
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
  });

  final List<PhoneLayout> phones;
  final CoverageMap coverage;
  final double mmToWorld;

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

/// Packs phones into the v1 arrangement: butted together left-to-right, top
/// edges aligned, forming a strip.
///
/// Freeform packing is explicitly out of scope. Phones may still differ in size
/// and density — that is absorbed entirely by the per-phone transform, which is
/// the part that actually needed proving.
class LayoutSolver {
  const LayoutSolver({this.mmToWorld = GameConfig.mmToWorld});

  final double mmToWorld;

  BoardLayout solve(List<CalibratedPhone> phones) {
    assert(phones.isNotEmpty, 'need at least one phone to build a board');

    // Pass 1: walk left to right accumulating x offsets.
    final offsets = <double>[];
    var cursor = 0.0;
    for (var i = 0; i < phones.length; i++) {
      offsets.add(cursor);
      cursor += phones[i].metrics.widthMm * mmToWorld;
      if (i < phones.length - 1) {
        // The gap between two active areas is the right bezel of the left phone
        // plus the left bezel of the right one. Physically real space the bird
        // must fly through, so it belongs in the world, not hidden away.
        final gapMm = phones[i].metrics.bezelMm + phones[i + 1].metrics.bezelMm;
        cursor += gapMm * mmToWorld;
      }
    }

    // The playfield hugs the covered area: its height is the *shortest* screen,
    // so the only dead zones left are real bezel gaps and they all mean the
    // same thing.
    final heights = phones.map((p) => p.metrics.heightMm * mmToWorld);
    final boardHeight = heights.reduce(math.min);
    final board = WorldRect(0, 0, cursor, boardHeight);

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
        worldOffsetX: offsets[i],
        worldOffsetY: 0, // top-aligned by construction
        mmToWorld: mmToWorld,
        dpi: m.dpi,
        devicePixelRatio: m.devicePixelRatio,
        activePxWidth: m.activePxWidth,
        activePxHeight: m.activePxHeight,
        board: board,
        placement: _placementFor(i, phones.length),
      );
      layouts.add(layout);
      liveRects.add(layout.viewport);
    }

    return BoardLayout(
      phones: layouts,
      coverage: CoverageMap(liveRects: liveRects, board: board),
      mmToWorld: mmToWorld,
    );
  }

  static String _placementFor(int index, int total) {
    if (total == 1) return 'alone — the whole board is on this screen';
    if (index == 0) return 'leftmost — everyone else goes to your right';
    return 'right of phone $index, top edges aligned';
  }
}
