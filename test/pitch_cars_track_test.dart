import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_config.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_game.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/pitch_cars_scale.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/track.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';

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

  group('the game and its board', () {
    /// A real device: pixels follow the millimetres at one density.
    PhoneSpec device(String id) => PhoneSpec(
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

    test('every phone on the table gets a piece of the track', () {
      // The contract between this game and the layout it asks for, and the
      // reason it asks for a path rather than any old arrangement: the track is
      // laid by walking the board end to end, so a board that forks makes the
      // walk pick one way and drop the rest — and a dropped phone is somebody
      // watching a blank screen for the whole round.
      //
      // Checked through `planBoard` rather than by calling the layout helper
      // directly, so it is the game's own choice being tested.
      const game = PitchCarsGame();

      for (var count = 2; count <= 8; count++) {
        for (var seed = 0; seed < 25; seed++) {
          final phones = [for (var i = 0; i < count; i++) device('p${i + 1}')];
          final board = const BoardCompiler()
              .compile(game.planBoard(LobbyInfo(phones)), LobbyInfo(phones));
          final track = TrackGenerator.generate(
            slices: board.slices,
            random: math.Random(seed),
          );

          for (final slice in board.slices) {
            final v = slice.viewport;
            final touched = track.waypoints.any((w) =>
                w.x >= v.left - 0.5 &&
                w.x <= v.right + 0.5 &&
                w.y >= v.top - 0.5 &&
                w.y <= v.bottom + 0.5);
            expect(touched, isTrue,
                reason: '$count phones, seed $seed: no track reaches '
                    '${slice.phoneId}');
          }
        }
      }
    });
  });

  group('TrackGenerator', () {
    /// Pixels follow the millimetres, at one fixed density.
    ///
    /// Derived rather than typed, so a fixture cannot name a size and keep
    /// somebody else's pixel count — that describes a device with
    /// non-square pixels, which does not exist, and a test built on one proves
    /// nothing about a real table.
    PhoneSpec phone(
      String id, {
      double widthMm = 68.58,
      double heightMm = 152.4,
      String? label,
    }) =>
        PhoneSpec(
          phoneId: id,
          label: label ?? 'phone $id',
          widthMm: widthMm,
          heightMm: heightMm,
          bezelMm: 3,
          dpi: 400,
          devicePixelRatio: 3,
          activePxWidth: widthMm * 400 / 25.4,
          activePxHeight: heightMm * 400 / 25.4,
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

    /// How far the road strays from the straight line between the points where
    /// it enters and leaves [phone] — the amplitude of that phone's wiggle.
    ///
    /// Measured as the furthest perpendicular distance of any of that phone's
    /// bend control points from the entry-to-exit chord, rather than as one
    /// named point's distance from the chord's midpoint. A small table now gets
    /// **two** bends per phone, thrown opposite ways at the thirds of the
    /// chord, so there is no longer a single middle point to look at and
    /// neither of the two sits at the middle anyway.
    ///
    /// The spline interpolates every control point exactly, at flattened index
    /// `k * splineSamplesPerSegment` for control index `k`. Phone `i` owns
    /// control points `i * (bends + 1) + 1 ..= i * (bends + 1) + bends`,
    /// between its entry at `i * (bends + 1)` and its exit at the next one.
    double wiggleAmplitude(PitchTrack t, int phone, int phones) {
      final bends = PitchCarsScale.forPlayers(phones).bendsPerPhone;
      const s = PitchCarsConfig.splineSamplesPerSegment;
      Waypoint at(int control) => t.waypoints[control * s];

      final entry = at(phone * (bends + 1));
      final exit = at((phone + 1) * (bends + 1));
      final dx = exit.x - entry.x;
      final dy = exit.y - entry.y;
      final chord = math.sqrt(dx * dx + dy * dy);
      if (chord < 1e-9) return 0;

      var worst = 0.0;
      for (var k = 1; k <= bends; k++) {
        final p = at(phone * (bends + 1) + k);
        final off =
            ((p.x - entry.x) * dy - (p.y - entry.y) * dx).abs() / chord;
        if (off > worst) worst = off;
      }
      return worst;
    }

    test('the centerline wiggles inside a straight-through phone', () {
      final board = straightRow();
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: _MaxRandom(),
      );
      // The middle phone of three: entered and left on opposite edges, so the
      // road has the whole screen to wander across.
      expect(wiggleAmplitude(track, 1, 3), greaterThan(0.1));
    });

    test('the wiggle amplitude through a turn is smaller than through a '
        'straight run', () {
      final straightTrack = TrackGenerator.generate(
        slices: straightRow().slices,
        random: _MaxRandom(),
      );
      final turnTrack = TrackGenerator.generate(
        slices: lShape().slices,
        random: _MaxRandom(),
      );

      expect(
        wiggleAmplitude(turnTrack, 1, 3),
        lessThan(wiggleAmplitude(straightTrack, 1, 3)),
      );
    });

    /// How many waypoints a chain of [phones] should sample to.
    ///
    /// Each phone contributes its bends plus the point where the road leaves
    /// it, and the whole chain one more where it enters the first phone:
    ///
    ///     control points = phones × (bends + 1) + 1
    ///
    /// [PitchCarsScale] sets the bends, and a small table now gets two of them
    /// — an S across each screen, to make a short board interesting. So this
    /// is no longer the fixed `one wiggle per phone` the counts were written
    /// against.
    int sampledLength(int phones) {
      final bends = PitchCarsScale.forPlayers(phones).bendsPerPhone;
      final segments = phones * (bends + 1);
      return segments * PitchCarsConfig.splineSamplesPerSegment + 1;
    }

    test('the spline is sampled densely between each control point', () {
      final board = straightRow(3);
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(1),
      );
      expect(track.waypoints.length, sampledLength(3));
    });

    test('the minimum 2-phone chain samples cleanly', () {
      final board = straightRow(2);
      final track = TrackGenerator.generate(
        slices: board.slices,
        random: math.Random(1),
      );
      expect(track.waypoints.length, sampledLength(2));
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

    test(
        'the start and finish anchor points sit at least half the track '
        'width from every edge of their own phone', () {
      for (final board in [straightRow(3), lShape(), zigzag()]) {
        final track = TrackGenerator.generate(
          slices: board.slices,
          random: math.Random(7),
        );
        final firstPhoneId = board.slices
            .firstWhere((s) =>
                (s.viewport.contains(track.waypoints.first.x, track.waypoints.first.y)))
            .phoneId;
        final lastPhoneId = board.slices
            .firstWhere((s) =>
                (s.viewport.contains(track.waypoints.last.x, track.waypoints.last.y)))
            .phoneId;
        final firstViewport =
            board.slices.firstWhere((s) => s.phoneId == firstPhoneId).viewport;
        final lastViewport =
            board.slices.firstWhere((s) => s.phoneId == lastPhoneId).viewport;
        // Half of *this table's* road, not the tuning constant: the width is
        // scaled by player count now, and a two-phone board's road is
        // narrower than the base figure. Asserting the constant here demands
        // a margin the generator was never asked to leave.
        final margin =
            PitchCarsScale.forPlayers(board.slices.length).trackWidthWorld / 2;
        const slack = 1e-6;

        void expectMargin(Waypoint w, WorldRect viewport) {
          expect(w.x, greaterThanOrEqualTo(viewport.left + margin - slack));
          expect(w.x, lessThanOrEqualTo(viewport.right - margin + slack));
          expect(w.y, greaterThanOrEqualTo(viewport.top + margin - slack));
          expect(w.y, lessThanOrEqualTo(viewport.bottom - margin + slack));
        }

        expectMargin(track.waypoints.first, firstViewport);
        expectMargin(track.waypoints.last, lastViewport);
      }
    });

    test('a very narrow corner phone does not throw', () {
      // A real sliver of a screen: 20mm across and full height, so its pixels
      // are 315 x 2400 at the same density. Narrow, and possible.
      final narrow = phone('p2', widthMm: 20, label: 'narrow');
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
