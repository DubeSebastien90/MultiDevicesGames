import 'dart:math' as math;
import 'dart:typed_data';

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/audio/sounds.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/score/scoreboard.dart';
import 'cops_robbers_config.dart';
import 'city_maze.dart';

/// Two teams, one city, two halves.
///
/// In the first half one team are the robbers, grabbing the coins lying in the
/// streets, and the other are the cops hunting them; once every robber is
/// caught — or the coins are gone, or the half runs out — the streets are
/// refilled and the roles swap. The team that grabbed more in its turn wins.
///
/// A swipe on your own phone picks the next way to turn, and the turn is taken
/// at the first junction that allows it — so a swipe can be made early, the
/// way a street is actually run.
///
/// The streets are the maze's corridors and the blocks its walls; underneath,
/// "dots" are the coins, which is what the code still calls them.
///
/// ## The teams
///
/// Each side of the table is a team: the top row against the bottom. The maze
/// is mirrored across both middles, so each team starts on the same streets
/// the other does.
class CopsRobbersSim implements GameSim {
  CopsRobbersSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _build();
  }

  final BoardContext context;
  final math.Random _random;

  /// Which pitch of the boup a dot gets. Its own generator, so a sound cannot
  /// change the maze a seeded round is dealt.
  final _boupPick = math.Random(6);

  late final CityMaze maze;
  late final String _mazeCode;

  late final double _ox;
  late final double _oy;
  late final double _tw;
  late final double _th;

  late final List<_Runner> _runners;

  /// Dots still in the maze, one byte a tile.
  late Uint8List _dots;

  /// Dots eaten by each team, in the half it was robbing.
  final _eaten = [0, 0];

  // 'role' | 'countdown' | 'playing' | 'switch' | 'over' | 'finished'
  String _phase = 'role';
  int _half = 0;
  double _clock = 0;

  /// Whether the half that just ended was ended by the clock, which the
  /// phones show as ROUND OVER before anything else.
  bool _timedOut = false;

  GameOutcome? _outcome;

  /// Which team robs this half: team 0 first, then team 1.
  int get robbingTeam => _half;

  // ------------------------------------------------------------------ build

  void _build() {
    final board = context.board;
    final cols = math.max(
      CopsRobbersConfig.minTiles,
      (board.width / CopsRobbersConfig.targetTile).floor(),
    );
    final rows = math.max(
      CopsRobbersConfig.minTiles,
      (board.height / CopsRobbersConfig.targetTile).floor(),
    );
    _ox = board.left;
    _oy = board.top;
    _tw = board.width / cols;
    _th = board.height / rows;
    maze = CityMaze.generate(cols, rows, _random);
    _mazeCode = maze.encode();

    // Split the table across whichever way its phones spread less: a block
    // of phones is split top from bottom, a pair side by side left from right.
    final slices = context.slices;
    final ys = slices.map((s) => s.viewport.centerY).toList();
    final spreadY = ys.reduce(math.max) - ys.reduce(math.min);
    final byRows = spreadY > _th;

    final taken = <int>{};
    _runners = [
      for (var i = 0; i < slices.length; i++)
        () {
          final v = slices[i].viewport;
          final team = byRows
              ? (v.centerY < board.centerY ? 0 : 1)
              : (v.centerX < board.centerX ? 0 : 1);
          final home = _freeTileNear(v.centerX, v.centerY, taken);
          taken.add(home);
          return _Runner(
            phoneId: slices[i].phoneId,
            index: i,
            team: team,
            home: home,
            color:
                context.colorOf(slices[i].phoneId)?.value.toARGB32() ??
                CopsRobbersConfig.fallbackColors[i %
                    CopsRobbersConfig.fallbackColors.length],
          );
        }(),
    ];
    _startHalf(0);
  }

  /// The tile nearest a point that nobody else starts on.
  int _freeTileNear(double x, double y, Set<int> taken) {
    var best = 0;
    var bestD = double.infinity;
    for (var k = 0; k < maze.tiles; k++) {
      if (taken.contains(k)) continue;
      final (cx, cy) = _centre(k % maze.cols, k ~/ maze.cols);
      final d = (cx - x) * (cx - x) + (cy - y) * (cy - y);
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return best;
  }

  (double, double) _centre(num c, num r) =>
      (_ox + (c + 0.5) * _tw, _oy + (r + 0.5) * _th);

  void _startHalf(int half) {
    _half = half;
    _phase = 'role';
    _clock = 0;
    _timedOut = false;
    _dots = Uint8List(maze.tiles)..fillRange(0, maze.tiles, 1);
    for (final p in _runners) {
      _dots[p.home] = 0;
      p
        ..c = (p.home % maze.cols).toDouble()
        ..r = (p.home ~/ maze.cols).toDouble()
        ..dc = 0
        ..dr = 0
        ..wantC = 0
        ..wantR = 0
        ..facing = 0
        ..caught = false
        ..swipeFrom = null;
    }
  }

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    _clock += dt;
    switch (_phase) {
      case 'role':
        if (_clock >= CopsRobbersConfig.roleSeconds) _next('countdown');
      case 'countdown':
        if (_clock >= CopsRobbersConfig.countdownSeconds) _next('playing');
      case 'playing':
        _stepPlaying(dt);
      case 'switch':
        if (_clock >= CopsRobbersConfig.switchSeconds) _startHalf(1);
      case 'over':
        if (_clock >= CopsRobbersConfig.overSeconds) _next('finished');
      case 'finished':
        break;
    }
  }

  void _next(String phase) {
    _phase = phase;
    _clock = 0;
  }

  void _stepPlaying(double dt) {
    for (final p in _runners) {
      if (p.caught) continue;
      final robber = p.team == robbingTeam;
      _move(
        p,
        (robber ? CopsRobbersConfig.robberSpeed : CopsRobbersConfig.copSpeed) *
            dt,
      );
      if (robber) _eat(p);
    }

    // Caught: any cop close enough to any robber.
    final reach = CopsRobbersConfig.catchReach * math.min(_tw, _th);
    for (final cop in _runners) {
      if (cop.team == robbingTeam) continue;
      final (gx, gy) = _centre(cop.c, cop.r);
      for (final prey in _runners) {
        if (prey.team != robbingTeam || prey.caught) continue;
        final (px, py) = _centre(prey.c, prey.r);
        if ((gx - px) * (gx - px) + (gy - py) * (gy - py) > reach * reach) {
          continue;
        }
        prey
          ..caught = true
          ..deadX = px
          ..deadY = py;
        // The bang where it happened, the robber's sad voice on their own
        // phone, and the cop's happy one on theirs.
        final at = context.nearestPhone(px, py);
        if (at != null) _playOn(at, CopsRobbersConfig.caught);
        final lost = context.roster.byPhone(prey.phoneId);
        if (lost != null) context.audio.playOnPhone(lost, lost.soundSad);
        final won = context.roster.byPhone(cop.phoneId);
        if (won != null) context.audio.playOnPhone(won, won.soundHappy);
      }
    }

    final anyLeft = _runners.any((p) => p.team == robbingTeam && !p.caught);
    final dotsLeft = _dots.any((d) => d == 1);
    final timeUp = _clock >= CopsRobbersConfig.halfSeconds;
    if (!anyLeft || !dotsLeft || timeUp) {
      _timedOut = timeUp && anyLeft && dotsLeft;
      _endHalf();
    }
  }

  void _endHalf() {
    if (_half == 0) {
      _next('switch');
      return;
    }
    _next('over');
    _decide();
  }

  /// Walk [p] up to [budget] tiles, turning where they asked to at the first
  /// junction that allows it and stopping at a wall.
  void _move(_Runner p, double budget) {
    var left = budget;
    for (var guard = 0; guard < 8 && left > 1e-9; guard++) {
      // Turning round is allowed anywhere, as in the original.
      if ((p.wantC != 0 || p.wantR != 0) &&
          p.wantC == -p.dc &&
          p.wantR == -p.dr &&
          (p.dc != 0 || p.dr != 0)) {
        p
          ..dc = p.wantC
          ..dr = p.wantR;
      }

      final atCentre =
          (p.c - p.c.roundToDouble()).abs() < 1e-9 &&
          (p.r - p.r.roundToDouble()).abs() < 1e-9;
      if (atCentre) {
        p
          ..c = p.c.roundToDouble()
          ..r = p.r.roundToDouble();
        final c = p.c.toInt();
        final r = p.r.toInt();
        if ((p.wantC != 0 || p.wantR != 0) &&
            maze.open(c, r, p.wantC, p.wantR)) {
          p
            ..dc = p.wantC
            ..dr = p.wantR;
        } else if (!maze.open(c, r, p.dc, p.dr)) {
          p
            ..dc = 0
            ..dr = 0;
          return;
        }
      }
      if (p.dc == 0 && p.dr == 0) return;
      p.facing = math.atan2(p.dr.toDouble(), p.dc.toDouble());

      // Distance to the next tile centre ahead.
      final along = p.dc != 0 ? p.c : p.r;
      final dir = p.dc != 0 ? p.dc : p.dr;
      final next = dir > 0 ? along.floorToDouble() + 1 : along.ceilToDouble() - 1;
      final toNext = (next - along).abs();
      final step = math.min(left, toNext);
      if (p.dc != 0) {
        p.c += p.dc * step;
      } else {
        p.r += p.dr * step;
      }
      if ((step - toNext).abs() < 1e-9) {
        // Landed exactly on a centre: snap, so the next loop sees it.
        if (p.dc != 0) {
          p.c = next;
        } else {
          p.r = next;
        }
      }
      left -= step;
    }
  }

  void _eat(_Runner p) {
    final c = p.c.round();
    final r = p.r.round();
    if ((p.c - c).abs() > CopsRobbersConfig.eatReach ||
        (p.r - r).abs() > CopsRobbersConfig.eatReach) {
      return;
    }
    final k = r * maze.cols + c;
    if (_dots[k] == 0) return;
    _dots[k] = 0;
    _eaten[p.team]++;
    p.ate++;

    // On the phone the dot was on.
    final (x, y) = _centre(c, r);
    final at = context.nearestPhone(x, y);
    final bites = Sounds.buttonPress;
    if (at != null) _playOn(at, bites[_boupPick.nextInt(bites.length)]);
  }

  /// [cue] on [phoneId]'s phone, if somebody is sitting at it.
  void _playOn(String phoneId, SoundCue cue) {
    final player = context.roster.byPhone(phoneId);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

  /// Whoever ate more in their turn takes the round, Flood's way: every
  /// winner first place's points, and a dead heat shared by everyone.
  void _decide() {
    final teams = {for (final p in _runners) p.phoneId: p.team};
    if (_eaten[0] == _eaten[1]) {
      context.scores.awardPlacements([teams.keys.toSet()]);
      _outcome = GameOutcome.draw(
        summary: 'dead level, ${_eaten[0]} coins each',
        lines: _lines(),
      );
      return;
    }
    final winning = _eaten[0] > _eaten[1] ? 0 : 1;
    final winners = <String>{};
    for (final p in _runners) {
      if (p.team != winning) continue;
      context.scores.award(p.phoneId, Scoreboard.pointsPerGame);
      winners.add(p.phoneId);
    }
    _outcome = GameOutcome.contest(
      winners: winners,
      summary: '${_eaten[winning]} coins to ${_eaten[1 - winning]}',
      lines: _lines(),
    );
  }

  Map<String, String> _lines() => {
    for (final p in _runners)
      p.phoneId:
          'Your team grabbed ${_eaten[p.team]} coins — '
          'you grabbed ${p.ate} of them',
  };

  // ------------------------------------------------------------------ input

  /// A swipe on your own glass picks where you turn next. One swipe, one turn,
  /// however far the finger carries on.
  @override
  void onTouch(TouchEvent touch) {
    if (_phase != 'playing' && _phase != 'countdown') return;
    _Runner? p;
    for (final q in _runners) {
      if (q.phoneId == touch.phoneId) p = q;
    }
    if (p == null || p.caught) return;

    switch (touch.phase) {
      case TouchPhase.down:
        p
          ..swipeFrom = (touch.worldX, touch.worldY)
          ..swiped = false;
      case TouchPhase.move || TouchPhase.up:
        final from = p.swipeFrom;
        if (from == null || p.swiped) break;
        final dx = touch.worldX - from.$1;
        final dy = touch.worldY - from.$2;
        if (math.max(dx.abs(), dy.abs()) < CopsRobbersConfig.swipeThreshold) {
          break;
        }
        p.swiped = true;
        if (dx.abs() >= dy.abs()) {
          p
            ..wantC = dx > 0 ? 1 : -1
            ..wantR = 0;
        } else {
          p
            ..wantC = 0
            ..wantR = dy > 0 ? 1 : -1;
        }
    }
    if (touch.phase == TouchPhase.up) p.swipeFrom = null;
  }

  // ---------------------------------------------------- what phones see

  @override
  Iterable<Entity> get entities sync* {
    for (final p in _runners) {
      if (p.caught) continue;
      final robber = p.team == robbingTeam;
      final (x, y) = _centre(p.c, p.r);
      yield Entity(
        descriptor: EntityDescriptor(
          // A new id each half: a runner changes what it is at half time, and
          // an entity's kind is fixed for its life.
          id: '${robber ? 'robber' : 'cop'}_${p.index}_$_half',
          kind: robber ? 'robber' : 'cop',
          props: {'phoneId': p.phoneId, 'index': p.index},
        ),
        x: x,
        y: y,
        angle: p.facing,
      );
    }
  }

  /// The dots as hex, four tiles a digit. Changes only when one is eaten.
  String get _dotString {
    final out = StringBuffer();
    for (var k = 0; k < _dots.length; k += 4) {
      var v = 0;
      for (var b = 0; b < 4; b++) {
        if (k + b < _dots.length && _dots[k + b] == 1) v |= 1 << b;
      }
      out.write(v.toRadixString(16));
    }
    return out.toString();
  }

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
      'half': _half,
      'robbing': robbingTeam,
      if (_phase == 'countdown')
        'countdown':
            ((CopsRobbersConfig.countdownSeconds - _clock) * 10).roundToDouble() /
            10,
      // Whole seconds of the half left: a value that changes every tick is a
      // packet every tick.
      if (_phase == 'playing')
        'left': (CopsRobbersConfig.halfSeconds - _clock).ceil(),
      // ROUND OVER, for as long as it holds the table after the clock ran out.
      if ((_phase == 'switch' || _phase == 'over') &&
          _timedOut &&
          _clock < CopsRobbersConfig.timeUpSeconds)
        'timeUp': true,
      // The maze and where it sits: fixed for the round.
      'maze': _mazeCode,
      'ox': _ox,
      'oy': _oy,
      'tw': _tw,
      'th': _th,
      'dots': _dotString,
      'eaten0': _eaten[0],
      'eaten1': _eaten[1],
    };
    for (final p in _runners) {
      final key = 'p${p.index}';
      map['phoneId_$key'] = p.phoneId;
      map['team_$key'] = p.team;
      map['color_$key'] = p.color;
      map['caught_$key'] = p.caught;
      if (p.caught) {
        map['deadX_$key'] = p.deadX.toStringAsFixed(2);
        map['deadY_$key'] = p.deadY.toStringAsFixed(2);
      }
    }
    return map;
  }

  // -------------------------------------------------------- for tests and HUD

  String get phase => _phase;
  int get half => _half;
  int eatenBy(int team) => _eaten[team];
  int teamOf(String phoneId) =>
      _runners.firstWhere((p) => p.phoneId == phoneId).team;
  bool isCaught(String phoneId) =>
      _runners.firstWhere((p) => p.phoneId == phoneId).caught;
  int get dotsLeft => _dots.where((d) => d == 1).length;
  bool dotAt(int c, int r) => _dots[r * maze.cols + c] == 1;

  /// Which tile [phoneId] is on, rounded to the nearest.
  (int, int) tileOf(String phoneId) {
    final p = _runners.firstWhere((p) => p.phoneId == phoneId);
    return (p.c.round(), p.r.round());
  }

  /// World position of a tile's centre.
  (double, double) centreOf(int c, int r) => _centre(c, r);

  @override
  GameOutcome? get outcome => _phase == 'finished' ? _outcome : null;

  @override
  void reset() {
    _eaten
      ..[0] = 0
      ..[1] = 0;
    _outcome = null;
    for (final p in _runners) {
      p.ate = 0;
    }
    _startHalf(0);
  }

  @override
  void dispose() {}
}

class _Runner {
  _Runner({
    required this.phoneId,
    required this.index,
    required this.team,
    required this.home,
    required this.color,
  });

  final String phoneId;
  final int index;
  final int team;
  final int home;
  final int color;

  /// Position in tiles — whole numbers at tile centres — and heading.
  double c = 0, r = 0;
  int dc = 0, dr = 0;

  /// The turn asked for, taken at the first junction that allows it.
  int wantC = 0, wantR = 0;
  double facing = 0;

  bool caught = false;
  double deadX = 0, deadY = 0;

  /// Dots this player ate, across the round.
  int ate = 0;

  (double, double)? swipeFrom;
  bool swiped = false;
}
