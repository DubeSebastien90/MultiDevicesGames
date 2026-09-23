import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/subway_skater/subway_skater_config.dart';
import 'package:multiscreen_slingshot/games/subway_skater/subway_skater_game.dart';
import 'package:multiscreen_slingshot/games/subway_skater/subway_skater_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/entity.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Subway Skater, driven entirely through the SDK contract.
///
/// The three things worth pinning down are the ones the game is actually made
/// of: where the line stands, what a hit does to it, and the rule of three that
/// turns position-time into a score out of sixty.
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

({SubwaySkaterSim sim, BoardLayout board, Scoreboard scores}) start(
  int phoneCount, {
  int seed = 5,
}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++) phone('p${i + 1}'),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  const game = SubwaySkaterGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = SubwaySkaterSim(
    board.contextFor(scores),
    random: math.Random(seed),
  );
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

const _tick = 1 / PlatformConfig.simHz;

void run(SubwaySkaterSim sim, double seconds) {
  final steps = (seconds * PlatformConfig.simHz).round();
  for (var i = 0; i < steps; i++) {
    sim.step(_tick);
  }
}

Entity skaterOf(SubwaySkaterSim sim, String phoneId) =>
    sim.entities.firstWhere((e) => e.id == 'skater-$phoneId');

List<String> orderOf(SubwaySkaterSim sim) =>
    (sim.sharedState['order']! as String).split(',');

/// Which lanes each wave in flight is blocking.
///
/// A wave is the blocks that were launched together: they start at the same
/// place and travel at the same speed, so they stay at the same x forever.
/// Lanes blocked *across* two different waves are not a wall — there is room to
/// move between them — which is why this groups rather than pooling everything
/// on the board.
Map<String, Set<int>> wavesOf(SubwaySkaterSim sim, WorldRect board) {
  final waves = <String, Set<int>>{};
  for (final e in sim.entities) {
    if (e.kind != 'obstacle') continue;
    waves
        .putIfAbsent(e.x.toStringAsFixed(4), () => <int>{})
        .add(SubwaySkaterConfig.laneAt(board, e.y));
  }
  return waves;
}

/// Where whoever is standing in [slot] should be.
double anchorOf(BoardLayout board, int slot) {
  final screen = board.slices[slot].viewport;
  return screen.left + screen.width * SubwaySkaterConfig.standFraction;
}

/// Whoever is standing in [slot].
Entity skaterAtSlot(SubwaySkaterSim sim, int slot) =>
    skaterOf(sim, orderOf(sim)[slot]);

/// Steer whoever is standing in [slot] into [lane], from the phone that place
/// in the line is driven by.
///
/// Does not step the sim, so a whole table can be aimed in one instant — the
/// lane is committed the moment the swipe lands, and the slide that follows is
/// only the circle catching up. Settle with [run] once everybody is pointed.
void steerSlotTo(SubwaySkaterSim sim, BoardLayout board, int slot, int lane) {
  final now = SubwaySkaterConfig.laneAt(board.board, skaterAtSlot(sim, slot).y);
  if (now == lane) return;
  swipe(
    sim,
    board.slices[slot].phoneId,
    lane > now ? 1 : -1,
    times: (lane - now).abs(),
  );
}

/// One swipe on [phoneId], as long as a real flick — several times the
/// threshold, because a finger does not stop at it.
void swipe(
  SubwaySkaterSim sim,
  String phoneId,
  int direction, {
  int times = 1,
}) {
  for (var i = 0; i < times; i++) {
    const reach = SubwaySkaterConfig.swipeThreshold * 4;
    for (final phase in [TouchPhase.down, TouchPhase.move, TouchPhase.up]) {
      sim.onTouch(
        TouchEvent(
          phoneId: phoneId,
          worldX: 0,
          worldY: phase == TouchPhase.down ? 0 : reach * direction,
          phase: phase,
        ),
      );
    }
  }
}

/// Line the table up so the first wave takes the player at the front and
/// nobody else: the front into a lane the wave blocks, everybody else into the
/// one it is guaranteed to leave open.
({int hit, int safe}) aimFirstWaveAtTheFront(
  SubwaySkaterSim sim,
  BoardLayout board,
) {
  run(sim, SubwaySkaterConfig.leadInSeconds + 0.05);
  final blocked = wavesOf(sim, board.board).values.single;
  expect(blocked, isNotEmpty, reason: 'no wave to aim');

  final safe = [
    for (var lane = 0; lane < SubwaySkaterConfig.lanes; lane++)
      if (!blocked.contains(lane)) lane,
  ].first;

  for (var slot = 1; slot < orderOf(sim).length; slot++) {
    steerSlotTo(sim, board, slot, safe);
  }
  steerSlotTo(sim, board, 0, blocked.first);
  run(sim, 0.2);
  return (hit: blocked.first, safe: safe);
}

void main() {
  group('the corridor', () {
    test('is one long runway down the line of phones', () {
      final started = start(4);
      expect(
        started.board.board.width,
        greaterThan(started.board.board.height * 6),
      );
      expect(started.board.instruction, contains('one long line'));
    });

    test('everyone starts one per phone, three fifths down their own', () {
      // The whole fairness argument rests on this: an obstacle arriving at the
      // top of a phone has the same fraction of that phone to cross before it
      // reaches whoever is standing on it, so the player at the front is warned
      // exactly as long as the one at the back — and a mismatched table does not
      // hand the big phone a longer runway than the small one.
      final started = start(3);
      final sim = started.sim;

      expect(orderOf(sim), ['p1', 'p2', 'p3']);
      for (var i = 0; i < 3; i++) {
        final slice = started.board.slices[i];
        expect(
          skaterOf(sim, slice.phoneId).x,
          closeTo(anchorOf(started.board, i), 1e-9),
        );

        // Standing past the middle, with runway in front and room behind.
        final screen = slice.viewport;
        expect(
          skaterOf(sim, slice.phoneId).x,
          greaterThan(screen.left + screen.width / 2),
        );
        expect(skaterOf(sim, slice.phoneId).x, lessThan(screen.right));
      }
    });

    test('nothing is thrown at the table before the lead-in is up', () {
      final started = start(3);
      run(started.sim, SubwaySkaterConfig.leadInSeconds * 0.5);
      expect(
        started.sim.entities.where((e) => e.kind == 'obstacle'),
        isEmpty,
        reason: 'the table had no time to find its own circle',
      );
    });

    test('a wave never blocks every lane', () {
      // Built so there is always a way through, rather than checked afterwards
      // and hoped about — so this walks a whole round and insists on it.
      final started = start(4);
      for (var i = 0; i < PlatformConfig.simHz * 60; i++) {
        started.sim.step(_tick);
        for (final blocked in wavesOf(
          started.sim,
          started.board.board,
        ).values) {
          expect(
            blocked.length,
            lessThan(SubwaySkaterConfig.lanes),
            reason: 'a wave with no way through is a tax, not a wave',
          );
        }
      }
    });
  });

  group('steering', () {
    test('one swipe moves exactly one lane, however long the flick', () {
      // A real flick crosses several centimetres. Spending a lane per stride of
      // the threshold pinned everybody against the far wall on every swipe and
      // made the middle lane unreachable from either side.
      final started = start(2);
      final sim = started.sim;
      final board = started.board.board;
      final middle = SubwaySkaterConfig.lanes ~/ 2;

      expect(SubwaySkaterConfig.laneAt(board, skaterOf(sim, 'p1').y), middle);

      swipe(sim, 'p1', 1);
      run(sim, 0.5);
      expect(
        SubwaySkaterConfig.laneAt(board, skaterOf(sim, 'p1').y),
        middle + 1,
      );
    });

    test('crossing two lanes takes two swipes', () {
      final started = start(2);
      final sim = started.sim;
      final board = started.board.board;

      swipe(sim, 'p1', -1);
      run(sim, 0.3);
      expect(SubwaySkaterConfig.laneAt(board, skaterOf(sim, 'p1').y), 0);

      // And no further: the wall of the corridor is the wall.
      swipe(sim, 'p1', -1);
      run(sim, 0.3);
      expect(SubwaySkaterConfig.laneAt(board, skaterOf(sim, 'p1').y), 0);

      swipe(sim, 'p1', 1, times: 2);
      run(sim, 0.5);
      expect(SubwaySkaterConfig.laneAt(board, skaterOf(sim, 'p1').y), 2);
    });

    test('a tap is not a swipe', () {
      final started = start(2);
      final sim = started.sim;
      final before = skaterOf(sim, 'p1').y;

      sim.onTouch(
        TouchEvent(phoneId: 'p1', worldX: 0, worldY: 0, phase: TouchPhase.down),
      );
      sim.onTouch(
        TouchEvent(
          phoneId: 'p1',
          worldX: 0,
          worldY: SubwaySkaterConfig.swipeThreshold * 0.4,
          phase: TouchPhase.up,
        ),
      );
      run(sim, 0.3);

      expect(skaterOf(sim, 'p1').y, closeTo(before, 1e-9));
    });

    test('a phone steers the circle standing in its place in the line', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board.board;

      swipe(sim, 'p3', -1);
      run(sim, 0.5);

      expect(SubwaySkaterConfig.laneAt(board, skaterAtSlot(sim, 2).y), 0);
      expect(
        SubwaySkaterConfig.laneAt(board, skaterAtSlot(sim, 0).y),
        1,
        reason: 'a swipe on the back phone moved the front of the line',
      );
    });

    test('a phone with nobody standing on it steers nothing', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board.board;

      // The line is two long now, so the third phone is past the end of it.
      sim.onPlayerLeft('p2');
      expect(sim.slotOfPhone('p3'), isNull);

      final before = [
        for (var slot = 0; slot < 2; slot++)
          SubwaySkaterConfig.laneAt(board, skaterAtSlot(sim, slot).y),
      ];
      swipe(sim, 'p3', -1);
      run(sim, 0.5);

      expect([
        for (var slot = 0; slot < 2; slot++)
          SubwaySkaterConfig.laneAt(board, skaterAtSlot(sim, slot).y),
      ], before);
    });
  });

  group('the corridor winding up', () {
    test('reaches full speed with twenty seconds left, and holds it', () {
      const peak = SubwaySkaterConfig.endSpeed;
      final peakAt =
          SubwaySkaterConfig.roundSeconds -
          SubwaySkaterConfig.peakWithSecondsLeft;

      expect(SubwaySkaterConfig.speedAt(0), SubwaySkaterConfig.obstacleSpeed);
      expect(SubwaySkaterConfig.speedAt(peakAt), closeTo(peak, 1e-9));

      // Flat out for the rest, rather than still climbing at the whistle: the
      // top speed has to be something the table plays at, not a number it
      // touches on the last tick.
      expect(SubwaySkaterConfig.speedAt(peakAt + 1), closeTo(peak, 1e-9));
      expect(
        SubwaySkaterConfig.speedAt(SubwaySkaterConfig.roundSeconds),
        closeTo(peak, 1e-9),
      );
      expect(SubwaySkaterConfig.speedAt(peakAt - 5), lessThan(peak));

      // And all the way up, never down.
      var last = 0.0;
      for (var t = 0.0; t <= SubwaySkaterConfig.roundSeconds; t += 1) {
        final now = SubwaySkaterConfig.speedAt(t);
        expect(now, greaterThanOrEqualTo(last));
        last = now;
      }
    });

    test('a block really covers more ground later on', () {
      final started = start(3);
      final sim = started.sim;

      double crossingSpeed() {
        final before = sim.entities.firstWhere((e) => e.kind == 'obstacle').x;
        run(sim, 1);
        final after = sim.entities
            .where((e) => e.kind == 'obstacle')
            .map((e) => e.x)
            .reduce(math.max);
        return after - before;
      }

      run(sim, SubwaySkaterConfig.leadInSeconds + 0.05);
      final early = crossingSpeed();
      run(sim, SubwaySkaterConfig.roundSeconds - 6);
      final late = crossingSpeed();

      expect(
        late,
        greaterThan(early * 1.25),
        reason: 'the corridor never wound up',
      );
    });

    test('the scrolling floor keeps step with what is on it', () {
      // The lane markings are drawn from a closed form and the blocks are moved
      // a tick at a time; if those two disagree the floor slides under the
      // traffic. Checked either side of the peak, because the closed form is
      // two pieces and the join between them is where it would go wrong.
      var walked = 0.0;
      var second = 0;
      for (var i = 0; i < PlatformConfig.simHz * 60; i++) {
        walked += SubwaySkaterConfig.speedAt(i * _tick) * _tick;
        if ((i + 1) % PlatformConfig.simHz != 0) continue;
        second++;
        expect(
          walked,
          closeTo(
            SubwaySkaterConfig.travelAt(second.toDouble()),
            SubwaySkaterConfig.endSpeed * _tick * 2,
          ),
          reason: 'the floor had slid under the traffic by ${second}s',
        );
      }
    });
  });

  group('climbing a place', () {
    test('comes with a second of running blocks over', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board;

      run(sim, SubwaySkaterConfig.leadInSeconds + 0.05);
      final blocked = wavesOf(sim, board.board).values.single;
      final lane = blocked.first;
      final safe = [
        for (var l = 0; l < SubwaySkaterConfig.lanes; l++)
          if (!blocked.contains(l)) l,
      ].first;

      // The front two both stand in the wave's lane and the third steps aside.
      // The front is clipped — which promotes the second — and the very block
      // that clipped them is now coming down the corridor at somebody who has
      // just been handed a second of going through things.
      steerSlotTo(sim, board, 2, safe);
      steerSlotTo(sim, board, 1, lane);
      steerSlotTo(sim, board, 0, lane);
      run(sim, 0.2);

      var steps = 0;
      while (sim.hitsOf('p1') == 0 && steps < PlatformConfig.simHz * 5) {
        sim.step(_tick);
        steps++;
      }
      expect(orderOf(sim), ['p2', 'p3', 'p1']);

      // Both of the players who moved up are charged, and the one who was
      // knocked down is not — being hit is not a promotion.
      final charging = (sim.sharedState['charging']! as String).split(',');
      expect(charging, containsAll(<String>['p2', 'p3']));
      expect(charging, isNot(contains('p1')));

      run(sim, SubwaySkaterConfig.chargeSeconds * 0.8);
      expect(
        sim.smashesOf('p2'),
        greaterThan(0),
        reason: 'the charge did not flatten the block it ran into',
      );
      expect(
        sim.hitsOf('p2'),
        0,
        reason: 'the block stopped a player it should have gone under',
      );
    });

    test('a flattened block leaves a shatter that clears itself up', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board;

      run(sim, SubwaySkaterConfig.leadInSeconds + 0.05);
      final blocked = wavesOf(sim, board.board).values.single;
      final lane = blocked.first;
      final safe = [
        for (var l = 0; l < SubwaySkaterConfig.lanes; l++)
          if (!blocked.contains(l)) l,
      ].first;
      steerSlotTo(sim, board, 2, safe);
      steerSlotTo(sim, board, 1, lane);
      steerSlotTo(sim, board, 0, lane);
      run(sim, 0.2);

      expect(sim.entities.where((e) => e.kind == 'burst'), isEmpty);

      var steps = 0;
      while (sim.smashesOf('p2') == 0 && steps < PlatformConfig.simHz * 6) {
        sim.step(_tick);
        steps++;
      }
      expect(
        sim.smashesOf('p2'),
        greaterThan(0),
        reason: 'nothing was smashed',
      );

      // The shatter is an entity like anything else, so it reaches every phone
      // on the shared timeline — and it carries the moment it began, which is
      // what lets each screen play it at the same instant without a packet per
      // frame.
      final burst = sim.entities.firstWhere((e) => e.kind == 'burst');
      expect(burst.props['born'], isA<double>());
      expect(burst.props['size'], isNotNull);

      // And it puts itself away rather than piling up over a round.
      run(sim, SubwaySkaterConfig.burstSeconds + 0.05);
      expect(
        sim.entities.where((e) => e.id == burst.id),
        isEmpty,
        reason: 'the debris outlived its animation',
      );
    });

    test('the second runs out, and then blocks stop you again', () {
      final started = start(3);
      final sim = started.sim;

      aimFirstWaveAtTheFront(sim, started.board);
      var steps = 0;
      while (sim.hitsOf('p1') == 0 && steps < PlatformConfig.simHz * 5) {
        sim.step(_tick);
        steps++;
      }
      expect(sim.sharedState['charging'], contains('p2'));

      run(sim, SubwaySkaterConfig.chargeSeconds + 0.05);
      expect(
        sim.sharedState['charging'],
        isNot(contains('p2')),
        reason: 'a promotion is a second, not the rest of the round',
      );
    });

    test('a place opening up because somebody left counts too', () {
      final started = start(4);
      final sim = started.sim;
      run(sim, 2);

      sim.onPlayerLeft('p2');
      final charging = (sim.sharedState['charging']! as String).split(',');
      expect(
        charging,
        containsAll(<String>['p3', 'p4']),
        reason: 'they moved up the corridor the same way',
      );
      expect(
        charging,
        isNot(contains('p1')),
        reason: 'the front did not move anywhere',
      );
    });
  });

  group('handing the controls on', () {
    test('climbing a place moves you to the next phone along', () {
      // The whole point of the rotation: your place in the line is your place at
      // the table, so the phone that steers you changes when the order does.
      final started = start(3);
      final sim = started.sim;
      final board = started.board;

      expect(sim.slotOfPhone('p1'), 0);
      expect(orderOf(sim)[0], 'p1');

      // Knock the front out and the line closes up over them.
      run(sim, SubwaySkaterConfig.leadInSeconds + 0.05);
      final blocked = wavesOf(sim, board.board).values.single;
      final safe = [
        for (var lane = 0; lane < SubwaySkaterConfig.lanes; lane++)
          if (!blocked.contains(lane)) lane,
      ].first;
      steerSlotTo(sim, board, 1, safe);
      steerSlotTo(sim, board, 2, safe);
      steerSlotTo(sim, board, 0, blocked.first);

      var steps = 0;
      while (sim.hitsOf('p1') == 0 && steps < PlatformConfig.simHz * 5) {
        sim.step(_tick);
        steps++;
      }
      expect(orderOf(sim), ['p2', 'p3', 'p1']);

      // p2 has climbed to the front, so the front phone is now the one that
      // steers p2 — and p2's own phone steers whoever is standing there.
      run(sim, 0.5);
      final was = SubwaySkaterConfig.laneAt(board.board, skaterOf(sim, 'p2').y);
      swipe(sim, 'p1', was == 0 ? 1 : -1);
      run(sim, 0.5);

      expect(
        SubwaySkaterConfig.laneAt(board.board, skaterOf(sim, 'p2').y),
        isNot(was),
        reason:
            'the front phone did not steer the player who had climbed to '
            'the front',
      );
    });
  });

  group('being clipped', () {
    test('tumbles you to the back and moves everyone else up', () {
      final started = start(3);
      final sim = started.sim;
      aimFirstWaveAtTheFront(sim, started.board);

      var steps = 0;
      while (sim.hitsOf('p1') == 0 && steps < PlatformConfig.simHz * 5) {
        sim.step(_tick);
        steps++;
      }

      expect(sim.hitsOf('p1'), 1, reason: 'the front was never clipped');
      expect(
        orderOf(sim),
        ['p2', 'p3', 'p1'],
        reason: 'the line did not close up over the player who was hit',
      );
      expect(sim.sharedState['tumbling'], contains('p1'));
    });

    test('the tumble carries you the length of the corridor, then lands', () {
      final started = start(3);
      final sim = started.sim;
      aimFirstWaveAtTheFront(sim, started.board);

      var steps = 0;
      while (sim.hitsOf('p1') == 0 && steps < PlatformConfig.simHz * 5) {
        sim.step(_tick);
        steps++;
      }
      expect(sim.hitsOf('p1'), 1, reason: 'never got hit at all');

      // It really travels: dragged downstream, and still short of the back —
      // the circle rides the corridor rather than teleporting to the end of it.
      run(sim, 0.3);
      final travelling = skaterOf(sim, 'p1').x;
      expect(
        travelling,
        greaterThan(anchorOf(started.board, 0) + 2),
        reason: 'the circle was not carried anywhere',
      );
      expect(
        travelling,
        lessThan(anchorOf(started.board, 2)),
        reason: 'it arrived at the back without making the journey',
      );

      // Long enough for the block carrying them to clear the far end.
      run(sim, started.board.board.width / SubwaySkaterConfig.obstacleSpeed);
      expect(sim.sharedState['tumbling'], isNot(contains('p1')));

      // Landed at whichever post is theirs now — the back, unless the line has
      // churned on without them since.
      final slot = orderOf(sim).indexOf('p1');
      expect(
        skaterOf(sim, 'p1').x,
        closeTo(anchorOf(started.board, slot), 1e-6),
        reason: 'the tumble did not put them back in the line',
      );
    });
  });

  group('scoring', () {
    test('places follow position-time', () {
      // Checked where the order is unambiguous: before anything can reach the
      // line, nobody has moved, so a line of three has been earning 2, 1 and 0
      // a tick — first, second and third place.
      final started = start(3);
      final sim = started.sim;
      run(sim, SubwaySkaterConfig.leadInSeconds * 0.5);

      expect(
        sim.positionTimeOf('p1'),
        closeTo(2 * sim.positionTimeOf('p2'), 1e-9),
      );
      expect(sim.positionTimeOf('p3'), 0);
      expect(sim.pointsOf('p1'), 100);
      expect(sim.pointsOf('p2'), 50);
      expect(sim.pointsOf('p3'), 0);
    });

    test('holding the front is first place at any table size', () {
      for (final n in [2, 3, 4, 6, 8]) {
        final started = start(n);
        run(started.sim, SubwaySkaterConfig.leadInSeconds * 0.5);

        expect(
          started.sim.pointsOf('p1'),
          Scoreboard.pointsPerGame,
          reason: 'the front of a line of $n was not first',
        );
        expect(
          started.sim.pointsOf('p$n'),
          0,
          reason: 'the back of a line of $n was worth something',
        );
      }
    });

    test('a place gained is worth more from then on, not retroactively', () {
      final started = start(3);
      final sim = started.sim;
      run(sim, 1.0);
      final backBefore = sim.positionTimeOf('p3');
      expect(backBefore, 0);

      // Promote the back player to the front by hand, through the only door
      // there is: the two ahead get knocked down.
      var steps = 0;
      while (orderOf(sim).first != 'p3' && steps < PlatformConfig.simHz * 45) {
        sim.step(_tick);
        steps++;
      }
      expect(orderOf(sim).first, 'p3', reason: 'the line never churned');

      final atPromotion = sim.positionTimeOf('p3');
      run(sim, 3);
      expect(sim.positionTimeOf('p3'), greaterThan(atPromotion));
    });

    test('the round ends after a minute, everybody with their own line', () {
      final started = start(3);
      final sim = started.sim;

      expect(sim.outcome, isNull);
      run(sim, SubwaySkaterConfig.roundSeconds + 0.1);

      final outcome = sim.outcome;
      expect(outcome, isNotNull);
      expect(
        outcome!.kind,
        OutcomeKind.personal,
        reason: 'a corridor has no winner, only a minute each',
      );
      expect(outcome.winners, isNull);
      expect(outcome.lines!.keys, containsAll(<String>['p1', 'p2', 'p3']));
      expect(outcome.lines!['p1'], contains('You scored'));

      // Polled several times a tick, so it has to be the same object each time.
      expect(sim.outcome, same(outcome));
    });

    test('the ladder is paid out, once', () {
      final started = start(3);
      run(started.sim, SubwaySkaterConfig.roundSeconds + 0.1);

      expect(
        started.scores.isUsed,
        isTrue,
        reason: 'a whole round went by and nobody was paid for it',
      );

      // The ladder is worth 50 a head however the places fell.
      const total = 50 * 3;
      final ranked = started.scores.view.ranked;
      for (final entry in ranked) {
        expect(entry.total, inInclusiveRange(0, Scoreboard.pointsPerGame));
      }
      expect(
        ranked.fold<int>(0, (sum, e) => sum + e.total),
        closeTo(total, ranked.length),
        reason: 'the table played for $total and did not take it home',
      );

      // Paid once. `step` keeps being called after the round is over on a host
      // that has not noticed yet, and a second helping would double everybody.
      final paid = started.scores.view.ranked.first.total;
      run(started.sim, 2);
      expect(started.scores.view.ranked.first.total, paid);
    });
  });

  group('the table changing under it', () {
    test(
      'somebody leaving closes the line up rather than ending the round',
      () {
        final started = start(4);
        final sim = started.sim;
        run(sim, 2);

        sim.onPlayerLeft('p2');
        expect(orderOf(sim), isNot(contains('p2')));
        expect(orderOf(sim), hasLength(3));
        expect(sim.entities.where((e) => e.id == 'skater-p2'), isEmpty);

        run(sim, 1);
        expect(sim.outcome, isNull, reason: 'the round should carry on');
      },
    );

    test('somebody coming back joins at the end of the queue', () {
      final started = start(4);
      final sim = started.sim;
      run(sim, 2);

      sim.onPlayerLeft('p1');
      run(sim, 1);
      sim.onPlayerReturned('p1');

      expect(orderOf(sim).last, 'p1');
      expect(orderOf(sim), hasLength(4));
    });

    test('a line of one stops paying rather than dividing by nothing', () {
      final started = start(2);
      final sim = started.sim;

      sim.onPlayerLeft('p2');
      run(sim, 5);

      // Nobody has a place to be ahead of, so there is no position-time to
      // share out and no best possible score to measure against.
      expect(sim.pointsOf('p1'), 0);
      run(sim, SubwaySkaterConfig.roundSeconds);
      expect(sim.outcome, isNotNull);
      expect(started.scores.isUsed, isFalse);
    });
  });

  test('reset puts the line back at the top of the corridor', () {
    final started = start(3);
    final sim = started.sim;
    run(sim, 20);

    sim.reset();
    expect(orderOf(sim), ['p1', 'p2', 'p3']);
    expect(sim.entities.where((e) => e.kind == 'obstacle'), isEmpty);
    expect(sim.pointsOf('p1'), 0);
    expect(sim.hitsOf('p1'), 0);
    expect(sim.outcome, isNull);
    expect(
      sim.sharedState['secondsLeft'],
      SubwaySkaterConfig.roundSeconds.round(),
    );
  });
}
