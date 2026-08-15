import 'dart:math' as math;

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/model/player_color.dart';
import 'guacamole_config.dart';

/// Where one mole can appear: a quarter of one phone's screen.
class Hole {
  const Hole({
    required this.index,
    required this.phoneId,
    required this.centerX,
    required this.centerY,
    required this.radius,
  });

  final int index;

  /// Whose screen this hole is on. Kept for diagnostics and tests only — the
  /// game deliberately does **not** use it to decide anything, because a hole
  /// being on your phone gives you no claim on what pops out of it.
  final String phoneId;

  final double centerX;
  final double centerY;

  /// The mole's radius here, in world units. Uniform across the board, but
  /// carried per hole so a future board with mismatched screens can vary it.
  final double radius;
}

/// A mole's life, in order.
enum MolePhase { rising, up, sinking, squished }

class _Mole {
  _Mole(this.id);

  final String id;

  bool live = false;
  Hole? hole;
  PlayerColor? owner;
  MolePhase phase = MolePhase.rising;

  /// Seconds spent in the current phase.
  double t = 0;

  /// How long this mole was told to stay up when it spawned. Recorded per mole
  /// rather than read from the clock, so a mole that appeared while the round
  /// was slow does not suddenly retract early when the ramp tightens.
  double upSeconds = GuacamoleConfig.visibleSecondsStart;
}

/// Avocados pop out of holes all over the table. Squish one and its **owner**
/// scores — whoever's finger did it.
///
/// The rule reads oddly until you watch it played: a mole is one player's
/// colour, and with four players only a quarter of the moles on your own screen
/// are yours. Yours are mostly on other people's phones, so the game is played
/// leaning across the table.
///
/// That physical fact is also why scoring credits the *mole*, never the finger.
/// A touch arrives tagged with the phone whose glass was pressed
/// ([TouchEvent.phoneId]), and once people are reaching, that phone is usually
/// not the person who reached. The tapper is genuinely unknowable — so the game
/// never asks. Points follow the colour, which is unambiguous, and a wrong tap
/// punishes itself by handing a point to a rival.
///
/// No physics: this is a schedule and a hit test. It implements [GameSim]
/// directly rather than extending the Forge2D base, because a world with no
/// bodies in it would only be a slower way to do nothing.
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

  late final List<Hole> _holes;
  late final List<PlayerColor> _players;
  late final List<_Mole> _pool;

  double _elapsed = 0;
  double _sinceSpawn = 0;

  /// Whose turn it is to get a mole, as a shuffled bag.
  ///
  /// Spawn *position* is uniform over every hole, as it should be — but the
  /// *colour* is dealt from a bag that is refilled and reshuffled once empty.
  /// Independent random colours would let one player get noticeably fewer moles
  /// than another across a 60-second round purely by luck, and losing to the
  /// dice is not losing to a person.
  final _bag = <PlayerColor>[];

  int get playerCount => _players.length;
  List<Hole> get holes => _holes;
  double get secondsLeft =>
      math.max(0, GuacamoleConfig.roundSeconds - _elapsed);

  // ------------------------------------------------------------------ build

  /// Four holes per screen, in a 2x2, inset from the edges.
  ///
  /// Built from the compiled slices, so this is where the phones actually are
  /// rather than where the plan hoped they would be.
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
          holes.add(Hole(
            index: index++,
            phoneId: slice.phoneId,
            centerX: usable.left + cellW * (col + 0.5),
            centerY: usable.top + cellH * (row + 0.5),
            radius: radius,
          ));
        }
      }
    }
    return holes;
  }

  // ------------------------------------------------------------------- step

  @override
  void step(double dt) {
    if (outcome != null) return;

    _elapsed += dt;

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
        // Escaped. Costs nobody anything — the only penalty in this game is
        // the point you did not get.
        if (mole.t >= GuacamoleConfig.sinkSeconds) _retire(mole);
      case MolePhase.squished:
        if (mole.t >= GuacamoleConfig.squishSeconds) _retire(mole);
    }
  }

  /// How far through the difficulty ramp we are, 0 to 1.
  double get _ramp {
    final t = GuacamoleConfig.roundSeconds * GuacamoleConfig.rampFraction;
    if (t <= 0) return 1;
    return (_elapsed / t).clamp(0.0, 1.0);
  }

  double get _spawnGap => _lerp(
        GuacamoleConfig.spawnGapStart,
        GuacamoleConfig.spawnGapEnd,
        _ramp,
      );

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

  /// Never fewer than one, so a two-player table is not becalmed.
  int get _targetLive => math.max(
        1,
        (playerCount * GuacamoleConfig.moleTargetPerPlayer).round(),
      );

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
  }

  _Mole? _freeMole() {
    for (final m in _pool) {
      if (!m.live) return m;
    }
    return null;
  }

  /// A uniformly random hole that is not already occupied.
  ///
  /// Uniform over the whole board on purpose: no bias toward the tapping
  /// player's own screen, and no attempt to place a player's moles near where
  /// they are sitting. Reaching is the game.
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

  // ------------------------------------------------------------------ input

  /// A finger came down somewhere on the board.
  ///
  /// [TouchEvent.phoneId] is deliberately ignored. It says which glass was
  /// pressed, not who pressed it, and conflating the two would quietly reward
  /// players for moles that happened to spawn in front of them.
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

    if (owner == null) return;
    final phoneId = context.phoneOfColor(owner);
    if (phoneId != null) {
      context.scores.award(phoneId, GuacamoleConfig.pointsPerSquish);
    }
  }

  /// The topmost squishable mole under a finger.
  ///
  /// Generous by a margin: fingers are wide, the target is small, and this is a
  /// party game. A mole already sinking still counts — snatching one on the way
  /// down is the best feeling the game has.
  _Mole? _moleAt(double x, double y) {
    _Mole? best;
    var bestDistance = double.infinity;

    for (final mole in _pool) {
      if (!mole.live || mole.phase == MolePhase.squished) continue;
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

  // -------------------------------------------------------------- entities

  /// Holes first, then moles, so a mole always draws over its own hole.
  ///
  /// A hole is a static entity that exists for the whole round; the platform
  /// sends its descriptor once and never mentions it again. The mole's
  /// animation phase rides in [sharedState] rather than the transform, because
  /// the transform is the only thing interpolated and a popping mole is a
  /// discrete state change, not a smooth glide between two snapshots.
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

  /// Per-mole animation state, keyed by id.
  ///
  /// This is the one place the contract's grain is worth explaining. Entity
  /// *props* are immutable for an entity's lifetime, and the transform is
  /// interpolated — neither can carry "this mole is 40% risen". Pooled ids are
  /// reused, so a mole's phase genuinely changes under a stable id. Shared
  /// state is the channel for exactly that: small, slow-ish, never interpolated.
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

  /// Built once: `outcome` is polled several times a tick and this one carries
  /// a line per phone.
  GameOutcome? _outcome;

  @override
  GameOutcome? get outcome {
    if (_elapsed < GuacamoleConfig.roundSeconds) return null;

    // Everybody played the same round and nobody is eliminated, so this is not
    // a win or a loss — it is what you personally managed. Each phone gets its
    // own tally under the platform's "Well played!", and the standings card
    // below it does the comparing.
    return _outcome ??= GameOutcome.perPhone(
      {for (final id in context.phoneIds) id: _tallyFor(id)},
      summary: _roundLeader(),
    );
  }

  /// One point per squish, so the round's score *is* the count.
  String _tallyFor(String phoneId) {
    final n = context.scores.view.roundDelta(phoneId);
    if (n == 0) return 'Not a single avocado';
    return 'You squished $n avocado${n == 1 ? '' : 's'}';
  }

  /// Who did best **this round**.
  ///
  /// Deliberately from the round's own deltas rather than the session leader:
  /// by the third game of a playlist the phone with the highest total may have
  /// squished nothing at all here, and announcing it as the winner of a round
  /// it lost is worse than saying nothing.
  String _roundLeader() {
    final view = context.scores.view;
    final ranked = [
      for (final id in context.phoneIds) (id: id, squished: view.roundDelta(id)),
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
    // The latched verdict belongs to the round that just ended.
    _outcome = null;
  }

  @override
  void dispose() {}
}
