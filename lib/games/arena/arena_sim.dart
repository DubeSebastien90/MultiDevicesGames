import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'arena_config.dart';

/// Last-fighter-standing arena brawler.
///
/// No physics engine — extends [GameSim] directly like Hot Potato. Movement,
/// attacks and blocking are encoded via touch gestures: drag to move, tap to
/// attack, hold to block.
class ArenaSim implements GameSim {
  ArenaSim(this.context) {
    _initFighters();
  }

  final BoardContext context;

  // -- game phase -------------------------------------------------------------
  String _phase = 'countdown'; // 'countdown' | 'playing' | 'finished'
  double _countdown = ArenaConfig.countdownSeconds;
  String? _winnerId;

  // -- fighters ---------------------------------------------------------------
  late final List<_Fighter> _fighters;

  void _initFighters() {
    _fighters = [
      for (var i = 0; i < context.slices.length; i++)
        _Fighter(
          phoneId: context.slices[i].phoneId,
          index: i,
          x: context.slices[i].screen.centerX,
          y: context.slices[i].screen.centerY,
          color: ArenaConfig.playerColors[i % ArenaConfig.playerColors.length],
        ),
    ];
  }

  _Fighter? _fighterOf(String phoneId) {
    for (final f in _fighters) {
      if (f.phoneId == phoneId) return f;
    }
    return null;
  }

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
    for (final f in _fighters) {
      if (!f.alive) continue;

      // Decrement timers.
      f.attackCooldownLeft = math.max(0, f.attackCooldownLeft - dt);
      f.attackActiveLeft = math.max(0, f.attackActiveLeft - dt);
      f.blockCooldownLeft = math.max(0, f.blockCooldownLeft - dt);
      f.stunLeft = math.max(0, f.stunLeft - dt);
      f.invincibleLeft = math.max(0, f.invincibleLeft - dt);

      // Block duration limit.
      if (f.blocking) {
        f.blockDuration += dt;
        if (f.blockDuration >= ArenaConfig.blockMaxDuration) {
          _endBlock(f);
        }
      }

      // Detect block gesture: touch is held without moving for blockHoldMs.
      if (f.touchDown && !f.touchMoved && !f.blocking && !f.isStunned) {
        f.touchHeldTime += dt;
        if (f.touchHeldTime * 1000 >= ArenaConfig.blockHoldMs &&
            f.blockCooldownLeft <= 0) {
          f.blocking = true;
          f.blockDuration = 0;
        }
      }

      // Movement (not while stunned).
      if (!f.isStunned && f.moveAngle != null) {
        final dx = math.cos(f.moveAngle!) * ArenaConfig.moveSpeed * dt;
        final dy = math.sin(f.moveAngle!) * ArenaConfig.moveSpeed * dt;
        f.x += dx;
        f.y += dy;
        f.facingAngle = f.moveAngle!;
      }

      // Clamp to board bounds.
      final r = ArenaConfig.characterRadius;
      f.x = f.x.clamp(context.board.left + r, context.board.right - r);
      f.y = f.y.clamp(context.board.top + r, context.board.bottom - r);
    }

    _checkWinCondition();
  }

  void _endBlock(_Fighter f) {
    f.blocking = false;
    f.blockDuration = 0;
    f.blockCooldownLeft = ArenaConfig.blockCooldown;
  }

  void _tryAttack(_Fighter attacker) {
    if (!attacker.alive || attacker.isStunned) return;
    if (attacker.attackCooldownLeft > 0) return;

    attacker.attackCooldownLeft = ArenaConfig.attackCooldown;
    attacker.attackActiveLeft = ArenaConfig.attackFlash;

    for (final target in _fighters) {
      if (target == attacker || !target.alive) continue;

      // Distance check.
      final dx = target.x - attacker.x;
      final dy = target.y - attacker.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist > ArenaConfig.attackRange) continue;

      // Cone check: angle from attacker's facing to target.
      final angleToTarget = math.atan2(dy, dx);
      var angleDiff = (angleToTarget - attacker.facingAngle) % (2 * math.pi);
      if (angleDiff > math.pi) angleDiff -= 2 * math.pi;
      if (angleDiff.abs() > ArenaConfig.attackArc) continue;

      // Target is in the cone.
      if (target.blocking && _isFacing(target, attacker)) {
        // Block reflects: attacker gets stunned.
        attacker.stunLeft = ArenaConfig.stunDuration;
        attacker.moveAngle = null;
        return; // Attack is negated.
      }

      if (target.invincibleLeft > 0) continue;

      target.hp -= ArenaConfig.attackDamage;
      if (target.hp <= 0) {
        target.hp = 0;
        target.alive = false;
        target.moveAngle = null;
        context.scores.award(attacker.phoneId, ArenaConfig.pointsPerKill);
      }
    }
  }

  /// Whether [defender] is roughly facing [attacker] (within 90 deg each side).
  bool _isFacing(_Fighter defender, _Fighter attacker) {
    final dx = attacker.x - defender.x;
    final dy = attacker.y - defender.y;
    final angleToAttacker = math.atan2(dy, dx);
    var diff = (angleToAttacker - defender.facingAngle) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    return diff.abs() <= math.pi / 2;
  }

  void _checkWinCondition() {
    final alive = _fighters.where((f) => f.alive).toList();
    if (alive.length <= 1 && _fighters.length > 1) {
      _phase = 'finished';
      if (alive.length == 1) {
        _winnerId = alive.first.phoneId;
        context.scores.award(_winnerId!, ArenaConfig.pointsForWinning);
      }
    }
  }

  // -- input ------------------------------------------------------------------

  @override
  void onTouch(TouchEvent touch) {
    if (_phase != 'playing') return;
    final f = _fighterOf(touch.phoneId);
    if (f == null || !f.alive) return;

    switch (touch.phase) {
      case TouchPhase.down:
        f.touchDownX = touch.worldX;
        f.touchDownY = touch.worldY;
        f.touchDownTime = 0;
        f.touchMoved = false;
        f.touchDown = true;
        f.touchHeldTime = 0;

      case TouchPhase.move:
        if (!f.touchDown) return;
        final dx = touch.worldX - f.touchDownX;
        final dy = touch.worldY - f.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= ArenaConfig.minMoveDistance) {
          f.touchMoved = true;
          if (!f.isStunned) {
            f.moveAngle = math.atan2(dy, dx);
          }
        }

      case TouchPhase.up:
        if (!f.touchDown) return;
        f.touchDown = false;

        if (f.blocking) {
          _endBlock(f);
          return;
        }

        final dx = touch.worldX - f.touchDownX;
        final dy = touch.worldY - f.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);

        // Tap detection: short, without movement.
        if (!f.touchMoved &&
            dist < ArenaConfig.minMoveDistance &&
            f.touchHeldTime * 1000 < ArenaConfig.tapMaxMs) {
          _tryAttack(f);
        }

        // Stop moving on finger up.
        f.moveAngle = null;
    }

    // Accumulate touch-down time in step(), not here.
  }

  // -- entities ---------------------------------------------------------------

  @override
  Iterable<Entity> get entities sync* {
    for (final f in _fighters) {
      if (!f.alive) continue;
      yield Entity(
        descriptor: EntityDescriptor(
          id: 'fighter_${f.index}',
          kind: 'fighter',
          props: {
            'phoneId': f.phoneId,
            'index': f.index,
            'color': f.color,
            'radius': ArenaConfig.characterRadius,
          },
        ),
        x: f.x,
        y: f.y,
        angle: f.facingAngle,
      );
    }
  }

  // -- shared state -----------------------------------------------------------

  double _quantize(double v) =>
      (v * 10).roundToDouble() / 10; // 0.1 granularity

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
      'countdown': _quantize(_countdown),
      'winner': _winnerId,
    };
    for (final f in _fighters) {
      final key = 'p${f.index}';
      map['phoneId_$key'] = f.phoneId;
      map['hp_$key'] = f.hp;
      map['stunned_$key'] = f.isStunned;
      map['blocking_$key'] = f.blocking;
      map['attacking_$key'] = f.attackActiveLeft > 0;
      map['atkCd_$key'] = _quantize(f.attackCooldownLeft);
      map['blkCd_$key'] = _quantize(f.blockCooldownLeft);
      map['invincible_$key'] = f.invincibleLeft > 0;
      map['alive_$key'] = f.alive;
    }
    return map;
  }

  // -- outcome ----------------------------------------------------------------

  @override
  GameOutcome? get outcome {
    if (_phase != 'finished') return null;
    return GameOutcome.won(
      summary: _winnerId != null ? 'last one standing' : 'mutual destruction',
    );
  }

  // -- reset ------------------------------------------------------------------

  @override
  void reset() {
    _phase = 'countdown';
    _countdown = ArenaConfig.countdownSeconds;
    _winnerId = null;
    for (var i = 0; i < _fighters.length; i++) {
      final f = _fighters[i];
      f.x = context.slices[i].screen.centerX;
      f.y = context.slices[i].screen.centerY;
      f.facingAngle = 0;
      f.hp = ArenaConfig.maxHp;
      f.alive = true;
      f.moveAngle = null;
      f.attackCooldownLeft = 0;
      f.attackActiveLeft = 0;
      f.blockCooldownLeft = 0;
      f.blocking = false;
      f.blockDuration = 0;
      f.stunLeft = 0;
      f.invincibleLeft = ArenaConfig.spawnInvincibility;
      f.touchDown = false;
      f.touchMoved = false;
      f.touchHeldTime = 0;
    }
  }

  @override
  void dispose() {}
}

class _Fighter {
  _Fighter({
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
  int hp = ArenaConfig.maxHp;
  bool alive = true;

  // Movement direction (null = stopped).
  double? moveAngle;

  // Timers.
  double attackCooldownLeft = 0;
  double attackActiveLeft = 0;
  double blockCooldownLeft = 0;
  bool blocking = false;
  double blockDuration = 0;
  double stunLeft = 0;
  double invincibleLeft = ArenaConfig.spawnInvincibility;

  bool get isStunned => stunLeft > 0;

  // Touch tracking for gesture detection.
  bool touchDown = false;
  double touchDownX = 0;
  double touchDownY = 0;
  double touchDownTime = 0;
  bool touchMoved = false;
  double touchHeldTime = 0;
}
