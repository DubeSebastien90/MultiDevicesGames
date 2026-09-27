import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/paint_war/paint_war_config.dart';
import 'package:multiscreen_slingshot/games/paint_war/paint_war_game.dart';
import 'package:multiscreen_slingshot/games/paint_war/paint_war_sim.dart';
import 'package:multiscreen_slingshot/games/paint_war/paint_war_view.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/sounds.dart';
import 'package:multiscreen_slingshot/sdk/audio/tone.dart';
import 'package:multiscreen_slingshot/sdk/contract/entity.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart';
import 'package:multiscreen_slingshot/sdk/contract/view.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/platform_config.dart';
import 'package:multiscreen_slingshot/sdk/score/scoreboard.dart';

/// Paint War, played headlessly: no host, no sockets, no rendering.
const _dt = 1 / PlatformConfig.simHz;

PhoneSpec phone(
  String id,
  PlayerColor color, {
  double widthMm = 68.58,
  double heightMm = 152.4,
}) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: widthMm,
  heightMm: heightMm,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: widthMm * 400 / 25.4,
  activePxHeight: heightMm * 400 / 25.4,
  color: color,
);

({PaintWarSim sim, BoardLayout board, Scoreboard scores, _HeardAudio audio})
start(int count, {bool skipIntro = true, bool tablets = false}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++)
      tablets
          ? phone(
              'p${i + 1}',
              PlayerPalette.all[i],
              widthMm: 120,
              heightMm: 170,
            )
          : phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const PaintWarGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = PaintWarSim(board.contextFor(scores, audio: audio));
  scores.beginRound();
  if (skipIntro) {
    run(
      sim,
      PaintWarConfig.briefingSeconds + PaintWarConfig.countdownSeconds + 0.1,
    );
    audio.plays.clear();
  }
  return (sim: sim, board: board, scores: scores, audio: audio);
}

void run(PaintWarSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

({double x, double y}) positionOf(PaintWarSim sim, String phoneId) {
  final e = sim.entities.firstWhere((e) => e.props['phoneId'] == phoneId);
  return (x: e.x, y: e.y);
}

void touch(PaintWarSim sim, String phoneId, String phase, double x, double y) =>
    sim.onTouch(
      TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: phase),
    );

/// Walk [phoneId] to (x, y) at full stick, the way a thumb would: down, push
/// towards it, and lift once there.
void walkTo(PaintWarSim sim, String phoneId, double x, double y) {
  for (var i = 0; i < PlatformConfig.simHz * 10; i++) {
    final at = positionOf(sim, phoneId);
    final dx = x - at.x;
    final dy = y - at.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 0.06) break;
    touch(sim, phoneId, TouchPhase.down, 0, 0);
    // Far enough out for full tilt; slower for the last step so it lands.
    final reach = d < 0.2 ? PaintWarConfig.minMoveDistance + 0.1 : 4.0;
    touch(sim, phoneId, TouchPhase.move, dx / d * reach, dy / d * reach);
    sim.step(_dt);
  }
  touch(sim, phoneId, TouchPhase.up, 0, 0);
}

// The briefing's loop paints out towards +x and +y of everyone's middle, so
// every walk here heads the other way, onto clean board.

void main() {
  group('the table', () {
    test('two to eight, laid out like Arena and Dodgeball', () {
      final manifest = const PaintWarGame().manifest;
      expect(manifest.fits(1), isFalse);
      for (var n = 2; n <= 8; n++) {
        expect(manifest.fits(n), isTrue, reason: '$n phones');
        final s = start(n, skipIntro: false);
        expect(s.board.slices, hasLength(n));
      }
      expect(manifest.isPremium, isFalse, reason: 'a free game');
    });

    test('everyone starts on an equal circle of their own paint', () {
      final s = start(4, skipIntro: false);
      final areas = {
        for (final id in s.sim.context.phoneIds) s.sim.cellsOf(id),
      };
      expect(areas, hasLength(1), reason: 'not everybody got the same circle');
      expect(areas.single, greaterThan(50));
      for (final id in s.sim.context.phoneIds) {
        final at = positionOf(s.sim, id);
        expect(s.sim.ownerAt(at.x, at.y), id);
      }
    });
  });

  group('the briefing', () {
    test('walks its three lines, grows everyone once, then counts', () {
      final s = start(3, skipIntro: false);
      final before = {
        for (final id in s.sim.context.phoneIds) id: s.sim.cellsOf(id),
      };

      run(s.sim, PaintWarConfig.briefingSeconds + 0.05);
      expect(s.sim.phase, 'countdown');
      for (final id in s.sim.context.phoneIds) {
        expect(
          s.sim.cellsOf(id),
          greaterThan(before[id]! * 1.5),
          reason: 'the demonstration loop was not filled in for $id',
        );
      }
      // One boup a capture, on each player's own glass.
      final boups = [
        for (final p in s.audio.plays)
          if (Sounds.buttonPress.contains(p.cue)) p.phoneId,
      ];
      expect(boups, unorderedEquals(s.sim.context.phoneIds));

      run(s.sim, PaintWarConfig.countdownSeconds + 0.1);
      expect(s.sim.phase, 'playing');
    });

    test('nobody can be cut during it', () {
      final s = start(2, skipIntro: false);
      run(s.sim, PaintWarConfig.briefingSeconds);
      for (final id in s.sim.context.phoneIds) {
        expect(s.sim.isAlive(id), isTrue);
      }
      expect(
        s.audio.plays.where((p) => p.cue == PaintWarConfig.cutTrail),
        isEmpty,
      );
    });
  });

  group('painting', () {
    test('walking off your paint leaves a wet trail', () {
      final s = start(2);
      final home = positionOf(s.sim, 'p1');
      walkTo(s.sim, 'p1', home.x - 3, home.y);

      expect(s.sim.trailAt('p1', home.x - 2.2, home.y), isTrue);
      expect(s.sim.ownerAt(home.x - 2.2, home.y), isNull, reason: 'still wet');
      expect(
        s.sim.sharedState['trail_p0'] ?? s.sim.sharedState['trail_p1'],
        isNotNull,
      );
    });

    test('closing a loop fills in everything inside it', () {
      final s = start(2);
      final home = positionOf(s.sim, 'p1');
      final before = s.sim.cellsOf('p1');

      walkTo(s.sim, 'p1', home.x - 3, home.y);
      walkTo(s.sim, 'p1', home.x - 3, home.y - 2);
      walkTo(s.sim, 'p1', home.x, home.y - 2);
      walkTo(s.sim, 'p1', home.x, home.y);

      // A 3 by 2 loop is six square centimetres, most of it new: at least
      // eighty cells of it, even after what overlapped the circle.
      expect(s.sim.cellsOf('p1'), greaterThan(before + 80));
      // The middle of the loop, never walked on, is painted now.
      expect(s.sim.ownerAt(home.x - 1.9, home.y - 1.1), 'p1');
      expect(s.sim.trailAt('p1', home.x - 2.2, home.y), isFalse, reason: 'dry');
      final boups = [
        for (final p in s.audio.plays)
          if (Sounds.buttonPress.contains(p.cue)) p.phoneId,
      ];
      expect(boups, hasLength(1));
    });

    test("a loop takes other people's paint inside it too", () {
      final s = start(2, tablets: true);
      final p1 = positionOf(s.sim, 'p1');
      final p2 = positionOf(s.sim, 'p2');
      // p1 walks right round everything p2 has painted, and home again.
      walkTo(s.sim, 'p1', p1.x, p2.y - 2.4);
      walkTo(s.sim, 'p1', p2.x + 3.2, p2.y - 2.4);
      walkTo(s.sim, 'p1', p2.x + 3.2, p2.y + 3.8);
      walkTo(s.sim, 'p1', p1.x, p2.y + 3.8);
      walkTo(s.sim, 'p1', p1.x, p1.y);

      // p2's paint is p1's now, and p2 is out — there was nothing left to go
      // home to.
      expect(s.sim.ownerAt(p2.x + 0.5, p2.y), 'p1');
      expect(s.sim.cellsOf('p2'), 0);
      expect(s.sim.isAlive('p2'), isFalse);
    });
  });

  group('being cut', () {
    test('touching a wet trail wipes its owner off, paint and all', () {
      final s = start(2);
      final home = positionOf(s.sim, 'p1');
      walkTo(s.sim, 'p1', home.x - 3, home.y);
      expect(s.sim.cellsOf('p1'), greaterThan(0));

      // p2 walks in across the middle of it.
      final p2 = positionOf(s.sim, 'p2');
      walkTo(s.sim, 'p2', p2.x, home.y - 2.5);
      walkTo(s.sim, 'p2', home.x - 2.2, home.y - 2.5);
      walkTo(s.sim, 'p2', home.x - 2.2, home.y + 1);

      expect(s.sim.isAlive('p1'), isFalse);
      expect(s.sim.cellsOf('p1'), 0, reason: 'their paint went with them');
      expect(s.sim.trailAt('p1', home.x - 2.6, home.y), isFalse);
      expect(s.sim.isAlive('p2'), isTrue, reason: 'the cutter is fine');

      final cuts = [
        for (final p in s.audio.plays)
          if (p.cue == PaintWarConfig.cutTrail) p.phoneId,
      ];
      expect(cuts, contains('p1'), reason: 'the one cut hears it');
    });

    test('crossing your own trail is not a cut', () {
      final s = start(2);
      final home = positionOf(s.sim, 'p1');
      walkTo(s.sim, 'p1', home.x - 3, home.y);
      walkTo(s.sim, 'p1', home.x - 3, home.y - 1.5);
      walkTo(s.sim, 'p1', home.x - 2, home.y + 1);
      expect(s.sim.isAlive('p1'), isTrue);
    });

    test('comes back on a fresh circle, somewhere clean and inside', () {
      final s = start(4);
      final home = positionOf(s.sim, 'p1');
      walkTo(s.sim, 'p1', home.x - 2.6, home.y);
      // Somebody cuts it: stand p2 on it by walking there.
      final at = (x: home.x - 2.2, y: home.y);
      walkTo(s.sim, 'p2', at.x, at.y);
      expect(s.sim.isAlive('p1'), isFalse);

      run(s.sim, PaintWarConfig.respawnSeconds + 0.1);
      expect(s.sim.isAlive('p1'), isTrue);
      expect(s.sim.cellsOf('p1'), greaterThan(50));

      // Far enough in that the whole circle and its margin are on the glass,
      // and on nobody else's paint.
      final back = positionOf(s.sim, 'p1');
      final board = s.board.board;
      const clear = PaintWarConfig.spawnRadius + PaintWarConfig.spawnMargin;
      expect(back.x, inInclusiveRange(board.left + clear, board.right - clear));
      expect(back.y, inInclusiveRange(board.top + clear, board.bottom - clear));
      for (final other in ['p2', 'p3', 'p4']) {
        expect(s.sim.ownerAt(back.x, back.y), isNot(other));
      }
    });
  });

  group('the end', () {
    test('counts down the last five, then OVER, then ranks by area', () {
      final s = start(3);
      // p2 grows a little, so there is a clear first place.
      final home = positionOf(s.sim, 'p2');
      walkTo(s.sim, 'p2', home.x - 2.5, home.y);
      walkTo(s.sim, 'p2', home.x - 2.5, home.y - 1.8);
      walkTo(s.sim, 'p2', home.x, home.y);

      final seen = <int>{};
      while (s.sim.phase == 'playing') {
        seen.add((s.sim.sharedState['left']! as num).toInt());
        s.sim.step(_dt);
      }
      expect(seen, containsAll(<int>[5, 4, 3, 2, 1]));
      expect(s.sim.phase, 'over');
      expect(s.sim.outcome, isNull, reason: 'OVER holds the table first');

      final top = s.scores.view.ranked.first;
      expect(top.phoneId, 'p2');

      run(s.sim, PaintWarConfig.overSeconds + 0.1);
      final outcome = s.sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.lines!['p2'], contains('%'));
      expect(identical(s.sim.outcome, outcome), isTrue, reason: 'latched');
    });

    test('nobody moves once it is OVER', () {
      final s = start(2);
      run(s.sim, PaintWarConfig.roundSeconds + 0.1);
      final at = positionOf(s.sim, 'p1');
      touch(s.sim, 'p1', TouchPhase.down, 0, 0);
      touch(s.sim, 'p1', TouchPhase.move, 4, 0);
      run(s.sim, 0.5);
      expect(positionOf(s.sim, 'p1').x, at.x);
    });
  });

  group('the stick', () {
    test('shows under the finger only while it is steering', () {
      final s = start(2);
      List<String> sticks() => [
        for (final e in s.sim.entities)
          if (e.kind == 'stick' || e.kind == 'knob') e.id,
      ];
      expect(sticks(), isEmpty);

      touch(s.sim, 'p1', TouchPhase.down, 1, 1);
      expect(sticks(), isEmpty, reason: 'a resting finger steers nothing');

      touch(s.sim, 'p1', TouchPhase.move, 1 + 3, 1);
      final anchor = s.sim.entities.firstWhere((e) => e.kind == 'stick');
      final knob = s.sim.entities.firstWhere((e) => e.kind == 'knob');
      expect(anchor.props['phoneId'], 'p1');
      expect((anchor.x, anchor.y), (1.0, 1.0));
      expect((knob.x, knob.y), (4.0, 1.0));

      touch(s.sim, 'p1', TouchPhase.up, 4, 1);
      expect(sticks(), isEmpty);
    });

    test('moves exactly like Dodgeball: faster the further it is pushed', () {
      double stride(double push) {
        final s = start(2);
        final from = positionOf(s.sim, 'p1');
        touch(s.sim, 'p1', TouchPhase.down, 0, 0);
        touch(s.sim, 'p1', TouchPhase.move, -push, 0);
        run(s.sim, 0.25);
        return from.x - positionOf(s.sim, 'p1').x;
      }

      expect(
        stride(PaintWarConfig.minMoveDistance * 0.9),
        0,
        reason: 'inside the dead zone',
      );
      final crawl = stride(
        (PaintWarConfig.minMoveDistance + PaintWarConfig.joystickRadius) / 2,
      );
      final run_ = stride(PaintWarConfig.joystickRadius * 2);
      expect(crawl, greaterThan(0));
      expect(run_, greaterThan(crawl * 1.5));
      expect(run_, closeTo(PaintWarConfig.moveSpeed * 0.25, 0.2));
    });
  });

  group('the wire', () {
    test('a straight walk does not change the shared state every tick', () {
      final s = start(2);
      final home = positionOf(s.sim, 'p1');
      // Out of the paint and into the straight.
      walkTo(s.sim, 'p1', home.x - 2.2, home.y);

      var changes = 0;
      var last = Map.of(s.sim.sharedState);
      touch(s.sim, 'p1', TouchPhase.down, 0, 0);
      touch(s.sim, 'p1', TouchPhase.move, -4, 0);
      for (var i = 0; i < 30; i++) {
        s.sim.step(_dt);
        final now = s.sim.sharedState;
        final same =
            now.length == last.length &&
            now.entries.every((e) => last[e.key] == e.value);
        if (!same) changes++;
        last = Map.of(now);
      }
      expect(changes, lessThan(5), reason: 'the state is resent whole');
    });
  });

  test('the view draws every phase without falling over', () {
    final s = start(2, skipIntro: false);
    final view = PaintWarView(phoneId: 'p1', roster: s.board.roster);

    void draw() {
      for (final slice in s.board.slices) {
        final recorder = ui.PictureRecorder();
        view.render(
          ui.Canvas(recorder),
          Frame(
            entities: {
              for (final e in s.sim.entities)
                e.id: RenderEntity(
                  descriptor: e.descriptor,
                  x: e.x,
                  y: e.y,
                  angle: e.angle,
                ),
            },
            sharedState: s.sim.sharedState,
            scores: ScoreView.empty,
            timeMs: 0,
            dt: 1 / 60,
            me: s.board.forPhone(slice.phoneId)!,
            board: s.board.coverage.board,
            coverage: s.board.coverage,
          ),
        );
        recorder.endRecording().dispose();
      }
    }

    draw(); // the briefing
    run(s.sim, PaintWarConfig.briefingSeconds + 0.2);
    draw(); // the count
    run(s.sim, PaintWarConfig.countdownSeconds);
    final home = positionOf(s.sim, 'p1');
    walkTo(s.sim, 'p1', home.x - 3, home.y);
    walkTo(s.sim, 'p1', home.x - 3, home.y - 1.5);
    expect(s.sim.sharedState.keys, contains(anyOf('trail_p0', 'trail_p1')));
    draw(); // a trail on the board
    touch(s.sim, 'p1', TouchPhase.down, home.x, home.y);
    touch(s.sim, 'p1', TouchPhase.move, home.x - 3, home.y);
    draw(); // the stick under a finger
    touch(s.sim, 'p1', TouchPhase.up, home.x - 3, home.y);
    final p2 = positionOf(s.sim, 'p2');
    walkTo(s.sim, 'p2', p2.x, home.y - 0.8);
    walkTo(s.sim, 'p2', home.x - 3.5, home.y - 0.8);
    expect(s.sim.isAlive('p1'), isFalse);
    draw(); // somebody cut
    run(s.sim, PaintWarConfig.roundSeconds);
    draw(); // OVER
  });

  test('reset starts a fresh round', () {
    final s = start(2);
    final home = positionOf(s.sim, 'p1');
    walkTo(s.sim, 'p1', home.x - 3, home.y);
    s.sim.reset();
    expect(s.sim.phase, 'briefing');
    expect(s.sim.trailAt('p1', home.x - 2.2, home.y), isFalse);
    expect(s.sim.cellsOf('p1'), s.sim.cellsOf('p2'));
  });
}

class _Play {
  _Play(this.phoneId, this.cue);
  final String phoneId;
  final SoundCue cue;
}

class _HeardAudio implements GameAudio {
  final plays = <_Play>[];
  var _next = 1;

  @override
  SoundHandle playGeneral(
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) => throw StateError('Paint War only ever plays on a phone');

  @override
  SoundHandle playOnPhone(
    Player player,
    SoundCue cue, {
    bool loop = false,
    double volume = 1.0,
    bool persist = false,
    Duration fadeIn = Duration.zero,
  }) {
    plays.add(_Play(player.phoneId, cue));
    return SoundHandle(_next++);
  }

  @override
  SoundHandle playToneOnPhone(
    Player player,
    Tone tone, {
    bool persist = false,
  }) => SoundHandle(_next++);

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}

  @override
  void stopRoundSounds() {}
}
