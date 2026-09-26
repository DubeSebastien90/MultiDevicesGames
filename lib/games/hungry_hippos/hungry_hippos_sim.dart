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

/// Marbles circling a shallow dish, and everyone lunging for them at once.
///
/// The board has no gravity. What it has instead is a **bowl**: every marble is
/// pulled toward the middle in proportion to how far out it is, which is what a
/// slice of a very large sphere does. On top of that the dish **turns**, a
/// gentle push along the rim that keeps the marbles circling on a ring rather
/// than piling up in the middle — so a marble comes round past each hippo at a
/// pace you can read, and a lunge is something you time.
///
/// Every player has a hippo at the rim of the table in front of them. Press to
/// charge it, let go to send it: a tap is a quick, short snap; a full charge
/// reaches the middle but is slow to launch and slow to recover. The jaws only
/// open at the end of the lunge, and whatever is just outside them is thrown
/// clear — which is how you steal a marble on its way to your neighbour. A
/// lunge that eats nothing leaves the hippo dazed, whatever it shoved.
///
/// One rule places all the hippos — out along the line from the middle of the
/// board through the middle of your phone — and each arrangement decides what
/// that means: an outer corner on a block of four, which is where the real toy
/// puts them.
class HungryHipposSim extends Forge2DGameSim {
  HungryHipposSim(super.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _buildHippos();
    _buildMarbles();
  }

  final math.Random _random;

  /// Which pitch of the boup a bite gets. Its own generator rather than
  /// [_random], so a sound cannot change how a seeded round deals.
  final _boupPick = math.Random(3);

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

  /// How long the dish has been empty. The round is called a moment after the
  /// last marble goes, not on the same tick, so everyone sees it swallowed.
  double _emptyFor = 0;

  bool get _over =>
      (_live.isEmpty && _emptyFor >= HungryHipposConfig.endDelaySeconds) ||
      _elapsed >= HungryHipposConfig.maxRoundSeconds;

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
          // The same for everyone, because they all start from the same place.
          // How much of it a lunge covers is up to the charge.
          toMiddle: along,
        ),
      );
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

  /// Every marble body, made once. Where they go is [_deal]'s business.
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

  /// Which way the dish turns this round: 1 or -1.
  double _swirlSign = 1;

  /// Puts every marble on the table, spread over a band of the dish and
  /// already circling — the round starts in motion rather than as a heap
  /// waiting for somebody to break it.
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

      // Square-rooted over the band's area so they spread evenly rather than
      // bunching at its inner edge.
      final r = math.sqrt(
        inner * inner + _random.nextDouble() * (outer * outer - inner * inner),
      );
      final a = _random.nextDouble() * 2 * math.pi;

      // The speed of a free orbit at that radius in this bowl, so each marble
      // starts on a path the dish would keep it on — give or take a little, so
      // they do not all travel in lockstep.
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

  /// The rim of the bowl. Settled once, while the hippos are placed, and
  /// published so the view draws the same circle the marbles were dealt into —
  /// this codebase has been bitten every time one fact had two implementations.
  double get dishRadius => _dishRadius;
  double _dishRadius = 1;

  /// How far a ray from the middle of a rectangle travels before it leaves,
  /// given half-extents and a unit direction.
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

  // ------------------------------------------------------------------ step

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

    // Swallowed *before* the physics runs, against the place each hippo is
    // about to be. A hippo is a solid kinematic body travelling most of the
    // board in a fraction of a second: let the step happen first and it punts
    // the marbles clear of its own mouth. Checking the target first means what
    // is in the jaws gets eaten, and only what is beside them gets shoved.
    _swallow();
    _shoveAndJudge();

    super.step(dt);

    // Awarded on the tick the round ends, not the one after: the platform stops
    // stepping the moment `outcome` goes non-null, so anything left for "next
    // time" never happens.
    if (_over) _awardOnce();
  }

  /// The bowl, and the slow turn of the dish.
  ///
  /// The pull is toward the middle, proportional to distance out — what a
  /// spherical dish gives. The swirl is a constant push along the rim; against
  /// the pull and the felt it holds every marble on a ring at
  /// [HungryHipposConfig.swirlRingFraction] of the dish. Worked out rather than
  /// tuned by hand: in a bowl of pull `k` an orbit of radius `r` runs at
  /// `r * sqrt(k)`, the felt takes `damping * v` off it, and that is exactly
  /// what the push puts back. Inside the ring a marble is going too fast for
  /// its orbit and drifts out; outside, too slow, and falls in.
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
      // No normalising for the pull: the distance *is* the slope.
      var fx = dx * HungryHipposConfig.bowlPull;
      var fy = dy * HungryHipposConfig.bowlPull;

      final r = math.sqrt(dx * dx + dy * dy);
      if (r > 1e-4) {
        // Square to the line from the middle, the same way round for everyone.
        fx += dy / r * swirl;
        fy -= dx / r * swirl;
      }
      body.applyForce(Vector2(fx * body.mass, fy * body.mass));
    }
  }

  /// Move each hippo: drawn back while charging, then out and back.
  void _driveHippos(double dt) {
    for (final h in _hippos) {
      final before = h._phase;
      h.advance(dt);
      _soundPhase(h, before);

      // Solid everywhere but on the way out. A lunge that knocked marbles
      // aside on the way in threw away the very marbles it was aimed at before
      // the jaws had opened: now the mouth decides what happens to what is in
      // its path, and the body only shoves on the way home.
      h.body.fixtures.first.setSensor(h.passesThrough);

      final along = h.reach * h.lungeDistance - h.recoil;
      final wantX = h.restX + h.dirX * along - h.dirY * h.sway;
      final wantY = h.restY + h.dirY * along + h.dirX * h.sway;
      h.targetX = wantX;
      h.targetY = wantY;

      // Driven by velocity rather than teleported: a kinematic body that is
      // moved by setting its transform passes straight through whatever is in
      // the way, and knocking marbles about is half of what a hippo is for.
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
        // A boup a marble, each at one of its pitches, so a mouthful of three
        // is three bites rather than one note played three times.
        final bites = Sounds.buttonPress;
        _playFor(h, bites[_boupPick.nextInt(bites.length)]);
      }
      h.ateThisLunge += swallowed.length;
    }
  }

  /// At full stretch: throw clear whatever is just outside the jaws, then
  /// decide whether that lunge was a miss.
  ///
  /// After [_swallow], so a marble is either eaten or shoved, never both.
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
        // Keep a little of where it was already going, so a shove bends a
        // marble's path rather than replacing it.
        final v = body.linearVelocity;
        body.linearVelocity = Vector2(
          v.x * 0.4 + dx * speed,
          v.y * 0.4 + dy * speed,
        );
      }

      _shoves++;
      _lastShove[h.phoneId] =
          '$_shoves:${mouthX.toStringAsFixed(2)}:${mouthY.toStringAsFixed(2)}';

      // Nothing swallowed is a miss, however many marbles went flying: a
      // shove is a bonus on top of a bite, not a way out of the penalty.
      if (h.ateThisLunge == 0) h.stunned = true;
    }
  }

  /// Counts every shove, so two from the same spot still read as two.
  int _shoves = 0;

  /// Where each hippo last shoved, for the view's flash: `count:x:y`. A string
  /// because shared state is diffed by value, and it changes once a lunge.
  final _lastShove = <String, String>{};

  // ----------------------------------------------------------------- input

  /// Press to charge your own hippo, let go to send it — wherever on your
  /// glass you happen to touch. There is nothing else on the screen to press,
  /// and asking someone to hit a target *and* time a lunge is one thing too
  /// many.
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

  // ----------------------------------------------------------------- sound

  /// The hold as a charge starts, and the shot as it is let go — however it
  /// happened: a finger, a press that was waiting out the recovery, or a
  /// charge held so long it went by itself.
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

  /// [cue] on [h]'s owner's phone, if somebody is sitting at it.
  SoundHandle? _playFor(_Hippo h, SoundCue cue) {
    final player = context.roster.byPhone(h.phoneId);
    if (player == null) return null;
    return context.audio.playOnPhone(player, cue);
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
    'secondsLeft': (HungryHipposConfig.maxRoundSeconds - _elapsed).ceil().clamp(
      0,
      999,
    ),
    // What each hippo is up to, for the picture: 'c' charging, 's' dazed after
    // a miss, '' otherwise. Changes a few times a lunge, never every tick.
    'hippos': {for (final h in _hippos) h.phoneId: h.status},
    'shoves': Map<String, String>.of(_lastShove),
  };

  // --------------------------------------------------------------- outcome

  /// What each phone was paid when the round ended.
  Map<String, int> _paid = const {};

  /// Marbles are counted as they go down and paid out here, on the placement
  /// ladder, once — so a round where the dish empties fast is worth no more to
  /// the evening than one where it does not.
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

    // Every player for themselves: nobody is eliminated and nobody is chasing
    // anybody, so there is no winner to name — just what your own hippo
    // managed. Built once, because `outcome` is polled several times a tick.
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

  // ----------------------------------------------------------------- reset

  @override
  void reset() {
    _elapsed = 0;
    _emptyFor = 0;
    _awarded = false;
    _paid = const {};
    // The latched verdict belongs to the round that just ended.
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
    required this.toMiddle,
  }) : targetX = restX,
       targetY = restY;

  final String phoneId;
  final String id;
  final Body body;

  /// Where it waits, and which way it goes.
  final double restX;
  final double restY;
  final double dirX;
  final double dirY;

  /// From here to the middle of the dish. A lunge covers a fraction of it,
  /// set by the charge, so every board size plays the same.
  final double toMiddle;

  _HippoPhase _phase = _HippoPhase.resting;
  double _t = 0;

  /// Fingers down on this phone right now.
  final _fingers = <int>{};

  /// 0 for a tap, 1 for a full charge. Grows while charging, then is fixed for
  /// the lunge it launched.
  double charge = 0;

  /// 0 at rest, 1 fully extended.
  double reach = 0;

  /// Drawn back while charging, and trembling — the tell everyone else reads.
  double recoil = 0;
  double sway = 0;

  /// What this lunge has eaten so far.
  int ateThisLunge = 0;

  /// Dazed after a miss: recovery takes longer.
  bool stunned = false;

  /// True on the one tick the lunge reaches full stretch — when the shove
  /// happens and the miss is judged.
  bool extendedThisTick = false;

  /// Where the body is being driven to this tick — and so where the mouth is
  /// about to be, which is what decides what it swallows.
  double targetX;
  double targetY;

  /// Whether the mouth is open this tick.
  ///
  /// Set inside [advance] rather than read off the phase: the tick where the
  /// lunge reaches full stretch is also the tick the phase turns around, and
  /// the deepest point of a lunge has to count — the bowl can leave marbles
  /// there, and a mouth that never covers it strands them.
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
          // Held too long: it goes anyway, and the finger still on the glass
          // does not start another one — that takes a fresh press.
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
        // Only at the end of the way out: timing, not sweeping.
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
          // A finger pressed a moment early is not thrown away.
          if (_fingers.isNotEmpty) _startCharging();
        }
    }
  }

  /// The hold playing while this hippo charges, so letting go can fade it.
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
