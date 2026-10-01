import 'dart:math' as math;

import '../audio/game_audio.dart';
import '../contract/sim.dart';
import '../model/coverage_map.dart';
import '../model/player.dart';
import '../model/phone_layout.dart';
import '../model/world_rect.dart';
import '../platform_config.dart';
import '../score/scoreboard.dart';
import 'board_links.dart';
import 'board_plan.dart';
import 'phone_spec.dart';

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

  final List<PhoneSlice> slices;

  final List<EdgeMarker> links;

  final String instruction;

  WorldRect get board => coverage.board;

  PhoneLayout? forPhone(String id) {
    for (final p in phones) {
      if (p.phoneId == id) return p;
    }
    return null;
  }

  Roster rosterFor({String? hostPhoneId}) => Roster([
    for (final s in slices)
      if (s.color != null)
        Player(phoneId: s.phoneId, color: s.color!, label: s.label),
  ], hostPhoneId: hostPhoneId);

  Roster get roster => rosterFor();

  BoardContext contextFor(
    Scoreboard scores, {
    GameAudio? audio,
    String? hostPhoneId,
  }) => BoardContext(
    board: board,
    coverage: coverage,
    scores: scores,
    slices: slices,
    roster: rosterFor(hostPhoneId: hostPhoneId),
    audio: audio ?? const SilentGameAudio(),
  );
}

class BoardCompiler {
  const BoardCompiler({this.mmToWorld = PlatformConfig.mmToWorld});

  final double mmToWorld;

  static const double _epsilonMm = 0.01;

  double get _reachMm => BoardLinks.maxJoinGap / mmToWorld;

  BoardLayout compile(BoardPlan plan, LobbyInfo lobby) {
    _validate(plan, lobby);

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

    final board = WorldRect(
      0,
      0,
      boardWidthMm * mmToWorld,
      boardHeightMm * mmToWorld,
    );

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
      slices.add(
        PhoneSlice(
          spec.phoneId,
          _screenOf(layout),
          label: spec.label,
          color: spec.color,
        ),
      );
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

  void _requireHonestScale(LobbyInfo lobby) {
    for (final spec in lobby.phones) {
      if (spec.activePxWidth <= 0 || spec.widthMm <= 0) continue;
      final byPixels = spec.activePxHeight / spec.activePxWidth;
      final byMillimetres = spec.heightMm / spec.widthMm;

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

  void _requireConnected(BoardPlan plan, LobbyInfo lobby) {
    if (plan.placements.length < 2) return;

    bool touches(PhonePlacement a, PhonePlacement b) {
      final ba = _Box.of(a, lobby.byId(a.phoneId)!);
      final bb = _Box.of(b, lobby.byId(b.phoneId)!);

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
      final reach =
          _project(sa, a.turnRadians, axis) + _project(sb, b.turnRadians, axis);

      if (centreGap > reach - _epsilonMm) return false;
    }
    return true;
  }

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
