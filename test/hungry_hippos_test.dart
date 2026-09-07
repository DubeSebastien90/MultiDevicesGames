import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/hungry_hippos/hungry_hippos_config.dart';
import 'package:multiscreen_slingshot/games/hungry_hippos/hungry_hippos_game.dart';
import 'package:multiscreen_slingshot/games/hungry_hippos/hungry_hippos_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/render/shape_view.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Marbles in a dish and everyone lunging at once. Driven through the SDK
/// contract — no host, no sockets, no rendering.
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

({HungryHipposSim sim, BoardLayout board, Scoreboard scores}) start(
  int phoneCount, {
  int seed = 5,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  const game = HungryHipposGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = HungryHipposSim(
    board.contextFor(scores),
    random: math.Random(seed),
  );
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

const _dt = 1 / 60;

void run(HungryHipposSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

void tap(HungryHipposSim sim, String phoneId) => sim.onTouch(TouchEvent(
      phoneId: phoneId,
      worldX: 0,
      worldY: 0,
      phase: TouchPhase.down,
    ));

Iterable<RenderableProbe> marblesOf(HungryHipposSim sim) sync* {
  for (final e in sim.entities) {
    if (e.kind == 'marble') yield RenderableProbe(e.id, e.x, e.y);
  }
}

class RenderableProbe {
  const RenderableProbe(this.id, this.x, this.y);
  final String id;
  final double x;
  final double y;
}

void main() {
  group('the table', () {
    test('takes two, four or six and nothing else', () {
      const game = HungryHipposGame();
      for (final n in [2, 4, 6]) {
        expect(game.manifest.fits(n), isTrue, reason: '$n should play');
      }
      for (final n in [1, 3, 5, 7, 8]) {
        expect(game.manifest.fits(n), isFalse, reason: '$n should not');
      }
    });

    test('every size it accepts lays out and runs', () {
      // Three different arrangements behind one manifest, so each is worth
      // proving separately: a helper that threw would take the round down with
      // it on the host, before anybody was told anything.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        expect(started.board.slices, hasLength(count));
        run(started.sim, 1);
        expect(started.sim.marblesLeft, HungryHipposConfig.marbleCount,
            reason: '$count phones: marbles vanished on their own');
      }
    });

    test('the board stays squarish, because a dish needs one', () {
      // A row of six would be a runway, and a dish drawn on a runway is a
      // sliver. This is the reason the game refuses odd counts at all.
      for (final count in [2, 4, 6]) {
        final board = start(count).board.board;
        final ratio = math.max(board.width, board.height) /
            math.min(board.width, board.height);
        expect(ratio, lessThan(2.6), reason: '$count phones: $ratio to 1');
      }
    });
  });

  group('the dish', () {
    test('takes as much of the board as it can', () {
      // It should read as the thing everybody is leaning into, not a coin in
      // the middle of the table.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final board = started.board.board;
        final shortHalf = math.min(board.width, board.height) / 2;

        expect(started.sim.dishRadius / shortHalf, greaterThan(0.5),
            reason: '$count phones: the dish is a coin on a big table');
      }
    });

    test('leaves each player a strip of their own glass', () {
      // Somewhere to say whose phone this is, which is why the dish stops short
      // of the board's short side rather than running to the edge.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final board = started.board.board;
        final shortHalf = math.min(board.width, board.height) / 2;

        expect(started.sim.dishRadius,
            lessThanOrEqualTo(shortHalf - HungryHipposConfig.playerMarginWorld),
            reason: '$count phones: the dish runs to the very edge');
      }
    });

    test('never swallows a hippo that is meant to be leaning into it', () {
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final board = started.board.board;

        for (final h in started.sim.entities.where((e) => e.kind == 'hippo')) {
          final d = math.sqrt(math.pow(h.x - board.centerX, 2) +
              math.pow(h.y - board.centerY, 2));
          expect(d - HungryHipposConfig.hippoRadius,
              greaterThanOrEqualTo(started.sim.dishRadius - 0.01),
              reason: '$count phones: ${h.id} starts inside the bowl');
        }
      }
    });

    test('the rim the view draws is the one the marbles were dealt into', () {
      // Published rather than worked out twice: every time one fact has had two
      // implementations in this codebase, they have eventually disagreed.
      final started = start(4);
      expect(started.sim.sharedState['dish'],
          closeTo(started.sim.dishRadius, 0.01));
    });
  });

  group('the bowl', () {
    test('marbles start in the middle, not under anybody', () {
      final started = start(4);
      final board = started.board.board;

      for (final m in marblesOf(started.sim)) {
        final d = math.sqrt(math.pow(m.x - board.centerX, 2) +
            math.pow(m.y - board.centerY, 2));
        expect(d, lessThan(math.min(board.width, board.height) / 2),
            reason: '${m.id} started outside the dish');
      }
    });

    test('a marble pushed out of the middle comes back', () {
      // The whole illusion: a slice of a very large sphere. Nothing in the
      // simulation is a bowl — it is a force — so this is the only thing that
      // says the dish exists.
      final started = start(4);
      final board = started.board.board;

      double furthest() {
        var far = 0.0;
        for (final m in marblesOf(started.sim)) {
          final d = math.sqrt(math.pow(m.x - board.centerX, 2) +
              math.pow(m.y - board.centerY, 2));
          if (d > far) far = d;
        }
        return far;
      }

      // Let them settle, then shove everything outward with a lunge from each
      // hippo and watch the dish gather them again.
      run(started.sim, 2);
      for (final id in ['p1', 'p2', 'p3', 'p4']) {
        tap(started.sim, id);
      }
      run(started.sim, 0.5);
      final scattered = furthest();

      run(started.sim, 4);
      expect(furthest(), lessThan(scattered),
          reason: 'the marbles never drifted back toward the middle');
    });

    test('marbles settle rather than rattling about forever', () {
      // Undamped, the dish is a pendulum and the marbles never stop, which
      // makes them impossible to aim at.
      final started = start(4);
      run(started.sim, 8);

      var moving = 0;
      for (final e in started.sim.entities) {
        if (e.kind != 'marble') continue;
        if (math.sqrt(e.vx * e.vx + e.vy * e.vy) > 1.0) moving++;
      }
      expect(moving, lessThan(4), reason: '$moving marbles still racing about');
    });
  });

  group('the hippos', () {
    test('one per phone, resting on its own glass', () {
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final hippos =
            started.sim.entities.where((e) => e.kind == 'hippo').toList();
        expect(hippos, hasLength(count));

        for (final h in hippos) {
          final phoneId = h.id.substring('hippo_'.length);
          final rect = started.board.forPhone(phoneId)!.viewport;
          expect(h.x, greaterThanOrEqualTo(rect.left - 0.01));
          expect(h.x, lessThanOrEqualTo(rect.right + 0.01));
          expect(h.y, greaterThanOrEqualTo(rect.top - 0.01));
          expect(h.y, lessThanOrEqualTo(rect.bottom + 0.01));
        }
      }
    });

    test('every hippo says whose it is, and faces the dish', () {
      // Two halves of one picture. The prop is what makes the piece a player's
      // character rather than a coloured disc — `ShapeView` draws nobody it
      // has not been told about — and the angle is which way that character is
      // turned. A hippo facing out of the bowl would be leaning away from the
      // marbles it is about to lunge at.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final centre = Offset(
          started.board.board.centerX,
          started.board.board.centerY,
        );

        for (final h in started.sim.entities.where((e) => e.kind == 'hippo')) {
          expect(
            h.props[ShapeProps.player],
            h.id.substring('hippo_'.length),
            reason: 'a hippo that names nobody is drawn as a plain circle',
          );

          final toCentre = centre - Offset(h.x, h.y);
          final facing = Offset(math.cos(h.angle), math.sin(h.angle));
          final aim = toCentre / toCentre.distance;
          // The dot product of two unit vectors: 1 is dead on.
          expect(facing.dx * aim.dx + facing.dy * aim.dy, closeTo(1, 0.01),
              reason: 'hippo ${h.id} is turned away from the dish');
        }
      }
    });

    test('every hippo starts the same distance out, whatever the layout', () {
      // How far a hippo sits is the game's business, not the arrangement's.
      // Let it fall out of the geometry and some players get a corner and
      // others an edge, which is quietly a different game for each of them.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final board = started.board.board;

        final distances = [
          for (final h in started.sim.entities.where((e) => e.kind == 'hippo'))
            math.sqrt(math.pow(h.x - board.centerX, 2) +
                math.pow(h.y - board.centerY, 2)),
        ];

        expect(distances, hasLength(count));
        for (final d in distances) {
          expect(d, closeTo(distances.first, 0.01),
              reason: '\$count phones: the hippos are not level with each other');
        }

        // And that distance is the rim of the dish, not something the board
        // happened to hand out.
        expect(distances.first,
            closeTo(started.sim.dishRadius + HungryHipposConfig.hippoRadius +
                HungryHipposConfig.hippoClearance, 0.01),
            reason: '\$count phones: hippos are not waiting at the rim');
      }
    });

    test('every hippo still stands on its own phone', () {
      // It no longer sits in the corner — the distance is the game's to set —
      // but it must be on its own glass, on the side its player is sitting.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final board = started.board.board;

        for (final h in started.sim.entities.where((e) => e.kind == 'hippo')) {
          final phoneId = h.id.substring('hippo_'.length);
          final rect = started.board.forPhone(phoneId)!.viewport;

          expect(h.x, greaterThanOrEqualTo(rect.left - 0.01),
              reason: '$count phones: $phoneId is off its own screen');
          expect(h.x, lessThanOrEqualTo(rect.right + 0.01));
          expect(h.y, greaterThanOrEqualTo(rect.top - 0.01));
          expect(h.y, lessThanOrEqualTo(rect.bottom + 0.01));

          // On the outward half of the board, with the dish in front of it.
          final toCentre = math.sqrt(math.pow(h.x - board.centerX, 2) +
              math.pow(h.y - board.centerY, 2));
          expect(toCentre, greaterThan(started.sim.dishRadius),
              reason: '$count phones: $phoneId begins inside the dish');
        }
      }
    });

    test('an open mouth covers the very middle of the dish', () {
      // The bug this pins, and it is a nasty one to see: the tick where a lunge
      // reaches full stretch is also the tick it turns around, so asking "is
      // the hippo still on its way out?" answered no at exactly the moment it
      // was deepest. That left a small disc at the centre that no mouth ever
      // swept — and the bowl gathers stragglers into precisely that spot, so
      // rounds ended with marbles nobody could reach. It showed at four and six
      // phones and not at two, because a hippo starting closer covered the
      // middle before the last tick anyway.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final board = started.board.board;
        run(started.sim, 0.5);

        tap(started.sim, 'p1');
        var closest = double.infinity;
        for (var i = 0; i < 60; i++) {
          started.sim.step(_dt);
          final h = started.sim.entities.firstWhere((e) => e.id == 'hippo_p1');
          final d = math.sqrt(math.pow(h.x - board.centerX, 2) +
              math.pow(h.y - board.centerY, 2));
          if (d < closest) closest = d;
        }

        expect(closest, lessThan(HungryHipposConfig.mouthRadius),
            reason: '$count phones: the middle of the dish is out of reach');
      }
    });

    test('one player alone can clear the whole dish', () {
      // The same bug seen from the table. Nobody else to jostle the last few
      // marbles loose, which is what used to hide it.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        var ticks = 0;
        while (started.sim.outcome == null && ticks < 60 * 60) {
          if (ticks % 45 == 0) tap(started.sim, 'p1');
          started.sim.step(_dt);
          ticks++;
        }
        expect(started.sim.marblesLeft, 0,
            reason: '$count phones: ${started.sim.marblesLeft} marbles were '
                'left stranded where nobody could eat them');
      }
    });

    test('a full lunge reaches the marbles but stops short of the middle', () {
      // The two ways this goes wrong, and both have happened: too short and the
      // hippo never touches a marble; too long and it sails clean through the
      // heap and out the far side, which on two phones it did.
      for (final count in [2, 4, 6]) {
        final started = start(count);
        final board = started.board.board;
        final dish = started.sim.dishRadius;

        run(started.sim, 0.5);
        tap(started.sim, 'p1');
        run(started.sim, HungryHipposConfig.lungeOutSeconds);

        final h = started.sim.entities.firstWhere((e) => e.id == 'hippo_p1');
        final reached = math.sqrt(math.pow(h.x - board.centerX, 2) +
            math.pow(h.y - board.centerY, 2));

        expect(reached, lessThan(dish),
            reason: '\$count phones: the lunge stops outside the dish');
        expect(reached, greaterThan(0),
            reason: '\$count phones: the lunge went past the middle');
      }
    });

    test('a tap sends your hippo out and brings it back', () {
      final started = start(2);
      run(started.sim, 0.5);

      double reachOf(String phoneId) {
        final h = started.sim.entities
            .firstWhere((e) => e.id == 'hippo_$phoneId');
        final board = started.board.board;
        return math.sqrt(math.pow(h.x - board.centerX, 2) +
            math.pow(h.y - board.centerY, 2));
      }

      final resting = reachOf('p1');
      tap(started.sim, 'p1');
      run(started.sim, HungryHipposConfig.lungeOutSeconds);
      expect(reachOf('p1'), lessThan(resting - 1),
          reason: 'the hippo never left home');

      run(started.sim, HungryHipposConfig.lungeBackSeconds +
          HungryHipposConfig.lungeCooldownSeconds + 0.1);
      expect(reachOf('p1'), closeTo(resting, 0.2),
          reason: 'the hippo did not come home');
    });

    test('a tap moves your own hippo and no one else', () {
      final started = start(4);
      run(started.sim, 0.5);

      Map<String, double> positions() => {
        for (final e in started.sim.entities.where((e) => e.kind == 'hippo'))
          e.id: e.x + e.y,
      };

      final before = positions();
      tap(started.sim, 'p1');
      run(started.sim, HungryHipposConfig.lungeOutSeconds);
      final after = positions();

      expect(after['hippo_p1'], isNot(closeTo(before['hippo_p1']!, 0.5)));
      for (final id in ['hippo_p2', 'hippo_p3', 'hippo_p4']) {
        expect(after[id], closeTo(before[id]!, 0.01),
            reason: '$id moved when p1 tapped');
      }
    });
  });

  group('eating', () {
    test('a hippo swallows what it lunges into, and scores it', () {
      final started = start(4);
      run(started.sim, 2);

      final before = started.sim.marblesLeft;
      // Everybody at once, several times: the marbles are in the middle and
      // four hippos reaching in will find some.
      for (var i = 0; i < 12; i++) {
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          tap(started.sim, id);
        }
        run(started.sim, 0.6);
      }

      expect(started.sim.marblesLeft, lessThan(before),
          reason: 'nobody managed to eat anything at all');

      var totalEaten = 0;
      for (final id in ['p1', 'p2', 'p3', 'p4']) {
        totalEaten += started.sim.eatenBy(id);
        expect(started.scores[id], started.sim.eatenBy(id),
            reason: '$id scored a different number than it ate');
      }
      expect(totalEaten, before - started.sim.marblesLeft,
          reason: 'marbles went missing without anybody eating them');
    });

    test('a marble is eaten once, by one hippo', () {
      final started = start(4);
      run(started.sim, 2);
      for (var i = 0; i < 20; i++) {
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          tap(started.sim, id);
        }
        run(started.sim, 0.5);
      }

      final eaten = HungryHipposConfig.marbleCount - started.sim.marblesLeft;
      final claimed = ['p1', 'p2', 'p3', 'p4']
          .fold<int>(0, (sum, id) => sum + started.sim.eatenBy(id));
      expect(claimed, eaten, reason: 'a marble was counted twice');
    });

    test('hammering the screen does not beat timing a lunge', () {
      // The cooldown is what makes it a game rather than a contest of thumbs.
      final started = start(2);
      run(started.sim, 1);

      for (var i = 0; i < 200; i++) {
        tap(started.sim, 'p1');
        started.sim.step(_dt);
      }
      final spammed = started.sim.eatenBy('p1');

      // Roughly the same window, but lunging only when it can.
      final other = start(2);
      run(other.sim, 1);
      for (var i = 0; i < 200 ~/ 12; i++) {
        tap(other.sim, 'p1');
        run(other.sim, 12 * _dt);
      }

      expect(spammed, lessThanOrEqualTo(other.sim.eatenBy('p1') + 2),
          reason: 'spamming ate far more than timing did');
    });
  });

  group('the ending', () {
    test('everybody gets their own tally, and nobody wins', () {
      // Every player for themselves, exactly as asked: no winner, no loser,
      // just what your own hippo managed.
      final started = start(4);
      run(started.sim, HungryHipposConfig.maxRoundSeconds + 1);

      final outcome = started.sim.outcome!;
      expect(outcome.kind, OutcomeKind.personal);
      expect(outcome.winners, isNull, reason: 'nobody is named a winner');
      expect(outcome.lines, hasLength(4));
      for (final id in ['p1', 'p2', 'p3', 'p4']) {
        expect(outcome.lines![id], isNotNull);
      }

      // Polled repeatedly, as the platform does: one verdict, built once.
      expect(identical(started.sim.outcome, outcome), isTrue);
    });

    test('the round ends when the marbles run out', () {
      final started = start(4);
      run(started.sim, 1);
      expect(started.sim.outcome, isNull, reason: 'ended before it began');
    });

    test('a replayed round starts over', () {
      final started = start(4);
      run(started.sim, HungryHipposConfig.maxRoundSeconds + 1);
      expect(started.sim.outcome, isNotNull);

      started.sim.reset();
      expect(started.sim.outcome, isNull);
      expect(started.sim.marblesLeft, HungryHipposConfig.marbleCount,
          reason: 'the marbles did not come back');
      expect(started.sim.eatenBy('p1'), 0);
    });
  });

  test('the shared state is quiet enough to send every tick', () {
    // Diffed value by value with `==`, so a Map in here would be a packet sixty
    // times a second — and two Maps are never equal in Dart.
    final started = start(4);
    run(started.sim, 0.5);
    final a = started.sim.sharedState;
    final b = started.sim.sharedState;

    expect(a.length, b.length);
    for (final entry in a.entries) {
      expect(b[entry.key], entry.value,
          reason: '${entry.key} is not comparable to itself');
    }
  });
}
