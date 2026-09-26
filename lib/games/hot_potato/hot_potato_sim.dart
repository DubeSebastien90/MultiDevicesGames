import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/audio/tone.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/render/shape_view.dart';
import 'hot_potato_config.dart';

/// Pass the potato before the fuse runs out.
///
/// **No physics.** This is the first game to extend [GameSim] directly rather
/// than the Forge2D base class, and it is the proof that the contract meant it:
/// there is nothing here to integrate — no forces, no contacts, no gravity. The
/// whole world is "who is holding it" and "how long is left".
///
/// It still uses an *entity* for the potato, and that is the distinction worth
/// keeping straight. Physics is optional; the platform's interpolation is not.
/// Because the potato is an entity, easing it from one phone to the next makes
/// it visibly slide across the table on every screen at once, in step, for the
/// price of a lerp.
///
/// **Juggled, not held.** The holder's two hands toss it back and forth, faster
/// and faster as the fuse burns. A swipe does not throw it on the spot: it is
/// thrown the next time it lands in a hand. That is the animation and the rule
/// at once — the potato is never somewhere a hand could not have sent it from.
/// All of that motion is worked out here, on the host, and sent as plain
/// transforms, so every screen juggles in step.
class HotPotatoSim implements GameSim {
  HotPotatoSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _startRound();
  }

  final BoardContext context;
  final math.Random _random;

  /// The seats, in the order they actually sit around the ring.
  ///
  /// Worked out from where the screens ended up, not taken from the order the
  /// board hands them over. `planBoard` does place them clockwise, but the
  /// compiler sorts the compiled board into reading order — top to bottom, left
  /// to right — which is the right answer for a row and meaningless for a ring.
  /// On four phones that put `slices[1]` and `slices[2]` on *opposite sides of
  /// the table*, so "pass to your neighbour" threw the potato straight across
  /// it. Three players hid the fault completely, because in a triangle every
  /// phone is next to every other.
  late final List<int> _ring = _seatsByAngle();

  /// Slice indices sorted by their angle about the middle of the board.
  List<int> _seatsByAngle() {
    final cx = context.board.centerX;
    final cy = context.board.centerY;
    return [for (var i = 0; i < context.slices.length; i++) i]..sort((a, b) {
      final sa = context.slices[a].screen;
      final sb = context.slices[b].screen;
      return math
          .atan2(sa.centerY - cy, sa.centerX - cx)
          .compareTo(math.atan2(sb.centerY - cy, sb.centerX - cx));
    });
  }

  /// Phone ids in ring order — the passing order.
  List<String> get _order => [for (final i in _ring) context.slices[i].phoneId];

  /// Where each seat's hands are, in ring order. Fixed for the round.
  late final List<_Seat> _seats = [
    for (var i = 0; i < _ring.length; i++) _Seat.of(this, i),
  ];

  static const _potatoId = 'potato';
  static const _shadowId = 'potato-shadow';
  static const _blastId = 'blast';

  late int _holderIndex;

  /// Where the potato is on the *ground* — under it, where its shadow falls.
  late _Point _ground;

  /// How high above [_ground] it is, in world units.
  double _height = 0;

  /// Accumulated rather than `time × rate`: the rate climbs with the heat, and
  /// multiplying would make it lurch as the rate moved.
  double _spin = 0;

  // Juggling: from hand [_hand] toward the other one, [_hopT] of the way.
  int _hand = 0;
  double _hopT = 0;

  // Throwing: from [_throwFrom] to [_throwTo], on the way to a neighbour.
  bool _flying = false;
  _Point _throwFrom = const _Point(0, 0);
  _Point _throwTo = const _Point(0, 0);

  /// A swipe waiting for the potato to land in a hand: +1 or -1 round the
  /// ring, 0 for none.
  int _pendingStep = 0;

  double _fuseLeft = HotPotatoConfig.fuseSeconds;
  double _elapsed = 0;
  bool _exploded = false;
  bool _awarded = false;

  /// The holder's neighbours round the ring when it went off, if the ring is
  /// big enough for them to be anybody but everyone else.
  Set<String> _caught = const {};

  /// Sim time since the bang — the round is only called once it has played.
  double _sinceBlast = 0;

  /// Swipes in progress, by phone. A pass is a down and an up far enough apart.
  final _swipeStart = <String, _Point>{};

  /// The kettle tone playing now, and on which phone.
  SoundHandle _kettle = SoundHandle.none;
  String? _kettlePhone;

  String get holder => _order[_holderIndex];

  /// A throw is queued and goes at the next catch.
  bool get passPending => _pendingStep != 0;

  /// 0 when the fuse is lit, 1 when it goes off.
  double get _urgency => 1 - (_fuseLeft / HotPotatoConfig.fuseSeconds);

  int get _tick => (_elapsed * 60).round();

  // ----------------------------------------------------------------- seats

  /// The middle of a seat's screen.
  _Point _seatOf(int index) {
    final slice = _sliceAt(index);
    return _Point(slice.screen.centerX, slice.screen.centerY);
  }

  /// The screen sitting at a place in the ring.
  PhoneSlice _sliceAt(int index) => context.slices[_ring[index % _ring.length]];

  /// Which way the next seat round the ring lies from this one.
  _Point _towardNeighbour(int from, int step) {
    final here = _seatOf(from);
    final there = _seatOf((from + step + _ring.length) % _ring.length);
    return (there - here).unit(orElse: const _Point(1, 0));
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (_exploded) return;
    // Only the phone actually holding it can pass it on.
    if (touch.phoneId != holder) return;

    switch (touch.phase) {
      case TouchPhase.down:
        _swipeStart[touch.phoneId] = _Point(touch.worldX, touch.worldY);

      case TouchPhase.up:
        final start = _swipeStart.remove(touch.phoneId);
        if (start == null) return;
        final dx = touch.worldX - start.x;
        final dy = touch.worldY - start.y;
        if (math.sqrt(dx * dx + dy * dy) < HotPotatoConfig.minSwipeWorld) {
          return; // A tap, not a throw.
        }
        // Latest swipe wins: changing your mind mid-hop is allowed.
        _pendingStep = _stepForSwipe(dx, dy);
    }
  }

  /// Which way round the ring a swipe goes, up or down the holder's screen.
  ///
  /// **Up and down, not left and right**, and the phones are the reason. They
  /// lie with their long edge along the rim, so each screen's top points *along*
  /// the ring — which makes up and down the two ways round it, and left and
  /// right the two ways across it. Comparing a left-right swipe against the two
  /// neighbours gave each of them exactly the same score, on any number of
  /// players: a tie broken by rounding error, which is why passing felt random.
  ///
  /// Which of up or down leads to which neighbour is read off the geometry
  /// rather than assumed from the angle the layout chose, so this keeps working
  /// if the ring is ever built the other way round.
  int _stepForSwipe(double dx, double dy) {
    final up = _screenUpOf(_holderIndex);
    final toNext = _towardNeighbour(_holderIndex, 1);
    final toPrev = _towardNeighbour(_holderIndex, -1);

    final upLeadsToNext = up.dot(toNext) > up.dot(toPrev);
    final swipedUp = dx * up.x + dy * up.y >= 0;

    return swipedUp == upLeadsToNext ? 1 : -1;
  }

  /// Which way "toward the top of the screen" points, in the world, for the
  /// phone at this seat.
  _Point _screenUpOf(int index) {
    final turn = _sliceAt(index).screen.turnRadians;
    // Screen space has y growing downward, so the top is (0, -1) turned into
    // the world by the phone's own angle.
    return _Point(math.sin(turn), -math.cos(turn));
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    _elapsed += dt;
    if (_exploded) {
      _sinceBlast += dt;
      return;
    }

    _fuseLeft = math.max(0, _fuseLeft - dt);

    // Out of fuse in somebody's hands: it goes now. Out of fuse mid-throw: it
    // does not — nobody should lose to a potato that went off in the air
    // between two phones. It keeps flying, and goes off the instant it lands
    // in the catcher's hand (see [_landed]).
    if (_fuseLeft == 0 && !_flying) {
      _explode();
      return;
    }

    final u = _urgency;
    _spin +=
        dt *
        _lerp(HotPotatoConfig.spinCalm, HotPotatoConfig.spinFrantic, u * u);

    if (_flying) {
      _stepThrow(dt);
    } else {
      _stepJuggle(dt, u);
    }
    _updateKettle(u);
  }

  /// The bang, wherever the potato is sitting — always in a hand.
  void _explode() {
    _exploded = true;
    // The whistle stops dead: that is what makes the bang land.
    context.audio.stopSound(_kettle);
    _kettle = SoundHandle.none;
    _kettlePhone = null;
    _playHere(HotPotatoConfig.explosion);

    // Award once, here rather than in `outcome` — that getter is polled more
    // than once a tick, and points must not be charged twice.
    if (!_awarded) {
      _awarded = true;
      _payOut();
    }
  }

  // ----------------------------------------------------------------- sound

  /// The phone whose screen the potato is over, for the one-off sounds. In a
  /// gap between screens it falls back to the holder — though every one-off
  /// sound happens at a hand, which is always on a screen.
  String get _phoneUnderPotato {
    final at = _drawnAt;
    return context.phoneAt(at.x, at.y) ?? holder;
  }

  /// [cue], once, on the phone the potato is over. Silence if that phone has
  /// nobody seated at it.
  void _playHere(SoundCue cue) {
    final player = context.roster.byPhone(_phoneUnderPotato);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

  /// Keeps the kettle on the holder's phone, and only while they hold it.
  ///
  /// It glides on its own — the phone moves the pitch every frame — so the
  /// only thing to do here is start and stop it: silent from the throw to the
  /// catch, then picked up on the catcher's phone at the pitch the fuse has
  /// reached by then.
  void _updateKettle(double u) {
    final phone = _flying ? null : holder;
    if (phone == _kettlePhone) return;

    context.audio.stopSound(_kettle, fade: HotPotatoConfig.kettleHandover);
    _kettle = SoundHandle.none;
    _kettlePhone = phone;
    if (phone == null) return;
    final player = context.roster.byPhone(phone);
    if (player == null) return;
    _kettle = context.audio.playToneOnPhone(player, kettleFrom(u, _fuseLeft));
  }

  /// The kettle from fuse progress [u] to the bang, [secondsLeft] away.
  ///
  /// Exponential in pitch, the same curve [Tone] glides along, so a kettle
  /// restarted halfway on another phone lands exactly on the one it replaced.
  static Tone kettleFrom(double u, double secondsLeft) => Tone(
    fromHz:
        HotPotatoConfig.kettleLowHz *
        math.pow(
          HotPotatoConfig.kettleHighHz / HotPotatoConfig.kettleLowHz,
          u.clamp(0.0, 1.0),
        ),
    toHz: HotPotatoConfig.kettleHighHz,
    glide: Duration(milliseconds: (secondsLeft * 1000).round()),
    volume: _lerp(
      HotPotatoConfig.kettleVolumeCalm,
      HotPotatoConfig.kettleVolumeFrantic,
      u,
    ),
    toVolume: HotPotatoConfig.kettleVolumeFrantic,
  );

  void _stepJuggle(double dt, double u) {
    final seat = _seats[_holderIndex];
    final hopSeconds = _lerp(
      HotPotatoConfig.hopSecondsCalm,
      HotPotatoConfig.hopSecondsFrantic,
      u,
    );
    _hopT += dt / hopSeconds;

    if (_hopT >= 1) {
      // Landed in the other hand. That is the moment a queued throw goes.
      _hopT = 0;
      _hand = 1 - _hand;
      _ground = seat.hands[_hand];
      _height = 0;
      _landed();
      return;
    }

    final from = seat.hands[_hand];
    final to = seat.hands[1 - _hand];
    _ground = from.lerp(to, _easeInOut(_hopT));
    _height =
        math.sin(math.pi * _hopT) *
        _lerp(HotPotatoConfig.hopArcCalm, HotPotatoConfig.hopArcFrantic, u);
  }

  /// It has just touched a hand — a hop, or a catch. Out it goes if a swipe is
  /// waiting, with a woosh; otherwise it stays, with a boing. Either way the
  /// sound comes from the phone it landed on, before [_throw] moves the holder.
  void _landed() {
    // Caught after the fuse ran out in the air: it goes off in this hand, and
    // this player is the one holding it.
    if (_fuseLeft == 0) {
      _explode();
      return;
    }
    if (_pendingStep != 0) {
      _playHere(HotPotatoConfig.woosh);
      _throw();
    } else {
      _playHere(HotPotatoConfig.boing);
    }
  }

  /// Off the hand it just landed in, toward the nearer hand of a neighbour.
  void _throw() {
    final step = _pendingStep;
    _pendingStep = 0;

    _throwFrom = _ground;
    _holderIndex = (_holderIndex + step + _ring.length) % _ring.length;
    // Thrown to the next seat, it lands in that seat's hand facing back — the
    // "previous" hand. Thrown the other way, the "next" one.
    _hand = step > 0 ? 0 : 1;
    _throwTo = _seats[_holderIndex].hands[_hand];
    _flying = true;
  }

  void _stepThrow(double dt) {
    final toGo = _throwTo - _ground;
    final stepLength = math.min(toGo.length, HotPotatoConfig.passSpeed * dt);
    _ground = _ground + toGo.unit() * stepLength;

    final remaining = (_throwTo - _ground).length;
    if (remaining <= 1e-6) {
      // Caught. Juggling carries on from this hand — and landing in a hand
      // counts as a contact, so a swipe made mid-flight goes straight back out.
      _flying = false;
      _ground = _throwTo;
      _height = 0;
      _hopT = 0;
      _landed();
      return;
    }

    final total = (_throwTo - _throwFrom).length;
    final progress = total < 1e-6 ? 1.0 : 1 - remaining / total;
    _height = math.sin(math.pi * progress) * HotPotatoConfig.throwArc;
  }

  /// The bang, in points: nothing for the holder, half for whoever sits either
  /// side of them, and the full prize for everybody clear of it.
  void _payOut() {
    final order = _order;
    final n = order.length;
    _caught = n > 3
        ? {order[(_holderIndex + 1) % n], order[(_holderIndex - 1 + n) % n]}
        : const {};
    for (final id in order) {
      if (id == holder) continue;
      context.scores.award(
        id,
        _caught.contains(id)
            ? HotPotatoConfig.caughtInBlastPoints
            : HotPotatoConfig.clearOfBlastPoints,
      );
    }
  }

  void _startRound() {
    _fuseLeft = HotPotatoConfig.fuseSeconds;
    _elapsed = 0;
    _exploded = false;
    _awarded = false;
    _caught = const {};
    _sinceBlast = 0;
    _swipeStart.clear();
    // The platform has already stopped every sound of the last round; only
    // the bookkeeping is left, so the first step starts the kettle afresh.
    _kettle = SoundHandle.none;
    _kettlePhone = null;
    _pendingStep = 0;
    _flying = false;
    _spin = 0;
    _holderIndex = _random.nextInt(_ring.length);
    _hand = _random.nextInt(2);
    _hopT = 0;
    _ground = _seats[_holderIndex].hands[_hand];
    _height = 0;
  }

  @override
  void reset() {
    _startRound();
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
  }

  // ------------------------------------------------------------- snapshots

  /// Where the potato is drawn: its height shown as a nudge toward the middle
  /// of the table, which from any seat is "away from me", which reads as up.
  _Point get _drawnAt {
    final middle = _Point(context.board.centerX, context.board.centerY);
    final inward = (middle - _ground).unit(orElse: const _Point(0, -1));
    return _ground + inward * (_height * HotPotatoConfig.heightShown);
  }

  @override
  Iterable<Entity> get entities sync* {
    // Everybody's arms, all the time: the potato always has hands to land in.
    for (var i = 0; i < _seats.length; i++) {
      for (var h = 0; h < 2; h++) {
        yield _seats[i].arm(h, bob: _bobOf(i, h));
      }
    }

    if (_exploded) {
      // A new id rather than a new kind: descriptors are sent once, when an
      // entity first appears, so a potato that *became* a blast would stay a
      // potato on every screen but the host's.
      yield Entity(
        descriptor: const EntityDescriptor(
          id: _blastId,
          kind: 'blast',
          props: {
            ShapeProps.shape: ShapeKind.circle,
            ShapeProps.radius:
                HotPotatoConfig.potatoRadius * HotPotatoConfig.blastScale,
            ShapeProps.color: HotPotatoConfig.colorBlast,
          },
        ),
        x: _ground.x,
        y: _ground.y,
      );
      return;
    }

    yield Entity(
      descriptor: const EntityDescriptor(id: _shadowId, kind: 'shadow'),
      x: _ground.x,
      y: _ground.y,
    );

    // The heat — colour, swell, smoke — is not in here: props are sent once,
    // so anything that changes over the round is read by the view off the fuse
    // in `sharedState`. Only the spin rides the transform.
    final at = _drawnAt;
    yield Entity(
      descriptor: const EntityDescriptor(
        id: _potatoId,
        kind: 'potato',
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: HotPotatoConfig.potatoRadius,
          ShapeProps.color: HotPotatoConfig.colorPotato,
          ShapeProps.spin: true,
        },
      ),
      x: at.x,
      y: at.y,
      angle: _spin,
    );
  }

  /// How far a hand is bobbing: the holder's hands give as they catch and
  /// flick as they throw. Nobody else's move.
  double _bobOf(int seat, int hand) {
    if (_exploded || _flying || seat != _holderIndex) return 0;
    // Just thrown from this hand, or about to catch in it.
    final t = hand == _hand ? _hopT : 1 - _hopT;
    const window = 0.3;
    if (t >= window) return 0;
    final k = 1 - t / window;
    return k * k * HotPotatoConfig.handBob;
  }

  @override
  Map<String, Object?> get sharedState => {
    'holder': holder,
    'secondsLeft': double.parse(_fuseLeft.toStringAsFixed(2)),
    'fuse': HotPotatoConfig.fuseSeconds,
    'exploded': _exploded,
    'tick': _tick,
  };

  @override
  GameOutcome? get outcome {
    if (!_exploded) return null;
    // Let the bang play first. The points were already charged at the bang;
    // this only holds back the results screen.
    if (_sinceBlast < HotPotatoConfig.blastHoldSeconds) return null;

    // Everyone clear of the blast; the holder and whoever sat beside them
    // were not. Built once — `outcome` is polled several times a tick.
    return _outcome ??= GameOutcome.contest(
      winners: {
        for (final id in _order)
          if (id != holder && !_caught.contains(id)) id,
      },
      summary: 'the potato went off',
      lines: {
        for (final id in _order)
          id: id == holder
              ? 'You were holding it — +0 pts'
              : _caught.contains(id)
              ? 'Caught in the blast — '
                    '+${HotPotatoConfig.caughtInBlastPoints} pts'
              : 'Clear of the blast — '
                    '+${HotPotatoConfig.clearOfBlastPoints} pts',
      },
    );
  }

  GameOutcome? _outcome;

  @override
  void dispose() {}
}

/// One seat's two hands, and the arms that reach them.
///
/// The player sits on the outside of the ring, so the arms come in from the
/// screen's outer edge. Hand 0 is on the side of the previous seat round the
/// ring and hand 1 the next: the potato juggles along the same line it is
/// thrown along.
class _Seat {
  _Seat(this.phoneId, this.hands, this.shoulders, this.isLeft, this.outward);

  factory _Seat.of(HotPotatoSim sim, int index) {
    final slice = sim._sliceAt(index);
    final screen = slice.screen;
    final centre = _Point(screen.centerX, screen.centerY);
    final middle = _Point(sim.context.board.centerX, sim.context.board.centerY);

    final outward = (centre - middle).unit(orElse: const _Point(0, 1));
    // Along the rim, toward the next seat.
    var along = _Point(-outward.y, outward.x);
    if (along.dot(sim._towardNeighbour(index, 1)) < 0) along = along * -1;

    // How far the screen reaches from its middle in a world direction.
    final c = math.cos(screen.turnRadians);
    final s = math.sin(screen.turnRadians);
    double reach(_Point d) =>
        (d.x * c + d.y * s).abs() * screen.width / 2 +
        (-d.x * s + d.y * c).abs() * screen.height / 2;
    final halfAlong = reach(along);
    final halfOut = reach(outward);

    _Point hand(double side) =>
        centre + along * (side * halfAlong * 0.4) + outward * (halfOut * 0.05);
    // Straight back from the hand and just off the screen: the arm is drawn
    // to fill the distance, so its cut end is never seen.
    _Point shoulder(double side) =>
        centre +
        along * (side * halfAlong * 0.4) +
        outward * (halfOut + HotPotatoConfig.shoulderOffscreen);

    // The player sits outside the ring looking in, so their right is a quarter
    // turn from outward. Whichever hand lies that way is their right hand.
    final right = _Point(outward.y, -outward.x);
    final leftSide = along.dot(right) > 0 ? -1.0 : 1.0;

    return _Seat(
      slice.phoneId,
      [hand(-1), hand(1)],
      [shoulder(-1), shoulder(1)],
      [leftSide == -1, leftSide == 1],
      outward,
    );
  }

  final String phoneId;
  final List<_Point> hands;
  final List<_Point> shoulders;

  /// Which of [hands] is the player's left, from where they sit.
  final List<bool> isLeft;
  final _Point outward;

  /// From shoulder to hand, pulled back toward the player by [bob].
  Entity arm(int hand, {double bob = 0}) {
    final from = shoulders[hand];
    final to = hands[hand];
    final reach = to - from;
    final mid = from.lerp(to, 0.5) + outward * bob;
    return Entity(
      descriptor: EntityDescriptor(
        id: 'arm-$phoneId-$hand',
        kind: 'arm',
        props: {
          ShapeProps.shape: ShapeKind.box,
          ShapeProps.width: reach.length,
          // Whose arm, so it is drawn in their colour, and which one, so the
          // right hand is drawn as a right hand.
          HotPotatoConfig.propSeat: phoneId,
          HotPotatoConfig.propLeft: isLeft[hand],
        },
      ),
      x: mid.x,
      y: mid.y,
      angle: math.atan2(reach.y, reach.x),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

double _easeInOut(double t) => t * t * (3 - 2 * t);

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;

  _Point operator +(_Point o) => _Point(x + o.x, y + o.y);
  _Point operator -(_Point o) => _Point(x - o.x, y - o.y);
  _Point operator *(double k) => _Point(x * k, y * k);

  double dot(_Point o) => x * o.x + y * o.y;
  double get length => math.sqrt(x * x + y * y);

  _Point unit({_Point orElse = const _Point(0, 0)}) {
    final l = length;
    return l < 1e-9 ? orElse : _Point(x / l, y / l);
  }

  _Point lerp(_Point o, double t) =>
      _Point(x + (o.x - x) * t, y + (o.y - y) * t);
}
