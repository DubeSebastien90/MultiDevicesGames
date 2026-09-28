import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/chomp_chase/chomp_chase_config.dart';
import 'package:multiscreen_slingshot/games/chomp_chase/chomp_chase_game.dart';
import 'package:multiscreen_slingshot/games/chomp_chase/chomp_chase_maze.dart';
import 'package:multiscreen_slingshot/games/chomp_chase/chomp_chase_sim.dart';
import 'package:multiscreen_slingshot/games/chomp_chase/chomp_chase_view.dart';
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

/// Chomp Chase, played headlessly: no host, no sockets, no rendering.
const _dt = 1 / PlatformConfig.simHz;

PhoneSpec phone(String id, PlayerColor color, {double heightMm = 152.4}) =>
    PhoneSpec(
      phoneId: id,
      label: 'phone $id',
      widthMm: 68.58,
      heightMm: heightMm,
      bezelMm: 3,
      dpi: 400,
      devicePixelRatio: 3,
      activePxWidth: 1080,
      activePxHeight: 1080 * heightMm / 68.58,
      color: color,
    );

({ChompChaseSim sim, BoardLayout board, Scoreboard scores, _HeardAudio audio})
start(int count, {int seed = 3, bool toPlay = true}) {
  final lobby = LobbyInfo([
    for (var i = 0; i < count; i++) phone('p${i + 1}', PlayerPalette.all[i]),
  ]);
  final scores = Scoreboard();
  for (final p in lobby.phones) {
    scores.register(p.phoneId, p.label);
  }
  final board = const BoardCompiler().compile(
    const ChompChaseGame().planBoard(lobby),
    lobby,
  );
  final audio = _HeardAudio();
  final sim = ChompChaseSim(
    board.contextFor(scores, audio: audio),
    random: math.Random(seed),
  );
  scores.beginRound();
  if (toPlay) toPlaying(sim);
  return (sim: sim, board: board, scores: scores, audio: audio);
}

void run(ChompChaseSim sim, double seconds) {
  for (var t = 0.0; t < seconds; t += _dt) {
    sim.step(_dt);
  }
}

/// Past the role card and the count.
void toPlaying(ChompChaseSim sim) {
  for (
    var i = 0;
    i < PlatformConfig.simHz * 10 && sim.phase != 'playing';
    i++
  ) {
    sim.step(_dt);
  }
}

void swipe(ChompChaseSim sim, String phoneId, int dc, int dr) {
  const far = ChompChaseConfig.swipeThreshold * 2;
  for (final (phase, x, y) in [
    (TouchPhase.down, 0.0, 0.0),
    (TouchPhase.move, dc * far, dr * far),
    (TouchPhase.up, dc * far, dr * far),
  ]) {
    sim.onTouch(
      TouchEvent(phoneId: phoneId, worldX: x, worldY: y, phase: phase),
    );
  }
}

/// The first step of a shortest path through the maze, or null if there.
(int, int)? firstStep(ChompMaze maze, (int, int) from, (int, int) to) {
  if (from == to) return null;
  final back = <(int, int), (int, int)>{from: from};
  final queue = [from];
  for (var head = 0; head < queue.length; head++) {
    final (c, r) = queue[head];
    if ((c, r) == to) break;
    for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      if (!maze.open(c, r, dc, dr)) continue;
      final next = (c + dc, r + dr);
      if (back.containsKey(next)) continue;
      back[next] = (c, r);
      queue.add(next);
    }
  }
  var step = to;
  while (back[step] != from) {
    step = back[step]!;
  }
  return (step.$1 - from.$1, step.$2 - from.$2);
}

/// Swipe [phoneId] along the shortest way to [target], a tick at a time,
/// until [done].
void chase(
  ChompChaseSim sim,
  String phoneId,
  (int, int) Function() target,
  bool Function() done, {
  double seconds = 30,
}) {
  (int, int)? last;
  for (var t = 0.0; t < seconds && !done(); t += _dt) {
    final step = firstStep(sim.maze, sim.tileOf(phoneId), target());
    if (step != null && step != last) {
      swipe(sim, phoneId, step.$1, step.$2);
      last = step;
    }
    sim.step(_dt);
  }
}

String onTeam(ChompChaseSim sim, int team) =>
    sim.board.phoneIds.firstWhere((id) => sim.teamOf(id) == team);

extension on ChompChaseSim {
  BoardContext get board => context;
}

void main() {
  group('the maze', () {
    for (final (cols, rows) in [(5, 5), (7, 6), (16, 7), (33, 15), (34, 16)]) {
      test('$cols by $rows: one piece, no dead ends, mirrored both ways', () {
        for (var seed = 0; seed < 6; seed++) {
          final maze = ChompMaze.generate(cols, rows, math.Random(seed));
          expect(maze.reachableFrom(0, 0), maze.tiles, reason: 'seed $seed');
          for (var r = 0; r < rows; r++) {
            for (var c = 0; c < cols; c++) {
              expect(
                maze.exits(c, r),
                greaterThanOrEqualTo(2),
                reason: 'dead end at $c,$r (seed $seed)',
              );
              expect(
                maze.open(c, r, 1, 0),
                maze.open(cols - 1 - c, r, -1, 0),
                reason: 'not mirrored left to right',
              );
              expect(
                maze.open(c, r, 0, 1),
                maze.open(c, rows - 1 - r, 0, -1),
                reason: 'not mirrored top to bottom',
              );
            }
          }
          final copy = ChompMaze.decode(maze.encode());
          expect(copy.encode(), maze.encode());
        }
      });
    }
  });

  group('the table', () {
    test('even tables only, two to eight', () {
      final manifest = const ChompChaseGame().manifest;
      for (var n = 1; n <= 9; n++) {
        expect(manifest.fits(n), n.isEven && n >= 2 && n <= 8, reason: '$n');
      }
    });

    test('a row for two, two facing rows beyond; each side a team', () {
      for (final n in [2, 4, 6, 8]) {
        final s = start(n, toPlay: false);
        final teams = [
          for (final id in s.sim.context.phoneIds) s.sim.teamOf(id),
        ];
        expect(teams.where((t) => t == 0), hasLength(n ~/ 2), reason: '$n');

        // Team 0 all on one side of the middle, team 1 on the other.
        final board = s.board.coverage.board;
        final byRows = n > 2;
        for (final slice in s.board.slices) {
          final v = slice.viewport;
          final firstSide = byRows
              ? v.centerY < board.centerY
              : v.centerX < board.centerX;
          expect(s.sim.teamOf(slice.phoneId), firstSide ? 0 : 1);
        }
      }
    });

    test('the maze fills exactly the board every screen can show', () {
      final lobby = LobbyInfo([
        phone('p1', PlayerPalette.all[0], heightMm: 160),
        phone('p2', PlayerPalette.all[1]),
        phone('p3', PlayerPalette.all[2], heightMm: 140),
        phone('p4', PlayerPalette.all[3]),
      ]);
      final scores = Scoreboard();
      for (final p in lobby.phones) {
        scores.register(p.phoneId, p.label);
      }
      final board = const BoardCompiler().compile(
        const ChompChaseGame().planBoard(lobby),
        lobby,
      );
      final sim = ChompChaseSim(board.contextFor(scores));
      final state = sim.sharedState;
      final ox = state['ox']! as double;
      final oy = state['oy']! as double;
      final right = ox + sim.maze.cols * (state['tw']! as double);
      final bottom = oy + sim.maze.rows * (state['th']! as double);
      final b = board.coverage.board;
      expect(ox, closeTo(b.left, 1e-9));
      expect(oy, closeTo(b.top, 1e-9));
      expect(right, closeTo(b.right, 1e-9));
      expect(bottom, closeTo(b.bottom, 1e-9));
    });
  });

  group('a half', () {
    test('tells each side its role, counts down, then plays', () {
      final s = start(2, toPlay: false);
      expect(s.sim.phase, 'role');
      run(s.sim, ChompChaseConfig.roleSeconds + 0.05);
      expect(s.sim.phase, 'countdown');
      run(s.sim, ChompChaseConfig.countdownSeconds + 0.05);
      expect(s.sim.phase, 'playing');
      expect(s.sim.chompingTeam, 0);
      expect({for (final e in s.sim.entities) e.kind}, {'chomper', 'ghost'});
    });

    test('a swipe turns you, and a chomper eats what it runs over', () {
      final s = start(2);
      final me = onTeam(s.sim, 0);
      final (c, r) = s.sim.tileOf(me);
      final way = [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
      ].firstWhere((d) => s.sim.maze.open(c, r, d.$1, d.$2));
      expect(s.sim.dotAt(c + way.$1, r + way.$2), isTrue);

      swipe(s.sim, me, way.$1, way.$2);
      run(s.sim, 1.0);

      expect(s.sim.tileOf(me), isNot((c, r)));
      expect(s.sim.dotAt(c + way.$1, r + way.$2), isFalse);
      expect(s.sim.eatenBy(0), greaterThan(0));

      // A boup for every dot, on the phone the dot was on.
      final boups = [
        for (final p in s.audio.plays)
          if (Sounds.buttonPress.contains(p.cue)) p.phoneId,
      ];
      expect(boups, hasLength(s.sim.eatenBy(0)));
      final (x, y) = s.sim.centreOf(c + way.$1, r + way.$2);
      expect(boups.first, s.sim.context.nearestPhone(x, y));
    });

    test('a swipe made early is taken at the next junction', () {
      final s = start(4);
      final me = onTeam(s.sim, 0);
      // Head off along a corridor, then ask for a turn that is not open yet.
      final (c, r) = s.sim.tileOf(me);
      final way = [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
      ].firstWhere((d) => s.sim.maze.open(c, r, d.$1, d.$2));
      swipe(s.sim, me, way.$1, way.$2);
      run(s.sim, 0.05);
      final side = (way.$2, way.$1); // a quarter turn
      swipe(s.sim, me, side.$1, side.$2);
      run(s.sim, 3);
      // Wherever it ended up, it got there by taking the turn somewhere
      // rather than stopping dead at the first wall.
      expect(s.sim.tileOf(me), isNot((c + way.$1, r + way.$2)));
    });

    test('ghosts catch chompers; the last one caught switches the roles', () {
      final s = start(2);
      final chomper = onTeam(s.sim, 0);
      final ghost = onTeam(s.sim, 1);
      chase(
        s.sim,
        ghost,
        () => s.sim.tileOf(chomper),
        () => s.sim.isCaught(chomper),
      );
      expect(s.sim.isCaught(chomper), isTrue);
      Player seat(String id) => Player(
        phoneId: id,
        color: PlayerPalette.all[int.parse(id.substring(1)) - 1],
      );
      List<String> heardOf(SoundCue cue) => [
        for (final p in s.audio.plays)
          if (p.cue == cue) p.phoneId,
      ];
      // The bang on the phone where it happened...
      final (x, y) = s.sim.centreOf(
        s.sim.tileOf(chomper).$1,
        s.sim.tileOf(chomper).$2,
      );
      expect(heardOf(ChompChaseConfig.explosion), [
        s.sim.context.nearestPhone(x, y),
      ]);
      // ...the chomper's sad voice on theirs, the ghost's happy one on theirs.
      expect(heardOf(seat(chomper).soundSad), [chomper]);
      expect(heardOf(seat(ghost).soundHappy), [ghost]);

      s.sim.step(_dt);
      expect(s.sim.phase, 'switch');
      run(s.sim, ChompChaseConfig.switchSeconds + 0.05);
      expect(s.sim.half, 1);
      expect(s.sim.chompingTeam, 1);
      expect(s.sim.isCaught(chomper), isFalse, reason: 'everyone back');
      expect(s.sim.dotsLeft, greaterThan(0), reason: 'the maze refilled');
    });
  });

  group('the clock', () {
    test('a half lasts 45 seconds at most, counting down the last five', () {
      final s = start(2);
      expect(ChompChaseConfig.halfSeconds, 45);
      final seen = <int>{};
      while (s.sim.phase == 'playing') {
        final left = s.sim.sharedState['left'];
        if (left is int) seen.add(left);
        s.sim.step(_dt);
      }
      expect(seen, containsAll(<int>[5, 4, 3, 2, 1]));
      expect(seen.reduce(math.max), 45);

      // Then ROUND OVER, for a moment, before the swap.
      expect(s.sim.phase, 'switch');
      expect(s.sim.sharedState['timeUp'], isTrue);
      run(s.sim, ChompChaseConfig.timeUpSeconds + 0.05);
      expect(s.sim.sharedState['timeUp'], isNull);
      expect(s.sim.phase, 'switch');
    });

    test('a half ended by a catch is not a time-out', () {
      final s = start(2);
      final chomper = onTeam(s.sim, 0);
      final ghost = onTeam(s.sim, 1);
      chase(
        s.sim,
        ghost,
        () => s.sim.tileOf(chomper),
        () => s.sim.isCaught(chomper),
      );
      s.sim.step(_dt);
      expect(s.sim.phase, 'switch');
      expect(s.sim.sharedState['timeUp'], isNull);
    });

    test('the second half times out into ROUND OVER too', () {
      final s = start(2);
      run(s.sim, ChompChaseConfig.halfSeconds + 0.1);
      run(s.sim, ChompChaseConfig.switchSeconds + 0.1);
      toPlaying(s.sim);
      run(s.sim, ChompChaseConfig.halfSeconds + 0.1);
      expect(s.sim.phase, 'over');
      expect(s.sim.sharedState['timeUp'], isTrue);
      expect(s.sim.outcome, isNull, reason: 'not before ROUND OVER has shown');
    });
  });

  test('corridors are about 1.3cm wide', () {
    for (final n in [2, 4, 8]) {
      final s = start(n, toPlay: false);
      final tw = s.sim.sharedState['tw']! as double;
      final th = s.sim.sharedState['th']! as double;
      expect(tw, inInclusiveRange(1.3, 1.3 * 1.25), reason: '$n phones');
      expect(th, inInclusiveRange(1.3, 1.3 * 1.4), reason: '$n phones');
    }
  });

  group('the round', () {
    test('the team that ate more in its turn wins, Flood\'s way', () {
      final s = start(2);
      final a = onTeam(s.sim, 0);
      final b = onTeam(s.sim, 1);

      // First half: a eats a few, then b catches them.
      final (c, r) = s.sim.tileOf(a);
      final way = [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
      ].firstWhere((d) => s.sim.maze.open(c, r, d.$1, d.$2));
      swipe(s.sim, a, way.$1, way.$2);
      run(s.sim, 0.8);
      expect(s.sim.eatenBy(0), greaterThan(0));
      chase(s.sim, b, () => s.sim.tileOf(a), () => s.sim.isCaught(a));
      run(s.sim, ChompChaseConfig.switchSeconds + 0.1);
      toPlaying(s.sim);

      // Second half: b stands still on a dotless start and is caught at once.
      expect(s.sim.chompingTeam, 1);
      chase(s.sim, a, () => s.sim.tileOf(b), () => s.sim.isCaught(b));
      expect(s.sim.eatenBy(1), lessThan(s.sim.eatenBy(0)));

      run(s.sim, ChompChaseConfig.overSeconds + 0.1);
      final outcome = s.sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.winners, {a});
      expect(s.scores.view.entryFor(a)!.total, Scoreboard.pointsPerGame);
      expect(s.scores.view.entryFor(b)?.total ?? 0, 0);
    });

    test('a half that nobody ends ends by the clock; a tie is a draw', () {
      final s = start(2);
      run(s.sim, ChompChaseConfig.halfSeconds + 0.1);
      expect(s.sim.phase, 'switch');
      run(s.sim, ChompChaseConfig.switchSeconds + 0.1);
      toPlaying(s.sim);
      run(
        s.sim,
        ChompChaseConfig.halfSeconds + ChompChaseConfig.overSeconds + 0.2,
      );
      final outcome = s.sim.outcome;
      expect(outcome, isNotNull);
      expect(outcome!.kind, OutcomeKind.draw);
    });
  });

  test('the view draws every phase without falling over', () {
    final s = start(4, toPlay: false);
    final view = ChompChaseView(phoneId: 'p1', roster: s.board.roster);
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

    draw();
    toPlaying(s.sim);
    draw();
    run(s.sim, ChompChaseConfig.halfSeconds + 0.1);
    draw();
    run(s.sim, ChompChaseConfig.switchSeconds + 0.1);
    toPlaying(s.sim);
    run(s.sim, ChompChaseConfig.halfSeconds + 0.1);
    draw();
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
  }) => SoundHandle(_next++);

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
