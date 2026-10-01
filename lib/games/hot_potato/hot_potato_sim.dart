import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/audio/tone.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/render/shape_view.dart';
import 'hot_potato_config.dart';

class HotPotatoSim implements GameSim {
  HotPotatoSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _startRound();
  }

  final BoardContext context;
  final math.Random _random;

  late final List<int> _ring = _seatsByAngle();

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

  List<String> get _order => [for (final i in _ring) context.slices[i].phoneId];

  late final List<_Seat> _seats = [
    for (var i = 0; i < _ring.length; i++) _Seat.of(this, i),
  ];

  static const _potatoId = 'potato';
  static const _shadowId = 'potato-shadow';
  static const _blastId = 'blast';

  late int _holderIndex;

  late _Point _ground;

  double _height = 0;

  double _spin = 0;

  int _hand = 0;
  double _hopT = 0;

  bool _flying = false;
  _Point _throwFrom = const _Point(0, 0);
  _Point _throwTo = const _Point(0, 0);

  int _pendingStep = 0;

  int _hopsHere = 0;

  bool get canPass => _hopsHere >= HotPotatoConfig.hopsBeforePass;

  int get hopsHere => _hopsHere;

  bool get inFlight => _flying;

  double _fuseLeft = HotPotatoConfig.fuseSeconds;
  double _elapsed = 0;
  bool _exploded = false;
  bool _awarded = false;

  Set<String> _caught = const {};

  double _sinceBlast = 0;

  final _swipeStart = <String, _Point>{};

  SoundHandle _kettle = SoundHandle.none;
  String? _kettlePhone;

  String get holder => _order[_holderIndex];

  bool get passPending => _pendingStep != 0;

  double get _urgency => 1 - (_fuseLeft / HotPotatoConfig.fuseSeconds);

  int get _tick => (_elapsed * 60).round();

  _Point _seatOf(int index) {
    final slice = _sliceAt(index);
    return _Point(slice.screen.centerX, slice.screen.centerY);
  }

  PhoneSlice _sliceAt(int index) => context.slices[_ring[index % _ring.length]];

  _Point _towardNeighbour(int from, int step) {
    final here = _seatOf(from);
    final there = _seatOf((from + step + _ring.length) % _ring.length);
    return (there - here).unit(orElse: const _Point(1, 0));
  }

  @override
  void onTouch(TouchEvent touch) {
    if (_exploded) return;

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
          return;
        }

        _pendingStep = _stepForSwipe(dx, dy);
    }
  }

  int _stepForSwipe(double dx, double dy) {
    final up = _screenUpOf(_holderIndex);
    final toNext = _towardNeighbour(_holderIndex, 1);
    final toPrev = _towardNeighbour(_holderIndex, -1);

    final upLeadsToNext = up.dot(toNext) > up.dot(toPrev);
    final swipedUp = dx * up.x + dy * up.y >= 0;

    return swipedUp == upLeadsToNext ? 1 : -1;
  }

  _Point _screenUpOf(int index) {
    final turn = _sliceAt(index).screen.turnRadians;

    return _Point(math.sin(turn), -math.cos(turn));
  }

  @override
  void step(double dt) {
    _elapsed += dt;
    if (_exploded) {
      _sinceBlast += dt;
      return;
    }

    _fuseLeft = math.max(0, _fuseLeft - dt);

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

    if (_exploded) return;
    _updateKettle(u);
  }

  void _explode() {
    _exploded = true;

    context.audio.stopSound(_kettle);
    _kettle = SoundHandle.none;
    _kettlePhone = null;
    _playHere(HotPotatoConfig.explosion);

    if (!_awarded) {
      _awarded = true;
      _payOut();
    }
  }

  String get _phoneUnderPotato {
    final at = _drawnAt;
    return context.phoneAt(at.x, at.y) ?? holder;
  }

  void _playHere(SoundCue cue) {
    final player = context.roster.byPhone(_phoneUnderPotato);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

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
      _hopT = 0;
      _hand = 1 - _hand;
      _ground = seat.hands[_hand];
      _height = 0;
      _hopsHere++;
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

  void _landed() {
    if (_fuseLeft == 0) {
      _explode();
      return;
    }

    if (_pendingStep != 0 && canPass) {
      _playHere(HotPotatoConfig.woosh);
      _throw();
    } else {
      _playHere(HotPotatoConfig.boing);
    }
  }

  void _throw() {
    final step = _pendingStep;
    _pendingStep = 0;

    _throwFrom = _ground;
    _holderIndex = (_holderIndex + step + _ring.length) % _ring.length;

    _hand = step > 0 ? 0 : 1;
    _throwTo = _seats[_holderIndex].hands[_hand];
    _flying = true;

    _hopsHere = 0;
  }

  void _stepThrow(double dt) {
    final toGo = _throwTo - _ground;
    final stepLength = math.min(toGo.length, HotPotatoConfig.passSpeed * dt);
    _ground = _ground + toGo.unit() * stepLength;

    final remaining = (_throwTo - _ground).length;
    if (remaining <= 1e-6) {
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

    _kettle = SoundHandle.none;
    _kettlePhone = null;
    _pendingStep = 0;
    _hopsHere = 0;
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

    _outcome = null;
  }

  _Point get _drawnAt {
    final middle = _Point(context.board.centerX, context.board.centerY);
    final inward = (middle - _ground).unit(orElse: const _Point(0, -1));
    return _ground + inward * (_height * HotPotatoConfig.heightShown);
  }

  @override
  Iterable<Entity> get entities sync* {
    for (var i = 0; i < _seats.length; i++) {
      for (var h = 0; h < 2; h++) {
        yield _seats[i].arm(h, bob: _bobOf(i, h));
      }
    }

    if (_exploded) {
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

  double _bobOf(int seat, int hand) {
    if (_exploded || _flying || seat != _holderIndex) return 0;

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

    if (_sinceBlast < HotPotatoConfig.blastHoldSeconds) return null;

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

class _Seat {
  _Seat(this.phoneId, this.hands, this.shoulders, this.isLeft, this.outward);

  factory _Seat.of(HotPotatoSim sim, int index) {
    final slice = sim._sliceAt(index);
    final screen = slice.screen;
    final centre = _Point(screen.centerX, screen.centerY);
    final middle = _Point(sim.context.board.centerX, sim.context.board.centerY);

    final outward = (centre - middle).unit(orElse: const _Point(0, 1));

    var along = _Point(-outward.y, outward.x);
    if (along.dot(sim._towardNeighbour(index, 1)) < 0) along = along * -1;

    final c = math.cos(screen.turnRadians);
    final s = math.sin(screen.turnRadians);
    double reach(_Point d) =>
        (d.x * c + d.y * s).abs() * screen.width / 2 +
        (-d.x * s + d.y * c).abs() * screen.height / 2;
    final halfAlong = reach(along);
    final halfOut = reach(outward);

    _Point hand(double side) =>
        centre + along * (side * halfAlong * 0.4) + outward * (halfOut * 0.05);

    _Point shoulder(double side) =>
        centre +
        along * (side * halfAlong * 0.4) +
        outward * (halfOut + HotPotatoConfig.shoulderOffscreen);

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

  final List<bool> isLeft;
  final _Point outward;

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
