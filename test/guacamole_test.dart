import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/guacamole/guacamole_config.dart';
import 'package:multiscreen_slingshot/games/guacamole/guacamole_game.dart';
import 'package:multiscreen_slingshot/games/guacamole/guacamole_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// A phone, seated in a colour — which is what makes it a *player*.
PhoneSpec phone(String id, PlayerColor? color) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
  color: color,
);

({GuacamoleSim sim, BoardLayout board, Scoreboard scores}) start(
  int phoneCount, {
  int seed = 7,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  const game = GuacamoleGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = GuacamoleSim(board.contextFor(scores), random: math.Random(seed));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// Run the round forward at a fixed rate, as the platform does.
void run(GuacamoleSim sim, double seconds, {double dt = 1 / 60}) {
  for (var t = 0.0; t < seconds; t += dt) {
    sim.step(dt);
  }
}

/// The first mole that is up and squishable, with its owner.
({String id, PlayerColor owner, Hole hole})? firstLiveMole(GuacamoleSim sim) {
  final states = sim.sharedState['moles'] as Map<String, Object?>;
  for (final entry in states.entries) {
    final phase = (entry.value as Map)['p'];
    if (phase == 'squished') continue;
    final e = sim.entities.firstWhere((e) => e.id == entry.key);
    final owner = PlayerPalette.byId(e.props['owner'] as String?);
    if (owner == null) continue;
    final hole = sim.holes.firstWhere(
      (h) => (h.centerX - e.x).abs() < 1e-9 && (h.centerY - e.y).abs() < 1e-9,
    );
    return (id: entry.key, owner: owner, hole: hole);
  }
  return null;
}

void main() {
  group('the board', () {
    test('four phones make a 2x2 block, not a strip', () {
      final started = start(4);
      final board = started.board.board;

      // A 2x2 of portrait phones is still taller than it is wide — the block
      // inherits the shape of the phones, and a phone is not square. What
      // matters is that it is drastically squarer than a strip: four in a
      // column would be ~9:1, four in a row ~1:9. Anything inside 1:3 is a
      // block somebody can reach across.
      final ratio = board.width / board.height;
      expect(ratio, greaterThan(1 / 3));
      expect(ratio, lessThan(3.0));
      expect(started.board.instruction, contains('Two rows'));

      // And concretely: two phone-widths across, two phone-heights down.
      expect(
        board.width,
        lessThan(board.height),
        reason: 'portrait phones make a portrait block',
      );
    });

    test('an odd table is refused rather than fudged', () {
      // Two rows cannot be split evenly five ways, and the manifest says so
      // before anyone is asked to move a phone.
      expect(const GuacamoleGame().manifest.fits(5), isFalse);

      // And the layout itself refuses, so the rule holds even if a future
      // manifest were to loosen.
      final lobby = LobbyInfo([
        for (var i = 0; i < 5; i++) phone('p${i + 1}', PlayerPalette.all[i]),
      ]);
      expect(
        () => Layouts.grid(lobby.phones, rows: 2),
        throwsA(isA<BoardPlanError>()),
      );
    });

    test('two rows, evenly split, whatever the table size', () {
      for (final n in [4, 6, 8]) {
        final lobby = LobbyInfo([
          for (var i = 0; i < n; i++) phone('p${i + 1}', PlayerPalette.all[i]),
        ]);
        final plan = Layouts.grid(lobby.phones, rows: 2);

        final byRow = <double, int>{};
        for (final p in plan.placements) {
          byRow[p.yMm] = (byRow[p.yMm] ?? 0) + 1;
        }
        expect(byRow, hasLength(2), reason: '$n phones should make two rows');
        expect(
          byRow.values.every((c) => c == n ~/ 2),
          isTrue,
          reason: '$n phones should split $byRow evenly',
        );
      }
    });

    test('every phone gets exactly four holes', () {
      for (final n in [4, 6, 8]) {
        final started = start(n);
        expect(
          started.sim.holes,
          hasLength(n * GuacamoleConfig.holesPerPhone),
          reason: '$n phones',
        );
        // Four per screen, and no screen missed.
        final byPhone = <String, int>{};
        for (final h in started.sim.holes) {
          byPhone[h.phoneId] = (byPhone[h.phoneId] ?? 0) + 1;
        }
        expect(byPhone, hasLength(n));
        expect(byPhone.values.every((c) => c == 4), isTrue);
      }
    });

    test('holes sit inside the screen they belong to', () {
      final started = start(4);
      for (final hole in started.sim.holes) {
        final slice = started.board.slices.firstWhere(
          (s) => s.phoneId == hole.phoneId,
        );
        expect(
          slice.viewport.contains(hole.centerX, hole.centerY),
          isTrue,
          reason: 'hole ${hole.index} escaped ${hole.phoneId}',
        );
      }
    });
  });

  group('scoring', () {
    test('a squish credits the mole owner, not the phone tapped', () {
      final started = start(4);
      run(started.sim, 2);

      final mole = firstLiveMole(started.sim);
      expect(mole, isNotNull, reason: 'no mole came up in two seconds');

      final ownerPhone = started.sim.context.phoneOfColor(mole!.owner)!;
      // Tap from a phone that is deliberately NOT the owner's — the case that
      // happens constantly in play, when somebody reaches across the table.
      final otherPhone = started.board.slices
          .firstWhere((s) => s.phoneId != ownerPhone)
          .phoneId;

      final before = started.sim.squishedBy(ownerPhone);
      final otherBefore = started.sim.squishedBy(otherPhone);

      started.sim.onTouch(
        TouchEvent(
          phoneId: otherPhone,
          worldX: mole.hole.centerX,
          worldY: mole.hole.centerY,
          phase: TouchPhase.down,
        ),
      );

      expect(
        started.sim.squishedBy(ownerPhone),
        before + 1,
        reason: 'the point belongs to the colour, whoever reached',
      );
      expect(
        started.sim.squishedBy(otherPhone),
        otherBefore,
        reason: 'the tapping phone must gain nothing',
      );
    });

    test('nothing is ever deducted', () {
      final started = start(4);
      final totals = <String, int>{};

      for (var i = 0; i < 600; i++) {
        started.sim.step(1 / 60);
        // Tap every hole every step: the most aggressive masher possible.
        for (final hole in started.sim.holes) {
          started.sim.onTouch(
            TouchEvent(
              phoneId: 'p1',
              worldX: hole.centerX,
              worldY: hole.centerY,
              phase: TouchPhase.down,
            ),
          );
        }
        for (final id in started.sim.context.phoneIds) {
          final now = started.scores[id];
          expect(
            now,
            greaterThanOrEqualTo(totals[id] ?? 0),
            reason: 'score went down for $id',
          );
          totals[id] = now;
        }
      }
    });

    test('a tap on empty ground scores nobody', () {
      final started = start(4);
      run(started.sim, 2);

      final before = {
        for (final id in started.sim.context.phoneIds)
          id: started.sim.squishedBy(id),
      };

      // Far outside the board.
      started.sim.onTouch(
        TouchEvent(
          phoneId: 'p1',
          worldX: started.board.board.left - 50,
          worldY: started.board.board.top - 50,
          phase: TouchPhase.down,
        ),
      );

      for (final id in started.sim.context.phoneIds) {
        expect(started.sim.squishedBy(id), before[id]);
      }
    });

    test('a mole can only be squished once', () {
      final started = start(4);
      run(started.sim, 2);

      final mole = firstLiveMole(started.sim)!;
      final ownerPhone = started.sim.context.phoneOfColor(mole.owner)!;
      final before = started.sim.squishedBy(ownerPhone);

      for (var i = 0; i < 5; i++) {
        started.sim.onTouch(
          TouchEvent(
            phoneId: 'p1',
            worldX: mole.hole.centerX,
            worldY: mole.hole.centerY,
            phase: TouchPhase.down,
          ),
        );
      }

      expect(started.sim.squishedBy(ownerPhone), before + 1);
    });

    test(
      'the round pays out on the placement ladder when the minute is up',
      () {
        final started = start(4);
        run(started.sim, 2);
        final mole = firstLiveMole(started.sim)!;
        final scorer = started.sim.context.phoneOfColor(mole.owner)!;
        started.sim.onTouch(
          TouchEvent(
            phoneId: scorer,
            worldX: mole.hole.centerX,
            worldY: mole.hole.centerY,
            phase: TouchPhase.down,
          ),
        );
        expect(started.scores[scorer], 0, reason: 'nothing is paid mid-round');

        run(started.sim, GuacamoleConfig.roundSeconds);
        expect(started.scores[scorer], Scoreboard.pointsPerGame);
        // The other three tie for second to fourth: (67 + 33 + 0) / 3.
        for (final id in started.sim.context.phoneIds.where(
          (i) => i != scorer,
        )) {
          expect(started.scores[id], 33);
        }
      },
    );
  });

  group('fairness', () {
    test('moles are dealt evenly between players', () {
      final started = start(4);
      final seen = <String, int>{};

      // Watch spawns for most of a round.
      var previous = <String>{};
      for (var t = 0.0; t < 45; t += 1 / 60) {
        started.sim.step(1 / 60);
        final states =
            (started.sim.sharedState['moles'] as Map<String, Object?>).keys
                .toSet();
        for (final id in states.difference(previous)) {
          final e = started.sim.entities.firstWhere((e) => e.id == id);
          final owner = e.props['owner'] as String?;
          if (owner != null) seen[owner] = (seen[owner] ?? 0) + 1;
        }
        previous = states;
      }

      expect(seen, hasLength(4), reason: 'every player must get moles');

      // The bag guarantees this: across a whole round no player can be more
      // than one deal behind another, whatever the dice do.
      final counts = seen.values.toList()..sort();
      expect(
        counts.last - counts.first,
        lessThanOrEqualTo(2),
        reason: 'spawns should be near-identical per player: $seen',
      );
    });

    test('spawn position is spread across every phone', () {
      final started = start(4);
      final byPhone = <String, int>{};

      var previous = <String>{};
      for (var t = 0.0; t < 50; t += 1 / 60) {
        started.sim.step(1 / 60);
        final states =
            (started.sim.sharedState['moles'] as Map<String, Object?>).keys
                .toSet();
        for (final id in states.difference(previous)) {
          final e = started.sim.entities.firstWhere((e) => e.id == id);
          final hole = started.sim.holes.firstWhere(
            (h) =>
                (h.centerX - e.x).abs() < 1e-9 &&
                (h.centerY - e.y).abs() < 1e-9,
          );
          byPhone[hole.phoneId] = (byPhone[hole.phoneId] ?? 0) + 1;
        }
        previous = states;
      }

      // Uniform over holes, so every screen sees action — no bias toward
      // anyone's own phone, which is the entire reason people have to reach.
      expect(byPhone, hasLength(4));
      for (final entry in byPhone.entries) {
        expect(
          entry.value,
          greaterThan(3),
          reason: '${entry.key} barely saw a mole: $byPhone',
        );
      }
    });

    test('two moles never share a hole', () {
      final started = start(4);

      for (var t = 0.0; t < 30; t += 1 / 60) {
        started.sim.step(1 / 60);
        final live = [
          for (final e in started.sim.entities)
            if (e.kind == 'mole') '${e.x},${e.y}',
        ];
        expect(
          live.toSet(),
          hasLength(live.length),
          reason: 'two moles occupied one hole at t=$t',
        );
      }
    });
  });

  group('the round', () {
    test('runs for a minute and then names a leader', () {
      final started = start(4);

      run(started.sim, GuacamoleConfig.roundSeconds - 1);
      expect(started.sim.outcome, isNull, reason: 'ended early');

      run(started.sim, 2);
      expect(started.sim.outcome, isNotNull, reason: 'never ended');
    });

    test('everyone is told what they personally managed', () {
      final started = start(4);

      // One phone squishes; the rest do not.
      run(started.sim, 2);
      final mole = firstLiveMole(started.sim)!;
      final scorer = started.sim.context.phoneOfColor(mole.owner)!;
      started.sim.onTouch(
        TouchEvent(
          phoneId: scorer,
          worldX: mole.hole.centerX,
          worldY: mole.hole.centerY,
          phase: TouchPhase.down,
        ),
      );

      run(started.sim, GuacamoleConfig.roundSeconds);
      final outcome = started.sim.outcome!;

      // Nobody is eliminated and nobody "wins" — it is what you managed. So
      // every phone gets its own line under the platform's "Well played!".
      expect(outcome.kind, OutcomeKind.personal);
      expect(outcome.winners, isNull);
      expect(outcome.lines, hasLength(4));
      expect(outcome.lines![scorer], contains('1 avocado'));
      expect(outcome.lines![scorer], contains('+100 pts'));

      for (final s in started.board.slices.where((s) => s.phoneId != scorer)) {
        expect(outcome.lines![s.phoneId], startsWith('Not a single avocado'));
      }

      // Polled repeatedly, as the platform does: one verdict, built once.
      expect(identical(started.sim.outcome, outcome), isTrue);
    });

    test('the summary names who did best in *this* round', () {
      final started = start(4);
      run(started.sim, 2);
      final mole = firstLiveMole(started.sim)!;
      final scorer = started.sim.context.phoneOfColor(mole.owner)!;

      // A lead carried in from earlier games. The line must be about the round
      // just played, not the session — by the third game of a playlist the
      // phone with the highest total may have squished nothing here.
      started.scores.award('p4', 99);
      started.scores.beginRound();

      started.sim.onTouch(
        TouchEvent(
          phoneId: scorer,
          worldX: mole.hole.centerX,
          worldY: mole.hole.centerY,
          phase: TouchPhase.down,
        ),
      );
      run(started.sim, GuacamoleConfig.roundSeconds);

      expect(started.sim.outcome!.summary, contains('phone $scorer'));
    });

    test('moles get faster as the round wears on', () {
      final early = start(4);
      run(early.sim, 1);
      final earlyUp = _anyUpSeconds(early.sim);

      final late = start(4);
      run(late.sim, GuacamoleConfig.roundSeconds * 0.9);
      final lateUp = _anyUpSeconds(late.sim);

      expect(
        lateUp,
        lessThan(earlyUp),
        reason: 'the ramp should shorten a mole\'s stay',
      );
      expect(lateUp, closeTo(GuacamoleConfig.visibleSecondsEnd, 0.05));
    });

    test('reset puts the round back to the start', () {
      final started = start(4);
      run(started.sim, 20);
      started.sim.reset();

      expect(started.sim.secondsLeft, GuacamoleConfig.roundSeconds);
      expect(started.sim.outcome, isNull);
      expect(
        started.sim.entities.where((e) => e.kind == 'mole'),
        isEmpty,
        reason: 'moles survived a reset',
      );
    });

    test('every phone knows which colour it is, without being told', () {
      final started = start(4);
      started.sim.step(1 / 60);

      // The colours used to be published into `sharedState` so a view could
      // find its own — a round trip through the wire for something the
      // platform had all along. The roster is assembled from the same slices
      // on both sides now, so the state carries moles and a clock and nothing
      // about identity.
      expect(started.sim.sharedState.containsKey('colors'), isFalse);

      final roster = started.board.roster;
      expect(roster.length, 4);
      for (final slice in started.board.slices) {
        expect(roster.byPhone(slice.phoneId)?.color.id, slice.color!.id);
      }
    });
  });

  group('the manifest', () {
    test('needs four phones and tops out at the palette', () {
      final manifest = const GuacamoleGame().manifest;
      expect(manifest.fits(3), isFalse, reason: 'three is not a table');
      expect(manifest.fits(4), isTrue);
      expect(manifest.fits(PlayerPalette.size), isTrue);
      expect(
        manifest.fits(PlayerPalette.size + 1),
        isFalse,
        reason: 'there would be no colour left for them',
      );
    });
  });
}

/// The `up` duration the sim last handed to a mole, in seconds.
double _anyUpSeconds(GuacamoleSim sim) {
  final states = sim.sharedState['moles'] as Map<String, Object?>;
  final values = [
    for (final v in states.values) ((v as Map)['up'] as num).toDouble() / 1000,
  ];
  expect(values, isNotEmpty, reason: 'no moles were up to measure');
  return values.reduce(math.max);
}
