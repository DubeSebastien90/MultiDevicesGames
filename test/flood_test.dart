import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/flood/flood_game.dart';
import 'package:multiscreen_slingshot/games/flood/flood_growing_sim.dart';
import 'package:multiscreen_slingshot/games/flood_closing/flood_closing_game.dart';
import 'package:multiscreen_slingshot/games/flood_closing/flood_shrinking_sim.dart';
import 'package:multiscreen_slingshot/games/flood_common/flood_config.dart';
import 'package:multiscreen_slingshot/games/flood_common/flood_sim.dart';
import 'package:multiscreen_slingshot/games/flood/flood_growing_view.dart';
import 'package:multiscreen_slingshot/sdk/contract/game.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Both Flood variants driven entirely through the SDK contract — no host, no
/// sockets, no rendering, exactly as `games_contract_test.dart` does it.
PhoneSpec phone(String id, {double widthMm = 68.58, double heightMm = 152.4}) =>
    PhoneSpec(
      phoneId: id,
      label: 'phone $id',
      widthMm: widthMm,
      heightMm: heightMm,
      bezelMm: 3,
      dpi: 400,
      devicePixelRatio: 3,
      activePxWidth: 1080,
      activePxHeight: 2400,
    );

({FloodSim sim, BoardLayout board, Scoreboard scores}) start(
  MultiscreenGame game,
  int phoneCount,
) {
  final lobby = LobbyInfo([
    for (var i = 0; i < phoneCount; i++) phone('p${i + 1}'),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = game.createSim(board.contextFor(scores)) as FloodSim;
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

/// Run the sim forward at the platform's fixed timestep.
///
/// Counts whole ticks rather than accumulating a float, so `advance(1.0)` is
/// exactly sixty steps and the elapsed clock lands where the arithmetic says.
void advance(FloodSim sim, double seconds) {
  const dt = 1 / 60;
  final ticks = (seconds * 60).round();
  for (var i = 0; i < ticks; i++) {
    sim.step(dt);
  }
}

/// Past the countdown, so taps count.
void goLive(FloodSim sim) =>
    advance(sim, FloodConfig.countdownSeconds + 1 / 60);

void tap(FloodSim sim, String phoneId) => sim.onTouch(
      TouchEvent(
        phoneId: phoneId,
        worldX: 0,
        worldY: 0,
        phase: TouchPhase.down,
      ),
    );

/// Taps spaced past the rate limit, since the limiter works on round time.
void mash(FloodSim sim, String phoneId, int times) {
  for (var i = 0; i < times; i++) {
    tap(sim, phoneId);
    advance(sim, FloodConfig.minTapIntervalSeconds + 1 / 60);
  }
}

List<String> phonesOn(FloodSim sim, String team) =>
    [for (final e in sim.teams.entries) if (e.value == team) e.key]..sort();

/// A frame as the given phone would be handed one, for asking a view where it
/// would actually paint the waterline.
Frame frameFor(
  BoardLayout board,
  FloodSim sim,
  String phoneId,
) =>
    Frame(
      entities: const {},
      sharedState: sim.sharedState,
      scores: ScoreView.empty,
      timeMs: 0,
      dt: 1 / 60,
      me: board.forPhone(phoneId)!,
      board: board.coverage.board,
      coverage: board.coverage,
    );

void main() {
  group('the board', () {
    test('is two equal rows, whatever the team size', () {
      for (final count in [2, 4, 6]) {
        final started = start(const FloodGame(), count);
        final blue = phonesOn(started.sim, FloodConfig.blue);
        final red = phonesOn(started.sim, FloodConfig.red);

        expect(blue, hasLength(count ~/ 2), reason: '$count phones');
        expect(red, hasLength(count ~/ 2), reason: '$count phones');

        // Every blue screen is above every red screen — the premise the whole
        // game rests on.
        final slices = {
          for (final s in started.board.slices) s.phoneId: s.viewport,
        };
        for (final b in blue) {
          for (final r in red) {
            expect(
              slices[b]!.bottom <= slices[r]!.top,
              isTrue,
              reason: '$b should sit above $r',
            );
          }
        }
      }
    });

    test('refuses an odd table rather than improvising a third team', () {
      for (final count in [1, 3, 5]) {
        final lobby = LobbyInfo([
          for (var i = 0; i < count; i++) phone('p${i + 1}'),
        ]);
        expect(
          () => const FloodGame().planBoard(lobby),
          throwsA(isA<BoardPlanError>()),
          reason: '$count phones cannot make two equal teams',
        );
      }
    });

    test('both variants plan the same board', () {
      final lobby = LobbyInfo([for (var i = 0; i < 4; i++) phone('p${i + 1}')]);
      final a = const FloodGame().planBoard(lobby);
      final b = const FloodClosingGame().planBoard(lobby);

      for (final placement in a.placements) {
        final other = b.forPhone(placement.phoneId)!;
        expect(other.xMm, placement.xMm);
        expect(other.yMm, placement.yMm);
      }
    });

    test('phones stand upright, so the push axis gets the long edge', () {
      final lobby = LobbyInfo([phone('p1'), phone('p2')]);
      for (final p in const FloodGame().planBoard(lobby).placements) {
        expect(p.turnDeg, 0, reason: 'upright, not turned onto its side');
      }
      // Two portrait phones stacked: the board is taller than it is wide.
      final started = start(const FloodGame(), 2);
      expect(started.board.board.height, greaterThan(started.board.board.width));
    });

    test('rows of different depths still split into two teams', () {
      // The case that hung the placement screen: two desktop windows of
      // different sizes make rows of different depths, so the board's centre
      // is *inside* the deeper row rather than on the seam. Splitting teams on
      // the centre put a top-row phone on the bottom team.
      final lobby = LobbyInfo([
        phone('p1', widthMm: 300, heightMm: 500),
        phone('p2', widthMm: 300, heightMm: 300),
      ]);
      final board =
          const BoardCompiler().compile(const FloodGame().planBoard(lobby), lobby);
      final scores = Scoreboard()
        ..register('p1', 'p1')
        ..register('p2', 'p2');
      final sim = const FloodGame().createSim(board.contextFor(scores))
          as FloodSim;

      expect(sim.teams['p1'], FloodConfig.blue, reason: 'p1 is the top row');
      expect(sim.teams['p2'], FloodConfig.red, reason: 'p2 is the bottom row');

      // And boundary 0 sits on the seam between them, not the board's middle.
      final top = board.slices.firstWhere((s) => s.phoneId == 'p1').viewport;
      final bottom = board.slices.firstWhere((s) => s.phoneId == 'p2').viewport;
      expect(sim.seamY, closeTo((top.bottom + bottom.top) / 2, 1e-9));
      expect(sim.seamY, isNot(closeTo(board.coverage.board.centerY, 0.5)));
    });

    test('mismatched phones still stack without overlapping', () {
      final lobby = LobbyInfo([
        phone('p1', widthMm: 68.58, heightMm: 152.4),
        phone('p2', widthMm: 77.0, heightMm: 163.0),
        phone('p3', widthMm: 64.0, heightMm: 138.0),
        phone('p4', widthMm: 71.0, heightMm: 146.0),
      ]);
      // The compiler rejects overlaps outright, so compiling is the assertion.
      final board =
          const BoardCompiler().compile(const FloodGame().planBoard(lobby), lobby);
      expect(board.phones, hasLength(4));
    });
  });

  group('which way the flood goes', () {
    // The sim can be entirely correct and the game still play backwards: the
    // axis runs blue-negative but the screen runs top-down, so the sign lives
    // in the view. These tests are the only thing that can catch that, because
    // every sim assertion passes either way.
    test('blue tapping pushes the waterline down onto red', () {
      final started = start(const FloodGame(), 2);
      final sim = started.sim;
      final view = FloodGrowingView(
        ViewContext(phoneId: 'p1', board: started.board.coverage.board),
      );
      goLive(sim);

      final atRest = view.waterlineY(frameFor(started.board, sim, 'p1'), 0);
      expect(atRest, closeTo(sim.seamY, 1e-9), reason: '0 is the seam');

      mash(sim, phonesOn(sim, FloodConfig.blue).first, 5);
      final afterBlue = view.waterlineY(
        frameFor(started.board, sim, 'p1'),
        sim.effectiveBoundary,
      );

      expect(
        afterBlue,
        greaterThan(atRest),
        reason: 'blue expands onto red, so the line moves DOWN the board',
      );
    });

    test('red tapping pushes the waterline up onto blue', () {
      final started = start(const FloodGame(), 2);
      final sim = started.sim;
      final view = FloodGrowingView(
        ViewContext(phoneId: 'p1', board: started.board.coverage.board),
      );
      goLive(sim);

      final atRest = view.waterlineY(frameFor(started.board, sim, 'p1'), 0);
      mash(sim, phonesOn(sim, FloodConfig.red).first, 5);
      final afterRed = view.waterlineY(
        frameFor(started.board, sim, 'p1'),
        sim.effectiveBoundary,
      );

      expect(
        afterRed,
        lessThan(atRest),
        reason: 'red expands onto blue, so the line moves UP the board',
      );
    });

    test('total victory floods the loser off the board entirely', () {
      final started = start(const FloodGame(), 2);
      final sim = started.sim;
      final view = FloodGrowingView(
        ViewContext(phoneId: 'p1', board: started.board.coverage.board),
      );
      final board = started.board.coverage.board;
      final frame = frameFor(started.board, sim, 'p1');

      // -1 is total blue victory: blue's colour fills both rows, so the
      // waterline sits at the far edge of red's last phone.
      expect(view.waterlineY(frame, -1), closeTo(board.bottom, 1e-9));
      // +1 is total red victory, at the far edge of blue's first phone.
      expect(view.waterlineY(frame, 1), closeTo(board.top, 1e-9));
    });
  });

  group('the countdown', () {
    test('swallows taps until it is over', () {
      final sim = start(const FloodGame(), 2).sim;
      expect(sim.phase, FloodPhase.countdown);

      final blue = phonesOn(sim, FloodConfig.blue).first;
      mash(sim, blue, 5);
      expect(sim.boundary, 0, reason: 'a head start must not bank');

      goLive(sim);
      expect(sim.phase, FloodPhase.live);
      tap(sim, blue);
      expect(sim.boundary, lessThan(0), reason: 'and now it counts');
    });

    test('reports itself so every phone can draw the same number', () {
      final sim = start(const FloodGame(), 2).sim;
      expect(
        sim.sharedState[FloodState.countdown],
        FloodConfig.countdownSeconds.ceil(),
      );
      // Just past a second in, the number on screen has ticked down by one.
      // Sampled a hair after the boundary rather than exactly on it: at the
      // instant itself the count is still legitimately the higher number.
      advance(sim, 1.1);
      expect(
        sim.sharedState[FloodState.countdown],
        FloodConfig.countdownSeconds.ceil() - 1,
      );

      // And it reaches GO exactly when the countdown runs out.
      advance(sim, FloodConfig.countdownSeconds);
      expect(sim.sharedState[FloodState.countdown], 0);
      expect(sim.phase, FloodPhase.live);
    });
  });

  group('Flood — growing power', () {
    test('a later tap moves the boundary further than an early one', () {
      final sim = start(const FloodGame(), 2).sim as FloodGrowingSim;
      goLive(sim);

      final blue = phonesOn(sim, FloodConfig.blue).first;
      tap(sim, blue);
      final firstTap = sim.boundary.abs();

      advance(sim, FloodGrowingConfig.rampWindow);
      tap(sim, blue);
      final laterTap = sim.boundary.abs() - firstTap;

      // One rampWindow in, a tap is worth double.
      expect(laterTap, closeTo(firstTap * 2, firstTap * 0.05));
    });

    test('an even mash goes nowhere, however hard it ramps', () {
      final sim = start(const FloodGame(), 4).sim;
      goLive(sim);

      final blue = phonesOn(sim, FloodConfig.blue);
      final red = phonesOn(sim, FloodConfig.red);
      for (var i = 0; i < 20; i++) {
        for (var t = 0; t < blue.length; t++) {
          tap(sim, blue[t]);
          tap(sim, red[t]);
        }
        advance(sim, FloodConfig.minTapIntervalSeconds + 1 / 60);
      }

      expect(sim.boundary, closeTo(0, 1e-9));
      expect(sim.outcome, isNull);
    });

    test('a team that only taps wins, and the scoreboard says who', () {
      final started = start(const FloodGame(), 4);
      final sim = started.sim;
      goLive(sim);

      final red = phonesOn(sim, FloodConfig.red);
      for (var i = 0; i < 60 && sim.outcome == null; i++) {
        for (final p in red) {
          tap(sim, p);
        }
        advance(sim, FloodConfig.minTapIntervalSeconds + 1 / 60);
      }

      expect(sim.outcome, isNotNull);
      expect(sim.outcome!.summary, contains('red'));
      for (final p in red) {
        expect(started.scores[p], 1, reason: 'every winner scores');
      }
      for (final p in phonesOn(sim, FloodConfig.blue)) {
        expect(started.scores[p], 0);
      }
    });

    test('twenty unopposed taps are about a full swing at the start', () {
      // The READMEs' tuning target for basePush.
      final sim = start(const FloodGame(), 2).sim;
      goLive(sim);
      mash(sim, phonesOn(sim, FloodConfig.red).first, 20);
      // Ramped slightly by the time spent tapping, so it is at or past the line.
      expect(sim.effectiveBoundary, greaterThanOrEqualTo(0.9));
    });
  });

  group('Flood: Closing In — shrinking field', () {
    test('every tap is worth the same, whenever it lands', () {
      final sim = start(const FloodClosingGame(), 2).sim;
      goLive(sim);

      final blue = phonesOn(sim, FloodConfig.blue).first;
      tap(sim, blue);
      final firstTap = sim.boundary.abs();

      advance(sim, FloodShrinkingConfig.shrinkWindow / 2);
      tap(sim, blue);
      final laterTap = sim.boundary.abs() - firstTap;

      expect(laterTap, closeTo(firstTap, 1e-9));
    });

    test('the same lead reads as a bigger swing as the field closes', () {
      final sim = start(const FloodClosingGame(), 2).sim as FloodShrinkingSim;
      goLive(sim);

      mash(sim, phonesOn(sim, FloodConfig.red).first, 3);
      final raw = sim.boundary;
      final early = sim.effectiveBoundary;

      advance(sim, FloodShrinkingConfig.shrinkWindow / 2);
      expect(sim.boundary, raw, reason: 'the raw tug-of-war has not moved');
      expect(sim.effectiveBoundary, greaterThan(early));
    });

    test('the field shrinks to its floor and stops', () {
      final sim = start(const FloodClosingGame(), 2).sim as FloodShrinkingSim;
      goLive(sim);
      expect(sim.rangeScale, closeTo(1.0, 0.02));

      advance(sim, FloodShrinkingConfig.shrinkWindow + 5);
      expect(sim.rangeScale, FloodShrinkingConfig.minScale);
    });

    test('a small stable lead eventually wins on its own', () {
      final started = start(const FloodClosingGame(), 2);
      final sim = started.sim;
      goLive(sim);

      // Three taps and then nobody touches anything again.
      final red = phonesOn(sim, FloodConfig.red).first;
      mash(sim, red, 3);
      expect(sim.outcome, isNull, reason: 'not decisive yet');

      advance(sim, FloodShrinkingConfig.shrinkWindow);
      expect(
        sim.outcome,
        isNotNull,
        reason: 'the closing field must resolve it without another tap',
      );
      expect(started.scores[red], 1);
    });
  });

  group('the backstop', () {
    test('a dead-level round is resolved as a draw, not left running', () {
      for (final game in [const FloodGame(), const FloodClosingGame()]) {
        final sim = start(game, 2).sim;
        goLive(sim);
        advance(sim, FloodConfig.maxRoundLength + 1);

        expect(sim.outcome, isNotNull, reason: '${game.manifest.id} must end');
        // Declared, not spelled out in prose: the platform is what tells each
        // phone "a draw", so the word being in the summary proved nothing.
        expect(sim.outcome!.kind, OutcomeKind.draw);
        expect(sim.outcome!.winners, isNull);
      }
    });

    test('no round outlives the cap', () {
      for (final game in [const FloodGame(), const FloodClosingGame()]) {
        final started = start(game, 2);
        final sim = started.sim;
        goLive(sim);

        // A near-stalemate: both sides mash in lockstep, but red got one tap
        // in first and never gives it back.
        final blue = phonesOn(sim, FloodConfig.blue).first;
        final red = phonesOn(sim, FloodConfig.red).first;
        tap(sim, red);
        advance(sim, FloodConfig.minTapIntervalSeconds + 1 / 60);
        for (var i = 0; i < 2000 && sim.outcome == null; i++) {
          tap(sim, blue);
          tap(sim, red);
          advance(sim, FloodConfig.minTapIntervalSeconds + 1 / 60);
        }

        expect(sim.outcome, isNotNull);
        expect(
          sim.elapsed,
          lessThanOrEqualTo(FloodConfig.maxRoundLength + 0.5),
          reason: '${game.manifest.id} respects the 90-second play rule',
        );
        expect(started.scores[red], 1, reason: 'the marginal lead takes it');
      }
    });

    test('taps stop counting once the round is over', () {
      final sim = start(const FloodGame(), 2).sim;
      goLive(sim);

      final red = phonesOn(sim, FloodConfig.red).first;
      for (var i = 0; i < 60 && sim.outcome == null; i++) {
        mash(sim, red, 1);
      }
      expect(sim.outcome, isNotNull);

      final settled = sim.boundary;
      mash(sim, phonesOn(sim, FloodConfig.blue).first, 5);
      expect(sim.boundary, settled, reason: 'the result cannot be tapped away');
    });
  });

  group('the shared contract', () {
    test('an idle board broadcasts nothing at all', () {
      // `sharedState` is diffed every tick by the host and sent only when it
      // changed. A value that drifts every tick — a raw elapsed float, an
      // undecayed pulse — turns that change-driven channel into a 60 Hz stream
      // for a game whose entire world is one number. This is the guard.
      bool sameShared(Map<String, Object?> a, Map<String, Object?> b) {
        if (a.length != b.length) return false;
        for (final e in a.entries) {
          if (b[e.key] != e.value) return false;
        }
        return true;
      }

      for (final game in [const FloodGame(), const FloodClosingGame()]) {
        final sim = start(game, 2).sim;
        goLive(sim);

        var last = Map.of(sim.sharedState);
        var sends = 0;
        for (var i = 0; i < 600; i++) {
          sim.step(1 / 60);
          final now = sim.sharedState;
          if (!sameShared(now, last)) {
            sends++;
            last = Map.of(now);
          }
        }

        // Ten seconds — 600 ticks — of nobody touching anything.
        //
        // Not zero for either variant: A's power ramps and B's field closes
        // whether anyone plays or not, so both have real news some of the
        // time. The bar is that it is a trickle rather than a tick-rate
        // stream. Unrounded, this was 600 — a packet every single tick.
        expect(
          sends,
          lessThan(50),
          reason: '${game.manifest.id} floods the network when idle',
        );
      }
    });

    test('a tug-of-war on one float needs no entities', () {
      final sim = start(const FloodGame(), 2).sim;
      goLive(sim);
      expect(sim.entities, isEmpty);
    });

    test('the boundary is always drawable, in [-1, +1]', () {
      final started = start(const FloodClosingGame(), 2);
      final sim = started.sim;
      goLive(sim);

      final red = phonesOn(sim, FloodConfig.red).first;
      for (var i = 0; i < 200; i++) {
        tap(sim, red);
        advance(sim, FloodConfig.minTapIntervalSeconds + 1 / 60);
        final b = sim.sharedState[FloodState.boundary] as double;
        expect(b, inInclusiveRange(-1.0, 1.0));
      }
    });

    test('reset puts the round back to its opening position', () {
      final sim = start(const FloodGame(), 2).sim;
      goLive(sim);
      mash(sim, phonesOn(sim, FloodConfig.red).first, 25);
      expect(sim.outcome, isNotNull);

      sim.reset();
      expect(sim.boundary, 0);
      expect(sim.outcome, isNull);
      expect(sim.phase, FloodPhase.countdown);
      expect(sim.elapsed, -FloodConfig.countdownSeconds);
    });

    test('a rate limit keeps an autoclicker from outrunning a thumb', () {
      final sim = start(const FloodGame(), 2).sim;
      goLive(sim);

      final red = phonesOn(sim, FloodConfig.red).first;
      // Ten taps in the same instant: only the first can count.
      for (var i = 0; i < 10; i++) {
        tap(sim, red);
      }
      expect(sim.boundary, closeTo(FloodConfig.basePush, 0.01));
    });

    test('a phone can only ever tap for its own team', () {
      final sim = start(const FloodGame(), 2).sim;
      goLive(sim);

      tap(sim, 'not-a-phone');
      expect(sim.boundary, 0, reason: 'an unknown phone has no team');
    });

    test('every phone is told which side it is on', () {
      final sim = start(const FloodClosingGame(), 4).sim;
      final teams = sim.sharedState[FloodState.teams] as Map;
      expect(teams, hasLength(4));
      expect(
        teams.values.toSet(),
        {FloodConfig.blue, FloodConfig.red},
      );
    });
  });
}
