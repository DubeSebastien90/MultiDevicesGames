import 'dart:math' as math;

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/audio/sounds.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/model/player_color.dart';
import '../../sdk/score/scoreboard.dart';
import 'guacamole_config.dart';

class Hole {
  const Hole({
    required this.index,
    required this.phoneId,
    required this.centerX,
    required this.centerY,
    required this.radius,
  });

  final int index;

  final String phoneId;

  final double centerX;
  final double centerY;

  final double radius;
}

enum MolePhase { rising, up, sinking, squished }

class _Mole {
  _Mole(this.id);

  final String id;

  bool live = false;
  Hole? hole;
  PlayerColor? owner;
  MolePhase phase = MolePhase.rising;

  double t = 0;

  double upSeconds = GuacamoleConfig.visibleSecondsStart;
}

class GuacamoleSim implements GameSim {
  GuacamoleSim(this.context, {math.Random? random})
    : _random = random ?? math.Random() {
    _holes = _buildHoles(context.slices);
    _players = context.players;
    _pool = [
      for (var i = 0; i < GuacamoleConfig.poolSize(_players.length); i++)
        _Mole('mole$i'),
    ];
  }

  final BoardContext context;
  final math.Random _random;

  final _soundPick = math.Random(9);

  int _lastVoice = -1;

  late final List<Hole> _holes;
  late final List<PlayerColor> _players;
  late final List<_Mole> _pool;

  double _elapsed = 0;
  double _sinceSpawn = 0;

  final _squished = <String, int>{};

  Map<String, int> _paid = const {};

  int squishedBy(String phoneId) => _squished[phoneId] ?? 0;

  final _bag = <PlayerColor>[];

  int get playerCount => _players.length;
  List<Hole> get holes => _holes;
  double get secondsLeft =>
      math.max(0, GuacamoleConfig.roundSeconds - _elapsed);

  static List<Hole> _buildHoles(List<PhoneSlice> slices) {
    final holes = <Hole>[];
    var index = 0;

    for (final slice in slices) {
      final v = slice.viewport;
      final inset = GuacamoleConfig.holeInset;
      final usable = v.inflate(-math.min(v.width, v.height) * inset);

      final cellW = usable.width / 2;
      final cellH = usable.height / 2;
      final radius =
          math.min(cellW, cellH) * GuacamoleConfig.moleRadiusFraction;

      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 2; col++) {
          holes.add(
            Hole(
              index: index++,
              phoneId: slice.phoneId,
              centerX: usable.left + cellW * (col + 0.5),
              centerY: usable.top + cellH * (row + 0.5),
              radius: radius,
            ),
          );
        }
      }
    }
    return holes;
  }

  @override
  void step(double dt) {
    if (outcome != null) return;

    _elapsed += dt;

    if (_elapsed >= GuacamoleConfig.roundSeconds) {
      _paid = context.scores.awardPlacements(
        Scoreboard.tiersBy({
          for (final id in context.phoneIds) id: squishedBy(id),
        }),
      );
      return;
    }

    for (final mole in _pool) {
      if (mole.live) _advance(mole, dt);
    }

    _sinceSpawn += dt;
    if (_sinceSpawn >= _spawnGap) {
      _sinceSpawn = 0;
      if (_liveCount < _targetLive) _spawn();
    }
  }

  void _advance(_Mole mole, double dt) {
    mole.t += dt;
    switch (mole.phase) {
      case MolePhase.rising:
        if (mole.t >= GuacamoleConfig.riseSeconds) {
          mole.phase = MolePhase.up;
          mole.t = 0;
        }
      case MolePhase.up:
        if (mole.t >= mole.upSeconds) {
          mole.phase = MolePhase.sinking;
          mole.t = 0;
        }
      case MolePhase.sinking:
        if (mole.t >= GuacamoleConfig.sinkSeconds) _retire(mole);
      case MolePhase.squished:
        if (mole.t >= GuacamoleConfig.squishSeconds) _retire(mole);
    }
  }

  double get _ramp {
    final t = GuacamoleConfig.roundSeconds * GuacamoleConfig.rampFraction;
    if (t <= 0) return 1;
    return (_elapsed / t).clamp(0.0, 1.0);
  }

  double get _spawnGap =>
      _lerp(GuacamoleConfig.spawnGapStart, GuacamoleConfig.spawnGapEnd, _ramp);

  double get _upSeconds => _lerp(
    GuacamoleConfig.visibleSecondsStart,
    GuacamoleConfig.visibleSecondsEnd,
    _ramp,
  );

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  int get _liveCount {
    var n = 0;
    for (final m in _pool) {
      if (m.live && m.phase != MolePhase.squished) n++;
    }
    return n;
  }

  int get _targetLive =>
      math.max(1, (playerCount * GuacamoleConfig.moleTargetPerPlayer).round());

  void _spawn() {
    if (_holes.isEmpty || _players.isEmpty) return;

    final mole = _freeMole();
    if (mole == null) return;

    final hole = _freeHole();
    if (hole == null) return;

    mole
      ..live = true
      ..hole = hole
      ..owner = _nextOwner()
      ..phase = MolePhase.rising
      ..t = 0
      ..upSeconds = _upSeconds;

    final voices = GuacamoleConfig.voices;
    var voice = _soundPick.nextInt(voices.length);
    if (voice == _lastVoice) voice = (voice + 1) % voices.length;
    _lastVoice = voice;
    _playOn(hole.phoneId, voices[voice]);
  }

  void _playOn(String phoneId, SoundCue cue) {
    final player = context.roster.byPhone(phoneId);
    if (player != null) context.audio.playOnPhone(player, cue);
  }

  _Mole? _freeMole() {
    for (final m in _pool) {
      if (!m.live) return m;
    }
    return null;
  }

  Hole? _freeHole() {
    final occupied = <int>{
      for (final m in _pool)
        if (m.live && m.hole != null) m.hole!.index,
    };
    if (occupied.length >= _holes.length) return null;

    final free = [
      for (final h in _holes)
        if (!occupied.contains(h.index)) h,
    ];
    return free[_random.nextInt(free.length)];
  }

  PlayerColor _nextOwner() {
    if (_bag.isEmpty) {
      _bag.addAll(_players);
      _bag.shuffle(_random);
    }
    return _bag.removeLast();
  }

  void _retire(_Mole mole) {
    mole
      ..live = false
      ..hole = null
      ..owner = null
      ..t = 0;
  }

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (outcome != null) return;

    final hit = _moleAt(touch.worldX, touch.worldY);
    if (hit == null) return;

    final owner = hit.owner;
    hit
      ..phase = MolePhase.squished
      ..t = 0;

    final bites = Sounds.buttonPress;
    final hole = hit.hole;
    if (hole != null) {
      _playOn(hole.phoneId, bites[_soundPick.nextInt(bites.length)]);
    }

    if (owner == null) return;
    final phoneId = context.phoneOfColor(owner);
    if (phoneId != null) {
      _squished[phoneId] = squishedBy(phoneId) + 1;
    }
  }

  _Mole? _moleAt(double x, double y) {
    _Mole? best;
    var bestDistance = double.infinity;

    for (final mole in _pool) {
      if (!mole.live) continue;
      if (mole.phase == MolePhase.squished) continue;
      if (mole.phase == MolePhase.sinking) continue;
      final hole = mole.hole;
      if (hole == null) continue;

      final dx = x - hole.centerX;
      final dy = y - hole.centerY;
      final d2 = dx * dx + dy * dy;
      final reach = hole.radius * 1.25;
      if (d2 > reach * reach) continue;

      if (d2 < bestDistance) {
        bestDistance = d2;
        best = mole;
      }
    }
    return best;
  }

  @override
  Iterable<Entity> get entities sync* {
    for (final hole in _holes) {
      yield Entity(
        descriptor: EntityDescriptor(
          id: 'hole${hole.index}',
          kind: 'hole',
          props: {'r': hole.radius},
        ),
        x: hole.centerX,
        y: hole.centerY,
      );
    }

    for (final mole in _pool) {
      final hole = mole.hole;
      if (!mole.live || hole == null) continue;
      yield Entity(
        descriptor: EntityDescriptor(
          id: mole.id,
          kind: 'mole',
          props: {
            'r': hole.radius,
            'color': mole.owner?.value.toARGB32() ?? 0xFFFFFFFF,
            'owner': mole.owner?.id,
          },
        ),
        x: hole.centerX,
        y: hole.centerY,
      );
    }
  }

  @override
  Map<String, Object?> get sharedState {
    final phases = <String, Object?>{};
    for (final mole in _pool) {
      if (!mole.live) continue;
      phases[mole.id] = {
        'p': mole.phase.name,
        't': (mole.t * 1000).round(),
        'up': (mole.upSeconds * 1000).round(),
      };
    }
    return {
      'moles': phases,
      'secondsLeft': secondsLeft.ceil(),
      'roundSeconds': GuacamoleConfig.roundSeconds.round(),
    };
  }

  GameOutcome? _outcome;

  @override
  GameOutcome? get outcome {
    if (_elapsed < GuacamoleConfig.roundSeconds) return null;

    return _outcome ??= GameOutcome.perPhone({
      for (final id in context.phoneIds) id: _tallyFor(id),
    }, summary: _roundLeader());
  }

  String _tallyFor(String phoneId) {
    final n = squishedBy(phoneId);
    final pts = ' — +${_paid[phoneId] ?? 0} pts';
    if (n == 0) return 'Not a single avocado$pts';
    return 'You squished $n avocado${n == 1 ? '' : 's'}$pts';
  }

  String _roundLeader() {
    final view = context.scores.view;
    final ranked = [
      for (final id in context.phoneIds) (id: id, squished: squishedBy(id)),
    ]..sort((a, b) => b.squished.compareTo(a.squished));

    if (ranked.isEmpty || ranked.first.squished == 0) return 'nobody scored';
    if (ranked.length > 1 && ranked[0].squished == ranked[1].squished) {
      return 'a dead heat';
    }
    final best = ranked.first;
    final label = view.entryFor(best.id)?.label ?? best.id;
    return '$label squished the most, ${best.squished}';
  }

  @override
  void reset() {
    for (final mole in _pool) {
      _retire(mole);
    }
    _bag.clear();
    _elapsed = 0;
    _sinceSpawn = 0;
    _squished.clear();
    _paid = const {};

    _outcome = null;
  }

  @override
  void dispose() {}
}
