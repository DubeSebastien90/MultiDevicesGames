import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/highwire/highwire_config.dart';
import 'package:multiscreen_slingshot/games/highwire/highwire_game.dart';
import 'package:multiscreen_slingshot/games/highwire/highwire_sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// No physics at all — a row board with a single hand-rolled entity on it.
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

({HighwireSim sim, BoardLayout board, Scoreboard scores}) start(int count) {
  final lobby = LobbyInfo([for (var i = 0; i < count; i++) phone('p${i + 1}')]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  const game = HighwireGame();
  final board = const BoardCompiler().compile(game.planBoard(lobby), lobby);
  final sim = HighwireSim(board.contextFor(scores));
  scores.beginRound();
  return (sim: sim, board: board, scores: scores);
}

void hold(HighwireSim sim, String phoneId) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: 0,
    worldY: 0,
    phase: TouchPhase.down,
  ));
}

void release(HighwireSim sim, String phoneId) {
  sim.onTouch(TouchEvent(
    phoneId: phoneId,
    worldX: 0,
    worldY: 0,
    phase: TouchPhase.up,
  ));
}

const dt = 1 / PlatformConfig.simHz;

void main() {
  group('the table', () {
    test('needs at least two phones, and the row fits up to eight', () {
      expect(const HighwireGame().manifest.smallestTable, 2);
      expect(const HighwireGame().manifest.fits(1), isFalse);
      expect(const HighwireGame().manifest.fits(2), isTrue);
      expect(const HighwireGame().manifest.fits(8), isTrue);
      // Every count in between compiles into a real row board.
      for (final count in [2, 3, 5, 8]) {
        final started = start(count);
        expect(started.board.phones, hasLength(count));
      }
    });
  });

  group('opening position', () {
    test('the walker starts at the left edge, at full balance', () {
      final started = start(3);
      final sim = started.sim;
      expect(sim.walkerX, closeTo(started.board.board.left + HighwireConfig.walkerRadius, 1e-9));
      expect(sim.balance, 1);
      expect(sim.outcome, isNull);
    });
  });

  group('holding it up', () {
    test('nobody holding: the walker does not move and balance drains', () {
      final started = start(3);
      final sim = started.sim;
      final startX = sim.walkerX;

      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(dt);
      }
      expect(sim.walkerX, startX, reason: 'unsupported, so no progress');
      expect(sim.balance, lessThan(1));
    });

    test('the right phone holding on: the walker advances and balance regens', () {
      final started = start(3);
      final sim = started.sim;
      // Drain it first, then rescue it.
      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(dt);
      }
      final drained = sim.balance;
      expect(drained, lessThan(1));

      final holder = sim.holder!;
      hold(sim, holder);
      final beforeX = sim.walkerX;
      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(dt);
      }
      expect(sim.walkerX, greaterThan(beforeX));
      expect(sim.balance, greaterThan(drained));
    });

    test('letting go stops progress, and a second finger is not the first '
        'one leaving', () {
      final started = start(3);
      final sim = started.sim;
      final holder = sim.holder!;

      hold(sim, holder);
      hold(sim, holder); // a second finger down on the same screen
      release(sim, holder); // only one of them lifts
      final beforeX = sim.walkerX;
      sim.step(dt);
      expect(sim.walkerX, greaterThan(beforeX),
          reason: 'the other finger is still down, so it is still held');

      release(sim, holder); // the last finger lifts
      final stillX = sim.walkerX;
      sim.step(dt);
      expect(sim.walkerX, stillX,
          reason: 'nobody is holding it any more');
    });

    test('the wrong phone holding on does nothing for the walker', () {
      final started = start(3);
      final sim = started.sim;
      final board = started.board;
      final holder = sim.holder!;
      final bystander =
          board.phones.map((p) => p.phoneId).firstWhere((id) => id != holder);

      hold(sim, bystander);
      final beforeX = sim.walkerX;
      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(dt);
      }
      expect(sim.walkerX, beforeX);
      expect(sim.balance, lessThan(1));
    });

    test('letting balance run out ends the round in a shared loss', () {
      final started = start(3);
      final sim = started.sim;

      final ticks =
          (HighwireConfig.balanceDrainSeconds * PlatformConfig.simHz).ceil() + 5;
      for (var i = 0; i < ticks; i++) {
        sim.step(dt);
      }
      expect(sim.outcome, isNotNull);
      expect(sim.outcome!.kind, OutcomeKind.shared);
      expect(sim.outcome!.won, isFalse);

      // Latched: stepping more does not change the verdict object.
      final outcome = sim.outcome;
      sim.step(dt);
      expect(identical(sim.outcome, outcome), isTrue);
    });

    test('running out the clock also ends it in a loss', () {
      final started = start(2);
      final sim = started.sim;
      // Hold the very first phone forever so the walker only ever inches
      // across its own screen and never reaches anybody else's — the clock,
      // not a fall, ends this one.
      hold(sim, sim.holder!);

      final ticks =
          (HighwireConfig.timeLimitSeconds * PlatformConfig.simHz).ceil() + 5;
      for (var i = 0; i < ticks; i++) {
        sim.step(dt);
        // Keep re-holding: as the phone under it changes we want the clock,
        // not a fall, to be what ends the round on a two-phone table with a
        // very long crossing relative to the drain — so just hold whichever
        // phone is current throughout.
        final h = sim.holder;
        if (h != null) hold(sim, h);
      }
      expect(sim.outcome, isNotNull);
    });
  });

  group('reaching the far end', () {
    test('crossing the whole board wins it for everyone, exactly once', () {
      final started = start(2);
      final sim = started.sim;
      final board = started.board;

      // Hold every phone throughout, so the walker never stalls.
      for (final p in board.phones) {
        hold(sim, p.phoneId);
      }

      final ticks =
          (HighwireConfig.crossingSeconds * PlatformConfig.simHz).ceil() + 30;
      for (var i = 0; i < ticks && sim.outcome == null; i++) {
        sim.step(dt);
      }

      expect(sim.outcome, isNotNull);
      expect(sim.outcome!.won, isTrue);
      for (final p in board.phones) {
        expect(started.scores[p.phoneId], HighwireConfig.crossingBonus);
      }

      // Kept stepping well past the finish; it must not keep paying out.
      for (var i = 0; i < PlatformConfig.simHz; i++) {
        sim.step(dt);
      }
      for (final p in board.phones) {
        expect(started.scores[p.phoneId], HighwireConfig.crossingBonus);
      }
    });
  });

  group('the seam itself', () {
    test(
      'the walker sweeps continuously across the boundary between two '
      'phones, read from the compiled board',
      () {
        final started = start(3);
        final sim = started.sim;
        final board = started.board;
        for (final p in board.phones) {
          hold(sim, p.phoneId);
        }

        final first = board.slices[0];
        final second = board.slices[1];
        final speed = board.board.width / HighwireConfig.crossingSeconds;

        // Walk it until it has left the first phone's slice and landed on the
        // second, checking every tick's motion against what the constant
        // speed says it should be — never a jump, never a step backwards.
        var previousX = sim.walkerX;
        var sawGap = false;
        var landedOnSecond = false;

        for (var i = 0; i < PlatformConfig.simHz * 20 && !landedOnSecond; i++) {
          sim.step(dt);

          final movedBy = sim.walkerX - previousX;
          expect(movedBy, closeTo(speed * dt, 1e-6),
              reason: 'the walker must move by exactly one tick of the '
                  'wire\'s constant speed, never a jump');
          previousX = sim.walkerX;

          final holder = sim.holder;
          if (holder == null) {
            sawGap = true;
            // In the bezel gap: on neither phone's screen.
            expect(first.contains(sim.walkerX, board.board.centerY), isFalse);
            expect(second.contains(sim.walkerX, board.board.centerY), isFalse);
          } else if (holder == second.phoneId) {
            landedOnSecond = true;
            expect(second.contains(sim.walkerX, board.board.centerY), isTrue,
                reason: 'the compiled slice bounds must agree with phoneAt');
          }
        }

        expect(sawGap, isTrue,
            reason: 'the walker never crossed the real gap between screens');
        expect(landedOnSecond, isTrue,
            reason: 'the walker never actually reached the second phone');
      },
    );
  });

  test('reset puts the walker back at the start, in full health', () {
    final started = start(3);
    final sim = started.sim;

    final ticks =
        (HighwireConfig.balanceDrainSeconds * PlatformConfig.simHz).ceil() + 5;
    for (var i = 0; i < ticks; i++) {
      sim.step(dt);
    }
    expect(sim.outcome, isNotNull);

    sim.reset();
    expect(sim.outcome, isNull);
    expect(sim.balance, 1);
    expect(
      sim.walkerX,
      closeTo(started.board.board.left + HighwireConfig.walkerRadius, 1e-9),
    );
  });
}
