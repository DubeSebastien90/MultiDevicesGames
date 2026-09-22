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
  // 'briefing' | 'countdown' | 'playing' | 'finished'
  String _phase = 'briefing';
  double _countdown = ArenaConfig.countdownSeconds;

  /// How far into the briefing we are, in seconds.
  double _briefing = 0;
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
      case 'briefing':
        _stepBriefing(dt);
      case 'countdown':
        _countdown -= dt;
        if (_countdown <= 0) {
          _countdown = 0;
          _phase = 'playing';
        }
        // The blades keep moving and the guard keeps recharging. Nothing else
        // does — nobody can be touched and nobody can act — but the sword the
        // briefing left across everybody's chest has to come back down, and
        // the guard it spent has to fill back up where they can watch it. A
        // count is three seconds with nothing else to look at, which is the
        // best place in the round to be shown what a recharge looks like.
        for (final f in _fighters) {
          f.blockCooldownLeft = math.max(0, f.blockCooldownLeft - dt);
          _moveSword(f, dt);
        }
      case 'playing':
        _stepPlaying(dt);
      case 'finished':
        break;
    }
  }

  /// The three lines, and a fighter doing what each one says.
  ///
  /// The demonstration is the point. 'Tap to attack' next to a still figure is
  /// a caption; next to a figure that swings as you read it, it is an
  /// instruction — and it is the only chance the game gets to show what a
  /// swing and a guard *look like* before they start mattering.
  ///
  /// Nothing can be hit here. Blades move and the poses run, but [_cutWithSword]
  /// is not called: a fighter who happens to have spawned within reach of a
  /// neighbour must not lose a life to a demonstration.
  void _stepBriefing(double dt) {
    final before = _briefing;
    _briefing += dt;

    final step = (_briefing / ArenaConfig.briefingStepSeconds).floor();
    final into = _briefing - step * ArenaConfig.briefingStepSeconds;
    final wasInto = before - step * ArenaConfig.briefingStepSeconds;

    // The moment this step's line becomes a thing being done, crossed once.
    final showNow =
        wasInto < ArenaConfig.briefingDemoAt &&
        into >= ArenaConfig.briefingDemoAt;

    for (final f in _fighters) {
      // Blocking is held for the rest of the 'hold to block' step and then
      // dropped *properly*, cooldown and all. The recharge is half of what
      // there is to learn about blocking — that it is spent, and that the
      // blade fills back up before it can be used again — and the count that
      // follows is exactly the window to watch it happen in.
      if (step != 2 && f.blocking) _endBlock(f);

      if (showNow) {
        if (step == 1) {
          f.attackCooldownLeft = 0;
          _tryAttack(f);
        } else if (step == 2) {
          f.blocking = true;
          f.blockDuration = 0;
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

      // Decrement timers.
      f.attackCooldownLeft = math.max(0, f.attackCooldownLeft - dt);
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

      // Movement (not while stunned). How fast is how far the finger is from
      // the anchor, up to [ArenaConfig.moveSpeed] at full tilt — a fighter
      // edging into range and one charging across the floor are different
      // intentions, and a drag that only ever means "go" cannot tell them
      // apart.
      if (!f.isStunned && f.moveAngle != null) {
        final speed = ArenaConfig.moveSpeed * f.moveScale;
        final dx = math.cos(f.moveAngle!) * speed * dt;
        final dy = math.sin(f.moveAngle!) * speed * dt;
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

      // The blade moves after the body, so a swing thrown while running is
      // swung from where the fighter actually ended up.
      _moveSword(f, dt);
    }

    // Cutting comes after every blade has moved, so an exchange does not
    // depend on who happens to sit earlier in the list. Only a blade actually
    // in its slash cuts: the trip up to the shoulder is a fighter getting
    // ready, and being cut down by somebody winding up is not a thing anybody
    // would believe.
    for (final f in _fighters) {
      if (f.alive && f.swingStage == _Swing.slashing) _cutWithSword(f);
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

  /// Ask for a slash. Nothing is hit here — that is the point.
  ///
  /// The old attack resolved the instant the finger came up: a cone was tested
  /// against everybody, damage was dealt, and the drawing that followed was
  /// decoration over a decision already made. Now the tap only *asks*, and
  /// what the blade touches on the way round is settled frame by frame in
  /// [_cutWithSword]. A slash that misses, misses because the sword went
  /// somewhere else.
  ///
  /// Two stages, and keeping them apart is what makes the cut readable. First
  /// the blade is carried up to [ArenaConfig.attackWindup] — an ordinary move
  /// between poses, smoothed like every other one, cutting nobody. Only when
  /// it is *exactly* there does the slash begin, and the slash runs from that
  /// angle to [ArenaConfig.attackFollow] and stops. The smoothing lives
  /// between the poses; the cut itself is the cut.
  void _tryAttack(_Fighter attacker) {
    if (!attacker.alive || attacker.isStunned) return;
    if (attacker.attackCooldownLeft > 0) return;
    if (attacker.blocking) return;

    attacker.attackCooldownLeft = ArenaConfig.attackCooldown;
    attacker.hitThisSwing.clear();
    attacker.swingStage = _Swing.raising;
    attacker.slashLeft = ArenaConfig.attackSwing;
  }

  /// Where the blade is at this instant, and what that costs anybody standing
  /// in the way.
  ///
  /// The hitbox *is* the blade: a segment from hilt to tip, tested against
  /// each fighter's body circle. No cone, no range check, no facing test — a
  /// blade that reaches somebody hits them, including one swung through
  /// somebody standing off to the side.
  void _cutWithSword(_Fighter attacker) {
    final (hilt, tip) = _blade(attacker);

    for (final target in _fighters) {
      if (target == attacker || !target.alive) continue;
      // Once per swing per fighter. The blade sweeps through a body over
      // several frames, and a life a frame is not a fight.
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

      // A raised guard turns the blow back on whoever threw it. Still judged
      // on facing rather than blade against blade: a block is a promise made
      // with a thumb, and asking two people to line rectangles up at arm's
      // length across a table is a different game.
      if (target.blocking && _isFacing(target, attacker)) {
        attacker.stunLeft = ArenaConfig.stunDuration;
        attacker.moveAngle = null;
        attacker.moveScale = 0;
        attacker.swingStage = _Swing.none;
        target.recordImpact(_Impact.parry);
        return;
      }

      if (target.invincibleLeft > 0) continue;

      target.lives -= 1;
      target.invincibleLeft = ArenaConfig.hitInvincibility;
      if (target.lives <= 0) {
        target.lives = 0;
        target.alive = false;
        // Where they fell. The entity goes with them, so without this the
        // phones have nothing left to hang a burst on.
        target.deadX = target.x;
        target.deadY = target.y;
        target.moveAngle = null;
        target.moveScale = 0;
        // Their finger is still on the glass, but [onTouch] turns a dead
        // fighter away — so the up that would have cleared this never arrives,
        // and without it their joystick would be left painted on the floor.
        target.touchDown = false;
        target.blocking = false;
        context.scores.award(attacker.phoneId, ArenaConfig.pointsPerKill);
      } else {
        // Only while they are still standing. A fatal blow has a burst of its
        // own and twice the size, and firing both would read as two events.
        target.recordImpact(_Impact.hit);
      }
    }
  }

  /// The blade's two ends, in world coordinates.
  (({double x, double y}), ({double x, double y})) _blade(_Fighter f) {
    final (hilt, angle) = _swordAt(f);
    final tip = (
      x: hilt.x + math.cos(angle) * ArenaConfig.swordLength,
      y: hilt.y + math.sin(angle) * ArenaConfig.swordLength,
    );
    return (hilt, tip);
  }

  /// Does the segment a-b come within [radius] of (cx, cy)?
  ///
  /// The ordinary point-to-segment distance, written out rather than pulled in
  /// so the degenerate case — a blade of no length, which cannot happen but
  /// would divide by zero if it did — is visibly handled.
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

  /// Where the hilt sits when a guard is up, as an angle off the facing.
  ///
  /// Derived rather than tuned: the bar is centred in front of the body and
  /// turned across it, so the hand is half a blade to one side of that centre.
  /// Written out here because [math.atan2] is not something a const can call.
  static final double _blockMountAngle = math.atan2(
    -ArenaConfig.swordLength / 2,
    ArenaConfig.swordBlockReach,
  );

  static final double _blockMountReach = math.sqrt(
    ArenaConfig.swordBlockReach * ArenaConfig.swordBlockReach +
        ArenaConfig.swordLength * ArenaConfig.swordLength / 4,
  );

  /// Move the blade one tick towards where it belongs.
  ///
  /// Everything here is measured *against the fighter's facing*, never in
  /// world angles: where the hand is (an angle and a distance from the body)
  /// and which way the blade lies (an angle). The world transform is that pose
  /// plus the facing, worked out afresh every tick in [_swordAt] — so turning
  /// on the spot takes the sword round with it exactly, with no lag and
  /// nothing to catch up on. The pose is what animates; the facing is not
  /// animated at all, because a sword that trails behind the hands holding it
  /// is not a smooth sword, it is a loose one.
  ///
  /// Three things the blade can be doing, and only one of them is a slash:
  ///
  /// * **raising** — travelling to the shoulder at the ordinary pose speed.
  ///   This is a transition, not an attack.
  /// * **slashing** — running from [ArenaConfig.attackWindup] to
  ///   [ArenaConfig.attackFollow] at a flat rate, starting and ending on those
  ///   angles exactly. No easing: a cut that slides into its ends looks like
  ///   it is being placed rather than swung.
  /// * **carried** — turning towards whatever pose the fighter's state calls
  ///   for, at the pose speed.
  void _moveSword(_Fighter f, double dt) {
    // A stunned fighter has dropped the idea, wherever the blade had got to.
    if (f.isStunned) f.swingStage = _Swing.none;

    // The cut ends *after* the tick that lands on the follow-through, not
    // during it. Ending it in the same breath as arriving would leave the
    // blade's final position — the end of the cut, and as good a place to be
    // hit from as any other — untested against anybody standing there.
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
        // [_turnTowards] lands exactly on the target rather than near it, so
        // the slash below always begins at the shoulder and not a hair off it.
        if (f.swordTilt == ArenaConfig.attackWindup) {
          f.swingStage = _Swing.slashing;
        }

      case _Swing.slashing:
        f.slashLeft = math.max(0, f.slashLeft - dt);
        final t = 1 - f.slashLeft / ArenaConfig.attackSwing;
        f.swordTilt = t >= 1
            // Exactly, not nearly: the blade finishes the cut on the angle the
            // cut was defined by.
            ? ArenaConfig.attackFollow
            : ArenaConfig.attackWindup +
                  (ArenaConfig.attackFollow - ArenaConfig.attackWindup) * t;

      case _Swing.none:
        final (mount, reach, tilt) = f.isStunned
            ? (0.0, ArenaConfig.swordGrip, ArenaConfig.swordStunAngle)
            : f.blocking
            ? (_blockMountAngle, _blockMountReach, ArenaConfig.swordBlockTilt)
            : (0.0, ArenaConfig.swordGrip, ArenaConfig.swordIdleAngle);

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

    // Raising or slashing, the hand comes back to the fist: a cut is thrown
    // from the shoulder, not from behind a guard.
    f.swordMount = _turnTowards(f.swordMount, 0, ArenaConfig.swordSlew * dt);
    f.swordReach = _moveTowards(
      f.swordReach,
      ArenaConfig.swordGrip,
      ArenaConfig.swordReachSlew * dt,
    );
  }

  /// [from], moved at most [maxStep] towards [to]. The straight-line twin of
  /// [_turnTowards], for the one part of the pose that is a distance.
  static double _moveTowards(double from, double to, double maxStep) {
    final d = to - from;
    if (d.abs() <= maxStep) return to;
    return from + (d.isNegative ? -maxStep : maxStep);
  }

  /// Where this fighter's sword is right now, in the world: the hilt, and the
  /// angle the blade lies at.
  ///
  /// The single place the pose and the facing are added together, which is why
  /// the sword can never be out of line with its owner — the drawing, the
  /// hitbox and the wire all read this.
  (({double x, double y}), double) _swordAt(_Fighter f) {
    final mount = f.facingAngle + f.swordMount;
    final hilt = (
      x: f.x + math.cos(mount) * f.swordReach,
      y: f.y + math.sin(mount) * f.swordReach,
    );
    return (hilt, f.facingAngle + f.swordTilt);
  }

  /// The short way round from [from] to [to], in (-pi, pi].
  static double _shortestTurn(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d;
  }

  /// [from], moved at most [maxStep] towards [to] the short way round.
  static double _turnTowards(double from, double to, double maxStep) {
    final d = _shortestTurn(from, to);
    if (d.abs() <= maxStep) return to;
    return from + (d.isNegative ? -maxStep : maxStep);
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

  /// Decide the round, but do not end it yet.
  ///
  /// The winner and the points are settled here, the instant the last fighter
  /// falls — that part must not wait for anything. What waits is the *phase*:
  /// the round keeps running for [ArenaConfig.deathShowSeconds] so the burst
  /// has somewhere to play, and only then does the table move on to the score.
  void _checkWinCondition() {
    if (_finishIn != null) return;

    final alive = _fighters.where((f) => f.alive).toList();
    if (alive.length <= 1 && _fighters.length > 1) {
      _finishIn = ArenaConfig.deathShowSeconds;
      if (alive.length == 1) {
        _winnerId = alive.first.phoneId;
        context.scores.award(_winnerId!, ArenaConfig.pointsForWinning);
      }
    }
  }

  /// Seconds left of the pause after the last fall, or null while the round is
  /// still being fought.
  double? _finishIn;

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
            f.moveScale = ArenaConfig.moveScaleFor(dist);
          }
        } else {
          // Back inside the dead zone, which on a stick is the middle: stop.
          // [touchMoved] deliberately stays set — this was a drag, and letting
          // it turn back into a hold would have a player who is steering
          // suddenly raise their shield.
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

        // Tap detection: short, without movement.
        if (!f.touchMoved &&
            dist < ArenaConfig.minMoveDistance &&
            f.touchHeldTime * 1000 < ArenaConfig.tapMaxMs) {
          _tryAttack(f);
        }

        // Stop moving on finger up.
        f.moveAngle = null;
        f.moveScale = 0;
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

      // The sword rides the wire as an entity of its own rather than as a
      // number in shared state, and that is what makes it move smoothly on
      // every phone: entities are interpolated between snapshots — angles by
      // the short way round — while shared state arrives in steps whenever it
      // happens to change.
      //
      // Anchored at the *hilt*, not the body. The hand moves as well as the
      // blade — a guard slides it across in front of the chest — so the view
      // is handed the hilt and an angle and has nothing left to work out.
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

  // -- shared state -----------------------------------------------------------

  double _quantize(double v) =>
      (v * 10).roundToDouble() / 10; // 0.1 granularity

  @override
  Map<String, Object?> get sharedState {
    final map = <String, Object?>{
      'phase': _phase,
      // Which line the briefing is on. The words themselves live in the view,
      // where every other string this game shows lives.
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
      // Cutting, as against carrying the blade up to the shoulder. The one
      // stretch of a swing that can take a life, and the only part of it worth
      // anybody else knowing about.
      map['slashing_$key'] = f.swingStage == _Swing.slashing;
      map['blkCd_$key'] = _quantize(f.blockCooldownLeft);
      map['invincible_$key'] = f.invincibleLeft > 0;
      map['alive_$key'] = f.alive;
      // Static for the round, and sent once because the broadcast is diffed.
      // The view needs it after the fighter is gone, which is exactly when the
      // entity that used to carry it no longer exists.
      map['color_$key'] = f.color;
      if (!f.alive) {
        map['deadX_$key'] = _quantize(f.deadX);
        map['deadY_$key'] = _quantize(f.deadY);
      }

      // The last thing that struck this fighter, as a counter and a place.
      //
      // A counter rather than a flag, because the broadcast is diffed and a
      // flag set twice running is a flag that never changed — the second blow
      // would land in silence. Counting makes every one of them an event.
      if (f.impacts > 0) {
        map['impacts_$key'] = f.impacts;
        map['impactKind_$key'] = f.impactKind.name;
        map['impactX_$key'] = _quantize(f.impactX);
        map['impactY_$key'] = _quantize(f.impactY);
      }

      // The stick, and only while it is actually steering — a finger resting
      // inside the dead zone is a tap or a block being held, and drawing a
      // ring under it would say "you are moving" to a player who is not.
      // Absent keys are how the view is told there is nothing to draw, which
      // also keeps four dead numbers per fighter off the wire for the whole of
      // every round nobody is dragging anything.
      if (f.touchDown && f.alive && f.moveAngle != null) {
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
    return _outcome ??= GameOutcome.perPhone({
      for (final f in _fighters)
        f.phoneId: 'You made ${_points(f.phoneId)} this round',
    }, summary: _winnerId != null ? 'last one standing' : 'mutual destruction');
  }

  String _points(String phoneId) {
    final n = context.scores.roundDelta(phoneId);
    return '$n point${n == 1 ? '' : 's'}';
  }

  // -- reset ------------------------------------------------------------------

  @override
  void reset() {
    _phase = 'briefing';
    _briefing = 0;
    _countdown = ArenaConfig.countdownSeconds;
    _winnerId = null;
    _finishIn = null;
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
      f.swordMount = 0;
      f.swordReach = ArenaConfig.swordGrip;
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

/// What happened when a blade reached somebody.
///
/// The two are drawn differently and mean opposite things — one is a life
/// gone, the other is a life saved — so the view is told which rather than
/// left to work it out from what changed.
enum _Impact {
  /// It landed. A life gone, and a small burst in the player's own colour.
  hit,

  /// It was turned away by a raised guard. White sparks, and the swinger is
  /// the one in trouble.
  parry,
}

/// What a blade is in the middle of.
///
/// Named rather than inferred from a timer, because the difference between the
/// two moving stages is the difference between getting ready and cutting
/// somebody, and that is not something to leave to the sign of a double.
enum _Swing {
  /// Carried: resting, guarding, or trailing from a stun.
  none,

  /// On its way to the shoulder, hurting nobody.
  raising,

  /// The cut, from one angle to the other.
  slashing,
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

  /// Where this fighter was standing when they fell. Read by the view, which
  /// has nothing else left to put a burst on.
  double deadX = 0;
  double deadY = 0;

  /// How many blows have struck this fighter, what the last one was, and where
  /// they were standing when it did.
  ///
  /// Their own middle, not the spot on the blade that reached them. The burst
  /// is about the person it happened to, and one thrown from the point of
  /// contact is a handful of dots off to one side of a fighter — which is
  /// what it looked like, and why it went unnoticed.
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

  /// Three of them, and every one is a dot on the screen.
  int lives = ArenaConfig.maxLives;

  bool alive = true;

  /// The sword's pose, every part of it measured against [facingAngle] rather
  /// than the world. Turning the fighter turns the sword with it exactly,
  /// because the world angle is never stored — it is this plus the facing,
  /// worked out when it is needed.
  ///
  /// [swordMount] is where the hand is around the body, [swordReach] how far
  /// out it is held, and [swordTilt] which way the blade lies from there.
  double swordMount = 0;
  double swordReach = ArenaConfig.swordGrip;
  double swordTilt = 0;

  /// What the blade is doing: being carried about, on its way to the
  /// shoulder, or cutting.
  _Swing swingStage = _Swing.none;

  /// Seconds left of the slash itself. Only meaningful while
  /// [swingStage] is [_Swing.slashing].
  double slashLeft = 0;

  /// Who this swing has already cut. A blade passes through a body over
  /// several frames and must only cost a life once.
  final hitThisSwing = <String>{};

  // Movement direction (null = stopped).
  double? moveAngle;

  /// How far the stick is pushed, 0..1, as a fraction of [ArenaConfig.moveSpeed].
  double moveScale = 0;

  // Timers.
  double attackCooldownLeft = 0;
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
