import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/play_area.dart';
import 'dodgeball_config.dart';

/// Dodge bouncing balls — last one standing wins.
///
/// Movement is the same as Arena (drag to move, held inside the [PlayArea]).
/// Instead of combat, balls spawn from its edges and bounce diagonally,
/// accelerating over time.
/// Players can tap to dash with a short cooldown.
class DodgeballSim implements GameSim {
  DodgeballSim(this.context) {
    _rng = math.Random(context.board.hashCode);
    _initPlayers();
  }

  final BoardContext context;
  late final math.Random _rng;

  /// Where a player may stand and a ball may travel: the screens themselves
  /// plus the seams between them, rather than the rectangle drawn around the
  /// lot. Built once — the table does not change shape mid-round.
  late final _area = PlayArea.of(context.coverage);

  // -- game phase -------------------------------------------------------------
  // 'briefing' | 'countdown' | 'playing' | 'finished'
  String _phase = 'briefing';
  double _countdown = DodgeballConfig.countdownSeconds;

  /// How far into the briefing we are, in seconds.
  double _briefing = 0;
  String? _winnerId;

  /// Who went out, one set per tick, first out first. Two players hit on the
  /// same tick went out together and share a place.
  final List<Set<String>> _fallen = [];

  /// What each phone was paid when the round ended.
  Map<String, int> _paid = const {};

  // -- players ----------------------------------------------------------------
  late final List<_Player> _players;

  void _initPlayers() {
    _players = [
      for (var i = 0; i < context.slices.length; i++)
        _Player(
          phoneId: context.slices[i].phoneId,
          index: i,
          x: context.slices[i].screen.centerX,
          y: context.slices[i].screen.centerY,
          color: DodgeballConfig
              .playerColors[i % DodgeballConfig.playerColors.length],
        ),
    ];
  }

  _Player? _playerOf(String phoneId) {
    for (final p in _players) {
      if (p.phoneId == phoneId) return p;
    }
    return null;
  }

  // -- balls ------------------------------------------------------------------
  final List<_Ball> _balls = [];
  int _nextBallId = 0;
  double _spawnTimer = DodgeballConfig.ballSpawnInterval;
  double _currentSpawnInterval = DodgeballConfig.ballSpawnInterval;
  double _currentBallSpeed = DodgeballConfig.ballBaseSpeed;

  // -- GameSim ----------------------------------------------------------------

  @override
  void step(double dt) {
    switch (_phase) {
      case 'briefing':
        _stepBriefing(dt);
      case 'countdown':
        _countdown -= dt;
        if (_countdown <= 0) {
          _countdown = 0;
          _phase = 'playing';
        }
        _stepWalkingHome(dt);
      case 'playing':
        _stepPlaying(dt);
        final ending = _finishIn;
        if (ending != null) {
          _finishIn = ending - dt;
          if (_finishIn! <= 0) _phase = 'finished';
        }
      case 'finished':
        break;
    }
  }

  /// Two lines, and a player doing what the second one says.
  ///
  /// The demonstration is the point. 'Tap to dash' beside a still figure is a
  /// caption; beside a figure that steps out of the way of a ball as you read
  /// it, it is an instruction — and it shows the one thing the words cannot,
  /// which is *when* to dash. The ball is nearly on them when they go.
  ///
  /// Nothing here can eliminate anybody: the collision check belongs to
  /// [_stepPlaying] and is not called. The demonstration ball passes through
  /// whoever it reaches.
  void _stepBriefing(double dt) {
    final before = _briefing;
    _briefing += dt;

    final step = (_briefing / DodgeballConfig.briefingStepSeconds).floor();
    final into = _briefing - step * DodgeballConfig.briefingStepSeconds;
    final was = before - step * DodgeballConfig.briefingStepSeconds;

    bool crossed(double at) => was < at && into >= at;

    // The demonstration ball belongs to its own line and goes with it. Left
    // lying about, it would still be crossing the board under the line after
    // — which says "here comes another one" to somebody who has just been
    // told not to get hit.
    if (step != 1) _balls.clear();

    // The last line has nothing to show, so the walk back from the dash plays
    // under it and carries on into the count.
    if (step >= 2) _stepWalkingHome(dt);

    if (step == 1) {
      if (crossed(DodgeballConfig.briefingDemoAt)) _throwDemoBalls();
      if (crossed(
        DodgeballConfig.briefingDemoAt + DodgeballConfig.demoDashAt,
      )) {
        for (final p in _players) {
          // Sideways out of the ball's line, in this player's own frame, so it
          // reads as a step aside on every phone however its slot is turned.
          p.dashAngle = _local(p).up;
          p.dashTimeLeft = DodgeballConfig.dashDuration;
          p.invincibleLeft = DodgeballConfig.dashInvincibility;
          _playOn(p.phoneId, DodgeballConfig.woosh);
        }
      }
    }

    for (final p in _players) {
      p.dashTimeLeft = math.max(0, p.dashTimeLeft - dt);
      p.invincibleLeft = math.max(0, p.invincibleLeft - dt);
      if (p.dashTimeLeft > 0) {
        p.x += math.cos(p.dashAngle) * DodgeballConfig.dashSpeed * dt;
        p.y += math.sin(p.dashAngle) * DodgeballConfig.dashSpeed * dt;
        p.facingAngle = p.dashAngle;
        final held = _area.clamp(p.x, p.y, DodgeballConfig.characterRadius);
        p.x = held.x;
        p.y = held.y;
      }
    }

    for (final ball in _balls) {
      ball.x += ball.vx * dt;
      ball.y += ball.vy * dt;
    }

    if (_briefing >= DodgeballConfig.briefingSeconds) {
      _balls.clear();
      for (final p in _players) {
        p.dashTimeLeft = 0;
        p.dashCooldownLeft = 0;
        p.invincibleLeft = 0;
      }
      _phase = 'countdown';
    }
  }

  /// The count, spent walking back to where the round starts.
  ///
  /// The demonstration leaves everybody a dash's length off their mark and
  /// facing sideways. Snapping them back when the round begins would be a
  /// teleport on every screen at once; walking them back over the three
  /// seconds nobody can act in costs nothing and shows the walk animation,
  /// which is the last thing on the list the briefing does not have a line
  /// for.
  void _stepWalkingHome(double dt) {
    for (final (i, p) in _players.indexed) {
      final home = context.slices[i].screen;
      final dx = home.centerX - p.x;
      final dy = home.centerY - p.y;
      final away = math.sqrt(dx * dx + dy * dy);

      final stride = DodgeballConfig.moveSpeed * dt;
      if (away > stride) {
        p.x += dx / away * stride;
        p.y += dy / away * stride;
        // Facing where they are walking, which is what the view reads to
        // decide somebody is walking at all.
        p.facingAngle = math.atan2(dy, dx);
        continue;
      }

      p.x = home.centerX;
      p.y = home.centerY;

      // Home, and now turning back to the way they started. Turned rather
      // than set, for the same reason they walked rather than jumped.
      p.facingAngle = _turnTowards(
        p.facingAngle,
        0,
        DodgeballConfig.homeTurnSpeed * dt,
      );
    }
  }

  /// One ball per player, aimed at them from the side.
  ///
  /// Per player rather than one for the table: every phone has to see the
  /// demonstration on its own glass, and a single ball crossing the board
  /// would be a lesson for whoever it happened to pass.
  void _throwDemoBalls() {
    for (final p in _players) {
      final axis = _local(p);
      final reach =
          DodgeballConfig.characterRadius * DodgeballConfig.demoBallDistance;
      final speed = reach / DodgeballConfig.demoBallTravel;

      _balls.add(
        _Ball(
          id: _nextBallId++,
          x: p.x - math.cos(axis.right) * reach,
          y: p.y - math.sin(axis.right) * reach,
          vx: math.cos(axis.right) * speed,
          vy: math.sin(axis.right) * speed,
          speed: speed,
        ),
      );
    }
  }

  /// This player's screen's own axes, as world angles: across the glass, and
  /// up it. A phone in a turned slot has its own idea of sideways, and a
  /// demonstration that ignores it comes at the player diagonally.
  ({double right, double up}) _local(_Player p) {
    final turn = context.slices[p.index].screen.turnRadians;
    return (right: turn, up: turn - math.pi / 2);
  }

  /// [from], moved at most [maxStep] towards [to] the short way round.
  static double _turnTowards(double from, double to, double maxStep) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    if (d.abs() <= maxStep) return to;
    return from + (d.isNegative ? -maxStep : maxStep);
  }

  void _stepPlaying(double dt) {
    // Update players.
    for (final p in _players) {
      if (!p.alive) continue;

      // Decrement timers.
      p.dashCooldownLeft = math.max(0, p.dashCooldownLeft - dt);
      p.dashTimeLeft = math.max(0, p.dashTimeLeft - dt);
      p.invincibleLeft = math.max(0, p.invincibleLeft - dt);
      if (p.touchDown) p.touchHeldTime += dt;

      // Movement. A dash runs on its own angle and its own clock, which is
      // what keeps it separable from the finger: the stick can be released,
      // re-aimed or left alone mid-dash without any of it changing where the
      // burst ends up, and the burst ending changes nothing about the stick.
      //
      // Walking speed is how far the finger is from the anchor, up to
      // [DodgeballConfig.moveSpeed] at full tilt — edging around a ball and
      // breaking for open floor are different intentions, and a drag that only
      // ever means "go" cannot tell them apart.
      final double? heading;
      final double speed;
      if (p.dashTimeLeft > 0) {
        heading = p.dashAngle;
        speed = DodgeballConfig.dashSpeed;
      } else {
        heading = p.moveAngle;
        speed = DodgeballConfig.moveSpeed * p.moveScale;
      }
      if (heading != null) {
        p.x += math.cos(heading) * speed * dt;
        p.y += math.sin(heading) * speed * dt;
        p.facingAngle = heading;
      }

      // Kept on a real screen rather than inside a rectangle drawn around
      // them — see [PlayArea]. The board is only as deep as the shallowest
      // phone, which shaded off half of the biggest screen and fenced players
      // out of it.
      final r = DodgeballConfig.characterRadius;
      final held = _area.clamp(p.x, p.y, r);
      p.x = held.x;
      p.y = held.y;
    }

    // Spawn balls.
    _spawnTimer -= dt;
    if (_spawnTimer <= 0 && _balls.length < DodgeballConfig.ballMaxCount) {
      _spawnBall();
      _spawnTimer = _currentSpawnInterval;
      _currentSpawnInterval = math.max(
        DodgeballConfig.ballSpawnIntervalMin,
        _currentSpawnInterval * DodgeballConfig.ballSpawnIntervalDecay,
      );
      _currentBallSpeed = math.min(
        DodgeballConfig.ballMaxSpeed,
        _currentBallSpeed + DodgeballConfig.ballSpeedIncrement,
      );
    }

    // Update balls.
    for (final ball in _balls) {
      ball.x += ball.vx * dt;
      ball.y += ball.vy * dt;

      // Bounce off the edge of the *screens*, which steps where a tall phone
      // meets a short one. The seams between phones are part of the area, so a
      // ball still crosses the bezel gap unseen and arrives on the next screen
      // with its momentum intact.
      final br = DodgeballConfig.ballRadius;
      final hit = _area.bounce(ball.x, ball.y, ball.vx, ball.vy, br);
      if (hit.vx != ball.vx || hit.vy != ball.vy) {
        // Nearest rather than exact: a ball against a wall can have its middle
        // a hair past the edge of the glass it is bouncing on.
        final phone = context.nearestPhone(hit.x, hit.y);
        if (phone != null) _playOn(phone, DodgeballConfig.boing);
      }
      ball
        ..x = hit.x
        ..y = hit.y
        ..vx = hit.vx
        ..vy = hit.vy;
    }

    // Collision: ball vs player. Not once the round is decided: the winner
    // is already paid, and going out in the second after winning would show
    // them bursting on the way to a score that says they won.
    final fell = <String>{};
    for (final p in _players) {
      if (_finishIn != null) break;
      if (!p.alive) continue;
      if (p.invincibleLeft > 0) continue;

      for (final ball in _balls) {
        final dx = p.x - ball.x;
        final dy = p.y - ball.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <
            DodgeballConfig.characterRadius + DodgeballConfig.ballRadius) {
          p.alive = false;
          p.deadX = p.x;
          p.deadY = p.y;
          fell.add(p.phoneId);
          // Out, in their own voice, on their own phone.
          final out = context.roster.byPhone(p.phoneId);
          if (out != null) context.audio.playOnPhone(out, out.soundSad);
          p.moveAngle = null;
          p.moveScale = 0;
          p.dashTimeLeft = 0;
          // Their finger is still on the glass, but [onTouch] turns an
          // eliminated player away — so the up that would have cleared this
          // never arrives, and without it their joystick would be left painted
          // on the floor.
          p.touchDown = false;
          break;
        }
      }
    }

    if (fell.isNotEmpty) _fallen.add(fell);
    _checkWinCondition();
  }

  void _spawnBall() {
    // Off a real edge of the screens rather than off one of four sides of a
    // rectangle. On a mismatched table that rectangle's top and bottom ran
    // across the middle of the biggest phone, so balls appeared out of the
    // shaded band instead of arriving from the edge of the board.
    final br = DodgeballConfig.ballRadius;
    final spawn = _area.edgeSpawn(_rng, br);

    // A diagonal, so the ball crosses the board rather than skimming an edge.
    final quadrant = _rng.nextInt(4);
    final baseAngle = math.pi / 4 + quadrant * math.pi / 2;
    final jitter = (_rng.nextDouble() - 0.5) * (math.pi / 6);
    final angle = baseAngle + jitter;

    var vx = math.cos(angle) * _currentBallSpeed;
    var vy = math.sin(angle) * _currentBallSpeed;

    // Turn it inward if the diagonal picked points back out through the wall
    // it just came from. The normal already faces the playable side, so the
    // test is the same whichever edge this is — including the stepped ones,
    // where "top / right / bottom / left" no longer means anything.
    if (vx * spawn.nx + vy * spawn.ny < 0) {
      vx = -vx;
      vy = -vy;
    }

    _balls.add(
      _Ball(
        id: _nextBallId++,
        x: spawn.x,
        y: spawn.y,
        vx: vx,
        vy: vy,
        speed: _currentBallSpeed,
      ),
    );
  }

  /// [cue] on [phoneId]'s phone, if somebody is sitting at it.
  void _playOn(String phoneId, SoundCue cue) {
    final player = context.roster.byPhone(phoneId);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

  void _tryDash(_Player p) {
    if (!p.alive) return;
    if (p.dashCooldownLeft > 0) return;

    p.dashTimeLeft = DodgeballConfig.dashDuration;
    p.dashCooldownLeft = DodgeballConfig.dashCooldown;
    p.invincibleLeft = DodgeballConfig.dashInvincibility;

    // Where they were heading, or where they are facing if they were standing
    // still. Latched here and never read from the finger again — a dash is a
    // committed burst, not a thing you steer.
    p.dashAngle = p.moveAngle ?? p.facingAngle;
    _playOn(p.phoneId, DodgeballConfig.woosh);
  }

  /// Decide the round, but do not end it yet.
  ///
  /// The winner and the points are settled here, the instant the last player
  /// but one goes out — that part must not wait for anything. What waits is
  /// the *phase*: the round keeps running for
  /// [DodgeballConfig.deathShowSeconds] so the burst has somewhere to play,
  /// and only then does the table move on to the score.
  void _checkWinCondition() {
    if (_finishIn != null) return;

    final alive = _players.where((p) => p.alive).toList();
    if (alive.length <= 1 && _players.length > 1) {
      _finishIn = DodgeballConfig.deathShowSeconds;
      if (alive.length == 1) _winnerId = alive.first.phoneId;
      // Paid by the order people went out in: the last one standing first,
      // the first one hit last.
      _paid = context.scores.awardPlacements([
        {for (final p in alive) p.phoneId},
        ..._fallen.reversed,
      ]);
    }
  }

  /// Seconds left of the pause after the round is decided, or null while it
  /// is still being played.
  double? _finishIn;

  // -- input ------------------------------------------------------------------

  @override
  void onTouch(TouchEvent touch) {
    if (_phase != 'playing') return;
    final p = _playerOf(touch.phoneId);
    if (p == null || !p.alive) return;

    switch (touch.phase) {
      case TouchPhase.down:
        p.touchDownX = touch.worldX;
        p.touchDownY = touch.worldY;
        p.touchX = touch.worldX;
        p.touchY = touch.worldY;
        p.touchMoved = false;
        p.touchDown = true;
        p.touchHeldTime = 0;

      case TouchPhase.move:
        if (!p.touchDown) return;
        p.touchX = touch.worldX;
        p.touchY = touch.worldY;
        final dx = touch.worldX - p.touchDownX;
        final dy = touch.worldY - p.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= DodgeballConfig.minMoveDistance) {
          p.touchMoved = true;
          p.moveAngle = math.atan2(dy, dx);
          p.moveScale = DodgeballConfig.moveScaleFor(dist);
        } else {
          // Back inside the dead zone, which on a stick is the middle: stop.
          // [touchMoved] deliberately stays set — this was a drag, and letting
          // it turn back into a tap would fire a dash the player never asked
          // for when they lifted their finger.
          p.moveAngle = null;
          p.moveScale = 0;
        }

      case TouchPhase.up:
        if (!p.touchDown) return;
        p.touchDown = false;

        final dx = touch.worldX - p.touchDownX;
        final dy = touch.worldY - p.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);

        // Tap detection → dash.
        if (!p.touchMoved &&
            dist < DodgeballConfig.minMoveDistance &&
            p.touchHeldTime * 1000 < DodgeballConfig.tapMaxMs) {
          _tryDash(p);
        }

        // Stop moving on finger up — including on the tap that just started a
        // dash.
        //
        // This used to be skipped while a dash was in flight, to keep the
        // burst from being cancelled by the very touch-up that launched it.
        // But the finger was already off the glass by then, so nothing would
        // ever clear the heading again: the dash ended and the player carried
        // on walking that way until they next dragged and released. The dash
        // keeps its own angle now, so stopping the walk here costs it nothing.
        p.moveAngle = null;
        p.moveScale = 0;
    }
  }

  // -- entities ---------------------------------------------------------------

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
            'radius': DodgeballConfig.characterRadius,
          },
        ),
        x: p.x,
        y: p.y,
        angle: p.facingAngle,
      );
    }

    for (final ball in _balls) {
      yield Entity(
        descriptor: EntityDescriptor(
          id: 'ball_${ball.id}',
          kind: 'ball',
          props: {'radius': DodgeballConfig.ballRadius},
        ),
        x: ball.x,
        y: ball.y,
        vx: ball.vx,
        vy: ball.vy,
      );
    }
  }

  // -- shared state -----------------------------------------------------------

  double _quantize(double v) => (v * 10).roundToDouble() / 10;

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
      // Which line the briefing is on, and how much of it is left — the view
      // fades the demonstration ball in and out off this. The words themselves
      // live in the view, where every other string this game shows lives.
      if (_phase == 'briefing') ...{
        'step': (_briefing / DodgeballConfig.briefingStepSeconds).floor(),
        'stepLeft': _quantize(
          DodgeballConfig.briefingStepSeconds -
              _briefing % DodgeballConfig.briefingStepSeconds,
        ),
      },
      'countdown': _quantize(_countdown),
      'winner': _winnerId,
      'ballCount': _balls.length,
    };
    for (final p in _players) {
      final key = 'p${p.index}';
      map['phoneId_$key'] = p.phoneId;
      map['alive_$key'] = p.alive;
      // Static for the round, and sent once because the broadcast is diffed.
      // The view needs it after the player is gone, which is exactly when the
      // entity that used to carry it no longer exists.
      map['color_$key'] = p.color;
      if (!p.alive) {
        map['deadX_$key'] = _quantize(p.deadX);
        map['deadY_$key'] = _quantize(p.deadY);
      }
      map['dashing_$key'] = p.dashTimeLeft > 0;
      map['dashCd_$key'] = _quantize(p.dashCooldownLeft);
      map['invincible_$key'] = p.invincibleLeft > 0;

      // The stick, and only while it is actually steering — a finger resting
      // inside the dead zone is a dash being aimed, and drawing a ring under
      // it would say "you are moving" to a player who is not. Absent keys are
      // how the view is told there is nothing to draw, which also keeps four
      // dead numbers per player off the wire for the whole of every round
      // nobody is dragging anything.
      if (p.touchDown && p.alive && p.moveAngle != null) {
        map['stickX_$key'] = _quantize(p.touchDownX);
        map['stickY_$key'] = _quantize(p.touchDownY);
        map['stickToX_$key'] = _quantize(p.touchX);
        map['stickToY_$key'] = _quantize(p.touchY);
      }
    }
    return map;
  }

  // -- outcome ----------------------------------------------------------------

  GameOutcome? _outcome;

  @override
  GameOutcome? get outcome {
    if (_phase != 'finished') return null;
    return _outcome ??= GameOutcome.perPhone({
      for (final p in _players)
        p.phoneId:
            '${_winnerId == p.phoneId ? 'Last one standing!' : 'Eliminated'}'
            ' — +${_paid[p.phoneId] ?? 0} pts',
    }, summary: _winnerId != null ? 'last one standing' : 'mutual destruction');
  }

  // -- reset ------------------------------------------------------------------

  @override
  void reset() {
    _phase = 'briefing';
    _briefing = 0;
    _countdown = DodgeballConfig.countdownSeconds;
    _winnerId = null;
    _finishIn = null;
    _fallen.clear();
    _paid = const {};
    _outcome = null;
    _balls.clear();
    _nextBallId = 0;
    _spawnTimer = DodgeballConfig.ballSpawnInterval;
    _currentSpawnInterval = DodgeballConfig.ballSpawnInterval;
    _currentBallSpeed = DodgeballConfig.ballBaseSpeed;
    for (var i = 0; i < _players.length; i++) {
      final p = _players[i];
      p.x = context.slices[i].screen.centerX;
      p.y = context.slices[i].screen.centerY;
      p.facingAngle = 0;
      p.alive = true;
      p.moveAngle = null;
      p.moveScale = 0;
      p.dashAngle = 0;
      p.dashCooldownLeft = 0;
      p.dashTimeLeft = 0;
      p.invincibleLeft = 0;
      p.touchDown = false;
      p.touchMoved = false;
      p.touchHeldTime = 0;
      p.touchX = p.x;
      p.touchY = p.y;
    }
  }

  @override
  void dispose() {}
}

class _Player {
  _Player({
    required this.phoneId,
    required this.index,
    required this.x,
    required this.y,
    required this.color,
  });

  final String phoneId;
  final int index;
  final int color;

  double x, y;
  double facingAngle = 0;
  bool alive = true;

  /// Where this player was standing when they went out. Read by the view,
  /// which has nothing else left to put a burst on.
  double deadX = 0;
  double deadY = 0;

  // Movement direction (null = stopped).
  double? moveAngle;

  /// How far the stick is pushed, 0..1, as a fraction of
  /// [DodgeballConfig.moveSpeed].
  double moveScale = 0;

  // Dash. Its own heading, held for the length of the burst, so a dash and a
  // finger are never the same variable.
  double dashAngle = 0;
  double dashCooldownLeft = 0;
  double dashTimeLeft = 0;
  double invincibleLeft = 0;

  // Touch tracking for gesture detection.
  bool touchDown = false;
  double touchDownX = 0;
  double touchDownY = 0;
  bool touchMoved = false;
  double touchHeldTime = 0;

  /// Where the finger is right now, as against [touchDownX]/[touchDownY] where
  /// it landed. Only the drawn joystick needs it — steering is an angle and a
  /// scale — but the stick cannot show a tilt it has not been told about.
  double touchX = 0;
  double touchY = 0;
}

class _Ball {
  _Ball({
    required this.id,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.speed,
  });

  final int id;
  final double speed;
  double x, y;
  double vx, vy;
}
