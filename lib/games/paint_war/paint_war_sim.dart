import 'dart:math' as math;
import 'dart:typed_data';

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/audio/sounds.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/play_area.dart';
import '../../sdk/score/scoreboard.dart';
import 'paint_war_config.dart';

/// Paint the table. Everyone starts on a circle of their own paint; walking
/// off it leaves a wet trail, and walking back onto it fills in everything the
/// trail closed off. Touch somebody else's wet trail and they are wiped off the
/// board — their paint with them — and start again somewhere empty.
///
/// Forty-five seconds, then the biggest territory wins.
///
/// ## The paint is a grid
///
/// The board is cut into [PaintWarConfig.cellSize] squares, and each belongs to
/// one player or nobody. A second grid holds the wet trails. Filling a loop is
/// a flood from the outside: every cell that can still reach the edge of the
/// board without crossing the painter's own colour stays as it is, and
/// everything else is theirs — including anybody else's paint caught inside.
///
/// ## What goes on the wire
///
/// The host resends the whole shared state whenever any of it changes, so
/// nothing in it may change every tick. The paint goes as one run-length string
/// that only moves when somebody captures, is cut or comes back; a trail goes
/// as its corners, which only move when the path bends. The stretch from the
/// last corner to the player is drawn to wherever their body is, which the
/// phones already have.
class PaintWarSim implements GameSim {
  PaintWarSim(this.context) {
    _buildGrid();
    _initPlayers();
  }

  final BoardContext context;

  /// Where a player may walk: the screens and the seams between them.
  late final _area = PlayArea.of(context.coverage);

  // -- the grid ---------------------------------------------------------------
  late final double _gx;
  late final double _gy;
  late final int _gw;
  late final int _gh;

  /// Whether each cell is on a screen (or a seam between two).
  late final Uint8List _inArea;

  /// Who has painted each cell: a player's index, or -1.
  late final Int8List _owner;

  /// Whose wet trail runs through each cell: a player's index, or -1.
  late final Int8List _trail;

  /// Cells on the board at all — the 100% a territory is measured against.
  int _areaCells = 0;

  /// Cells inside a spawn circle, as offsets from its middle cell.
  late final List<(int, int)> _spawnDisc;

  /// Cells within a trail's half-width of a point, likewise.
  late final List<(int, int)> _trailDisc;

  /// Bumped whenever the paint changes, so its string is rebuilt only then.
  int _paintVersion = 0;
  int _encodedVersion = -1;
  String _encoded = '';

  // -- the round --------------------------------------------------------------
  // 'briefing' | 'countdown' | 'playing' | 'over' | 'finished'
  String _phase = 'briefing';
  double _briefing = 0;
  double _countdown = PaintWarConfig.countdownSeconds;
  double _elapsed = 0;
  double _overLeft = PaintWarConfig.overSeconds;

  Map<String, int> _paid = const {};
  GameOutcome? _outcome;

  late final List<_Player> _players;

  /// A boup a capture, at one of its pitches. Its own generator: which pitch
  /// plays must not depend on anything else in the round.
  final _boupPick = math.Random(5);

  // ------------------------------------------------------------------ build

  void _buildGrid() {
    const cell = PaintWarConfig.cellSize;
    final board = context.board;
    _gx = board.left;
    _gy = board.top;
    _gw = (board.width / cell).ceil();
    _gh = (board.height / cell).ceil();
    _inArea = Uint8List(_gw * _gh);
    _owner = Int8List(_gw * _gh)..fillRange(0, _gw * _gh, -1);
    _trail = Int8List(_gw * _gh)..fillRange(0, _gw * _gh, -1);

    for (var j = 0; j < _gh; j++) {
      for (var i = 0; i < _gw; i++) {
        final (x, y) = _cellCentre(i, j);
        if (_area.contains(x, y)) {
          _inArea[j * _gw + i] = 1;
          _areaCells++;
        }
      }
    }

    _spawnDisc = _disc(PaintWarConfig.spawnRadius);
    _trailDisc = _disc(PaintWarConfig.trailRadius);
  }

  static List<(int, int)> _disc(double radius) {
    final reach = (radius / PaintWarConfig.cellSize).ceil();
    final limit = radius / PaintWarConfig.cellSize;
    return [
      for (var dj = -reach; dj <= reach; dj++)
        for (var di = -reach; di <= reach; di++)
          if (di * di + dj * dj <= limit * limit) (di, dj),
    ];
  }

  (double, double) _cellCentre(int i, int j) => (
    _gx + (i + 0.5) * PaintWarConfig.cellSize,
    _gy + (j + 0.5) * PaintWarConfig.cellSize,
  );

  /// The cell under a point, or -1 off the grid.
  int _cellAt(double x, double y) {
    final i = ((x - _gx) / PaintWarConfig.cellSize).floor();
    final j = ((y - _gy) / PaintWarConfig.cellSize).floor();
    if (i < 0 || j < 0 || i >= _gw || j >= _gh) return -1;
    return j * _gw + i;
  }

  void _initPlayers() {
    _players = [
      for (var i = 0; i < context.slices.length; i++)
        _Player(
          phoneId: context.slices[i].phoneId,
          index: i,
          color:
              context.colorOf(context.slices[i].phoneId)?.value.toARGB32() ??
              PaintWarConfig.fallbackColors[i %
                  PaintWarConfig.fallbackColors.length],
        ),
    ];
    _placeEveryoneHome();
  }

  /// Everyone on a fresh circle in the middle of their own phone.
  void _placeEveryoneHome() {
    for (final p in _players) {
      final home = context.slices[p.index].screen;
      p
        ..x = home.centerX
        ..y = home.centerY
        ..prevX = home.centerX
        ..prevY = home.centerY
        ..facingAngle = 0;
      _paintCircle(p);
    }
  }

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    switch (_phase) {
      case 'briefing':
        _stepBriefing(dt);
      case 'countdown':
        _countdown -= dt;
        _stepWalkingHome(dt);
        if (_countdown <= 0) {
          _countdown = 0;
          _phase = 'playing';
        }
      case 'playing':
        _stepPlaying(dt);
      case 'over':
        _overLeft -= dt;
        if (_overLeft <= 0) _phase = 'finished';
      case 'finished':
        break;
    }
  }

  // -- the briefing -----------------------------------------------------------

  /// Three lines, and everyone doing what they say with the real rules: the
  /// second line's loop really is painted and really is filled in when they
  /// get back, which is the whole game in a second and a half. Nobody can be
  /// cut here — the check that does it is only run in [_stepPlaying].
  void _stepBriefing(double dt) {
    final before = _briefing;
    _briefing += dt;

    final step = (_briefing / PaintWarConfig.briefingStepSeconds).floor();
    final into = _briefing - step * PaintWarConfig.briefingStepSeconds;
    final was = before - step * PaintWarConfig.briefingStepSeconds;
    final showNow =
        was < PaintWarConfig.briefingDemoAt &&
        into >= PaintWarConfig.briefingDemoAt;

    if (showNow) {
      for (final p in _players) {
        final axis = _local(p);
        final home = context.slices[p.index].screen;
        (double, double) at(double across, double up) => (
          home.centerX +
              math.cos(axis.right) * across +
              math.cos(axis.up) * up,
          home.centerY +
              math.sin(axis.right) * across +
              math.sin(axis.up) * up,
        );

        if (step == 0) {
          // A small ring inside their own paint: moving, painting nothing.
          const r = PaintWarConfig.demoStrollRadius;
          p.script = [
            for (var k = 1; k <= 8; k++)
              at(r * math.sin(k * math.pi / 4), r - r * math.cos(k * math.pi / 4)),
            at(0, 0),
          ];
        } else if (step == 1) {
          // Out, round, and back in: the loop that grows the territory.
          const across = PaintWarConfig.demoLoopAcross;
          const up = PaintWarConfig.demoLoopUp;
          // Ending exactly where they started: a loop that stopped a few
          // millimetres short left the count to walk them the rest, and a
          // body turning round to take two steps and turning back reads as a
          // jolt towards the middle of the screen.
          p.script = [at(across, 0), at(across, up), at(0, up), at(0, 0)];
        }
      }
    }

    for (final p in _players) {
      _followScript(p, dt);
      _paint(p);
    }

    if (_briefing >= PaintWarConfig.briefingSeconds) {
      for (final p in _players) {
        p.script = const [];
      }
      _phase = 'countdown';
    }
  }

  /// Walk the next point of a demonstration, at walking pace.
  void _followScript(_Player p, double dt) {
    p.prevX = p.x;
    p.prevY = p.y;
    if (p.script.isEmpty) return;
    final (tx, ty) = p.script.first;
    final dx = tx - p.x;
    final dy = ty - p.y;
    final away = math.sqrt(dx * dx + dy * dy);
    final stride = PaintWarConfig.moveSpeed * dt;
    if (away <= stride) {
      p
        ..x = tx
        ..y = ty;
      p.script = p.script.sublist(1);
    } else {
      p
        ..x += dx / away * stride
        ..y += dy / away * stride;
    }
    if (away > 1e-6) {
      p.facingAngle = _turnTowards(
        p.facingAngle,
        math.atan2(dy, dx),
        PaintWarConfig.demoTurnSpeed * dt,
      );
    }
  }

  /// The count, spent walking back to the middle of their own phone and
  /// turning to face the way everyone started.
  void _stepWalkingHome(double dt) {
    for (final p in _players) {
      final home = context.slices[p.index].screen;
      final dx = home.centerX - p.x;
      final dy = home.centerY - p.y;
      final away = math.sqrt(dx * dx + dy * dy);
      final stride = PaintWarConfig.moveSpeed * dt;
      if (away > stride) {
        p
          ..x += dx / away * stride
          ..y += dy / away * stride;
        // Only turned to face the walk when there is a walk to face: a
        // shuffle of a few millimetres is not worth spinning round for.
        if (away > PaintWarConfig.characterRadius) {
          p.facingAngle = _turnTowards(
            p.facingAngle,
            math.atan2(dy, dx),
            PaintWarConfig.demoTurnSpeed * dt,
          );
        }
      } else {
        p
          ..x = home.centerX
          ..y = home.centerY
          ..facingAngle = _turnTowards(p.facingAngle, 0, 6 * dt);
      }
      p
        ..prevX = p.x
        ..prevY = p.y;
    }
  }

  /// This player's screen's own axes, as world angles.
  ({double right, double up}) _local(_Player p) {
    final turn = context.slices[p.index].screen.turnRadians;
    return (right: turn, up: turn - math.pi / 2);
  }

  static double _turnTowards(double from, double to, double maxStep) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    if (d.abs() <= maxStep) return to;
    return from + (d.isNegative ? -maxStep : maxStep);
  }

  // -- the round itself -------------------------------------------------------

  void _stepPlaying(double dt) {
    _elapsed += dt;
    if (_elapsed >= PaintWarConfig.roundSeconds) {
      _elapsed = PaintWarConfig.roundSeconds;
      _endRound();
      return;
    }

    for (final p in _players) {
      if (!p.alive) {
        p.respawnIn -= dt;
        if (p.respawnIn <= 0) _respawn(p);
        continue;
      }

      p.prevX = p.x;
      p.prevY = p.y;
      final heading = p.moveAngle;
      if (heading != null) {
        final speed = PaintWarConfig.moveSpeed * p.moveScale;
        p
          ..x += math.cos(heading) * speed * dt
          ..y += math.sin(heading) * speed * dt
          ..facingAngle = heading;
        final held = _area.clamp(p.x, p.y, PaintWarConfig.characterRadius);
        p
          ..x = held.x
          ..y = held.y;
      }
      _paint(p);
    }

    // After everybody has moved and filled, so somebody who got home this tick
    // has a dry trail that can no longer be cut.
    for (final cutter in _players) {
      if (!cutter.alive) continue;
      final cell = _cellAt(cutter.x, cutter.y);
      if (cell < 0) continue;
      final victim = _trail[cell];
      if (victim < 0 || victim == cutter.index) continue;
      final v = _players[victim];
      if (v.alive) _eliminate(v, atX: cutter.x, atY: cutter.y);
    }
  }

  /// Where [p] is standing decides everything: on their own paint a trail is
  /// filled in, off it the trail grows.
  void _paint(_Player p) {
    final cell = _cellAt(p.x, p.y);
    if (cell < 0) return;

    if (_owner[cell] == p.index) {
      if (p.trailCells.isNotEmpty) {
        _capture(p);
      } else if (p.corners.isNotEmpty) {
        // Stepped off and straight back without laying any paint: there is
        // nothing to fill, only a trail to forget.
        p.corners.clear();
        p.runAngle = null;
      }
      return;
    }

    // Leaving home: the trail starts where they stepped off.
    if (p.trailCells.isEmpty && p.corners.isEmpty) {
      p.corners.add((p.prevX, p.prevY));
      p.runAngle = null;
    }

    final ci = cell % _gw;
    final cj = cell ~/ _gw;
    for (final (di, dj) in _trailDisc) {
      final i = ci + di;
      final j = cj + dj;
      if (i < 0 || j < 0 || i >= _gw || j >= _gh) continue;
      final k = j * _gw + i;
      if (_inArea[k] == 0) continue;
      if (_owner[k] == p.index) continue;
      if (_trail[k] != -1) continue;
      _trail[k] = p.index;
      p.trailCells.add(k);
    }
    _trackCorner(p);
  }

  /// Keep only the trail's corners: a new one where the path bends, or after
  /// a long straight run. What is sent is these; the stretch after the last
  /// one is drawn to the player.
  void _trackCorner(_Player p) {
    final (lx, ly) = p.corners.last;
    final dx = p.x - lx;
    final dy = p.y - ly;
    final run = math.sqrt(dx * dx + dy * dy);
    if (run < 1e-6) return;
    final angle = math.atan2(dy, dx);
    final heading = p.runAngle;
    if (heading == null) {
      if (run >= PaintWarConfig.cellSize) p.runAngle = angle;
      return;
    }
    var bend = (angle - heading).abs() % (2 * math.pi);
    if (bend > math.pi) bend = 2 * math.pi - bend;
    if (bend > PaintWarConfig.trailBendRadians ||
        run >= PaintWarConfig.trailMaxRun) {
      p.corners.add((p.prevX, p.prevY));
      p.runAngle = null;
    }
  }

  /// Home with a trail: it dries into paint, and everything it closed off from
  /// the edge of the board is filled in with it.
  void _capture(_Player p) {
    final me = p.index;
    for (final k in p.trailCells) {
      if (_trail[k] == me) _trail[k] = -1;
      _setOwner(k, me);
    }
    p.trailCells.clear();
    p.corners.clear();
    p.runAngle = null;

    // Flood the outside in: from every edge cell and every cell off the
    // screens, through everything that is not the painter's.
    final reached = Uint8List(_gw * _gh);
    final queue = <int>[];
    void seed(int k) {
      if (reached[k] == 1 || _owner[k] == me) return;
      reached[k] = 1;
      queue.add(k);
    }

    for (var k = 0; k < _gw * _gh; k++) {
      final i = k % _gw;
      final j = k ~/ _gw;
      final edge = i == 0 || j == 0 || i == _gw - 1 || j == _gh - 1;
      if (edge || _inArea[k] == 0) seed(k);
    }
    for (var head = 0; head < queue.length; head++) {
      final k = queue[head];
      final i = k % _gw;
      if (i > 0) seed(k - 1);
      if (i < _gw - 1) seed(k + 1);
      if (k >= _gw) seed(k - _gw);
      if (k < _gw * (_gh - 1)) seed(k + _gw);
    }
    for (var k = 0; k < _gw * _gh; k++) {
      if (reached[k] == 0 && _inArea[k] == 1 && _owner[k] != me) {
        _setOwner(k, me);
      }
    }
    _paintVersion++;

    final bites = Sounds.buttonPress;
    _playAt(p.x, p.y, bites[_boupPick.nextInt(bites.length)]);

    // Anybody whose whole territory was just swallowed has nowhere to go
    // home to.
    for (final other in _players) {
      if (other == p || !other.alive || other.cells > 0) continue;
      _eliminate(other, atX: other.x, atY: other.y);
    }
  }

  void _setOwner(int k, int owner) {
    final old = _owner[k];
    if (old == owner) return;
    if (old >= 0) _players[old].cells--;
    _owner[k] = owner;
    if (owner >= 0) _players[owner].cells++;
  }

  /// Cut: off the board, and every drop of their paint with them.
  void _eliminate(_Player v, {required double atX, required double atY}) {
    v
      ..alive = false
      ..deadX = v.x
      ..deadY = v.y
      ..respawnIn = PaintWarConfig.respawnSeconds
      ..moveAngle = null
      ..moveScale = 0
      ..touchDown = false;
    for (var k = 0; k < _gw * _gh; k++) {
      if (_owner[k] == v.index) _setOwner(k, -1);
      if (_trail[k] == v.index) _trail[k] = -1;
    }
    v.trailCells.clear();
    v.corners.clear();
    v.runAngle = null;
    _paintVersion++;

    // Where it was cut, and on their own phone if that is somewhere else.
    final at = context.nearestPhone(atX, atY);
    if (at != null) _playOn(at, PaintWarConfig.cutTrail);
    if (at != v.phoneId) _playOn(v.phoneId, PaintWarConfig.cutTrail);
    // And out, in their own voice, on their own phone.
    final out = context.roster.byPhone(v.phoneId);
    if (out != null) context.audio.playOnPhone(out, out.soundSad);
  }

  void _respawn(_Player p) {
    final spot = _bestSpawn(p);
    p
      ..alive = true
      ..x = spot.$1
      ..y = spot.$2
      ..prevX = spot.$1
      ..prevY = spot.$2;
    _paintCircle(p);
  }

  /// Where a fresh circle takes the most clean board: well inside the glass,
  /// on as little paint as possible, never on a wet trail, and — between two
  /// equally empty spots — as far from everybody else as it can be.
  (double, double) _bestSpawn(_Player p) {
    for (final margin in [PaintWarConfig.spawnMargin, 0.0]) {
      final best = _searchSpawn(p, margin);
      if (best != null) return best;
    }
    final home = context.slices[p.index].screen;
    return (home.centerX, home.centerY);
  }

  (double, double)? _searchSpawn(_Player p, double margin) {
    final board = context.board;
    const step = PaintWarConfig.spawnSearchStep;
    const r = PaintWarConfig.spawnRadius;
    final clearance = r + margin;

    (double, double)? best;
    var bestWhite = -1;
    var bestRoom = -1.0;

    for (var y = board.top + clearance; y <= board.bottom - clearance; y += step) {
      for (
        var x = board.left + clearance;
        x <= board.right - clearance;
        x += step
      ) {
        if (!_fits(x, y, clearance)) continue;

        final centre = _cellAt(x, y);
        if (centre < 0) continue;
        final ci = centre % _gw;
        final cj = centre ~/ _gw;
        var white = 0;
        var wet = false;
        for (final (di, dj) in _spawnDisc) {
          final i = ci + di;
          final j = cj + dj;
          if (i < 0 || j < 0 || i >= _gw || j >= _gh) continue;
          final k = j * _gw + i;
          if (_trail[k] != -1) {
            wet = true;
            break;
          }
          if (_inArea[k] == 1 && _owner[k] == -1) white++;
        }
        if (wet) continue;

        var room = double.infinity;
        for (final other in _players) {
          if (other == p || !other.alive) continue;
          final dx = other.x - x;
          final dy = other.y - y;
          room = math.min(room, dx * dx + dy * dy);
        }

        if (white > bestWhite || (white == bestWhite && room > bestRoom)) {
          best = (x, y);
          bestWhite = white;
          bestRoom = room;
        }
      }
    }
    return best;
  }

  /// A circle of [radius] round (x, y) lies wholly on the glass.
  bool _fits(double x, double y, double radius) {
    if (!_area.contains(x, y)) return false;
    for (var k = 0; k < 16; k++) {
      final a = k * math.pi / 8;
      if (!_area.contains(x + math.cos(a) * radius, y + math.sin(a) * radius)) {
        return false;
      }
    }
    return true;
  }

  /// A fresh circle of [p]'s paint where they stand, over whatever was there.
  void _paintCircle(_Player p) {
    final centre = _cellAt(p.x, p.y);
    if (centre < 0) return;
    final ci = centre % _gw;
    final cj = centre ~/ _gw;
    for (final (di, dj) in _spawnDisc) {
      final i = ci + di;
      final j = cj + dj;
      if (i < 0 || j < 0 || i >= _gw || j >= _gh) continue;
      final k = j * _gw + i;
      if (_inArea[k] == 0) continue;
      _setOwner(k, p.index);
    }
    _paintVersion++;
  }

  void _endRound() {
    _phase = 'over';
    for (final p in _players) {
      p
        ..moveAngle = null
        ..moveScale = 0
        ..touchDown = false;
    }
    // Paid the instant the clock runs out, on the territories as they stand.
    _paid = context.scores.awardPlacements(
      Scoreboard.tiersBy({for (final p in _players) p.phoneId: p.cells}),
    );
  }

  // -- sound ------------------------------------------------------------------

  void _playOn(String phoneId, SoundCue cue) {
    final player = context.roster.byPhone(phoneId);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

  void _playAt(double x, double y, SoundCue cue) {
    final phone = context.nearestPhone(x, y);
    if (phone != null) _playOn(phone, cue);
  }

  // -- input ------------------------------------------------------------------

  @override
  void onTouch(TouchEvent touch) {
    if (_phase != 'playing') return;
    _Player? p;
    for (final q in _players) {
      if (q.phoneId == touch.phoneId) p = q;
    }
    if (p == null || !p.alive) return;

    switch (touch.phase) {
      case TouchPhase.down:
        p
          ..touchDown = true
          ..touchDownX = touch.worldX
          ..touchDownY = touch.worldY
          ..touchX = touch.worldX
          ..touchY = touch.worldY;
      case TouchPhase.move:
        if (!p.touchDown) return;
        p
          ..touchX = touch.worldX
          ..touchY = touch.worldY;
        final dx = touch.worldX - p.touchDownX;
        final dy = touch.worldY - p.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= PaintWarConfig.minMoveDistance) {
          p
            ..moveAngle = math.atan2(dy, dx)
            ..moveScale = PaintWarConfig.moveScaleFor(dist);
        } else {
          p
            ..moveAngle = null
            ..moveScale = 0;
        }
      case TouchPhase.up:
        p
          ..touchDown = false
          ..moveAngle = null
          ..moveScale = 0;
    }
  }

  // -- what the phones see ----------------------------------------------------

  @override
  Iterable<Entity> get entities sync* {
    for (final p in _players) {
      if (!p.alive) continue;
      yield Entity(
        descriptor: EntityDescriptor(
          id: 'player_${p.index}',
          kind: 'player',
          props: {
            'phoneId': p.phoneId,
            'index': p.index,
            'color': p.color,
            'radius': PaintWarConfig.characterRadius,
          },
        ),
        x: p.x,
        y: p.y,
        angle: p.facingAngle,
      );

      // The stick, as two entities rather than as shared state: the whole of
      // the shared state is resent whenever any of it changes, and that
      // carries the paint — a finger in it would send the paint sixty times a
      // second. Entity positions go every tick anyway. Only while the drag is
      // actually steering, as in Dodgeball: a finger resting inside the dead
      // zone draws nothing.
      if (p.touchDown && p.moveAngle != null) {
        final props = {'phoneId': p.phoneId, 'index': p.index};
        yield Entity(
          descriptor: EntityDescriptor(
            id: 'stick_${p.index}',
            kind: 'stick',
            props: props,
          ),
          x: p.touchDownX,
          y: p.touchDownY,
        );
        yield Entity(
          descriptor: EntityDescriptor(
            id: 'knob_${p.index}',
            kind: 'knob',
            props: props,
          ),
          x: p.touchX,
          y: p.touchY,
        );
      }
    }
  }

  static String _q(double v) => v.toStringAsFixed(2);

  /// The paint, row after row, as runs: a letter for whose (`.` for nobody)
  /// and how many cells of it. Rebuilt only when the paint changed.
  String get _paintString {
    if (_encodedVersion == _paintVersion) return _encoded;
    final out = StringBuffer();
    var run = 0;
    var current = _owner.isEmpty ? -1 : _owner[0];
    for (var k = 0; k < _owner.length; k++) {
      final o = _owner[k];
      if (o == current) {
        run++;
        continue;
      }
      out
        ..write(current < 0 ? '.' : String.fromCharCode(97 + current))
        ..write(run);
      current = o;
      run = 1;
    }
    out
      ..write(current < 0 ? '.' : String.fromCharCode(97 + current))
      ..write(run);
    _encoded = out.toString();
    _encodedVersion = _paintVersion;
    return _encoded;
  }

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
      if (_phase == 'briefing')
        'step': (_briefing / PaintWarConfig.briefingStepSeconds).floor(),
      if (_phase == 'countdown')
        'countdown': (_countdown * 10).roundToDouble() / 10,
      // Whole seconds: a value that changes every tick is a packet every tick.
      'left': (PaintWarConfig.roundSeconds - _elapsed).ceil(),
      // The grid: fixed for the round.
      'gx': _gx,
      'gy': _gy,
      'gw': _gw,
      'gc': PaintWarConfig.cellSize,
      'paint': _paintString,
    };
    for (final p in _players) {
      final key = 'p${p.index}';
      map['phoneId_$key'] = p.phoneId;
      map['alive_$key'] = p.alive;
      map['color_$key'] = p.color;
      if (!p.alive) {
        map['deadX_$key'] = _q(p.deadX);
        map['deadY_$key'] = _q(p.deadY);
      }
      if (p.corners.isNotEmpty) {
        map['trail_$key'] = [
          for (final (x, y) in p.corners) '${_q(x)},${_q(y)}',
        ].join(';');
      }
    }
    return map;
  }

  // -- scoring and the end ----------------------------------------------------

  /// How much of the board [phoneId] has painted, 0 to 1.
  double shareOf(String phoneId) {
    if (_areaCells == 0) return 0;
    for (final p in _players) {
      if (p.phoneId == phoneId) return p.cells / _areaCells;
    }
    return 0;
  }

  /// Cells [phoneId] has painted right now.
  int cellsOf(String phoneId) {
    for (final p in _players) {
      if (p.phoneId == phoneId) return p.cells;
    }
    return 0;
  }

  /// Whether [phoneId] is on the board, rather than waiting to respawn.
  bool isAlive(String phoneId) =>
      _players.any((p) => p.phoneId == phoneId && p.alive);

  /// Whether a wet trail of [phoneId]'s runs through the point.
  bool trailAt(String phoneId, double x, double y) {
    final k = _cellAt(x, y);
    if (k < 0) return false;
    final t = _trail[k];
    return t >= 0 && _players[t].phoneId == phoneId;
  }

  /// Who has painted the point, or null.
  String? ownerAt(double x, double y) {
    final k = _cellAt(x, y);
    if (k < 0 || _owner[k] < 0) return null;
    return _players[_owner[k]].phoneId;
  }

  String get phase => _phase;

  @override
  GameOutcome? get outcome {
    if (_phase != 'finished') return null;
    return _outcome ??= GameOutcome.perPhone({
      for (final p in _players) p.phoneId: _lineFor(p),
    }, summary: _summary());
  }

  String _lineFor(_Player p) {
    final pct = (shareOf(p.phoneId) * 100).round();
    return 'You painted $pct% of the table — +${_paid[p.phoneId] ?? 0} pts';
  }

  String _summary() {
    final ranked = [..._players]..sort((a, b) => b.cells.compareTo(a.cells));
    if (ranked.isEmpty || ranked.first.cells == 0) return 'nobody painted';
    if (ranked.length > 1 && ranked[0].cells == ranked[1].cells) {
      return 'a dead heat';
    }
    final best = ranked.first;
    final label =
        context.scores.view.entryFor(best.phoneId)?.label ?? best.phoneId;
    return '$label painted the most';
  }

  // -- reset ------------------------------------------------------------------

  @override
  void reset() {
    _phase = 'briefing';
    _briefing = 0;
    _countdown = PaintWarConfig.countdownSeconds;
    _elapsed = 0;
    _overLeft = PaintWarConfig.overSeconds;
    _paid = const {};
    _outcome = null;
    _owner.fillRange(0, _owner.length, -1);
    _trail.fillRange(0, _trail.length, -1);
    for (final p in _players) {
      p
        ..alive = true
        ..cells = 0
        ..respawnIn = 0
        ..moveAngle = null
        ..moveScale = 0
        ..touchDown = false
        ..script = const []
        ..runAngle = null;
      p.trailCells.clear();
      p.corners.clear();
    }
    _placeEveryoneHome();
  }

  @override
  void dispose() {}
}

class _Player {
  _Player({required this.phoneId, required this.index, required this.color});

  final String phoneId;
  final int index;
  final int color;

  double x = 0, y = 0;

  /// Where they were a tick ago: where a trail starts, and where a corner goes.
  double prevX = 0, prevY = 0;
  double facingAngle = 0;

  bool alive = true;
  double respawnIn = 0;
  double deadX = 0, deadY = 0;

  /// How many cells of paint are theirs.
  int cells = 0;

  /// The wet trail: every cell it covers, and the corners it is drawn by.
  final trailCells = <int>[];
  final corners = <(double, double)>[];

  /// The direction of the trail since its last corner, once it has one.
  double? runAngle;

  /// A demonstration walk, point by point. Empty outside the briefing.
  List<(double, double)> script = const [];

  double? moveAngle;
  double moveScale = 0;
  bool touchDown = false;
  double touchDownX = 0, touchDownY = 0;

  /// Where the finger is now, as against where it came down: only the drawn
  /// stick needs it.
  double touchX = 0, touchY = 0;
}
