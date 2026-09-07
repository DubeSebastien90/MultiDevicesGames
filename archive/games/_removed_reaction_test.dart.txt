import 'dart:math' as math;
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/reaction/reaction_config.dart';
import 'package:multiscreen_slingshot/games/reaction/reaction_game.dart';
import 'package:multiscreen_slingshot/games/reaction/reaction_sim.dart';
import 'package:multiscreen_slingshot/games/reaction/reaction_view.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// One screen lights, one player taps, and the only thing that matters is how
/// long that took. Driven entirely through the SDK contract — no host, no
/// sockets, no rendering.
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

({ReactionSim sim, Scoreboard scores}) start(int phoneCount, {int seed = 3}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }

  const game = ReactionGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = ReactionSim(board.contextFor(scores), random: math.Random(seed));
  scores.beginRound();
  return (sim: sim, scores: scores);
}

const _dt = 1 / 60;

void run(ReactionSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

String? litPhone(ReactionSim sim) => sim.sharedState['lit'] as String?;

({double x, double y}) dotOf(ReactionSim sim) => (
      x: (sim.sharedState['dotX'] as num).toDouble(),
      y: (sim.sharedState['dotY'] as num).toDouble(),
    );

/// Tap the dot — what a player who saw it does.
void tapDot(ReactionSim sim, String phoneId) =>
    tapAt(sim, phoneId, dotOf(sim));

/// Tap a spot noted earlier.
///
/// Where the dot *was* when it appeared, not where it is by the time the finger
/// lands: a slow answer can outlast the prompt, and a player aims at what they
/// saw rather than at whatever the sim has moved on to.
void tapAt(ReactionSim sim, String phoneId, ({double x, double y}) at) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: at.x,
    worldY: at.y,
    phase: TouchPhase.down,
  ));
}

/// Tap somewhere that is definitely not the dot.
void tapAway(ReactionSim sim, String phoneId) {
  final dot = dotOf(sim);
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: dot.x + ReactionConfig.dotRadiusWorld * 6,
    worldY: dot.y,
    phase: TouchPhase.down,
  ));
}

/// The compiled board for a table of [phoneCount], as the sim sees it.
BoardLayout boardOf(int phoneCount) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++)
      phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  return const BoardCompiler()
      .compile(const ReactionGame().planBoard(lobby), lobby);
}

int faultsOf(ReactionSim sim, String phoneId) => sim.faultsOf(phoneId);

/// Exactly how the host decides whether shared state is worth sending: value
/// by value, with `==`.
bool sameShared(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Step until somebody's screen lights, then answer it after [afterSeconds].
///
/// Returns the phone that was lit, or null if the round ended first.
String? answerNextPrompt(ReactionSim sim, {required double afterSeconds}) {
  while (litPhone(sim) == null) {
    if (sim.outcome != null) return null;
    sim.step(_dt);
  }
  final lit = litPhone(sim)!;
  final dot = dotOf(sim);
  run(sim, afterSeconds);
  tapAt(sim, lit, dot);
  return lit;
}

void main() {
  group('the table', () {
    test('two players is a full game', () {
      // The common case: two phones on a table, racing each other. Pinned
      // because it is the size a raised minimum would quietly take away.
      const game = ReactionGame();
      expect(game.manifest.fits(2), isTrue);
      expect(game.manifest.fits(1), isFalse,
          reason: 'alone there is nobody to be faster than');

      // And it genuinely plays: both get turns, both get measured.
      final started = start(2);
      final turns = <String>{};
      while (started.sim.outcome == null) {
        if (litPhone(started.sim) == null) {
          started.sim.step(_dt);
          continue;
        }
        final lit = litPhone(started.sim)!;
        final dot = dotOf(started.sim);
        turns.add(lit);
        run(started.sim, lit == 'p1' ? 0.2 : 0.5);
        tapAt(started.sim, lit, dot);
      }

      expect(turns, {'p1', 'p2'}, reason: 'both phones must get turns');
      expect(started.sim.averageMsOf('p1'), isNotNull);
      expect(started.sim.averageMsOf('p2'), isNotNull);
      expect(started.scores['p1'], ReactionConfig.bestScore);
      expect(started.scores['p2'], 0);
    });
  });

  group('the arrangement', () {
    test('three or more sit in a circle', () {
      for (final count in [3, 4, 6]) {
        final lobby = LobbyInfo([
          for (var i = 0; i < count; i++)
            phone('p${i + 1}', PlayerPalette.all[i]),
        ]);
        final board =
            const BoardCompiler().compile(
                const ReactionGame().planBoard(lobby), lobby);

        // A ring: nothing touches, and every screen is turned to face in.
        expect(board.slices.where((s) => s.screen.isTurned), hasLength(count),
            reason: 'a ring turns every phone to its own place on the rim');
        expect(board.instruction, contains('circle'));
      }
    });

    test('two sit facing each other, because a ring of two is not one', () {
      // `Layouts.circle` refuses below three rather than drawing a very short
      // ring, so the game has to choose — and two players must still play.
      final lobby = LobbyInfo([
        phone('p1', PlayerPalette.all[0]),
        phone('p2', PlayerPalette.all[1]),
      ]);

      final board = const BoardCompiler()
          .compile(const ReactionGame().planBoard(lobby), lobby);
      expect(board.slices, hasLength(2));
      expect(board.instruction, isNot(contains('circle')));
    });
  });

  group('the round', () {
    test('lights one screen at a time, and nobody else', () {
      final started = start(4);
      var sawSomething = false;

      for (var t = 0.0; t < 10; t += _dt) {
        started.sim.step(_dt);
        final lit = litPhone(started.sim);
        if (lit != null) {
          sawSomething = true;
          expect(['p1', 'p2', 'p3', 'p4'], contains(lit));
        }
      }
      expect(sawSomething, isTrue, reason: 'no screen ever lit');
    });

    test('deals turns out evenly rather than at random', () {
      // Averages are only comparable if everyone got roughly the same number
      // of goes, so turns come from a bag rather than a die.
      final started = start(4);
      final turns = <String, int>{};
      String? previous;

      while (started.sim.outcome == null) {
        started.sim.step(_dt);
        final lit = litPhone(started.sim);
        if (lit != null && lit != previous) turns[lit] = (turns[lit] ?? 0) + 1;
        previous = lit;
      }

      expect(turns.keys, hasLength(4), reason: 'somebody never got a turn');
      final counts = turns.values.toList()..sort();
      expect(counts.last - counts.first, lessThanOrEqualTo(1),
          reason: 'turns were not dealt evenly: $turns');
    });

    test('ends after thirty seconds', () {
      final started = start(2);
      run(started.sim, ReactionConfig.roundSeconds - 1);
      expect(started.sim.outcome, isNull, reason: 'ended early');

      run(started.sim, 2);
      expect(started.sim.outcome, isNotNull, reason: 'never ended');
      expect(started.sim.sharedState['lit'], isNull,
          reason: 'a screen was left lit after the whistle');
    });
  });

  group('the dot', () {
    test('lands on the lit phone, never half off it', () {
      // Picked in the screen's own frame and turned into the world, because a
      // phone in a ring sits at whatever angle the rim gives it — a point
      // chosen in world coordinates would wander off a turned panel.
      final started = start(4);

      var checked = 0;
      while (checked < 12 && started.sim.outcome == null) {
        started.sim.step(_dt);
        final lit = litPhone(started.sim);
        if (lit == null) continue;

        final dot = dotOf(started.sim);
        final screen = boardOf(4).slices.firstWhere((s) => s.phoneId == lit);
        expect(screen.contains(dot.x, dot.y), isTrue,
            reason: 'the dot for $lit was drawn off its screen');
        checked++;

        tapAt(started.sim, lit, dot);
      }
      expect(checked, greaterThan(0), reason: 'no dot was ever placed');
    });

    test('moves between turns', () {
      // A fixed spot would be memorised, and the game would stop being about
      // finding it.
      final started = start(2);
      final seen = <String>{};

      while (started.sim.outcome == null && seen.length < 6) {
        if (litPhone(started.sim) == null) {
          started.sim.step(_dt);
          continue;
        }
        final lit = litPhone(started.sim)!;
        final dot = dotOf(started.sim);
        seen.add('${dot.x.toStringAsFixed(2)},${dot.y.toStringAsFixed(2)}');
        tapAt(started.sim, lit, dot);
      }

      expect(seen.length, greaterThan(1), reason: 'the dot never moved');
    });
  });

  group('a fumble', () {
    test('tapping beside the dot costs the turn', () {
      final started = start(2);
      while (litPhone(started.sim) == null) {
        started.sim.step(_dt);
      }
      final lit = litPhone(started.sim)!;

      tapAway(started.sim, lit);

      // Charged as the slowest possible answer, and the turn is spent — or
      // hammering the screen would beat looking at it.
      expect(started.sim.averageMsOf(lit),
          ReactionConfig.falseStartSeconds * 1000);
      expect(litPhone(started.sim), isNull, reason: 'the turn survived a miss');
      expect(faultsOf(started.sim, lit), 1);
    });

    test('is counted per phone, so only the culprit is told', () {
      final started = start(2);
      while (litPhone(started.sim) == null) {
        started.sim.step(_dt);
      }
      final lit = litPhone(started.sim)!;
      final other = lit == 'p1' ? 'p2' : 'p1';

      // Jumping the gun on a black screen.
      started.sim.onTouch(TouchEvent(
        phoneId: other,
        worldX: 0,
        worldY: 0,
        phase: TouchPhase.down,
      ));

      expect(faultsOf(started.sim, other), 1);
      expect(faultsOf(started.sim, lit), 0,
          reason: 'somebody else fumbling must not buzz your phone');
    });

    test('counts up, so two mistakes are two pieces of feedback', () {
      // A flag would swallow the second: the phone has already been told.
      final started = start(2);
      for (var i = 0; i < 2; i++) {
        while (litPhone(started.sim) == null) {
          started.sim.step(_dt);
        }
        tapAway(started.sim, litPhone(started.sim)!);
      }

      final total = faultsOf(started.sim, 'p1') + faultsOf(started.sim, 'p2');
      expect(total, 2);
    });

    test('a clean round reports nothing to buzz about', () {
      final started = start(2);
      for (var i = 0; i < 3; i++) {
        while (litPhone(started.sim) == null) {
          started.sim.step(_dt);
        }
        tapDot(started.sim, litPhone(started.sim)!);
      }

      expect(faultsOf(started.sim, 'p1'), 0);
      expect(faultsOf(started.sim, 'p2'), 0);
    });
  });

  group('measuring', () {
    test('an answer is timed from the moment the screen lit', () {
      final started = start(2);
      final lit = answerNextPrompt(started.sim, afterSeconds: 0.25)!;

      // Not exact: the answer lands on the tick after the wait.
      expect(started.sim.averageMsOf(lit), closeTo(250, 20));
    });

    test('a prompt nobody answers is a miss, not a free pass', () {
      final started = start(2);
      while (litPhone(started.sim) == null) {
        started.sim.step(_dt);
      }
      final ignored = litPhone(started.sim)!;

      run(started.sim, ReactionConfig.maxWaitSeconds + 0.1);

      // Putting the phone down must not protect an average.
      expect(started.sim.averageMsOf(ignored),
          closeTo(ReactionConfig.maxWaitSeconds * 1000, 40));
      expect(litPhone(started.sim), isNot(ignored),
          reason: 'the round stalled on a prompt nobody answered');
    });

    test('tapping a black screen costs you', () {
      // Otherwise the winning strategy is to hammer the glass until one of the
      // taps happens to land on the instant the colour appears.
      final started = start(2);
      while (litPhone(started.sim) == null) {
        started.sim.step(_dt);
      }
      final lit = litPhone(started.sim)!;
      final other = lit == 'p1' ? 'p2' : 'p1';

      started.sim.onTouch(TouchEvent(
        phoneId: other,
        worldX: 0,
        worldY: 0,
        phase: TouchPhase.down,
      ));

      expect(started.sim.averageMsOf(other),
          ReactionConfig.falseStartSeconds * 1000);
      expect(started.sim.averageMsOf(lit), isNull,
          reason: 'somebody else jumping the gun must not touch your score');
    });
  });

  group('scoring', () {
    /// A round in which each phone answers every one of its prompts after a
    /// fixed delay — so the fastest, and the order, are known in advance.
    Scoreboard playWithDelays(Map<String, double> delays) {
      final started = start(delays.length);
      while (started.sim.outcome == null) {
        if (litPhone(started.sim) == null) {
          started.sim.step(_dt);
          continue;
        }
        final lit = litPhone(started.sim)!;
        final dot = dotOf(started.sim);
        run(started.sim, delays[lit]!);
        tapAt(started.sim, lit, dot);
      }
      return started.scores;
    }

    test('thirty for the fastest, nothing for the slowest', () {
      final scores = playWithDelays({'p1': 0.2, 'p2': 0.5});

      expect(scores['p1'], ReactionConfig.bestScore);
      expect(scores['p2'], 0);
    });

    test('and evenly spaced in between', () {
      final scores = playWithDelays({'p1': 0.15, 'p2': 0.35, 'p3': 0.55});

      // Three players: 30, 15, 0. By position rather than by margin, so one
      // person having a shocker cannot flatten everybody else's score.
      expect(scores['p1'], 30);
      expect(scores['p2'], 15);
      expect(scores['p3'], 0);
    });

    test('a tie shares the better position', () {
      // Two players answering at exactly the same speed are not separable, and
      // inventing a tie-break out of the last bits of a double would hand one
      // of them a loss they did not suffer.
      final scores = playWithDelays({'p1': 0.3, 'p2': 0.3, 'p3': 0.6});

      expect(scores['p1'], ReactionConfig.bestScore);
      expect(scores['p2'], ReactionConfig.bestScore);
      expect(scores['p3'], 0);
    });

    test('never answering means no points, not a crash', () {
      final started = start(2);
      run(started.sim, ReactionConfig.roundSeconds + 1);

      expect(started.sim.outcome, isNotNull);
      // Both phones ignored every prompt, so both averaged the miss value and
      // the curve has nothing to separate them.
      expect(started.scores['p1'], 0);
      expect(started.scores['p2'], 0);
    });

    test('points are awarded once, however long the round is stepped', () {
      final started = start(2);
      while (started.sim.outcome == null) {
        if (litPhone(started.sim) == null) {
          started.sim.step(_dt);
          continue;
        }
        final lit = litPhone(started.sim)!;
        final dot = dotOf(started.sim);
        run(started.sim, lit == 'p1' ? 0.2 : 0.6);
        tapAt(started.sim, lit, dot);
      }

      final awarded = started.scores['p1'];
      expect(awarded, ReactionConfig.bestScore);

      // The platform keeps polling `outcome`, and a host that is slow to notice
      // may step again. Neither may pay out a second time.
      for (var i = 0; i < 120; i++) {
        started.sim.step(_dt);
        started.sim.outcome;
      }
      expect(started.scores['p1'], awarded);
    });
  });

  group('the ending', () {
    test('tells each phone its own average', () {
      final started = start(2);
      while (started.sim.outcome == null) {
        if (litPhone(started.sim) == null) {
          started.sim.step(_dt);
          continue;
        }
        final lit = litPhone(started.sim)!;
        final dot = dotOf(started.sim);
        // Different speeds, so there is a fastest to name.
        run(started.sim, lit == 'p1' ? 0.25 : 0.45);
        tapAt(started.sim, lit, dot);
      }

      final outcome = started.sim.outcome!;
      expect(outcome.kind, OutcomeKind.personal);
      expect(outcome.lines, hasLength(2));
      expect(outcome.lines!['p1'], contains('ms'));
      expect(outcome.summary, contains('fastest'));

      // Polled repeatedly, as the platform does: one verdict, built once.
      expect(identical(started.sim.outcome, outcome), isTrue);
    });

    test('a replayed round does not reuse the last verdict', () {
      final started = start(2);
      run(started.sim, ReactionConfig.roundSeconds + 1);
      expect(started.sim.outcome, isNotNull);

      started.sim.reset();
      expect(started.sim.outcome, isNull);
      expect(started.sim.averageMsOf('p1'), isNull);
    });
  });

  reactionViewTests();

  test('an unchanged round is not worth a packet', () {
    // The host compares shared state value by value with `==`, and in Dart two
    // Maps are never equal however identical their contents. A Map in here is
    // therefore a broadcast sixty times a second for a game in which nothing
    // moves — which is exactly what publishing the fault tally as a map did.
    final started = start(3);
    run(started.sim, 0.1);

    expect(sameShared(started.sim.sharedState, started.sim.sharedState), isTrue,
        reason: 'a value in sharedState is not comparable to itself');
  });

  test('the screen state is quiet enough to send every tick', () {
    // `sharedState` is diffed and sent when it changes, so a value that always
    // differs is a packet sixty times a second for a game with nothing moving.
    final started = start(3);
    var changes = 0;
    var previous = '${started.sim.sharedState}';

    for (var t = 0.0; t < 10; t += _dt) {
      started.sim.step(_dt);
      final now = '${started.sim.sharedState}';
      if (now != previous) changes++;
      previous = now;
    }

    // Ten seconds is a handful of prompts and ten ticks of the countdown.
    expect(changes, lessThan(40), reason: '$changes changes in ten seconds');
  });
}

/// A frame as the platform would hand one to a view.
Frame frameFor(
  BoardLayout board,
  int index, {
  required Map<String, Object?> state,
  double timeMs = 0,
  double dt = 1 / 60,
}) {
  final me = board.phones[index];
  return Frame(
    entities: const {},
    sharedState: state,
    scores: ScoreView.empty,
    timeMs: timeMs,
    dt: dt,
    me: me,
    board: me.board,
    coverage: board.coverage,
  );
}

void renderFor(
  ReactionView view,
  BoardLayout board,
  int index, {
  required Map<String, Object?> state,
  double timeMs = 0,
  double dt = 1 / 60,
}) {
  view.render(
    Canvas(PictureRecorder()),
    frameFor(board, index, state: state, timeMs: timeMs, dt: dt),
  );
}

void reactionViewTests() {
  group('the red wash', () {
    final board = boardOf(2);
    Map<String, Object?> state({int seq = 0, String? by}) => {
          'lit': null,
          'litColor': null,
          'dotX': null,
          'dotY': null,
          'dotR': ReactionConfig.dotRadiusWorld,
          'faultSeq': seq,
          'faultBy': by,
          'secondsLeft': 10,
          'over': false,
        };

    testWidgets('shows for the phone that fumbled, and nobody else',
        (tester) async {
      final mine = ReactionView(ViewContext(phoneId: 'p1', board: board.board));
      final theirs =
          ReactionView(ViewContext(phoneId: 'p2', board: board.board));

      renderFor(mine, board, 0, state: state());
      renderFor(theirs, board, 1, state: state());
      expect(mine.isFlashing, isFalse);

      renderFor(mine, board, 0, state: state(seq: 1, by: 'p1'));
      renderFor(theirs, board, 1, state: state(seq: 1, by: 'p1'));

      expect(mine.isFlashing, isTrue);
      expect(theirs.isFlashing, isFalse,
          reason: 'somebody else fumbling must not light up your screen');
    });

    testWidgets('fades out on its own', (tester) async {
      final view = ReactionView(ViewContext(phoneId: 'p1', board: board.board));
      renderFor(view, board, 0, state: state(seq: 1, by: 'p1'));
      expect(view.isFlashing, isTrue);

      // Long enough to have finished, one ordinary frame at a time.
      for (var i = 0; i < 60; i++) {
        renderFor(view, board, 0, state: state(seq: 1, by: 'p1'));
      }
      expect(view.isFlashing, isFalse);
    });

    testWidgets('does not come back when the round clock restarts',
        (tester) async {
      // The reported bug, exactly: nobody touches anything and two phones wash
      // red together. `frame.timeMs` is the *round's* clock and returns to zero
      // at every new round, so an effect that remembered the instant it started
      // fired again when the new clock reached that number.
      final view = ReactionView(ViewContext(phoneId: 'p1', board: board.board));

      renderFor(view, board, 0, state: state(seq: 1, by: 'p1'), timeMs: 12000);
      for (var i = 0; i < 60; i++) {
        renderFor(view, board, 0,
            state: state(seq: 1, by: 'p1'), timeMs: 12000 + i * 16.0);
      }
      expect(view.isFlashing, isFalse, reason: 'the wash should be spent');

      // A new round: the clock starts again from nothing and climbs back past
      // where the mistake happened. Nobody has touched anything.
      for (var ms = 0.0; ms < 20000; ms += 100) {
        renderFor(view, board, 0, state: state(), timeMs: ms, dt: 0.1);
        expect(view.isFlashing, isFalse,
            reason: 'red at ${ms}ms of a round nobody has touched');
      }
    });
  });
}
