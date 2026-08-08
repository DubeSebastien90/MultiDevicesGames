import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_config.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/track.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';

void main() {
  group('PitchTrack — an open two-point track', () {
    final track = PitchTrack(
      waypoints: const [Waypoint(0, 0), Waypoint(10, 0)],
      widthWorld: 2,
      closed: false,
    );

    test('length is the straight-line distance', () {
      expect(track.length, closeTo(10, 1e-9));
    });

    test('a point on the centerline is on track', () {
      expect(track.isOnTrack(5, 0), isTrue);
    });

    test('a point just inside the width is on track', () {
      expect(track.isOnTrack(5, 0.9), isTrue);
    });

    test('a point outside the width is off track', () {
      expect(track.isOnTrack(5, 1.1), isFalse);
    });

    test('progress runs from 0 at the start to length at the end', () {
      expect(track.progressAt(0, 0), closeTo(0, 1e-9));
      expect(track.progressAt(10, 0), closeTo(10, 1e-9));
      expect(track.progressAt(5, 0), closeTo(5, 1e-9));
    });

    test('pointAtArclength is the inverse of progressAt on the centerline', () {
      final p = track.pointAtArclength(3);
      expect(p.x, closeTo(3, 1e-9));
      expect(p.y, closeTo(0, 1e-9));
    });

    test('tangentAt points along the track', () {
      final t = track.tangentAt(5);
      expect(t.x, closeTo(1, 1e-6));
      expect(t.y, closeTo(0, 1e-6));
    });
  });

  group('PitchTrack — a closed square loop', () {
    final track = PitchTrack(
      waypoints: const [
        Waypoint(-5, -5),
        Waypoint(5, -5),
        Waypoint(5, 5),
        Waypoint(-5, 5),
      ],
      widthWorld: 2,
      closed: true,
    );

    test('length includes the closing segment back to the first point', () {
      expect(track.length, closeTo(40, 1e-9));
    });

    test('the ring is on track; its hollow centre is not', () {
      expect(track.isOnTrack(0, -5), isTrue); // on the bottom edge
      expect(track.isOnTrack(0, 0), isFalse); // the donut hole
    });

    test('a point well outside the ring is off track', () {
      expect(track.isOnTrack(0, -20), isFalse);
    });

    test('progress wraps: the point after the last waypoint is near the start',
        () {
      // Just past the last waypoint, heading back toward the first.
      final p = track.pointAtArclength(39.5);
      expect(p.x, closeTo(-5, 1e-6));
      expect(p.y, closeTo(-4.5, 1e-6));
    });
  });

  group('TrackGenerator', () {
    PhoneSpec phone(String id) => PhoneSpec(
          phoneId: id,
          label: 'phone $id',
          widthMm: 68.58,
          heightMm: 152.4,
          bezelMm: 3,
          dpi: 400,
          devicePixelRatio: 3,
          activePxWidth: 1080,
          activePxHeight: 2400,
        );

    /// Three phones placed by hand into an L: p1—p2 side by side, p2—p3
    /// stacked below p2 — deterministic, so the turn is guaranteed rather
    /// than hunted for with a random seed.
    BoardLayout lShape() {
      final phones = [phone('p1'), phone('p2'), phone('p3')];
      final plan = BoardPlan(const [
        PhonePlacement('p1', xMm: 0, yMm: 0),
        PhonePlacement('p2', xMm: 68.58, yMm: 0),
        PhonePlacement('p3', xMm: 68.58, yMm: 152.4),
      ]);
      return const BoardCompiler().compile(plan, LobbyInfo(phones));
    }

    BoardLayout straightRow([int count = 3]) {
      final phones = [for (var i = 0; i < count; i++) phone('p${i + 1}')];
      return const BoardCompiler()
          .compile(Layouts.row(phones), LobbyInfo(phones));
    }

    /// A 4-phone zigzag: p1—p2 side by side, p2—p3 stacked below p2, p3—p4
    /// side by side to the right of p3 (right, down, right).
    BoardLayout zigzag() {
      final phones = [phone('p1'), phone('p2'), phone('p3'), phone('p4')];
      final plan = BoardPlan(const [
        PhonePlacement('p1', xMm: 0, yMm: 0),
        PhonePlacement('p2', xMm: 68.58, yMm: 0),
        PhonePlacement('p3', xMm: 68.58, yMm: 152.4),
        PhonePlacement('p4', xMm: 137.16, yMm: 152.4),
      ]);
      return const BoardCompiler().compile(plan, LobbyInfo(phones));
    }

    /// True when (w.x, w.y) is either on a screen or inside one of the
    /// board's seam gaps — the property a continuous centerline can actually
    /// guarantee on a real (gapped) board, unlike full `CoverageMap` coverage.
    bool onBoard(BoardLayout board, Waypoint w) {
      if (board.coverage.isCovered(w.x, w.y)) return true;
      for (final seam in board.coverage.seamRects()) {
        if (seam.inflate(0.05).contains(w.x, w.y)) return true;
      }
      return false;
    }

    test('closed is always false', () {
      final board = straightRow();
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(1),
      );
      expect(track.closed, isFalse);
    });

    test('follows the chain order, not the order slices were passed in', () {
      final board = lShape();
      // Fed in an order that does not match the physical chain — recovery
      // must not depend on input order.
      final shuffled = [
        board.slices.firstWhere((s) => s.phoneId == 'p3'),
        board.slices.firstWhere((s) => s.phoneId == 'p1'),
        board.slices.firstWhere((s) => s.phoneId == 'p2'),
      ];
      final track = TrackGenerator.generate(
        slices: shuffled,
        random: math.Random(1),
      );

      final p1 = board.slices.firstWhere((s) => s.phoneId == 'p1').viewport;
      final p3 = board.slices.firstWhere((s) => s.phoneId == 'p3').viewport;
      final endpoints = [track.waypoints.first, track.waypoints.last];
      // The chain has two valid directions (p1->p3 or p3->p1) — either is
      // correct, so check both ends are the outer phones, not which is
      // first.
      expect(endpoints.any((w) => p1.contains(w.x, w.y)), isTrue);
      expect(endpoints.any((w) => p3.contains(w.x, w.y)), isTrue);
    });

    test('a straight row stays within the board coverage', () {
      final board = straightRow();
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(2),
      );
      for (final w in track.waypoints) {
        expect(onBoard(board, w), isTrue);
      }
    });

    test(
        'an L-shaped chain turns the corner instead of cutting across the '
        'missing square', () {
      final board = lShape();
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(3),
      );
      for (final w in track.waypoints) {
        expect(onBoard(board, w), isTrue);
      }
    });

    test('the centerline wiggles inside a straight-through phone', () {
      final board = straightRow();
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: _MaxRandom(),
      );
      // Control points for a 3-phone chain: [start, offset0, seam0,
      // offset1, seam1, offset2, end] — offset1 is the interior phone's.
      // The spline interpolates every control point exactly, at flattened
      // index `k * splineSamplesPerSegment` for control index `k`.
      const s = PitchCarsConfig.splineSamplesPerSegment;
      final offset = track.waypoints[3 * s];
      final before = track.waypoints[2 * s];
      final after = track.waypoints[4 * s];
      final chordMidX = (before.x + after.x) / 2;
      final chordMidY = (before.y + after.y) / 2;
      final deviation = math.sqrt(
        math.pow(offset.x - chordMidX, 2) + math.pow(offset.y - chordMidY, 2),
      );
      expect(deviation, greaterThan(0.1));
    });

    test('the wiggle amplitude through a turn is smaller than through a '
        'straight run', () {
      double deviation(PitchTrack t) {
        // See the comment in the previous test for the index mapping.
        const s = PitchCarsConfig.splineSamplesPerSegment;
        final offset = t.waypoints[3 * s];
        final before = t.waypoints[2 * s];
        final after = t.waypoints[4 * s];
        final midX = (before.x + after.x) / 2;
        final midY = (before.y + after.y) / 2;
        return math.sqrt(math.pow(offset.x - midX, 2) + math.pow(offset.y - midY, 2));
      }

      final straightTrack = TrackGenerator.generate(
        slices: straightRow().slices,
        random: _MaxRandom(),
      );
      final turnTrack = TrackGenerator.generate(
        slices: lShape().slices,
        random: _MaxRandom(),
      );

      expect(deviation(turnTrack), lessThan(deviation(straightTrack)));
    });

    test('the spline is sampled densely between each control point', () {
      final board = straightRow(3);
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(1),
      );
      // 3 phones -> 7 control points (start, offset, seam, offset, seam,
      // offset, end) -> 6 segments between them.
      final expected = 6 * PitchCarsConfig.splineSamplesPerSegment + 1;
      expect(track.waypoints.length, expected);
    });

    test('the minimum 2-phone chain samples cleanly', () {
      final board = straightRow(2);
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(1),
      );
      // 2 phones -> 5 control points -> 4 segments.
      expect(track.waypoints.length, 4 * PitchCarsConfig.splineSamplesPerSegment + 1);
      expect(track.closed, isFalse);
    });

    test(
        'the sampled centerline stays within coverage after spline '
        'smoothing, even at maximum wiggle', () {
      for (final board in [straightRow(), lShape()]) {
        final track = TrackGenerator.generate(
          slices: board.slices,
          random: _MaxRandom(),
        );
        for (final w in track.waypoints) {
          expect(onBoard(board, w), isTrue);
        }
      }
    });

    test('a zigzag chain does not throw and stays on board', () {
      final board = zigzag();
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(4),
      );
      for (final w in track.waypoints) {
        expect(onBoard(board, w), isTrue);
      }
    });

    test('a longer (6-phone) straight row stays on board structurally', () {
      final board = straightRow(6);
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(5),
      );
      for (final w in track.waypoints) {
        expect(onBoard(board, w), isTrue);
      }
    });

    test('a longer chain produces a longer track', () {
      final shortTrack = TrackGenerator.generate(
        slices: straightRow(2).slices,
        random: math.Random(1),
      );
      final longTrack = TrackGenerator.generate(
        slices: straightRow(6).slices,
        random: math.Random(1),
      );
      expect(longTrack.length, greaterThan(shortTrack.length));
    });

    test('a very narrow corner phone does not throw', () {
      final narrow = PhoneSpec(
        phoneId: 'p2',
        label: 'narrow',
        widthMm: 20,
        heightMm: 152.4,
        bezelMm: 3,
        dpi: 400,
        devicePixelRatio: 3,
        activePxWidth: 1080,
        activePxHeight: 2400,
      );
      final phones = [phone('p1'), narrow, phone('p3')];
      final plan = BoardPlan(const [
        PhonePlacement('p1', xMm: 0, yMm: 0),
        PhonePlacement('p2', xMm: 68.58, yMm: 0),
        PhonePlacement('p3', xMm: 68.58, yMm: 152.4),
      ]);
      final board = const BoardCompiler().compile(plan, LobbyInfo(phones));
      expect(
        () => TrackGenerator.generate(slices: board.slices, random: _MaxRandom()),
        returnsNormally,
      );
    });

    test('a branched (non-chain) board degrades instead of crashing', () {
      // A "T": p1 left of p2, p3 right of p2, p4 below p2 — p2 has three
      // neighbours, so no simple walk reaches every phone. `Layouts.path`
      // never produces this today, but the algorithm must not need to
      // change if a future iteration widens `PlayerCount.range`.
      final phones = [phone('p1'), phone('p2'), phone('p3'), phone('p4')];
      final plan = BoardPlan(const [
        PhonePlacement('p1', xMm: 0, yMm: 0),
        PhonePlacement('p2', xMm: 68.58, yMm: 0),
        PhonePlacement('p3', xMm: 137.16, yMm: 0),
        PhonePlacement('p4', xMm: 68.58, yMm: 152.4),
      ]);
      final board = const BoardCompiler().compile(plan, LobbyInfo(phones));
      expect(
        () => TrackGenerator.generate(slices: board.slices, random: _MaxRandom()),
        returnsNormally,
      );
    });
  });
}

/// Forces every random draw to its maximum — for testing the wiggle
/// amplitude clamp at its boundary rather than hoping a seed reaches it.
class _MaxRandom implements math.Random {
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 1.0;
  @override
  int nextInt(int max) => max - 1;
}
