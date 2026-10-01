import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/play_area.dart';
import 'dodgeball_config.dart';

class DodgeballSim implements GameSim {
  DodgeballSim(this.context) {
    _rng = math.Random(context.board.hashCode);
    _initPlayers();
  }

  final BoardContext context;
  late final math.Random _rng;

  late final _area = PlayArea.of(context.coverage);

  String _phase = 'briefing';
  double _countdown = DodgeballConfig.countdownSeconds;

  double _briefing = 0;
  String? _winnerId;

  final List<Set<String>> _fallen = [];

  Map<String, int> _paid = const {};

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

  final List<_Ball> _balls = [];
  int _nextBallId = 0;
  double _spawnTimer = DodgeballConfig.ballSpawnInterval;
  double _currentSpawnInterval = DodgeballConfig.ballSpawnInterval;
  double _currentBallSpeed = DodgeballConfig.ballBaseSpeed;

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

  void _stepBriefing(double dt) {
    final before = _briefing;
    _briefing += dt;

    final step = (_briefing / DodgeballConfig.briefingStepSeconds).floor();
    final into = _briefing - step * DodgeballConfig.briefingStepSeconds;
    final was = before - step * DodgeballConfig.briefingStepSeconds;

    bool crossed(double at) => was < at && into >= at;

    if (step != 1) _balls.clear();

    if (step >= 2) _stepWalkingHome(dt);

    if (step == 1) {
      if (crossed(DodgeballConfig.briefingDemoAt)) _throwDemoBalls();
      if (crossed(
        DodgeballConfig.briefingDemoAt + DodgeballConfig.demoDashAt,
      )) {
        for (final p in _players) {
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

        p.facingAngle = math.atan2(dy, dx);
        continue;
      }

      p.x = home.centerX;
      p.y = home.centerY;

      p.facingAngle = _turnTowards(
        p.facingAngle,
        0,
        DodgeballConfig.homeTurnSpeed * dt,
      );
    }
  }

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

  void _stepPlaying(double dt) {
    for (final p in _players) {
      if (!p.alive) continue;

      p.dashCooldownLeft = math.max(0, p.dashCooldownLeft - dt);
      p.dashTimeLeft = math.max(0, p.dashTimeLeft - dt);
      p.invincibleLeft = math.max(0, p.invincibleLeft - dt);
      if (p.touchDown) p.touchHeldTime += dt;

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

      final r = DodgeballConfig.characterRadius;
      final held = _area.clamp(p.x, p.y, r);
      p.x = held.x;
      p.y = held.y;
    }

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

    for (final ball in _balls) {
      ball.x += ball.vx * dt;
      ball.y += ball.vy * dt;

      final br = DodgeballConfig.ballRadius;
      final hit = _area.bounce(ball.x, ball.y, ball.vx, ball.vy, br);
      if (hit.vx != ball.vx || hit.vy != ball.vy) {
        final phone = context.nearestPhone(hit.x, hit.y);
        if (phone != null) {
          _playOn(
            phone,
            DodgeballConfig.boing,
            volume: DodgeballConfig.boingVolume,
          );
        }
      }
      ball
        ..x = hit.x
        ..y = hit.y
        ..vx = hit.vx
        ..vy = hit.vy;
    }

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

          final out = context.roster.byPhone(p.phoneId);
          if (out != null) context.audio.playOnPhone(out, out.soundSad);
          p.moveAngle = null;
          p.moveScale = 0;
          p.dashTimeLeft = 0;

          p.touchDown = false;
          break;
        }
      }
    }

    if (fell.isNotEmpty) _fallen.add(fell);
    _checkWinCondition();
  }

  void _spawnBall() {
    final br = DodgeballConfig.ballRadius;
    final spawn = _area.edgeSpawn(_rng, br);

    final quadrant = _rng.nextInt(4);
    final baseAngle = math.pi / 4 + quadrant * math.pi / 2;
    final jitter = (_rng.nextDouble() - 0.5) * (math.pi / 6);
    final angle = baseAngle + jitter;

    var vx = math.cos(angle) * _currentBallSpeed;
    var vy = math.sin(angle) * _currentBallSpeed;

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

  void _playOn(String phoneId, SoundCue cue, {double volume = 1.0}) {
    final player = context.roster.byPhone(phoneId);
    if (player != null) {
      context.audio.playOnPhone(player, cue, volume: volume);
    }
  }

  void _tryDash(_Player p) {
    if (!p.alive) return;
    if (p.dashCooldownLeft > 0) return;

    p.dashTimeLeft = DodgeballConfig.dashDuration;
    p.dashCooldownLeft = DodgeballConfig.dashCooldown;
    p.invincibleLeft = DodgeballConfig.dashInvincibility;

    p.dashAngle = p.moveAngle ?? p.facingAngle;
    _playOn(p.phoneId, DodgeballConfig.woosh);
  }

  void _checkWinCondition() {
    if (_finishIn != null) return;

    final alive = _players.where((p) => p.alive).toList();
    if (alive.length <= 1 && _players.length > 1) {
      _finishIn = DodgeballConfig.deathShowSeconds;
      if (alive.length == 1) _winnerId = alive.first.phoneId;

      _paid = context.scores.awardPlacements([
        {for (final p in alive) p.phoneId},
        ..._fallen.reversed,
      ]);
    }
  }

  double? _finishIn;

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
          p.moveAngle = null;
          p.moveScale = 0;
        }

      case TouchPhase.up:
        if (!p.touchDown) return;
        p.touchDown = false;

        final dx = touch.worldX - p.touchDownX;
        final dy = touch.worldY - p.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);

        if (!p.touchMoved &&
            dist < DodgeballConfig.minMoveDistance &&
            p.touchHeldTime * 1000 < DodgeballConfig.tapMaxMs) {
          _tryDash(p);
        }

        p.moveAngle = null;
        p.moveScale = 0;
    }
  }

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

  double _quantize(double v) => (v * 10).roundToDouble() / 10;

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
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

      map['color_$key'] = p.color;
      if (!p.alive) {
        map['deadX_$key'] = _quantize(p.deadX);
        map['deadY_$key'] = _quantize(p.deadY);
      }
      map['dashing_$key'] = p.dashTimeLeft > 0;
      map['dashCd_$key'] = _quantize(p.dashCooldownLeft);
      map['invincible_$key'] = p.invincibleLeft > 0;

      if (p.touchDown && p.alive && p.moveAngle != null) {
        map['stickX_$key'] = _quantize(p.touchDownX);
        map['stickY_$key'] = _quantize(p.touchDownY);
        map['stickToX_$key'] = _quantize(p.touchX);
        map['stickToY_$key'] = _quantize(p.touchY);
      }
    }
    return map;
  }

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

  double deadX = 0;
  double deadY = 0;

  double? moveAngle;

  double moveScale = 0;

  double dashAngle = 0;
  double dashCooldownLeft = 0;
  double dashTimeLeft = 0;
  double invincibleLeft = 0;

  bool touchDown = false;
  double touchDownX = 0;
  double touchDownY = 0;
  bool touchMoved = false;
  double touchHeldTime = 0;

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
