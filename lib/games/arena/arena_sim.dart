import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/play_area.dart';
import 'arena_config.dart';

/// Last-fighter-standing arena brawler.
///
/// No physics engine — extends [GameSim] directly like Hot Potato. Movement,
/// attacks and blocking are encoded via touch gestures: drag to move, tap to
/// attack, hold to block.
// Presence is deliberately not implemented — see the commented block under
// 'who is still here' at the bottom of this class for what it used to do.
class ArenaSim implements GameSim {
  ArenaSim(this.context) {
    _initFighters();
  }

  final BoardContext context;

  /// Where a fighter is allowed to stand: the screens themselves, not the
  /// rectangle drawn around them. Built once — the table does not change shape
  /// mid-round.
  late final _area = PlayArea.of(context.coverage);

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

      // Kept on a real screen, not inside a rectangle drawn around them.
      //
      // The board rectangle is only as deep as the *shallowest* phone, so on a
      // table of mismatched sizes it shaded off half of the biggest screen and
      // refused to let anybody walk there. The area follows the screens
      // themselves, so every phone is playable to its own edges and the wall
      // steps where a tall screen meets a short one.
      final r = ArenaConfig.characterRadius;
      final held = _area.clamp(f.x, f.y, r);
      f.x = held.x;
      f.y = held.y;
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
        // Their finger is still on the glass, but [onTouch] turns a dead
        // fighter away — so the up that would have cleared this never arrives,
        // and without it their joystick would be left painted on the floor.
        target.touchDown = false;
        target.blocking = false;
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

  // -- who is still here ------------------------------------------------------

  // Kept as reference, not implemented. A fighter whose player has dropped out
  // is treated exactly like one whose player is standing still: they stay where
  // they are, they can still be cut down — a body left standing in the middle
  // of a brawl is fair game, and taking it off the board would rescue whoever
  // was losing to it — and nothing on screen says otherwise.
  //
  // To bring it back: `implements GameSim, PlayerPresence` on the class, the
  // `_away` set, `map['away_$key'] = _away.contains(f.phoneId)` in
  // [sharedState], and the grey body in `ArenaView`, which is commented there
  // for the same reason.
  //
  // @override
  // void onPlayerLeft(String phoneId) {
  //   _away.add(phoneId);
  //   // Their hands are off the glass, so nothing should still be held down.
  //   final f = _fighterOf(phoneId);
  //   if (f == null) return;
  //   f
  //     ..moveAngle = null
  //     ..touchDown = false
  //     ..touchMoved = false
  //     ..touchHeldTime = 0;
  //   if (f.blocking) _endBlock(f);
  // }
  //
  // @override
  // void onPlayerReturned(String phoneId) => _away.remove(phoneId);

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

      // The stick, and only while a finger is actually down: absent keys are
      // how the view is told there is nothing to draw, which keeps four dead
      // numbers per fighter off the wire for the whole of every round nobody
      // is touching anything.
      if (f.touchDown && f.alive) {
        map['stickX_$key'] = _quantize(f.touchDownX);
        map['stickY_$key'] = _quantize(f.touchDownY);
        map['stickToX_$key'] = _quantize(f.touchX);
        map['stickToY_$key'] = _quantize(f.touchY);
      }
    }
    return map;
  }

  // -- outcome ----------------------------------------------------------------

  /// Built once. `outcome` is polled several times a tick and this one carries
  /// a map, so constructing it fresh each time would be pure waste.
  GameOutcome? _outcome;

  @override
  GameOutcome? get outcome {
    if (_phase != 'finished') return null;

    // Everyone gets their own tally rather than a shared verdict: a round of
    // Arena is worth more to a player as "you made 40 points" than as a win or
    // a loss, and the kills are already in the scoreboard by the time the last
    // fighter falls.
    return _outcome ??= GameOutcome.perPhone(
      {
        for (final f in _fighters)
          f.phoneId: 'You made ${_points(f.phoneId)} this round',
      },
      summary: _winnerId != null ? 'last one standing' : 'mutual destruction',
    );
  }

  String _points(String phoneId) {
    final n = context.scores.roundDelta(phoneId);
    return '$n point${n == 1 ? '' : 's'}';
  }

  // -- reset ------------------------------------------------------------------

  @override
  void reset() {
    _phase = 'countdown';
    _countdown = ArenaConfig.countdownSeconds;
    _winnerId = null;
    // Who is at the table is the session's business, not the round's, so this
    // is deliberately *not* cleared: a player who is away stays away across a
    // replay until they actually come back.
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
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
      f.touchX = f.x;
      f.touchY = f.y;
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

  /// Where the finger is right now, as against [touchDownX]/[touchDownY] where
  /// it landed. Only the drawn joystick needs it — steering is an angle, and an
  /// angle does not care how far the drag went — but the stick cannot show a
  /// tilt it has not been told about.
  double touchX = 0;
  double touchY = 0;
}
