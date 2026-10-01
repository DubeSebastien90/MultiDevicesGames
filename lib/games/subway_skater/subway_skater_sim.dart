import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/score/scoreboard.dart';
import 'subway_skater_config.dart';

class SubwaySkaterSim implements GameSim {
  SubwaySkaterSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _build();
  }

  final BoardContext context;
  final math.Random _random;

  final _honkDice = math.Random(4);

  final _skaters = <String, _Skater>{};

  final _order = <String>[];

  final _obstacles = <_Obstacle>[];

  final _bursts = <_Burst>[];

  String _boardOrder = '';

  double _elapsed = 0;
  double _nextSpawnAt = 0;

  bool _awarded = false;
  GameOutcome? _outcome;

  bool get _over => _elapsed >= SubwaySkaterConfig.roundSeconds;

  int get secondsLeft =>
      (SubwaySkaterConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  void _build() {
    final board = context.board;
    final middle = SubwaySkaterConfig.lanes ~/ 2;

    _skaters.clear();
    _order.clear();
    for (var i = 0; i < context.slices.length; i++) {
      final slice = context.slices[i];
      final skater =
          _Skater(
              phoneId: slice.phoneId,
              descriptor: EntityDescriptor(
                id: 'skater-${slice.phoneId}',
                kind: 'skater',
                props: {
                  'phone': slice.phoneId,
                  'color': slice.color?.id,
                  'r': SubwaySkaterConfig.skaterRadius,
                },
              ),
            )
            ..lane = middle
            ..y = SubwaySkaterConfig.laneCenter(board, middle);
      skater.x = _anchorX(i);
      _skaters[slice.phoneId] = skater;
      _order.add(slice.phoneId);
    }
    _boardOrder = _order.join(',');

    _obstacles
      ..clear()
      ..addAll([
        for (var i = 0; i < SubwaySkaterConfig.obstaclePool; i++)
          _Obstacle(
            'block$i',
            height:
                SubwaySkaterConfig.laneHeight(board) *
                SubwaySkaterConfig.obstacleLaneFraction,
          ),
      ]);

    _bursts
      ..clear()
      ..addAll([
        for (var i = 0; i < SubwaySkaterConfig.burstPool; i++)
          _Burst('burst$i'),
      ]);

    _elapsed = 0;
    _nextSpawnAt = SubwaySkaterConfig.leadInSeconds;
    _awarded = false;
    _outcome = null;
  }

  double _anchorX(int slot) {
    final slices = context.slices;
    final i = slot.clamp(0, slices.length - 1);
    final screen = slices[i].viewport;
    return screen.left + screen.width * SubwaySkaterConfig.standFraction;
  }

  double get _backAnchorX => _anchorX(_order.length - 1);

  @override
  void step(double dt) {
    if (_over) return;
    _elapsed += dt;

    if (_over) {
      _awardOnce();
      return;
    }

    _spawnDue();
    _moveObstacles(dt);
    _moveSkaters(dt);
    _collide();
    _fadeBursts();
    _scoreTick();
  }

  void _fadeBursts() {
    for (final burst in _bursts) {
      if (!burst.active) continue;
      if (_elapsed * 1000 - burst.bornMs >=
          SubwaySkaterConfig.burstSeconds * 1000) {
        burst.active = false;
      }
    }
  }

  void _spawnDue() {
    if (_elapsed < _nextSpawnAt) return;
    _launchWave();
    _nextSpawnAt =
        _elapsed +
        _ramp(
          SubwaySkaterConfig.firstSpawnGap,
          SubwaySkaterConfig.lastSpawnGap,
        );
  }

  void _launchWave() {
    final open = _random.nextInt(SubwaySkaterConfig.lanes);
    final blocked = [
      for (var lane = 0; lane < SubwaySkaterConfig.lanes; lane++)
        if (lane != open) lane,
    ]..shuffle(_random);

    final double chance = _ramp(
      SubwaySkaterConfig.firstDoubleChance,
      SubwaySkaterConfig.lastDoubleChance,
    );
    final count = _random.nextDouble() < chance ? 2 : 1;

    final startX = context.board.left - SubwaySkaterConfig.obstacleLength;
    for (final lane in blocked.take(count)) {
      final free = _obstacles.where((o) => !o.active);
      if (free.isEmpty) return;
      free.first.launch(
        lane: lane,
        x: startX,
        car: _random.nextInt(SubwaySkaterConfig.carModels),
      );
    }
  }

  double _ramp(double from, double to) {
    final t = (_elapsed / SubwaySkaterConfig.roundSeconds).clamp(0.0, 1.0);
    return from + (to - from) * t;
  }

  void _moveObstacles(double dt) {
    final limit = context.board.right + SubwaySkaterConfig.obstacleLength * 2;
    final speed = SubwaySkaterConfig.speedAt(_elapsed);
    for (final o in _obstacles) {
      if (!o.active) continue;
      o.x += speed * dt;
      if (o.x > limit) o.active = false;
      if (o.active) _honkOnArrival(o);
    }
  }

  void _honkOnArrival(_Obstacle o) {
    final front = o.x + SubwaySkaterConfig.obstacleLength / 2;
    final y = SubwaySkaterConfig.laneCenter(context.board, o.lane);
    final phone = context.phoneAt(front, y);
    if (phone == null || phone == o.onPhone) return;
    o.onPhone = phone;
    if (_honkDice.nextInt(SubwaySkaterConfig.honkOneIn) == 0) {
      _playOn(phone, SubwaySkaterConfig.honk);
    }
  }

  void _playOn(String phoneId, SoundCue cue) {
    final player = context.roster.byPhone(phoneId);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

  void _playAt(double x, double y, SoundCue cue) {
    final phone = context.nearestPhone(x, y);
    if (phone != null) _playOn(phone, cue);
  }

  void _moveSkaters(double dt) {
    final board = context.board;

    for (var slot = 0; slot < _order.length; slot++) {
      final s = _skaters[_order[slot]]!;

      final riding = s.riding == null ? null : _obstacleById(s.riding!);
      if (riding != null && riding.active) {
        s.tumbleFor += dt;
        s.x = riding.x;
        s.lane = riding.lane;
        s.y = SubwaySkaterConfig.laneCenter(board, riding.lane);
        s.spin += SubwaySkaterConfig.speedAt(_elapsed) * dt;

        final done =
            s.tumbleFor >= SubwaySkaterConfig.minTumbleSeconds &&
            (riding.x >= _backAnchorX ||
                s.tumbleFor >= SubwaySkaterConfig.maxTumbleSeconds);
        if (done) _land(s);
        continue;
      }
      if (riding != null) _land(s);

      s.x = _toward(s.x, _anchorX(slot), SubwaySkaterConfig.climbSpeed * dt);
      s.y = _toward(
        s.y,
        SubwaySkaterConfig.laneCenter(board, s.lane),
        SubwaySkaterConfig.laneChangeSpeed * dt,
      );

      s.spin = _toward(
        s.spin,
        _uprightFrom(s.spin),
        SubwaySkaterConfig.rightingSpeed * dt,
      );
      if (s.graceFor > 0) s.graceFor = math.max(0, s.graceFor - dt);
      if (s.chargeFor > 0) s.chargeFor = math.max(0, s.chargeFor - dt);
    }
  }

  void _land(_Skater s) {
    s.riding = null;
    s.tumbleFor = 0;
    s.graceFor = SubwaySkaterConfig.graceSeconds;
  }

  static double _uprightFrom(double spin) {
    const turn = 2 * math.pi;
    final turns = ((spin - SubwaySkaterConfig.facingAngle) / turn).ceil();
    return SubwaySkaterConfig.facingAngle + turns * turn;
  }

  static double _toward(double value, double target, double step) {
    final delta = target - value;
    if (delta.abs() <= step) return target;
    return value + (delta.isNegative ? -step : step);
  }

  _Obstacle? _obstacleById(String id) {
    for (final o in _obstacles) {
      if (o.id == id) return o;
    }
    return null;
  }

  bool _isVulnerable(_Skater s, int slot) =>
      s.riding == null &&
      s.graceFor <= 0 &&
      s.chargeFor <= 0 &&
      (s.x - _anchorX(slot)).abs() < 1e-6;

  void _collide() {
    final reach =
        SubwaySkaterConfig.skaterRadius + SubwaySkaterConfig.obstacleLength / 2;

    for (final o in _obstacles) {
      if (!o.active) continue;

      for (var slot = 0; slot < _order.length; slot++) {
        final s = _skaters[_order[slot]]!;
        if (s.lane != o.lane) continue;
        if ((o.x - s.x).abs() > reach) continue;

        if (s.chargeFor > 0) {
          o.active = false;
          s.smashed++;
          _shatter(o);
          _playAt(s.x, s.y, SubwaySkaterConfig.crash);
          break;
        }

        if (!_isVulnerable(s, slot)) continue;
        _knockDown(s, o);
        break;
      }
    }
  }

  void _knockDown(_Skater s, _Obstacle o) {
    final slot = _order.indexOf(s.phoneId);
    if (slot < 0) return;

    _promoteBehind(slot);

    _order.removeAt(slot);
    _order.add(s.phoneId);

    s.riding = o.id;
    s.tumbleFor = 0;
    s.chargeFor = 0;
    s.hits++;

    _playAt(s.x, s.y, SubwaySkaterConfig.crash);
    _playAt(s.x, s.y, SubwaySkaterConfig.knockedDown);
  }

  void _shatter(_Obstacle o) {
    for (final burst in _bursts) {
      if (burst.active) continue;
      burst.light(
        x: o.x,
        y: SubwaySkaterConfig.laneCenter(context.board, o.lane),
        bornMs: _elapsed * 1000,
        size:
            SubwaySkaterConfig.laneHeight(context.board) *
            SubwaySkaterConfig.obstacleLaneFraction,
        tilt: _random.nextDouble() * math.pi,
      );
      return;
    }
  }

  void _promoteBehind(int slot) {
    for (var i = slot + 1; i < _order.length; i++) {
      _skaters[_order[i]]!.chargeFor = SubwaySkaterConfig.chargeSeconds;
    }
  }

  void _scoreTick() {
    final n = _order.length;
    for (var slot = 0; slot < n; slot++) {
      _skaters[_order[slot]]!.raw += n - 1 - slot;
    }
  }

  double get _totalRaw {
    var total = 0.0;
    for (final s in _skaters.values) {
      total += s.raw;
    }
    return total;
  }

  double positionTimeOf(String phoneId) => _skaters[phoneId]?.raw ?? 0;

  int pointsOf(String phoneId) {
    if (_totalRaw <= 0) return 0;
    return _placements()[phoneId] ?? 0;
  }

  Map<String, int> _placements() => Scoreboard.placements(
    Scoreboard.tiersBy({
      for (final id in context.phoneIds) id: positionTimeOf(id),
    }),
  );

  int hitsOf(String phoneId) => _skaters[phoneId]?.hits ?? 0;

  int smashesOf(String phoneId) => _skaters[phoneId]?.smashed ?? 0;

  void _awardOnce() {
    if (_awarded) return;
    _awarded = true;
    for (final id in context.phoneIds) {
      final points = pointsOf(id);
      if (points != 0) context.scores.award(id, points);
    }
  }

  final _dragFrom = <String, double>{};

  final _dragSpent = <String>{};

  @override
  void onTouch(TouchEvent touch) {
    if (_over) return;

    final s = _skaters[touch.phoneId];
    if (s == null) return;

    if (touch.phase == TouchPhase.down) {
      _dragFrom[touch.phoneId] = touch.worldY;
      _dragSpent.remove(touch.phoneId);
      return;
    }

    final from = _dragFrom[touch.phoneId];
    if (from == null) return;

    if (!_dragSpent.contains(touch.phoneId)) {
      final delta = touch.worldY - from;
      if (delta.abs() >= SubwaySkaterConfig.swipeThreshold) {
        _dragSpent.add(touch.phoneId);

        if (s.riding == null) {
          final dir = delta.isNegative ? -1 : 1;
          final lane = (s.lane + dir).clamp(0, SubwaySkaterConfig.lanes - 1);

          if (lane != s.lane) {
            s.lane = lane;
            _playOn(touch.phoneId, SubwaySkaterConfig.woosh);
          }
        }
      }
    }

    if (touch.phase == TouchPhase.up) {
      _dragFrom.remove(touch.phoneId);
      _dragSpent.remove(touch.phoneId);
    }
  }

  @override
  Iterable<Entity> get entities sync* {
    final board = context.board;
    for (final o in _obstacles) {
      if (!o.active) continue;
      yield Entity(
        descriptor: o.descriptor,
        x: o.x,
        y: SubwaySkaterConfig.laneCenter(board, o.lane),
        vx: SubwaySkaterConfig.obstacleSpeed,
      );
    }
    for (final burst in _bursts) {
      if (!burst.active) continue;
      yield Entity(
        descriptor: burst.descriptor!,
        x: burst.x,
        y: burst.y,
        angle: burst.tilt,
      );
    }
    for (final id in _order) {
      final s = _skaters[id]!;
      yield Entity(descriptor: s.descriptor, x: s.x, y: s.y, angle: s.spin);
    }
  }

  @override
  Map<String, Object?> get sharedState => {
    'phones': _boardOrder,
    'order': _order.join(','),
    'tumbling': [
      for (final id in _order)
        if (_skaters[id]!.riding != null) id,
    ].join(','),
    'charging': [
      for (final id in _order)
        if (_skaters[id]!.chargeFor > 0) id,
    ].join(','),
    'secondsLeft': secondsLeft,
    'over': _over,
  };

  @override
  GameOutcome? get outcome {
    if (!_over) return null;

    return _outcome ??= GameOutcome.perPhone({
      for (final id in context.phoneIds) id: _lineFor(id),
    }, summary: _summary());
  }

  String _lineFor(String phoneId) {
    final points = pointsOf(phoneId);
    final hits = hitsOf(phoneId);
    final smashed = smashesOf(phoneId);

    final tail = smashed == 0
        ? ''
        : ', $smashed car${smashed == 1 ? '' : 's'} wrecked';
    if (hits == 0) return 'You scored $points, never run over$tail';
    return 'You scored $points, run over $hits time${hits == 1 ? '' : 's'}$tail';
  }

  String _summary() {
    final ranked = [
      for (final id in context.phoneIds) (id: id, points: pointsOf(id)),
    ]..sort((a, b) => b.points.compareTo(a.points));

    if (ranked.isEmpty || ranked.first.points == 0) {
      return 'nobody held the front for long';
    }
    if (ranked.length > 1 && ranked[0].points == ranked[1].points) {
      return 'the line never settled';
    }
    final label =
        context.scores.view.entryFor(ranked.first.id)?.label ?? ranked.first.id;
    return '$label led the line, ${ranked.first.points} points';
  }

  @override
  void reset() {
    _dragFrom.clear();
    _dragSpent.clear();
    _build();
  }

  @override
  void dispose() {}
}

class _Skater {
  _Skater({required this.phoneId, required this.descriptor});

  final String phoneId;
  final EntityDescriptor descriptor;

  double x = 0;
  double y = 0;

  int lane = 0;

  String? riding;
  double tumbleFor = 0;
  double graceFor = 0;

  double chargeFor = 0;

  double spin = SubwaySkaterConfig.facingAngle;

  double raw = 0;
  int hits = 0;
  int smashed = 0;
}

class _Obstacle {
  _Obstacle(this.id, {required this.height})
    : descriptor = EntityDescriptor(id: id, kind: 'obstacle');

  final String id;
  final double height;
  EntityDescriptor descriptor;

  bool active = false;
  double x = 0;
  int lane = 0;

  String? onPhone;

  void launch({required int lane, required double x, required int car}) {
    this.lane = lane;
    this.x = x;
    onPhone = null;
    active = true;
    descriptor = EntityDescriptor(
      id: id,
      kind: 'obstacle',
      props: {'w': SubwaySkaterConfig.obstacleLength, 'h': height, 'car': car},
    );
  }
}

class _Burst {
  _Burst(this.id);

  final String id;
  EntityDescriptor? descriptor;

  bool active = false;
  double x = 0;
  double y = 0;
  double bornMs = 0;
  double tilt = 0;

  void light({
    required double x,
    required double y,
    required double bornMs,
    required double size,
    required double tilt,
  }) {
    this.x = x;
    this.y = y;
    this.bornMs = bornMs;
    this.tilt = tilt;
    active = true;
    descriptor = EntityDescriptor(
      id: id,
      kind: 'burst',
      props: {'born': bornMs, 'size': size},
    );
  }
}
