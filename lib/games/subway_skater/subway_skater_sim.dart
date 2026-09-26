import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/score/scoreboard.dart';
import 'subway_skater_config.dart';

/// A corridor down a line of phones, and a queue of people running it.
///
/// The board is the corridor: three lanes across it, obstacles entering at one
/// end and travelling to the other at a constant speed. Each player stands at
/// the downstream edge of one phone, so an obstacle crossing that phone is the
/// warning they get, and every player in the line gets the same warning.
///
/// **The line is the game.** Where you stand is worth points every tick — the
/// front of the line is worth the most and the back is worth nothing — and the
/// front is also where obstacles arrive first. Being clipped tumbles you the
/// whole length of the corridor to the back and moves everybody behind you up
/// one, so the order churns and nobody holds the front for a whole minute.
///
/// **Your phone steers your runner, wherever they are in the line.** The one
/// you joined on is yours for the whole round: climb a place or tumble to the
/// back and it is still your colour your swipes move, on whichever screen it
/// happens to be standing.
///
/// One other thing worth stating, because it looks like a bug otherwise: a
/// skater is only hittable while standing still at its post. Tumbling and
/// closing up the line are both invulnerable, or the shuffle after a hit would
/// be a second punishment for the people it rewards.
class SubwaySkaterSim implements GameSim {
  SubwaySkaterSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _build();
  }

  final BoardContext context;
  final math.Random _random;

  /// Whether a car honks. Its own generator rather than [_random], so the
  /// sounds cannot change which waves a seeded round deals.
  final _honkDice = math.Random(4);

  final _skaters = <String, _Skater>{};

  /// Who is where, front of the line first. Slot *i* stands at the downstream
  /// edge of the *i*th phone.
  final _order = <String>[];

  final _obstacles = <_Obstacle>[];

  /// What is left of the blocks somebody has run through. Cosmetic, and on the
  /// shared timeline like everything else, so the shatter happens at the same
  /// instant on every screen that can see it.
  final _bursts = <_Burst>[];

  /// The phones in board order, joined once — the front of the line first.
  String _boardOrder = '';

  double _elapsed = 0;
  double _nextSpawnAt = 0;

  bool _awarded = false;
  GameOutcome? _outcome;

  bool get _over => _elapsed >= SubwaySkaterConfig.roundSeconds;

  /// Seconds remaining, whole — `sharedState` is diffed every tick, and a raw
  /// float that always differs is a packet every tick.
  int get secondsLeft =>
      (SubwaySkaterConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  // ----------------------------------------------------------------- set-up

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

  /// Where slot [slot] stands: three fifths down its own phone.
  ///
  /// Read off the compiled board rather than divided out of the board's width,
  /// so a table of mismatched phones puts each player the same fraction into
  /// their *own* screen — which is what makes the warning the same length for
  /// everybody rather than the same number of centimetres.
  double _anchorX(int slot) {
    final slices = context.slices;
    final i = slot.clamp(0, slices.length - 1);
    final screen = slices[i].viewport;
    return screen.left + screen.width * SubwaySkaterConfig.standFraction;
  }

  double get _backAnchorX => _anchorX(_order.length - 1);

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (_over) return;
    _elapsed += dt;

    // Awarded on the very tick the round ends, not the one after: the platform
    // stops stepping as soon as `outcome` goes non-null, so anything left for
    // "next time" never happens.
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

  /// One or two lanes blocked, never all three.
  ///
  /// A lane is chosen to stay open first and the blocks are dealt out of what is
  /// left, so "there is always a way through" is a property of how the wave is
  /// built rather than something to check afterwards and hope about.
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

  /// [from] at the start of the round, [to] at the end of it.
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

  /// When a car's bonnet crosses onto a new phone, one time in
  /// [SubwaySkaterConfig.honkOneIn] it honks there. The gap between two
  /// screens is no phone at all, so it does not count as arriving anywhere.
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

  /// [cue] on [phoneId]'s phone, if somebody is sitting at it.
  void _playOn(String phoneId, SoundCue cue) {
    final player = context.roster.byPhone(phoneId);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

  /// [cue] on the phone under ([x], [y]), or the nearest one to it.
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
        // Carried along by the thing that hit you, the whole length of the
        // corridor, in full view of everyone you were ahead of.
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

      // Closing up the line, or sliding across to the lane you asked for.
      s.x = _toward(s.x, _anchorX(slot), SubwaySkaterConfig.climbSpeed * dt);
      s.y = _toward(
        s.y,
        SubwaySkaterConfig.laneCenter(board, s.lane),
        SubwaySkaterConfig.laneChangeSpeed * dt,
      );
      // Back on their feet, so they turn to face the way they are going. The
      // spin carries on the way it was already turning until it arrives — see
      // [_uprightFrom] for why it never winds backwards.
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

  /// The next angle at or after [spin] that faces up the corridor.
  ///
  /// Forward is every [SubwaySkaterConfig.facingAngle] plus a whole number of
  /// turns, and this picks the first one the spin has not already passed — so
  /// righting a skater always *finishes* the rotation it was in the middle of
  /// rather than unwinding it, and [_Skater.spin] keeps only ever growing,
  /// which is what stops an interpolated angle from spinning backwards across
  /// a snapshot.
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

  /// Only a skater standing still at its own post can be hit.
  ///
  /// Tumbling is obvious. Closing up the line is the one worth spelling out: a
  /// player who has just been promoted is sprinting up the corridor *through*
  /// the traffic that knocked the last person out, and clipping them for it
  /// would punish them for somebody else's mistake.
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
      // Re-read the slot every time: an earlier hit in this same tick may have
      // moved everybody along.
      for (var slot = 0; slot < _order.length; slot++) {
        final s = _skaters[_order[slot]]!;
        if (s.lane != o.lane) continue;
        if ((o.x - s.x).abs() > reach) continue;

        // Fresh off a promotion: they go through it. The second after climbing
        // a place is the one thing in this game that pays out for being in the
        // way rather than out of it.
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

    // The whole mechanic, in three lines: out of the line, on to the back, and
    // everyone who was behind is now one place further forward.
    _order.removeAt(slot);
    _order.add(s.phoneId);

    s.riding = o.id;
    s.tumbleFor = 0;
    s.chargeFor = 0;
    s.hits++;

    // Where it happened, before the car carries them off down the corridor.
    _playAt(s.x, s.y, SubwaySkaterConfig.crash);
    _playAt(s.x, s.y, SubwaySkaterConfig.knockedDown);
  }

  /// Leave a shatter where a block was flattened.
  ///
  /// The birth time rides in the descriptor rather than the shatter carrying a
  /// progress value that ticks: props are sent once, on spawn, and every phone
  /// already shares the clock they would be measured against. So the view
  /// subtracts one from the other and gets the same answer everywhere, with
  /// nothing on the wire per frame.
  ///
  /// Silently does nothing if the pool is empty — a missing puff of debris is
  /// not worth a frame of anybody's attention.
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

  /// Everybody behind [slot] is about to move up one, so hand them the second
  /// that comes with it.
  ///
  /// Read before the line is rearranged, because afterwards there is no way to
  /// tell who moved: the slots have already shifted under them.
  void _promoteBehind(int slot) {
    for (var i = slot + 1; i < _order.length; i++) {
      _skaters[_order[i]]!.chargeFor = SubwaySkaterConfig.chargeSeconds;
    }
  }

  /// Position-points, every tick, for everybody standing in the line.
  ///
  /// The back is worth nothing and each place forward is worth one more, so the
  /// front of a line of four is worth three a tick. A line of one is worth
  /// nothing to the one person in it, which needs no special case: there is
  /// nobody to be ahead of.
  void _scoreTick() {
    final n = _order.length;
    for (var slot = 0; slot < n; slot++) {
      _skaters[_order[slot]]!.raw += n - 1 - slot;
    }
  }

  // ---------------------------------------------------------------- scoring

  /// Every position-point anybody has earned this round.
  double get _totalRaw {
    var total = 0.0;
    for (final s in _skaters.values) {
      total += s.raw;
    }
    return total;
  }

  /// How much position-time [phoneId] has banked: one a tick for every
  /// skater behind them in the line.
  double positionTimeOf(String phoneId) => _skaters[phoneId]?.raw ?? 0;

  /// [phoneId]'s place on the shared ladder if the round ended now, and the
  /// only place the split is worked out.
  ///
  /// Ranked by position-time, the whole table including anybody who has left:
  /// what they banked before going is still theirs. Zero for everybody until
  /// somebody has been ahead of somebody — a line of one has earned nothing
  /// and has nobody to be ranked against.
  int pointsOf(String phoneId) {
    if (_totalRaw <= 0) return 0;
    return _placements()[phoneId] ?? 0;
  }

  Map<String, int> _placements() => Scoreboard.placements(
    Scoreboard.tiersBy({
      for (final id in context.phoneIds) id: positionTimeOf(id),
    }),
  );

  /// How many times [phoneId] has been clipped this round.
  int hitsOf(String phoneId) => _skaters[phoneId]?.hits ?? 0;

  /// How many blocks [phoneId] has run through on the way up the line.
  int smashesOf(String phoneId) => _skaters[phoneId]?.smashed ?? 0;

  void _awardOnce() {
    if (_awarded) return;
    _awarded = true;
    for (final id in context.phoneIds) {
      final points = pointsOf(id);
      if (points != 0) context.scores.award(id, points);
    }
  }

  // ------------------------------------------------------------------ input

  /// Where each finger started, so a drag can be measured against it.
  final _dragFrom = <String, double>{};

  /// Phones whose current drag has already moved its lane.
  final _dragSpent = <String>{};

  @override
  void onTouch(TouchEvent touch) {
    if (_over) return;

    // By owner, not by place: your phone steers your runner wherever in the
    // line they have got to.
    final s = _skaters[touch.phoneId];
    if (s == null) return;

    if (touch.phase == TouchPhase.down) {
      _dragFrom[touch.phoneId] = touch.worldY;
      _dragSpent.remove(touch.phoneId);
      return;
    }

    final from = _dragFrom[touch.phoneId];
    if (from == null) return;

    // One swipe, one lane — however far the finger carries on.
    //
    // It used to spend a lane for every stride of the threshold the drag
    // covered, which reads fine on paper and is unusable in the hand: a real
    // flick crosses several centimetres, so every swipe pinned you against the
    // far wall of the corridor and the middle lane could not be reached from
    // either side. Moving to the *next* lane is the whole vocabulary of the
    // game; crossing two is two swipes.
    if (!_dragSpent.contains(touch.phoneId)) {
      final delta = touch.worldY - from;
      if (delta.abs() >= SubwaySkaterConfig.swipeThreshold) {
        _dragSpent.add(touch.phoneId);
        // Not while being carried: you are not on your feet.
        if (s.riding == null) {
          final dir = delta.isNegative ? -1 : 1;
          final lane = (s.lane + dir).clamp(0, SubwaySkaterConfig.lanes - 1);
          // Only a real change: a swipe into the wall of the corridor goes
          // nowhere and says nothing.
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

  // -------------------------------------------------------------- snapshots

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

  /// Joined into strings rather than sent as lists, and that is not a style
  /// choice: the host diffs shared state value by value with `==`, and two Lists
  /// are never equal in Dart however identical their contents. A list here would
  /// be a packet to every phone sixty times a second.
  @override
  Map<String, Object?> get sharedState => {
    // The phones in board order, so a screen can work out which place in the
    // line it *is* — which is the question it has to answer to know which
    // circle its swipes move. Constant for the round: diffed once, then never
    // sent again.
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

  // ---------------------------------------------------------------- outcome

  @override
  GameOutcome? get outcome {
    if (!_over) return null;

    // Nobody wins a corridor. Everyone ran the same minute and the only thing
    // to report is how much of it each of them spent near the front. Built once
    // and kept: `outcome` is polled several times a tick.
    return _outcome ??= GameOutcome.perPhone({
      for (final id in context.phoneIds) id: _lineFor(id),
    }, summary: _summary());
  }

  String _lineFor(String phoneId) {
    final points = pointsOf(phoneId);
    final hits = hitsOf(phoneId);
    final smashed = smashesOf(phoneId);
    // Cars now, not blocks: run over by them, and wrecking them when charged.
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

  // ------------------------------------------------------------------ reset

  @override
  void reset() {
    _dragFrom.clear();
    _dragSpent.clear();
    _build();
  }

  @override
  void dispose() {}
}

/// One player, wherever in the line they currently are.
class _Skater {
  _Skater({required this.phoneId, required this.descriptor});

  final String phoneId;
  final EntityDescriptor descriptor;

  /// Where the circle actually is, which is not always where its slot says it
  /// should be — it takes a moment to close up the line, and a tumble takes it
  /// somewhere else entirely. Collision reads this, not the slot.
  double x = 0;
  double y = 0;

  /// The lane it has committed to. The dodge counts from the instant of the
  /// swipe; [y] catches up over the next fraction of a second.
  int lane = 0;

  /// Which obstacle is carrying it to the back, if any.
  String? riding;
  double tumbleFor = 0;
  double graceFor = 0;

  /// Seconds left of the second that comes with climbing a place: untouchable,
  /// and smashing anything it runs into.
  double chargeFor = 0;

  /// Only ever grows, so interpolating it across a snapshot never has to cross
  /// a wrap and spin the circle backwards for a frame.
  ///
  /// Starts facing up the corridor, which is where it returns to after every
  /// tumble: a skater is looking where they are going for all of the round
  /// except the seconds they are being carried backwards.
  double spin = SubwaySkaterConfig.facingAngle;

  double raw = 0;
  int hits = 0;
  int smashed = 0;
}

/// A car coming down a lane.
///
/// The descriptor is rebuilt on every launch, like [_Burst]'s, because which
/// car it is lives in it: the platform sends props on spawn, and a pooled id
/// coming back is a spawn, so every phone draws the same car for it.
class _Obstacle {
  _Obstacle(this.id, {required this.height})
    : descriptor = EntityDescriptor(id: id, kind: 'obstacle');

  final String id;
  final double height;
  EntityDescriptor descriptor;

  bool active = false;
  double x = 0;
  int lane = 0;

  /// The phone its bonnet is on, for telling when it arrives on the next.
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

/// What is left of a block somebody ran through.
///
/// The descriptor is rebuilt on every lighting rather than made once, because
/// the birth time is in it — the platform sends props on spawn, and a pooled id
/// coming back is a spawn, so each shatter arrives stamped with its own moment.
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
