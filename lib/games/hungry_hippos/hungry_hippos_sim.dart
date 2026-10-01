import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/audio/sounds.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/model/world_rect.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';
import '../../sdk/score/scoreboard.dart';
import 'hungry_hippos_config.dart';

class HungryHipposSim extends Forge2DGameSim {
  HungryHipposSim(super.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _buildHippos();
    _buildMarbles();
  }

  final math.Random _random;

  final _boupPick = math.Random(3);

  final _hippos = <_Hippo>[];

  final _live = <String>{};

  final _eaten = <String, int>{};

  double _elapsed = 0;
  bool _awarded = false;
  GameOutcome? _outcome;

  double get _centreX => board.centerX;
  double get _centreY => board.centerY;

  double _emptyFor = 0;

  bool get _over =>
      (_live.isEmpty && _emptyFor >= HungryHipposConfig.endDelaySeconds) ||
      _elapsed >= HungryHipposConfig.maxRoundSeconds;

  int eatenBy(String phoneId) => _eaten[phoneId] ?? 0;

  int get marblesLeft => _live.length;

  void _buildHippos() {
    final placements = [
      for (final slice in context.slices) _aim(slice.viewport),
    ];

    final headroom = placements
        .map((p) => p.centreDistance + p.toEdge - HungryHipposConfig.hippoInset)
        .fold<double>(double.infinity, math.min);

    final shortHalf = math.min(board.width, board.height) / 2;
    final byBoard = shortHalf - HungryHipposConfig.playerMarginWorld;
    final byHippos =
        headroom -
        HungryHipposConfig.hippoRadius -
        HungryHipposConfig.hippoClearance;
    _dishRadius = math.max(1.0, math.min(byBoard, byHippos));

    final restDistance =
        _dishRadius +
        HungryHipposConfig.hippoRadius +
        HungryHipposConfig.hippoClearance;

    for (var i = 0; i < context.slices.length; i++) {
      final slice = context.slices[i];
      final aim = placements[i];

      final along = restDistance.clamp(
        aim.centreDistance - aim.toEdge + HungryHipposConfig.hippoInset,
        aim.centreDistance + aim.toEdge - HungryHipposConfig.hippoInset,
      );

      final restX = _centreX + aim.awayX * along;
      final restY = _centreY + aim.awayY * along;

      final id = 'hippo_${slice.phoneId}';
      final body = addBody(
        id,
        'hippo',
        BodyDef(
          type: BodyType.kinematic,
          position: Vector2(restX, restY),
          angle: math.atan2(-aim.awayY, -aim.awayX),
        ),
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: HungryHipposConfig.hippoRadius,
          ShapeProps.color:
              context.colorOf(slice.phoneId)?.value.toARGB32() ??
              HungryHipposConfig.colorHippoFallback,
          ShapeProps.player: slice.phoneId,
        },
      );
      body.createFixture(
        FixtureDef(
          CircleShape()..radius = HungryHipposConfig.hippoRadius,
          density: 1,
          friction: 0.1,
          restitution: HungryHipposConfig.hippoRestitution,
        ),
      );

      _hippos.add(
        _Hippo(
          phoneId: slice.phoneId,
          id: id,
          body: body,
          restX: restX,
          restY: restY,
          dirX: -aim.awayX,
          dirY: -aim.awayY,
          toMiddle: along,
        ),
      );
      _eaten[slice.phoneId] = 0;
    }
  }

  _Aim _aim(WorldRect rect) {
    var awayX = rect.centerX - _centreX;
    var awayY = rect.centerY - _centreY;
    var len = math.sqrt(awayX * awayX + awayY * awayY);
    if (len < 1e-6) {
      awayX = 0;
      awayY = 1;
      len = 1;
    } else {
      awayX /= len;
      awayY /= len;
    }
    return _Aim(
      awayX: awayX,
      awayY: awayY,
      centreDistance: len,
      toEdge: _edgeDistance(rect.width / 2, rect.height / 2, awayX, awayY),
    );
  }

  void _buildMarbles() {
    for (var i = 0; i < HungryHipposConfig.marbleCount; i++) {
      final body = addBody(
        'marble$i',
        'marble',
        BodyDef(
          type: BodyType.dynamic,
          position: Vector2(_centreX, _centreY),
          linearDamping: HungryHipposConfig.marbleDamping,
          angularDamping: HungryHipposConfig.marbleDamping,
        ),
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: HungryHipposConfig.marbleRadius,
          ShapeProps.color: HungryHipposConfig.colorMarble,
          ShapeProps.spin: true,
        },
      );
      body.createFixture(
        FixtureDef(
          CircleShape()..radius = HungryHipposConfig.marbleRadius,
          density: 1,
          friction: 0.2,
          restitution: HungryHipposConfig.marbleRestitution,
        ),
      );
    }
    _deal();
  }

  double _swirlSign = 1;

  void _deal() {
    _live.clear();
    _swirlSign = _random.nextBool() ? 1 : -1;

    final inner = dishRadius * HungryHipposConfig.spawnInnerFraction;
    final outer = dishRadius * HungryHipposConfig.spawnOuterFraction;
    final omega = math.sqrt(HungryHipposConfig.bowlPull);

    for (var i = 0; i < HungryHipposConfig.marbleCount; i++) {
      final id = 'marble$i';
      final body = bodyOf(id);
      if (body == null) continue;

      final r = math.sqrt(
        inner * inner + _random.nextDouble() * (outer * outer - inner * inner),
      );
      final a = _random.nextDouble() * 2 * math.pi;

      final jitter =
          1 +
          HungryHipposConfig.spawnSpeedJitter * (_random.nextDouble() * 2 - 1);
      final speed = r * omega * jitter * _swirlSign;

      show(id);
      body
        ..setTransform(
          Vector2(_centreX + r * math.cos(a), _centreY + r * math.sin(a)),
          0,
        )
        ..linearVelocity = Vector2(-math.sin(a) * speed, math.cos(a) * speed)
        ..angularVelocity = 0;
      _live.add(id);
    }
  }

  double get dishRadius => _dishRadius;
  double _dishRadius = 1;

  static double _edgeDistance(
    double halfW,
    double halfH,
    double dx,
    double dy,
  ) {
    final tx = dx.abs() < 1e-9 ? double.infinity : halfW / dx.abs();
    final ty = dy.abs() < 1e-9 ? double.infinity : halfH / dy.abs();
    return math.min(tx, ty);
  }

  @override
  void step(double dt) {
    if (_over) {
      _awardOnce();
      return;
    }
    _elapsed += dt;
    if (_live.isEmpty) _emptyFor += dt;

    _turnTheBowl();
    _driveHippos(dt);

    _swallow();
    _shoveAndJudge();

    super.step(dt);

    if (_over) _awardOnce();
  }

  void _turnTheBowl() {
    final ring = dishRadius * HungryHipposConfig.swirlRingFraction;
    final swirl =
        HungryHipposConfig.marbleDamping *
        ring *
        math.sqrt(HungryHipposConfig.bowlPull) *
        _swirlSign;

    for (final id in _live) {
      final body = bodyOf(id);
      if (body == null) continue;
      final dx = _centreX - body.position.x;
      final dy = _centreY - body.position.y;

      var fx = dx * HungryHipposConfig.bowlPull;
      var fy = dy * HungryHipposConfig.bowlPull;

      final r = math.sqrt(dx * dx + dy * dy);
      if (r > 1e-4) {
        fx += dy / r * swirl;
        fy -= dx / r * swirl;
      }
      body.applyForce(Vector2(fx * body.mass, fy * body.mass));
    }
  }

  void _driveHippos(double dt) {
    for (final h in _hippos) {
      final before = h._phase;
      h.advance(dt);
      _soundPhase(h, before);

      h.body.fixtures.first.setSensor(h.passesThrough);

      final along = h.reach * h.lungeDistance - h.recoil;
      final wantX = h.restX + h.dirX * along - h.dirY * h.sway;
      final wantY = h.restY + h.dirY * along + h.dirX * h.sway;
      h.targetX = wantX;
      h.targetY = wantY;

      h.body.linearVelocity = Vector2(
        (wantX - h.body.position.x) / dt,
        (wantY - h.body.position.y) / dt,
      );
    }
  }

  void _swallow() {
    for (final h in _hippos) {
      if (!h.mouthOpen) continue;

      final mouthX = h.targetX;
      final mouthY = h.targetY;
      const reach = HungryHipposConfig.mouthRadius;

      final swallowed = <String>[];
      for (final id in _live) {
        final body = bodyOf(id);
        if (body == null) continue;
        final dx = body.position.x - mouthX;
        final dy = body.position.y - mouthY;
        if (dx * dx + dy * dy <= reach * reach) swallowed.add(id);
      }

      for (final id in swallowed) {
        _live.remove(id);
        hide(id);
        _eaten[h.phoneId] = (_eaten[h.phoneId] ?? 0) + 1;

        final bites = Sounds.buttonPress;
        _playFor(h, bites[_boupPick.nextInt(bites.length)]);
      }
      h.ateThisLunge += swallowed.length;
    }
  }

  void _shoveAndJudge() {
    for (final h in _hippos) {
      if (!h.extendedThisTick) continue;

      final mouthX = h.targetX;
      final mouthY = h.targetY;
      const reach = HungryHipposConfig.pushRadius;
      final speed = _lerp(
        HungryHipposConfig.pushSpeedTap,
        HungryHipposConfig.pushSpeedFull,
        h.charge,
      );

      for (final id in _live) {
        final body = bodyOf(id);
        if (body == null) continue;
        var dx = body.position.x - mouthX;
        var dy = body.position.y - mouthY;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > reach) continue;
        if (d < 1e-4) {
          dx = h.dirX;
          dy = h.dirY;
        } else {
          dx /= d;
          dy /= d;
        }

        final v = body.linearVelocity;
        body.linearVelocity = Vector2(
          v.x * 0.4 + dx * speed,
          v.y * 0.4 + dy * speed,
        );
      }

      _shoves++;
      _lastShove[h.phoneId] =
          '$_shoves:${mouthX.toStringAsFixed(2)}:${mouthY.toStringAsFixed(2)}';

      if (h.ateThisLunge == 0) h.stunned = true;
    }
  }

  int _shoves = 0;

  final _lastShove = <String, String>{};

  @override
  void onTouch(TouchEvent touch) {
    if (_over) return;
    for (final h in _hippos) {
      if (h.phoneId != touch.phoneId) continue;
      final before = h._phase;
      if (touch.phase == TouchPhase.down) {
        h.press(touch.pointerId);
      } else if (touch.phase == TouchPhase.up) {
        h.lift(touch.pointerId);
      }
      _soundPhase(h, before);
    }
  }

  void _soundPhase(_Hippo h, _HippoPhase before) {
    final now = h._phase;
    if (now == before) return;
    if (now == _HippoPhase.charging) {
      _stopHold(h);
      h.holdSound = _playFor(h, HungryHipposConfig.hold);
    } else if (before == _HippoPhase.charging && now == _HippoPhase.out) {
      _stopHold(h);
      _playFor(h, HungryHipposConfig.shot);
    }
  }

  void _stopHold(_Hippo h) {
    final hold = h.holdSound;
    if (hold == null) return;
    h.holdSound = null;
    context.audio.stopSound(hold, fade: HungryHipposConfig.holdFadeOut);
  }

  SoundHandle? _playFor(_Hippo h, SoundCue cue) {
    final player = context.roster.byPhone(h.phoneId);
    if (player == null) return null;
    return context.audio.playOnPhone(player, cue);
  }

  @override
  Map<String, Object?> get sharedState => {
    'marblesLeft': _live.length,
    'dish': double.parse(dishRadius.toStringAsFixed(3)),
    'over': _over,
    'secondsLeft': (HungryHipposConfig.maxRoundSeconds - _elapsed).ceil().clamp(
      0,
      999,
    ),
    'hippos': {for (final h in _hippos) h.phoneId: h.status},
    'shoves': Map<String, String>.of(_lastShove),
  };

  Map<String, int> _paid = const {};

  void _awardOnce() {
    if (_awarded) return;
    _awarded = true;
    _paid = context.scores.awardPlacements(
      Scoreboard.tiersBy({
        for (final h in _hippos) h.phoneId: eatenBy(h.phoneId),
      }),
    );
  }

  @override
  GameOutcome? get outcome {
    if (!_over) return null;
    if (!_awarded) return null;

    return _outcome ??= GameOutcome.perPhone({
      for (final h in _hippos) h.phoneId: _lineFor(h.phoneId),
    }, summary: _summary());
  }

  String _lineFor(String phoneId) {
    final n = eatenBy(phoneId);
    final pts = ' — +${_paid[phoneId] ?? 0} pts';
    if (n == 0) return 'Your hippo went hungry$pts';
    return 'You ate $n marble${n == 1 ? '' : 's'}$pts';
  }

  String _summary() {
    final total = _eaten.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 'not a single marble';
    return '$total of ${HungryHipposConfig.marbleCount} marbles gone';
  }

  @override
  void reset() {
    _elapsed = 0;
    _emptyFor = 0;
    _awarded = false;
    _paid = const {};

    _outcome = null;
    _lastShove.clear();

    for (final h in _hippos) {
      h.reset();
      h.body
        ..setTransform(Vector2(h.restX, h.restY), h.body.angle)
        ..linearVelocity = Vector2.zero();
    }

    for (final key in _eaten.keys.toList()) {
      _eaten[key] = 0;
    }

    _deal();
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _Hippo {
  _Hippo({
    required this.phoneId,
    required this.id,
    required this.body,
    required this.restX,
    required this.restY,
    required this.dirX,
    required this.dirY,
    required this.toMiddle,
  }) : targetX = restX,
       targetY = restY;

  final String phoneId;
  final String id;
  final Body body;

  final double restX;
  final double restY;
  final double dirX;
  final double dirY;

  final double toMiddle;

  _HippoPhase _phase = _HippoPhase.resting;
  double _t = 0;

  final _fingers = <int>{};

  double charge = 0;

  double reach = 0;

  double recoil = 0;
  double sway = 0;

  int ateThisLunge = 0;

  bool stunned = false;

  bool extendedThisTick = false;

  double targetX;
  double targetY;

  bool mouthOpen = false;

  double get lungeDistance =>
      toMiddle *
      _lerp(
        HungryHipposConfig.lungeFractionTap,
        HungryHipposConfig.lungeFractionFull,
        charge,
      );

  bool get passesThrough => _phase == _HippoPhase.out;

  String get status {
    if (_phase == _HippoPhase.charging) return 'c';
    if (stunned) return 's';
    return '';
  }

  void press(int pointer) {
    _fingers.add(pointer);
    if (_phase == _HippoPhase.resting) _startCharging();
  }

  void lift(int pointer) {
    _fingers.remove(pointer);
    if (_fingers.isEmpty && _phase == _HippoPhase.charging) _release();
  }

  void _startCharging() {
    _phase = _HippoPhase.charging;
    _t = 0;
    charge = 0;
  }

  void _release() {
    _phase = _HippoPhase.out;
    _t = 0;
    recoil = 0;
    sway = 0;
    ateThisLunge = 0;
    stunned = false;
  }

  void advance(double dt) {
    _t += dt;
    mouthOpen = false;
    extendedThisTick = false;
    switch (_phase) {
      case _HippoPhase.resting:
        reach = 0;
      case _HippoPhase.charging:
        reach = 0;
        charge = (_t / HungryHipposConfig.chargeFullSeconds).clamp(0.0, 1.0);
        recoil = HungryHipposConfig.chargeRecoil * charge;
        sway = math.sin(_t * 50) * HungryHipposConfig.chargeShake * charge;
        if (_t >= HungryHipposConfig.chargeMaxHoldSeconds) {
          _fingers.clear();
          _release();
        }
      case _HippoPhase.out:
        final seconds = _lerp(
          HungryHipposConfig.lungeOutSecondsTap,
          HungryHipposConfig.lungeOutSecondsFull,
          charge,
        );
        final p = (_t / seconds).clamp(0.0, 1.0);
        reach = p;

        mouthOpen = p >= 1 - HungryHipposConfig.mouthOpenFraction;
        if (p >= 1) {
          extendedThisTick = true;
          _phase = _HippoPhase.back;
          _t = 0;
        }
      case _HippoPhase.back:
        final seconds = _lerp(
          HungryHipposConfig.lungeBackSecondsTap,
          HungryHipposConfig.lungeBackSecondsFull,
          charge,
        );
        final p = (_t / seconds).clamp(0.0, 1.0);
        reach = 1 - p;
        if (p >= 1) {
          _phase = _HippoPhase.recovering;
          _t = 0;
        }
      case _HippoPhase.recovering:
        reach = 0;
        final wait =
            _lerp(
              HungryHipposConfig.recoverSecondsTap,
              HungryHipposConfig.recoverSecondsFull,
              charge,
            ) +
            (stunned ? HungryHipposConfig.missStunSeconds : 0);
        if (_t >= wait) {
          stunned = false;
          _phase = _HippoPhase.resting;
          _t = 0;

          if (_fingers.isNotEmpty) _startCharging();
        }
    }
  }

  SoundHandle? holdSound;

  void reset() {
    _phase = _HippoPhase.resting;
    _t = 0;
    holdSound = null;
    _fingers.clear();
    charge = 0;
    reach = 0;
    recoil = 0;
    sway = 0;
    ateThisLunge = 0;
    stunned = false;
    extendedThisTick = false;
    mouthOpen = false;
    targetX = restX;
    targetY = restY;
  }
}

enum _HippoPhase { resting, charging, out, back, recovering }

class _Aim {
  const _Aim({
    required this.awayX,
    required this.awayY,
    required this.centreDistance,
    required this.toEdge,
  });

  final double awayX;
  final double awayY;

  final double centreDistance;

  final double toEdge;
}
