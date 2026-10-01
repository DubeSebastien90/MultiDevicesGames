import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/player_color.dart';
import '../render/player_art.dart';
import '../score/scoreboard.dart';
import 'sticker/sticker.dart';

class StandingsCard extends StatelessWidget {
  const StandingsCard({
    super.key,
    required this.scores,
    this.meId,
    this.colors = const {},
    this.showDeltas = false,
    this.offline = const {},
    this.onReset,
    this.maxListHeight = 156,
  });

  static const plateKey = Key('standings-plate');

  final ScoreView scores;
  final String? meId;

  final Map<String, PlayerColor?> colors;

  final bool showDeltas;

  final Set<String> offline;

  final VoidCallback? onReset;

  final double maxListHeight;

  @override
  Widget build(BuildContext context) {
    if (!scores.isUsed) return const SizedBox.shrink();

    final ranked = scores.ranked;

    final list = _ScoreList(
      maxHeight: maxListHeight,
      children: [
        for (final (i, entry) in ranked.indexed)
          _Row(
            place: i + 1,
            entry: entry,
            me: entry.phoneId == meId,
            away: offline.contains(entry.phoneId),
            color: colors[entry.phoneId],
            showDelta: showDeltas,
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) => StickerCard(
        key: plateKey,
        padding: EdgeInsets.zero,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: St.ink, width: 3)),
              ),
              child: ColoredBox(
                color: St.premium,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    onReset == null ? 16 : 8,
                    8,
                  ),
                  child: Row(
                    children: [
                      const StIcon(
                        Symbols.trophy_rounded,
                        size: 22,
                        color: St.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Standings',
                          style: St.display(20, color: St.white, height: 1.1),
                        ),
                      ),
                      if (onReset != null)
                        StickerButton(
                          height: 30,
                          radius: 10,
                          shadow: 2,
                          border: 2.5,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          onTap: onReset,
                          child: Text('Reset', style: St.display(14)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (box.maxHeight.isFinite)
              Flexible(child: _padded(list))
            else
              _padded(list),
          ],
        ),
      ),
    );
  }

  static Widget _padded(Widget list) =>
      Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 6), child: list);
}

class _Row extends StatelessWidget {
  const _Row({
    required this.place,
    required this.entry,
    required this.me,
    required this.away,
    required this.color,
    required this.showDelta,
  });

  final int place;
  final ScoreEntry entry;
  final bool me;
  final bool away;
  final PlayerColor? color;
  final bool showDelta;

  static const _art = 28.0;

  static const _podium = [St.gold, St.silver, St.bronze];
  static const _awayText = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    final art = away ? PlayerPalette.away : color;
    final podium = place <= 3;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
      decoration: BoxDecoration(
        color: me && color != null
            ? Color.alphaBlend(
                color!.skinLight.withValues(alpha: .33),
                St.white,
              )
            : St.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: me ? St.ink : Colors.transparent, width: 2.5),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: podium ? _podium[place - 1] : St.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: podium ? St.ink : const Color(0x33000000),
                width: 2,
              ),
            ),
            child: Center(
              child: Text('$place', style: St.display(12, height: 1)),
            ),
          ),
          const SizedBox(width: 8),
          if (art != null) ...[
            PlayerArt.of(art, PlayerArtSlot.face).widget(size: _art),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              me ? '${entry.label} (you)' : entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: me
                  ? St.display(16)
                  : St.body(15, color: away ? _awayText : St.ink),
            ),
          ),
          if (away) ...[
            const StIcon(
              Symbols.cloud_off_rounded,
              size: 14,
              color: Color(0xFF777777),
            ),
            const SizedBox(width: 3),
            Text(
              'away',
              style: St.body(11, color: const Color(0xFF777777), height: 1),
            ),
            const SizedBox(width: 8),
          ],
          if (showDelta && entry.roundDelta != 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: entry.roundDelta > 0 ? St.go : St.back,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: St.ink, width: 2),
              ),
              child: Text(
                entry.roundDelta > 0
                    ? '+${entry.roundDelta}'
                    : '${entry.roundDelta}',
                style: St.display(12, color: St.white, height: 1),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${entry.total}',
            style: St.display(
              19,
              color: away ? const Color(0xFFAAAAAA) : St.ink,
              height: 1,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _ScoreList extends StatefulWidget {
  const _ScoreList({required this.maxHeight, required this.children});

  final double maxHeight;
  final List<Widget> children;

  @override
  State<_ScoreList> createState() => _ScoreListState();
}

class _ScoreListState extends State<_ScoreList> {
  final _controller = ScrollController();

  bool _scrolls = false;

  static const _gutter = 12.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onMetrics(ScrollMetricsNotification note) {
    final scrolls = note.metrics.maxScrollExtent > 0;
    if (scrolls == _scrolls) return false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _scrolls = scrolls);
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: Scrollbar(
          controller: _controller,
          child: ListView(
            controller: _controller,
            shrinkWrap: true,
            primary: false,
            padding: EdgeInsets.only(right: _scrolls ? _gutter : 0),
            children: widget.children,
          ),
        ),
      ),
    );
  }
}

Set<String> awayPhoneIds(AppController controller) {
  final host = controller.host;
  if (host != null) {
    return {
      for (final p in host.phones)
        if (!p.connected) p.phoneId,
    };
  }
  return {
    for (final p in controller.client!.lobbyPhones)
      if (((p['connected'] as bool?) ?? true) == false) p['phoneId'] as String,
  };
}

Map<String, PlayerColor?> playerColors(AppController controller) {
  final host = controller.host;
  if (host != null) {
    return {for (final p in host.phones) p.phoneId: p.color};
  }
  return {
    for (final p in controller.client!.lobbyPhones)
      p['phoneId'] as String: PlayerPalette.byId(p['color'] as String?),
  };
}
