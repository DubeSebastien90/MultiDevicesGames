import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
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
        expect(board.coverage.isCovered(w.x, w.y), isTrue);
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
        expect(board.coverage.isCovered(w.x, w.y), isTrue);
      }
    });
  });
}
