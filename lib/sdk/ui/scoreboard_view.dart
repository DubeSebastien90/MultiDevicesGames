import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../model/player_color.dart';
import '../render/player_animation.dart';
import '../score/scoreboard.dart';
import 'sticker/sticker.dart';

class ScoreboardView extends StatefulWidget {
  const ScoreboardView({
    super.key,
    required this.scores,
    required this.meId,
    this.colors = const {},
    this.offline = const <String>{},
    this.onBackToLobby,
  });

  final ScoreView scores;
  final String? meId;

  final Map<String, PlayerColor?> colors;

  final Set<String> offline;

  final VoidCallback? onBackToLobby;

  static const listKey = ValueKey('scoreboard-list');

  @override
  State<ScoreboardView> createState() => _ScoreboardViewState();
}

class _ScoreboardViewState extends State<ScoreboardView>
    with SingleTickerProviderStateMixin {
  Map<PlayerMotion, PlayerAnimations> _casts = {
    for (final motion in PlayerMotion.values)
      motion: PlayerAnimations.noneFor(motion),
  };

  Set<String> _castIds = const {};

  int _loadGen = 0;

  final _clock = _RunClock();
  late final Ticker _ticker = createTicker(_clock.tick);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final moving = StickerMotion.of(context);
    if (!moving && _ticker.isActive) _ticker.stop();
    if (moving && !_ticker.isActive) _ticker.start();
  }

  @override
  void didUpdateWidget(ScoreboardView old) {
    super.didUpdateWidget(old);
    final wanted = _wantedColors();
    if (!wanted.keys.toSet().containsAll(_castIds) ||
        !_castIds.containsAll(wanted.keys)) {
      _load();
    }
  }

  @override
  void dispose() {
    _loadGen++;
    _ticker.dispose();
    _clock.dispose();
    for (final cast in _casts.values) {
      cast.dispose();
    }
    super.dispose();
  }

  Map<String, PlayerColor> _wantedColors() {
    final wanted = <String, PlayerColor>{};
    for (final e in widget.scores.ranked) {
      final color = _artFor(e.phoneId);
      if (color != null) wanted[color.id] = color;
    }
    return wanted;
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final wanted = _wantedColors();
    final loaded = await Future.wait([
      for (final motion in PlayerMotion.values)
        PlayerAnimations.load(wanted.values, motion: motion),
    ]);
    if (!mounted || gen != _loadGen) {
      for (final cast in loaded) {
        cast.dispose();
      }
      return;
    }
    final old = _casts;
    setState(() {
      _casts = {
        for (final (i, motion) in PlayerMotion.values.indexed)
          motion: loaded[i],
      };
      _castIds = wanted.keys.toSet();
    });
    for (final cast in old.values) {
      cast.dispose();
    }
  }

  PlayerColor? _artFor(String phoneId) => widget.offline.contains(phoneId)
      ? PlayerPalette.away
      : widget.colors[phoneId];

  Widget? _runner(String phoneId, double size, PlayerMotion motion) {
    final color = _artFor(phoneId);
    if (color == null) return null;
    return _Runner(
      animation: _casts[motion]!.of(color)..start(),
      clock: _clock,
      size: size,
      angle: motion == PlayerMotion.run ? 1.5707963267948966 : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scores = widget.scores;
    final ranked = scores.ranked;

    final places = _places(ranked);

    return StickerPage(
      maxWidth: 520,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _headline(scores, widget.meId),
                textAlign: TextAlign.center,
                style: St.display(40, height: 1),
              ),
              const SizedBox(height: 6),
              Text(
                'Final standings',
                style: St.body(15, color: St.muted).copyWith(letterSpacing: 2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              if (scores.isUsed && ranked.isNotEmpty) ...[
                _Podium(
                  entries: ranked.take(3).toList(),
                  places: places.take(3).toList(),
                  meId: widget.meId,
                  offline: widget.offline,
                  runner: _runner,
                ),
                const SizedBox(height: 22),
              ],
              StickerCard(
                key: ScoreboardView.listKey,
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    for (final (i, entry) in ranked.indexed)
                      _Row(
                        place: places[i],
                        entry: entry,
                        me: entry.phoneId == widget.meId,
                        away: widget.offline.contains(entry.phoneId),
                        color: widget.colors[entry.phoneId],
                        runner: _runner(
                          entry.phoneId,
                          _Row._art,
                          PlayerMotion.run,
                        ),
                        medals: scores.isUsed,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              if (widget.onBackToLobby != null)
                StickerWideButton(
                  onTap: widget.onBackToLobby,
                  icon: Symbols.meeting_room_rounded,
                  label: 'Back to lobby',
                  color: St.go,
                  textColor: St.white,
                  height: 68,
                  fontSize: 24,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const StickerSpinner(size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Waiting for the host…',
                      style: St.body(15, color: St.muted),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _headline(ScoreView scores, String? meId) {
    if (!scores.isUsed) return 'That is the lot';

    final winner = scores.leader;

    if (winner == null) return 'It is a tie!';
    return winner.phoneId == meId ? 'You win!' : '${winner.label} wins!';
  }

  static List<int> _places(List<ScoreEntry> ranked) {
    final places = <int>[];
    for (var i = 0; i < ranked.length; i++) {
      if (i > 0 && ranked[i].total == ranked[i - 1].total) {
        places.add(places[i - 1]);
      } else {
        places.add(i + 1);
      }
    }
    return places;
  }
}

const _medal = <int, Color>{1: St.gold, 2: St.silver, 3: St.bronze};

const _medalText = <int, Color>{
  1: Color(0xFFE0A800),
  2: Color(0xFF9A9A9A),
  3: St.bronze,
};

class _Podium extends StatelessWidget {
  const _Podium({
    required this.entries,
    required this.places,
    required this.meId,
    required this.offline,
    required this.runner,
  });

  final List<ScoreEntry> entries;
  final List<int> places;
  final String? meId;
  final Set<String> offline;
  final Widget? Function(String phoneId, double size, PlayerMotion motion)
  runner;

  static const _heights = [124.0, 96.0, 80.0];

  static int _flex(int slot) => slot == 0 ? 11 : 10;

  static const _fills = [1.0, .86, .8];

  @override
  Widget build(BuildContext context) {
    final order = [1, 0, 2].where((i) => i < entries.length).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = constraints.maxWidth / (_flex(0) + _flex(1) + _flex(2));
        double art(int slot) => unit * _flex(slot) * _fills[slot];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final i in order)
              Expanded(
                flex: _flex(i),
                child: _Step(
                  entry: entries[i],
                  place: places[i],
                  slot: i,
                  me: entries[i].phoneId == meId,
                  away: offline.contains(entries[i].phoneId),
                  art: art(i),
                  runner: runner(
                    entries[i].phoneId,
                    art(i),
                    places[i] == 1 ? PlayerMotion.win : PlayerMotion.lose,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.entry,
    required this.place,
    required this.slot,
    required this.me,
    required this.away,
    required this.art,
    required this.runner,
  });

  final ScoreEntry entry;
  final int place;

  final int slot;
  final bool me;
  final bool away;

  final double art;
  final Widget? runner;

  @override
  Widget build(BuildContext context) {
    final first = slot == 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: St.body(
              13,
              weight: FontWeight.w700,
              color: away ? const Color(0xFF777777) : St.ink,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: runner ?? SizedBox.square(dimension: art),
                ),
                Container(
                  height: _Podium._heights[slot],
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: first ? const Color(0xFFFFF3C4) : St.white,
                    border: Border.all(color: St.ink, width: 3),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    boxShadow: St.hard(5),
                  ),
                  padding: EdgeInsets.only(top: me ? 14 : 10),
                  child: Column(
                    children: [
                      Text(
                        '$place',
                        style: St.display(
                          first ? 46 : 36,
                          color: _medalText[place] ?? St.ink,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.total}',
                        style: St.display(first ? 20 : 17, height: 1).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (me)
              Positioned(
                top: art + 4 - 10,
                child: StickerPill(
                  'YOU',
                  color: St.ink,
                  textColor: St.white,
                  size: 11,
                  border: 2,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.place,
    required this.entry,
    required this.me,
    required this.away,
    required this.color,
    required this.runner,
    required this.medals,
  });

  final int place;
  final ScoreEntry entry;
  final bool me;
  final bool away;
  final PlayerColor? color;
  final Widget? runner;
  final bool medals;

  static const _art = 36.0;

  static const _awayText = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    final badge = medals ? _medal[place] : null;
    final art = runner;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.fromLTRB(8, 3, 12, 3),
      decoration: BoxDecoration(
        color: me && color != null
            ? Color.alphaBlend(
                color!.skinLight.withValues(alpha: .33),
                St.white,
              )
            : St.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: me ? St.ink : Colors.transparent, width: 3),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge ?? St.white,
              shape: BoxShape.circle,
              border: Border.all(color: St.ink, width: 2),
            ),
            child: Text('$place', style: St.display(15, height: 1)),
          ),
          const SizedBox(width: 10),
          if (art != null) ...[art, const SizedBox(width: 10)],
          Expanded(
            child: Text(
              me ? '${entry.label} (you)' : entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: me
                  ? St.display(17)
                  : St.body(
                      16,
                      weight: FontWeight.w700,
                      color: away ? _awayText : St.ink,
                    ),
            ),
          ),
          if (away) ...[
            const StIcon(
              Symbols.cloud_off_rounded,
              size: 16,
              color: Color(0xFF777777),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${entry.total}',
            style: St.display(
              22,
              color: away ? const Color(0xFFAAAAAA) : St.ink,
              height: 1,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _RunClock extends ChangeNotifier {
  Duration _now = Duration.zero;

  final _advancedTo = Expando<Duration>();

  void tick(Duration elapsed) {
    _now = elapsed;
    notifyListeners();
  }

  double dtFor(PlayerAnimation animation) {
    final last = _advancedTo[animation];
    _advancedTo[animation] = _now;
    if (last == null || last >= _now) return 0;
    return (_now - last).inMicroseconds / 1e6;
  }
}

class _Runner extends StatelessWidget {
  const _Runner({
    required this.animation,
    required this.clock,
    required this.size,
    required this.angle,
  });

  final PlayerAnimation animation;
  final _RunClock clock;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: RepaintBoundary(
      child: CustomPaint(painter: _RunnerPainter(animation, clock, angle)),
    ),
  );
}

class _RunnerPainter extends CustomPainter {
  _RunnerPainter(this.animation, this.clock, this.angle)
    : super(repaint: clock);

  final PlayerAnimation animation;
  final _RunClock clock;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    animation.draw(
      canvas,
      size.center(Offset.zero),
      worldSize: size.shortestSide,
      dt: clock.dtFor(animation),
      angle: angle,
    );
  }

  @override
  bool shouldRepaint(_RunnerPainter old) =>
      old.animation != animation || old.clock != clock || old.angle != angle;
}
