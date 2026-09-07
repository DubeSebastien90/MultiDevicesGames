import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import '../../sdk/contract/sim.dart';
import '../../sdk/model/world_rect.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';
import 'hungry_hippos_config.dart';

/// Marbles in a shallow dish, and everyone lunging for them at once.
///
/// The board has no gravity. What it has instead is a **bowl**: every marble is
/// pulled toward the middle in proportion to how far out it is, which is what a
/// slice of a very large sphere does. The radius is large on purpose — the dish
/// is nearly flat, so marbles drift back and mill about in the middle rather
/// than rolling to the centre like ball bearings in a saucer.
///
/// Every player has a hippo at the rim of the table in front of them, and a tap
/// sends it lunging in. One rule places all of them — out along the line from
/// the middle of the board through the middle of your phone — and each
/// arrangement decides what that means: an outer corner on a block of four,
/// which is where the real toy puts them.
///
/// This is the first game here where the seam is the *whole* board rather than
/// a line across it: marbles wander from screen to screen constantly, and the
/// physics never learns the gaps exist.
class HungryHipposSim extends Forge2DGameSim {
  HungryHipposSim(super.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _buildHippos();
    _buildMarbles();
  }

  final math.Random _random;

  final _hippos = <_Hippo>[];

  /// Marble ids still on the table. A marble that has been eaten is hidden, not
  /// destroyed — nothing is created or torn down mid-step.
  final _live = <String>{};

  final _eaten = <String, int>{};

  double _elapsed = 0;
  bool _awarded = false;
  GameOutcome? _outcome;

  double get _centreX => board.centerX;
  double get _centreY => board.centerY;

  bool get _over => _live.isEmpty || _elapsed >= HungryHipposConfig.maxRoundSeconds;

  /// How many marbles [phoneId] has swallowed this round.
  int eatenBy(String phoneId) => _eaten[phoneId] ?? 0;

  int get marblesLeft => _live.length;

  // ----------------------------------------------------------------- build

  /// One hippo per phone, all of them the same distance from the middle.
  ///
  /// Two decisions, and they are separate on purpose.
  ///
  /// **Which way** comes from the layout: out along the line from the middle of
  /// the table through the middle of your phone, so every hippo sits on its own
  /// glass on the side its player is sitting.
  ///
  /// **How far** does not. Every hippo waits exactly at the rim of the dish,
  /// however the phones happen to be arranged — so a lunge is the same length
  /// for everybody at the table, and the same game whether four are playing or
  /// six. Letting the distance fall out of the geometry put some players at a
  /// corner and others at an edge, which quietly made it a different game for
  /// each of them. A hippo does not have to be *in* the corner of its phone,
  /// only on it.
  void _buildHippos() {
    final placements = [
      for (final slice in context.slices) _aim(slice.viewport),
    ];

    // How far out any one of them could go before running off its own screen.
    // The tightest of those is what everyone has to live within.
    final headroom = placements
        .map((p) => p.centreDistance + p.toEdge - HungryHipposConfig.hippoInset)
        .fold<double>(double.infinity, math.min);

    // The dish takes what the board can spare, less a strip of each player's
    // own glass to say whose phone it is; and never so much that a hippo would
    // begin the round standing in it.
    final shortHalf = math.min(board.width, board.height) / 2;
    final byBoard = shortHalf - HungryHipposConfig.playerMarginWorld;
    final byHippos =
        headroom - HungryHipposConfig.hippoRadius - HungryHipposConfig.hippoClearance;
    _dishRadius = math.max(1.0, math.min(byBoard, byHippos));

    final restDistance = _dishRadius +
        HungryHipposConfig.hippoRadius +
        HungryHipposConfig.hippoClearance;

    for (var i = 0; i < context.slices.length; i++) {
      final slice = context.slices[i];
      final aim = placements[i];

      // On its own screen even if the board is a shape this arithmetic did not
      // expect — a hippo drawn onto somebody else's phone is worse than one
      // standing a little closer in than the rest.
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
          // Facing the dish they are all leaning into. Nothing in the physics
          // reads this — the fixture is a circle — but the character drawn on
          // top of it does, and a hippo turned away from the marbles would be
          // a picture that disagrees with the lunge.
          angle: math.atan2(-aim.awayY, -aim.awayX),
        ),
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: HungryHipposConfig.hippoRadius,
          ShapeProps.color: context.colorOf(slice.phoneId)?.value.toARGB32() ??
              HungryHipposConfig.colorHippoFallback,
          ShapeProps.player: slice.phoneId,
        },
      );
      body.createFixture(
        FixtureDef(
          CircleShape()..radius = HungryHipposConfig.hippoRadius,
          density: 1,
          friction: 0.1,
          restitution: 0.1,
        ),
      );

      _hippos.add(_Hippo(
        phoneId: slice.phoneId,
        id: id,
        body: body,
        restX: restX,
        restY: restY,
        dirX: -aim.awayX,
        dirY: -aim.awayY,
        // Right to the middle of the dish. The same for everyone, because they
        // all start from the same place.
        lungeDistance: along * HungryHipposConfig.lungeFraction,
      ));
      _eaten[slice.phoneId] = 0;
    }
  }

  /// Which way one phone faces, and how much room it has along that line.
  _Aim _aim(WorldRect rect) {
    var awayX = rect.centerX - _centreX;
    var awayY = rect.centerY - _centreY;
    var len = math.sqrt(awayX * awayX + awayY * awayY);
    if (len < 1e-6) {
      // A single phone centred on the board has no outward direction of its
      // own. Down is as good an answer as any, and better than dividing by
      // nothing.
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

  /// Marbles scattered in the middle, well short of anybody's reach.
  void _buildMarbles() {
    final spread = _scatterRadius();

    for (var i = 0; i < HungryHipposConfig.marbleCount; i++) {
      // Square-rooted so they spread evenly over the disc rather than bunching
      // in the middle, which is what a plain random radius does.
      final r = spread * math.sqrt(_random.nextDouble());
      final a = _random.nextDouble() * 2 * math.pi;

      final id = 'marble$i';
      final body = addBody(
        id,
        'marble',
        BodyDef(
          type: BodyType.dynamic,
          position: Vector2(_centreX + r * math.cos(a), _centreY + r * math.sin(a)),
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
      _live.add(id);
    }
  }

  /// The rim of the bowl. Settled once, while the hippos are placed, and
  /// published so the view draws the same circle the marbles were dealt into —
  /// this codebase has been bitten every time one fact had two implementations.
  double get dishRadius => _dishRadius;
  double _dishRadius = 1;

  /// How far a ray from the middle of a rectangle travels before it leaves,
  /// given half-extents and a unit direction.
  static double _edgeDistance(double halfW, double halfH, double dx, double dy) {
    final tx = dx.abs() < 1e-9 ? double.infinity : halfW / dx.abs();
    final ty = dy.abs() < 1e-9 ? double.infinity : halfH / dy.abs();
    return math.min(tx, ty);
  }

  /// Where the marbles are dealt — a heap in the middle, not spread to the rim.
  double _scatterRadius() =>
      dishRadius * HungryHipposConfig.scatterFraction;

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_over) {
      _awardOnce();
      return;
    }
    _elapsed += dt;

    _pullMarblesToTheMiddle();
    _driveHippos(dt);

    // Swallowed *before* the physics runs, against the place each hippo is
    // about to be. A hippo is a solid kinematic body travelling most of the
    // board in a sixth of a second: let the step happen first and it punts the
    // marbles clear of its own mouth, and a lunge dead through the heap eats
    // nothing at all. Checking the target first means what is in the way gets
    // eaten, and only what is beside it gets shoved.
    _swallow();

    super.step(dt);

    // Awarded on the tick the round ends, not the one after: the platform stops
    // stepping the moment `outcome` goes non-null, so anything left for "next
    // time" never happens.
    if (_over) _awardOnce();
  }

  /// The bowl. A pull toward the middle, proportional to distance out.
  void _pullMarblesToTheMiddle() {
    for (final id in _live) {
      final body = bodyOf(id);
      if (body == null) continue;
      final dx = _centreX - body.position.x;
      final dy = _centreY - body.position.y;
      // Proportional to displacement, which is what a spherical dish gives —
      // no normalising, because the distance *is* the slope.
      body.applyForce(Vector2(
        dx * HungryHipposConfig.bowlPull * body.mass,
        dy * HungryHipposConfig.bowlPull * body.mass,
      ));
    }
  }

  /// Move each hippo along its lunge, out and back.
  void _driveHippos(double dt) {
    for (final h in _hippos) {
      h.advance(dt);

      final target = h.reach * h.lungeDistance;
      final wantX = h.restX + h.dirX * target;
      final wantY = h.restY + h.dirY * target;
      h.targetX = wantX;
      h.targetY = wantY;

      // Driven by velocity rather than teleported: a kinematic body that is
      // moved by setting its transform passes straight through whatever is in
      // the way, and shoving the marbles aside is half of what a hippo is for.
      h.body.linearVelocity = Vector2(
        (wantX - h.body.position.x) / dt,
        (wantY - h.body.position.y) / dt,
      );
    }
  }

  /// Anything in an open mouth is gone.
  void _swallow() {
    for (final h in _hippos) {
      if (!h.mouthOpen) continue;

      final mouthX = h.targetX;
      final mouthY = h.targetY;
      const reach = HungryHipposConfig.mouthRadius;

      // Collected first: hiding a marble inside the loop would mutate the set
      // being walked.
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
        context.scores.award(h.phoneId, HungryHipposConfig.pointsPerMarble);
      }
    }
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down || _over) return;
    for (final h in _hippos) {
      // Your own hippo, wherever on your glass you happened to tap. There is
      // nothing else on the screen to press, and asking someone to hit a target
      // *and* time a lunge is one thing too many.
      if (h.phoneId == touch.phoneId) h.lunge();
    }
  }

  // ------------------------------------------------------------- snapshots

  @override
  Map<String, Object?> get sharedState => {
    'marblesLeft': _live.length,
    // Constant for the whole round, so it costs one value and never changes.
    'dish': double.parse(dishRadius.toStringAsFixed(3)),
    'over': _over,
    // Whole seconds: shared state is diffed every tick, and a value that always
    // differs is a packet sixty times a second.
    'secondsLeft':
        (HungryHipposConfig.maxRoundSeconds - _elapsed).ceil().clamp(0, 999),
  };

  // --------------------------------------------------------------- outcome

  void _awardOnce() {
    // Points are awarded as marbles are eaten, so there is nothing to pay out
    // here. This exists to make the round's end idempotent.
    _awarded = true;
  }

  @override
  GameOutcome? get outcome {
    if (!_over) return null;
    if (!_awarded) return null;

    // Every player for themselves: nobody is eliminated and nobody is chasing
    // anybody, so there is no winner to name — just what your own hippo
    // managed. Built once, because `outcome` is polled several times a tick.
    return _outcome ??= GameOutcome.perPhone(
      {
        for (final h in _hippos) h.phoneId: _lineFor(h.phoneId),
      },
      summary: _summary(),
    );
  }

  String _lineFor(String phoneId) {
    final n = eatenBy(phoneId);
    if (n == 0) return 'Your hippo went hungry';
    return 'You ate $n marble${n == 1 ? '' : 's'}';
  }

  String _summary() {
    final total = _eaten.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 'not a single marble';
    return '$total of ${HungryHipposConfig.marbleCount} marbles gone';
  }

  // ----------------------------------------------------------------- reset

  @override
  void reset() {
    _elapsed = 0;
    _awarded = false;
    // The latched verdict belongs to the round that just ended.
    _outcome = null;

    for (final h in _hippos) {
      h.reset();
      h.body
        ..setTransform(Vector2(h.restX, h.restY), 0)
        ..linearVelocity = Vector2.zero();
    }

    for (final key in _eaten.keys.toList()) {
      _eaten[key] = 0;
    }

    _live.clear();
    final spread = _scatterRadius();
    for (var i = 0; i < HungryHipposConfig.marbleCount; i++) {
      final id = 'marble$i';
      final body = bodyOf(id);
      if (body == null) continue;

      final r = spread * math.sqrt(_random.nextDouble());
      final a = _random.nextDouble() * 2 * math.pi;
      show(id);
      body
        ..setTransform(
          Vector2(_centreX + r * math.cos(a), _centreY + r * math.sin(a)),
          0,
        )
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      _live.add(id);
    }
  }
}

/// One player's hippo, and where it is in its lunge.
class _Hippo {
  _Hippo({
    required this.phoneId,
    required this.id,
    required this.body,
    required this.restX,
    required this.restY,
    required this.dirX,
    required this.dirY,
    required this.lungeDistance,
  })  : targetX = restX,
        targetY = restY;

  final String phoneId;
  final String id;
  final Body body;

  /// Where it waits, and which way it goes.
  final double restX;
  final double restY;
  final double dirX;
  final double dirY;

  /// How far this hippo travels when it lunges — its own distance to the
  /// middle, scaled, so every board size plays the same.
  final double lungeDistance;

  _HippoPhase _phase = _HippoPhase.resting;
  double _t = 0;

  /// 0 at rest, 1 fully extended.
  double reach = 0;

  /// Where the body is being driven to this tick — and so where the mouth is
  /// about to be, which is what decides what it swallows.
  double targetX;
  double targetY;

  /// Whether the mouth is open this tick.
  ///
  /// Set inside [advance] rather than read off the phase, and that is the whole
  /// point: the tick where the lunge reaches full stretch is also the tick the
  /// phase turns around, so asking "is the phase still `out`?" answered no at
  /// exactly the moment the hippo was deepest. That left a small disc at the
  /// very middle of the dish that no mouth ever covered — and the bowl gathers
  /// stragglers into precisely that spot, so every round ended with a few
  /// marbles sitting in the centre that nobody could reach.
  ///
  /// Only on the way out, so a hippo still cannot hoover marbles up on the way
  /// home: the lunge has to be aimed.
  bool mouthOpen = false;

  bool get canLunge => _phase == _HippoPhase.resting;

  void lunge() {
    if (!canLunge) return;
    _phase = _HippoPhase.out;
    _t = 0;
  }

  void advance(double dt) {
    _t += dt;
    mouthOpen = false;
    switch (_phase) {
      case _HippoPhase.resting:
        reach = 0;
      case _HippoPhase.out:
        final p = (_t / HungryHipposConfig.lungeOutSeconds).clamp(0.0, 1.0);
        reach = p;
        // Open for every tick of the lunge, this one included — even when it
        // is the one that turns the hippo around.
        mouthOpen = true;
        if (p >= 1) {
          _phase = _HippoPhase.back;
          _t = 0;
        }
      case _HippoPhase.back:
        final p = (_t / HungryHipposConfig.lungeBackSeconds).clamp(0.0, 1.0);
        reach = 1 - p;
        if (p >= 1) {
          _phase = _HippoPhase.cooling;
          _t = 0;
        }
      case _HippoPhase.cooling:
        reach = 0;
        if (_t >= HungryHipposConfig.lungeCooldownSeconds) {
          _phase = _HippoPhase.resting;
          _t = 0;
        }
    }
  }

  void reset() {
    _phase = _HippoPhase.resting;
    _t = 0;
    reach = 0;
    mouthOpen = false;
    targetX = restX;
    targetY = restY;
  }
}

enum _HippoPhase { resting, out, back, cooling }

/// Which way a phone faces from the middle of the table, and how much of its
/// own glass lies along that line.
class _Aim {
  const _Aim({
    required this.awayX,
    required this.awayY,
    required this.centreDistance,
    required this.toEdge,
  });

  /// Unit vector from the middle of the board toward this phone.
  final double awayX;
  final double awayY;

  /// How far the phone's own middle is from the middle of the board.
  final double centreDistance;

  /// How far that direction runs from the phone's middle before it leaves.
  final double toEdge;
}
