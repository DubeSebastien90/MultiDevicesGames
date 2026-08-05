import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'dodgeball_config.dart';

/// Dodge bouncing balls — last one standing wins.
///
/// Movement is the same as Arena (drag to move, clamp to board). Instead of
/// combat, balls spawn from walls and bounce diagonally, accelerating over time.
/// Players can tap to dash with a short cooldown.
class DodgeballSim implements GameSim {
  DodgeballSim(this.context) {
    _rng = math.Random(context.board.hashCode);
    _initPlayers();
  }

  final BoardContext context;
  late final math.Random _rng;

  // -- game phase -------------------------------------------------------------
  String _phase = 'countdown'; // 'countdown' | 'playing' | 'finished'
  double _countdown = DodgeballConfig.countdownSeconds;
  String? _winnerId;

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
          color: DodgeballConfig.playerColors[
              i % DodgeballConfig.playerColors.length],
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
      case 'countdown':
        _countdown -= dt;
        if (_countdown <= 0) {
          _countdown = 0;
          _phase = 'playing';
        }
      case 'playing':
        _stepPlaying(dt);
      case 'finished':
        break;
    }
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

      // Movement.
      if (p.moveAngle != null) {
        final isDashing = p.dashTimeLeft > 0;
        final speed =
            isDashing ? DodgeballConfig.dashSpeed : DodgeballConfig.moveSpeed;
        final dx = math.cos(p.moveAngle!) * speed * dt;
        final dy = math.sin(p.moveAngle!) * speed * dt;
        p.x += dx;
        p.y += dy;
        p.facingAngle = p.moveAngle!;
      }

      // Clamp to board bounds.
      final r = DodgeballConfig.characterRadius;
      p.x = p.x.clamp(context.board.left + r, context.board.right - r);
      p.y = p.y.clamp(context.board.top + r, context.board.bottom - r);
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

      // Bounce off walls.
      final br = DodgeballConfig.ballRadius;
      if (ball.x - br <= context.board.left) {
        ball.x = context.board.left + br;
        ball.vx = ball.vx.abs();
      } else if (ball.x + br >= context.board.right) {
        ball.x = context.board.right - br;
        ball.vx = -ball.vx.abs();
      }
      if (ball.y - br <= context.board.top) {
        ball.y = context.board.top + br;
        ball.vy = ball.vy.abs();
      } else if (ball.y + br >= context.board.bottom) {
        ball.y = context.board.bottom - br;
        ball.vy = -ball.vy.abs();
      }
    }

    // Collision: ball vs player.
    for (final p in _players) {
      if (!p.alive) continue;
      if (p.invincibleLeft > 0) continue;

      for (final ball in _balls) {
        final dx = p.x - ball.x;
        final dy = p.y - ball.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < DodgeballConfig.characterRadius + DodgeballConfig.ballRadius) {
          p.alive = false;
          p.moveAngle = null;
          break;
        }
      }
    }

    _checkWinCondition();
  }

  void _spawnBall() {
    // Pick a random wall (0=top, 1=right, 2=bottom, 3=left).
    final wall = _rng.nextInt(4);
    double x, y;
    final br = DodgeballConfig.ballRadius;

    switch (wall) {
      case 0: // top
        x = context.board.left +
            br +
            _rng.nextDouble() * (context.board.width - 2 * br);
        y = context.board.top + br;
      case 1: // right
        x = context.board.right - br;
        y = context.board.top +
            br +
            _rng.nextDouble() * (context.board.height - 2 * br);
      case 2: // bottom
        x = context.board.left +
            br +
            _rng.nextDouble() * (context.board.width - 2 * br);
        y = context.board.bottom - br;
      default: // left
        x = context.board.left + br;
        y = context.board.top +
            br +
            _rng.nextDouble() * (context.board.height - 2 * br);
    }

    // Random diagonal angle (avoid near-axis angles for interesting bounces).
    // Pick an angle in one of 4 diagonal quadrants.
    final quadrant = _rng.nextInt(4);
    final baseAngle = math.pi / 4 + quadrant * math.pi / 2;
    final jitter = (_rng.nextDouble() - 0.5) * (math.pi / 6);
    final angle = baseAngle + jitter;

    // Ensure the ball moves inward from its spawn wall.
    var vx = math.cos(angle) * _currentBallSpeed;
    var vy = math.sin(angle) * _currentBallSpeed;

    switch (wall) {
      case 0: // top → must go down
        if (vy < 0) vy = -vy;
      case 1: // right → must go left
        if (vx > 0) vx = -vx;
      case 2: // bottom → must go up
        if (vy > 0) vy = -vy;
      default: // left → must go right
        if (vx < 0) vx = -vx;
    }

    _balls.add(_Ball(
      id: _nextBallId++,
      x: x,
      y: y,
      vx: vx,
      vy: vy,
      speed: _currentBallSpeed,
    ));
  }

  void _tryDash(_Player p) {
    if (!p.alive) return;
    if (p.dashCooldownLeft > 0) return;

    p.dashTimeLeft = DodgeballConfig.dashDuration;
    p.dashCooldownLeft = DodgeballConfig.dashCooldown;
    p.invincibleLeft = DodgeballConfig.dashInvincibility;

    // If not moving, dash in facing direction.
    p.moveAngle ??= p.facingAngle;
  }

  void _checkWinCondition() {
    final alive = _players.where((p) => p.alive).toList();
    if (alive.length <= 1 && _players.length > 1) {
      _phase = 'finished';
      if (alive.length == 1) {
        _winnerId = alive.first.phoneId;
        context.scores.award(_winnerId!, DodgeballConfig.pointsForWinning);
      }
    }
  }

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
        p.touchMoved = false;
        p.touchDown = true;
        p.touchHeldTime = 0;

      case TouchPhase.move:
        if (!p.touchDown) return;
        final dx = touch.worldX - p.touchDownX;
        final dy = touch.worldY - p.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= DodgeballConfig.minMoveDistance) {
          p.touchMoved = true;
          p.moveAngle = math.atan2(dy, dx);
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

        // Stop moving on finger up (unless mid-dash).
        if (p.dashTimeLeft <= 0) {
          p.moveAngle = null;
        }
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
          props: {
            'radius': DodgeballConfig.ballRadius,
          },
        ),
        x: ball.x,
        y: ball.y,
        vx: ball.vx,
        vy: ball.vy,
      );
    }
  }

  // -- shared state -----------------------------------------------------------

  double _quantize(double v) =>
      (v * 10).roundToDouble() / 10;

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
      'countdown': _quantize(_countdown),
      'winner': _winnerId,
      'ballCount': _balls.length,
    };
    for (final p in _players) {
      final key = 'p${p.index}';
      map['phoneId_$key'] = p.phoneId;
      map['alive_$key'] = p.alive;
      map['dashing_$key'] = p.dashTimeLeft > 0;
      map['dashCd_$key'] = _quantize(p.dashCooldownLeft);
      map['invincible_$key'] = p.invincibleLeft > 0;
    }
    return map;
  }

  // -- outcome ----------------------------------------------------------------

  GameOutcome? _outcome;

  @override
  GameOutcome? get outcome {
    if (_phase != 'finished') return null;
    return _outcome ??= GameOutcome.perPhone(
      {
        for (final p in _players)
          p.phoneId: _winnerId == p.phoneId
              ? 'Last one standing!'
              : 'Eliminated',
      },
      summary: _winnerId != null ? 'last one standing' : 'mutual destruction',
    );
  }

  // -- reset ------------------------------------------------------------------

  @override
  void reset() {
    _phase = 'countdown';
    _countdown = DodgeballConfig.countdownSeconds;
    _winnerId = null;
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
      p.dashCooldownLeft = 0;
      p.dashTimeLeft = 0;
      p.invincibleLeft = 0;
      p.touchDown = false;
      p.touchMoved = false;
      p.touchHeldTime = 0;
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

  // Movement direction (null = stopped).
  double? moveAngle;

  // Dash.
  double dashCooldownLeft = 0;
  double dashTimeLeft = 0;
  double invincibleLeft = 0;

  // Touch tracking for gesture detection.
  bool touchDown = false;
  double touchDownX = 0;
  double touchDownY = 0;
  bool touchMoved = false;
  double touchHeldTime = 0;
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
