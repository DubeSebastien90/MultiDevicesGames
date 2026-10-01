import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/audio/sound_cue.dart';
import '../../sdk/physics/play_area.dart';
import 'arena_config.dart';

class ArenaSim implements GameSim {
  ArenaSim(this.context) {
    _initFighters();
  }

  final BoardContext context;

  late final _area = PlayArea.of(context.coverage);

  String _phase = 'briefing';
  double _countdown = ArenaConfig.countdownSeconds;

  double _briefing = 0;
  String? _winnerId;

  final List<Set<String>> _fallen = [];
  final Set<String> _fellThisTick = {};

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

  final _soundPick = math.Random(7);

  final _lastTake = <List<SoundCue>, int>{};

  void _playFor(_Fighter fighter, List<SoundCue> takes) {
    if (takes.isEmpty) return;
    final last = _lastTake[takes];
    var pick = _soundPick.nextInt(takes.length);
    if (takes.length > 1 && pick == last) {
      pick = (pick + 1 + _soundPick.nextInt(takes.length - 1)) % takes.length;
    }
    _lastTake[takes] = pick;
    final player = context.roster.byPhone(fighter.phoneId);
    if (player != null) context.audio.playOnPhone(player, takes[pick]);
  }

  void _rechargeGuard(_Fighter f, double dt) {
    final recharging = f.blockCooldownLeft > 0;
    f.blockCooldownLeft = math.max(0, f.blockCooldownLeft - dt);
    if (recharging && f.blockCooldownLeft <= 0) {
      _playFor(f, const [ArenaConfig.saberOn]);
    }
  }

  void _startDaze(_Fighter fighter) {
    _stopDaze(fighter);
    if (_phase != 'playing') return;
    final player = context.roster.byPhone(fighter.phoneId);
    if (player == null) return;
    fighter.daze = context.audio.playOnPhone(
      player,
      ArenaConfig.knockedOut,
      fadeIn: ArenaConfig.knockedOutFadeIn,
    );
  }

  void _stopDaze(_Fighter fighter) {
    final daze = fighter.daze;
    if (daze == null) return;
    fighter.daze = null;
    context.audio.stopSound(daze, fade: ArenaConfig.knockedOutFadeOut);
  }

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

        for (final f in _fighters) {
          _rechargeGuard(f, dt);
          _moveSword(f, dt);
        }
      case 'playing':
        _stepPlaying(dt);
      case 'finished':
        break;
    }
  }

  void _stepBriefing(double dt) {
    final before = _briefing;
    _briefing += dt;

    final step = (_briefing / ArenaConfig.briefingStepSeconds).floor();
    final into = _briefing - step * ArenaConfig.briefingStepSeconds;
    final wasInto = before - step * ArenaConfig.briefingStepSeconds;

    final showNow =
        wasInto < ArenaConfig.briefingDemoAt &&
        into >= ArenaConfig.briefingDemoAt;

    for (final f in _fighters) {
      if (step != 2 && f.blocking) _endBlock(f);

      if (showNow) {
        if (step == 1) {
          f.attackCooldownLeft = 0;
          _tryAttack(f);
        } else if (step == 2) {
          f.blocking = true;
          f.blockDuration = 0;
          _playFor(f, ArenaConfig.saberVoid);
        }
      }

      f.attackCooldownLeft = math.max(0, f.attackCooldownLeft - dt);
      _moveSword(f, dt);
    }

    if (_briefing >= ArenaConfig.briefingSeconds) {
      for (final f in _fighters) {
        if (f.blocking) _endBlock(f);
        f.swingStage = _Swing.none;
      }
      _phase = 'countdown';
    }
  }

  void _stepPlaying(double dt) {
    for (final f in _fighters) {
      if (!f.alive) continue;

      f.attackCooldownLeft = math.max(0, f.attackCooldownLeft - dt);
      _rechargeGuard(f, dt);
      f.stunLeft = math.max(0, f.stunLeft - dt);
      if (!f.isStunned) _stopDaze(f);
      f.invincibleLeft = math.max(0, f.invincibleLeft - dt);

      if (f.blocking) {
        f.blockDuration += dt;
        if (f.blockDuration >= ArenaConfig.blockMaxDuration) {
          _endBlock(f);
        }
      }

      if (f.touchDown && !f.touchMoved && !f.blocking && !f.isStunned) {
        f.touchHeldTime += dt;
        if (f.touchHeldTime * 1000 >= ArenaConfig.blockHoldMs &&
            f.blockCooldownLeft <= 0) {
          f.blocking = true;
          f.blockDuration = 0;
          _playFor(f, ArenaConfig.saberVoid);
        }
      }

      if (!f.isStunned && f.moveAngle != null) {
        final speed = ArenaConfig.moveSpeed * f.moveScale;
        final dx = math.cos(f.moveAngle!) * speed * dt;
        final dy = math.sin(f.moveAngle!) * speed * dt;
        f.x += dx;
        f.y += dy;
        f.facingAngle = f.moveAngle!;
      }

      final r = ArenaConfig.characterRadius;
      final held = _area.clamp(f.x, f.y, r);
      f.x = held.x;
      f.y = held.y;

      _moveSword(f, dt);
    }

    for (final f in _fighters) {
      if (f.alive && f.swingStage == _Swing.slashing) _cutWithSword(f);
    }

    if (_fellThisTick.isNotEmpty) {
      _fallen.add({..._fellThisTick});
      _fellThisTick.clear();
    }
    _checkWinCondition();

    final ending = _finishIn;
    if (ending != null) {
      _finishIn = ending - dt;
      if (_finishIn! <= 0) _phase = 'finished';
    }
  }

  void _endBlock(_Fighter f) {
    f.blocking = false;
    f.blockDuration = 0;
    f.blockCooldownLeft = ArenaConfig.blockCooldown;
  }

  void _tryAttack(_Fighter attacker) {
    if (!attacker.alive || attacker.isStunned) return;
    if (attacker.attackCooldownLeft > 0) return;
    if (attacker.blocking) return;

    attacker.attackCooldownLeft = ArenaConfig.attackCooldown;
    attacker.hitThisSwing.clear();
    attacker.swingStage = _Swing.raising;
    attacker.slashLeft = ArenaConfig.attackSwing;
  }

  void _cutWithSword(_Fighter attacker) {
    final (hilt, tip) = _blade(attacker);

    for (final target in _fighters) {
      if (target == attacker || !target.alive) continue;

      if (attacker.hitThisSwing.contains(target.phoneId)) continue;
      if (!_bladeReaches(
        hilt,
        tip,
        target.x,
        target.y,
        ArenaConfig.characterRadius,
      )) {
        continue;
      }

      attacker.hitThisSwing.add(target.phoneId);

      if (target.blocking && _isFacing(target, attacker)) {
        attacker.stunLeft = ArenaConfig.stunDuration;
        attacker.moveAngle = null;
        attacker.moveScale = 0;
        attacker.swingStage = _Swing.none;

        _playFor(attacker, ArenaConfig.saberHit);
        _playFor(target, ArenaConfig.saberHit);
        _startDaze(attacker);
        target.recordImpact(_Impact.parry);
        return;
      }

      if (target.invincibleLeft > 0) continue;

      _playFor(attacker, ArenaConfig.saberHit);
      _playFor(target, ArenaConfig.saberHit);
      target.lives -= 1;
      target.invincibleLeft = ArenaConfig.hitInvincibility;
      if (target.lives <= 0) {
        target.lives = 0;
        target.alive = false;
        _fellThisTick.add(target.phoneId);

        target.deadX = target.x;
        target.deadY = target.y;
        target.moveAngle = null;
        target.moveScale = 0;

        target.touchDown = false;
        target.blocking = false;
        _stopDaze(target);

        final fallen = context.roster.byPhone(target.phoneId);
        if (fallen != null) context.audio.playOnPhone(fallen, fallen.soundSad);
        context.scores.award(attacker.phoneId, ArenaConfig.pointsPerKill);
      } else {
        target.recordImpact(_Impact.hit);
      }
    }
  }

  (({double x, double y}), ({double x, double y})) _blade(_Fighter f) {
    final (hilt, angle) = _swordAt(f);
    final tip = (
      x: hilt.x + math.cos(angle) * ArenaConfig.swordLength,
      y: hilt.y + math.sin(angle) * ArenaConfig.swordLength,
    );
    return (hilt, tip);
  }

  static bool _bladeReaches(
    ({double x, double y}) a,
    ({double x, double y}) b,
    double cx,
    double cy,
    double radius,
  ) {
    final vx = b.x - a.x;
    final vy = b.y - a.y;
    final wx = cx - a.x;
    final wy = cy - a.y;
    final len2 = vx * vx + vy * vy;

    var t = len2 <= 0 ? 0.0 : (wx * vx + wy * vy) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;

    final dx = cx - (a.x + vx * t);
    final dy = cy - (a.y + vy * t);
    return dx * dx + dy * dy <= radius * radius;
  }

  static final double _blockMountAngle = math.atan2(
    -ArenaConfig.swordLength / 2,
    ArenaConfig.swordBlockReach,
  );

  static final double _blockMountReach = math.sqrt(
    ArenaConfig.swordBlockReach * ArenaConfig.swordBlockReach +
        ArenaConfig.swordLength * ArenaConfig.swordLength / 4,
  );

  static final double _handMountAngle = math.atan2(
    ArenaConfig.swordHandSide,
    ArenaConfig.swordGrip,
  );

  static final double _handMountReach = math.sqrt(
    ArenaConfig.swordGrip * ArenaConfig.swordGrip +
        ArenaConfig.swordHandSide * ArenaConfig.swordHandSide,
  );

  void _moveSword(_Fighter f, double dt) {
    if (f.isStunned) f.swingStage = _Swing.none;

    if (f.swingStage == _Swing.slashing && f.slashLeft <= 0) {
      f.swingStage = _Swing.none;
    }

    switch (f.swingStage) {
      case _Swing.raising:
        f.swordTilt = _turnTowards(
          f.swordTilt,
          ArenaConfig.attackWindup,
          ArenaConfig.swordSlew * dt,
        );

        if (f.swordTilt == ArenaConfig.attackWindup) {
          f.swingStage = _Swing.slashing;

          _playFor(f, ArenaConfig.saberVoid);
        }

      case _Swing.slashing:
        f.slashLeft = math.max(0, f.slashLeft - dt);
        final t = 1 - f.slashLeft / ArenaConfig.attackSwing;
        f.swordTilt = t >= 1
            ? ArenaConfig.attackFollow
            : ArenaConfig.attackWindup +
                  (ArenaConfig.attackFollow - ArenaConfig.attackWindup) * t;

      case _Swing.none:
        final (mount, reach, tilt) = f.isStunned
            ? (_handMountAngle, _handMountReach, ArenaConfig.swordStunAngle)
            : f.blocking
            ? (_blockMountAngle, _blockMountReach, ArenaConfig.swordBlockTilt)
            : (_handMountAngle, _handMountReach, ArenaConfig.swordIdleAngle);

        f.swordMount = _turnTowards(
          f.swordMount,
          mount,
          ArenaConfig.swordSlew * dt,
        );
        f.swordReach = _moveTowards(
          f.swordReach,
          reach,
          ArenaConfig.swordReachSlew * dt,
        );
        f.swordTilt = _turnTowards(
          f.swordTilt,
          tilt,
          ArenaConfig.swordSlew * dt,
        );
        return;
    }

    f.swordMount = _turnTowards(
      f.swordMount,
      _handMountAngle,
      ArenaConfig.swordSlew * dt,
    );
    f.swordReach = _moveTowards(
      f.swordReach,
      _handMountReach,
      ArenaConfig.swordReachSlew * dt,
    );
  }

  static double _moveTowards(double from, double to, double maxStep) {
    final d = to - from;
    if (d.abs() <= maxStep) return to;
    return from + (d.isNegative ? -maxStep : maxStep);
  }

  (({double x, double y}), double) _swordAt(_Fighter f) {
    final mount = f.facingAngle + f.swordMount;
    final hilt = (
      x: f.x + math.cos(mount) * f.swordReach,
      y: f.y + math.sin(mount) * f.swordReach,
    );
    return (hilt, f.facingAngle + f.swordTilt);
  }

  static double _shortestTurn(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d;
  }

  static double _turnTowards(double from, double to, double maxStep) {
    final d = _shortestTurn(from, to);
    if (d.abs() <= maxStep) return to;
    return from + (d.isNegative ? -maxStep : maxStep);
  }

  bool _isFacing(_Fighter defender, _Fighter attacker) {
    final dx = attacker.x - defender.x;
    final dy = attacker.y - defender.y;
    final angleToAttacker = math.atan2(dy, dx);
    var diff = (angleToAttacker - defender.facingAngle) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    return diff.abs() <= math.pi / 2;
  }

  void _checkWinCondition() {
    if (_finishIn != null) return;

    final alive = _fighters.where((f) => f.alive).toList();
    if (alive.length <= 1 && _fighters.length > 1) {
      _finishIn = ArenaConfig.deathShowSeconds;
      if (alive.length == 1) _winnerId = alive.first.phoneId;

      context.scores.awardPlacements([
        {for (final f in alive) f.phoneId},
        ..._fallen.reversed,
      ], max: ArenaConfig.placementMax(_fighters.length));
    }
  }

  double? _finishIn;

  @override
  void onTouch(TouchEvent touch) {
    if (_phase != 'playing') return;
    final f = _fighterOf(touch.phoneId);
    if (f == null || !f.alive) return;

    switch (touch.phase) {
      case TouchPhase.down:
        f.touchDownX = touch.worldX;
        f.touchDownY = touch.worldY;
        f.touchX = touch.worldX;
        f.touchY = touch.worldY;
        f.touchDownTime = 0;
        f.touchMoved = false;
        f.touchDown = true;
        f.touchHeldTime = 0;

      case TouchPhase.move:
        if (!f.touchDown) return;
        f.touchX = touch.worldX;
        f.touchY = touch.worldY;
        final dx = touch.worldX - f.touchDownX;
        final dy = touch.worldY - f.touchDownY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist >= ArenaConfig.minMoveDistance) {
          f.touchMoved = true;
          if (!f.isStunned) {
            f.moveAngle = math.atan2(dy, dx);
            f.moveScale = ArenaConfig.moveScaleFor(dist);
          }
        } else {
          f.moveAngle = null;
          f.moveScale = 0;
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

        if (!f.touchMoved &&
            dist < ArenaConfig.minMoveDistance &&
            f.touchHeldTime * 1000 < ArenaConfig.tapMaxMs) {
          _tryAttack(f);
        }

        f.moveAngle = null;
        f.moveScale = 0;
    }
  }

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

      final (hilt, angle) = _swordAt(f);
      yield Entity(
        descriptor: EntityDescriptor(
          id: 'sword_${f.index}',
          kind: 'sword',
          props: {
            'index': f.index,
            'length': ArenaConfig.swordLength,
            'width': ArenaConfig.swordWidth,
          },
        ),
        x: hilt.x,
        y: hilt.y,
        angle: angle,
      );
    }
  }

  double _quantize(double v) => (v * 10).roundToDouble() / 10;

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
      if (_phase == 'briefing')
        'step': (_briefing / ArenaConfig.briefingStepSeconds).floor(),
      'countdown': _quantize(_countdown),
      'winner': _winnerId,
    };
    for (final f in _fighters) {
      final key = 'p${f.index}';
      map['phoneId_$key'] = f.phoneId;
      map['lives_$key'] = f.lives;
      map['stunned_$key'] = f.isStunned;
      map['blocking_$key'] = f.blocking;

      map['slashing_$key'] = f.swingStage == _Swing.slashing;
      map['blkCd_$key'] = _quantize(f.blockCooldownLeft);
      map['invincible_$key'] = f.invincibleLeft > 0;
      map['alive_$key'] = f.alive;

      map['color_$key'] = f.color;
      if (!f.alive) {
        map['deadX_$key'] = _quantize(f.deadX);
        map['deadY_$key'] = _quantize(f.deadY);
      }

      if (f.impacts > 0) {
        map['impacts_$key'] = f.impacts;
        map['impactKind_$key'] = f.impactKind.name;
        map['impactX_$key'] = _quantize(f.impactX);
        map['impactY_$key'] = _quantize(f.impactY);
      }

      if (f.touchDown && f.alive && f.moveAngle != null) {
        map['stickX_$key'] = _quantize(f.touchDownX);
        map['stickY_$key'] = _quantize(f.touchDownY);
        map['stickToX_$key'] = _quantize(f.touchX);
        map['stickToY_$key'] = _quantize(f.touchY);
      }
    }
    return map;
  }

  GameOutcome? _outcome;

  @override
  GameOutcome? get outcome {
    if (_phase != 'finished') return null;

    return _outcome ??= GameOutcome.perPhone({
      for (final f in _fighters)
        f.phoneId: 'You made ${_points(f.phoneId)} this round',
    }, summary: _winnerId != null ? 'last one standing' : 'mutual destruction');
  }

  String _points(String phoneId) {
    final n = context.scores.roundDelta(phoneId);
    return '$n point${n == 1 ? '' : 's'}';
  }

  @override
  void reset() {
    _phase = 'briefing';
    _briefing = 0;
    _countdown = ArenaConfig.countdownSeconds;
    _winnerId = null;
    _fallen.clear();
    _fellThisTick.clear();
    _finishIn = null;

    _outcome = null;
    for (var i = 0; i < _fighters.length; i++) {
      final f = _fighters[i];
      f.x = context.slices[i].screen.centerX;
      f.y = context.slices[i].screen.centerY;
      f.facingAngle = 0;
      f.swordMount = _handMountAngle;
      f.swordReach = _handMountReach;
      f.swordTilt = 0;
      f.swingStage = _Swing.none;
      f.slashLeft = 0;
      f.impacts = 0;
      f.hitThisSwing.clear();
      f.lives = ArenaConfig.maxLives;
      f.alive = true;
      f.moveAngle = null;
      f.moveScale = 0;
      f.attackCooldownLeft = 0;
      f.blockCooldownLeft = 0;
      f.blocking = false;
      f.blockDuration = 0;
      f.stunLeft = 0;

      f.daze = null;
      f.invincibleLeft = ArenaConfig.spawnInvincibility;
      f.touchDown = false;
      f.touchMoved = false;
      f.touchHeldTime = 0;
      f.touchX = f.x;
      f.touchY = f.y;
    }
  }

  @override
  void dispose() {}
}

enum _Impact { hit, parry }

enum _Swing { none, raising, slashing }

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

  double deadX = 0;
  double deadY = 0;

  int impacts = 0;
  _Impact impactKind = _Impact.hit;
  double impactX = 0;
  double impactY = 0;

  void recordImpact(_Impact kind) {
    impacts++;
    impactKind = kind;
    impactX = x;
    impactY = y;
  }

  double facingAngle = 0;

  int lives = ArenaConfig.maxLives;

  bool alive = true;

  double swordMount = 0;
  double swordReach = ArenaConfig.swordGrip;
  double swordTilt = 0;

  _Swing swingStage = _Swing.none;

  double slashLeft = 0;

  final hitThisSwing = <String>{};

  double? moveAngle;

  double moveScale = 0;

  double attackCooldownLeft = 0;
  double blockCooldownLeft = 0;
  bool blocking = false;
  double blockDuration = 0;
  double stunLeft = 0;

  SoundHandle? daze;
  double invincibleLeft = ArenaConfig.spawnInvincibility;

  bool get isStunned => stunLeft > 0;

  bool touchDown = false;
  double touchDownX = 0;
  double touchDownY = 0;
  double touchDownTime = 0;
  bool touchMoved = false;
  double touchHeldTime = 0;

  double touchX = 0;
  double touchY = 0;
}
