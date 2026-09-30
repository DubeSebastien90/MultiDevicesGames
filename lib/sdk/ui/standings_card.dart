import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/player_color.dart';
import '../render/player_art.dart';
import '../score/scoreboard.dart';
import 'sticker/sticker.dart';

/// The session standings.
///
/// Renders nothing at all until somebody scores, because both shipped games are
/// co-operative and an all-zero table is noise. A game that never awards points
/// simply never makes this appear.
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

  /// The plate itself, for a test that wants to measure it.
  static const plateKey = Key('standings-plate');

  final ScoreView scores;
  final String? meId;

  /// Each phone's character, so a row is recognisable to somebody who has spent
  /// the evening being the frog. Missing entries simply get no portrait — a
  /// joiner who never picked, or a screen that has no roster to hand.
  final Map<String, PlayerColor?> colors;

  /// Show each phone's change this round — the results screen wants it, the
  /// lobby does not.
  final bool showDeltas;

  /// Phones the session remembers but that are not here right now.
  ///
  /// They keep their row and their score — a player who drops out has not
  /// stopped having played — but the row says so, because a name sitting in the
  /// standings with nobody behind it is worth knowing about before you wait for
  /// them.
  final Set<String> offline;

  final VoidCallback? onReset;

  /// How tall the names may get before they start scrolling — about five rows
  /// at the default.
  ///
  /// Only the names. 'Standings' and its Reset button sit above this and never
  /// move, so what scrolls is a list rather than the card's own contents.
  ///
  /// A ceiling and not a height: three players draw three rows and the card is
  /// short, which is what a card that has nothing more to say should look like.
  /// It is only a full table — eight rows is half again what fits — that turns
  /// the names into a window with the rest below the fold.
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

    // The card has to know whether it is being held to a height, and only the
    // thing holding it knows that.
    //
    // Given a ceiling, the names take what is left under the heading and no
    // more. That cannot be worked out from outside: the heading's height is not
    // a number anybody else can know — a host sees a Reset button in it and
    // nobody else does — and it was guessed at from the outside once, twelve
    // pixels short, and the card overflowed its slot by exactly that as soon as
    // a fifth player made the list long enough to reach the cap.
    //
    // Unbounded — inside a scroll view, which is where the results screen and
    // the waiting room put it — there is nothing to fit under, and a flex child
    // in a Column with no ceiling is an assertion rather than a layout. So the
    // names fall back to their own [maxListHeight].
    return LayoutBuilder(
      builder: (context, box) => StickerCard(
        key: plateKey,
        padding: EdgeInsets.zero,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // As tall as the heading and the names it actually has. Without this
          // the card fills whatever it is offered, which on a screen with room
          // to spare is a heading with an acre of white under it, and in the
          // lobby is the whole leftover slot for two names.
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

  /// The rows' breathing room inside the card, kept outside the list so the
  /// list's own padding is only ever the scrollbar's lane.
  static Widget _padded(Widget list) =>
      Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 6), child: list);
}

/// One person's line: where they came, who they are, and what they have.
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

  /// The character, at the size the old coloured dot should always have been.
  ///
  /// That dot was ten pixels of paint: enough to tell two rows apart, not
  /// enough to be anybody. The art is the same picture the player has been
  /// looking for on the board all evening.
  static const _art = 28.0;

  static const _podium = [St.gold, St.silver, St.bronze];
  static const _awayText = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    // Somebody who is not here is the grey character, whatever colour they
    // last wore: between rounds that colour has gone back to the palette and
    // may be on somebody else by now, and mid-round it is only being kept for
    // the game's sake.
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
                // A negative number brings its own sign. Prefixing every delta
                // made a loss read '+-10'.
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

/// The names: as tall as they are, up to [maxHeight], and scrolling past that.
///
/// Its own widget for the scroll controller: a [Scrollbar] has to be given the
/// same controller as the list it describes, and on a desktop build that bar is
/// the only thing on screen saying there are more people below the fold. It
/// takes itself out of the way when everybody fits — nothing to scroll, no bar.
class _ScoreList extends StatefulWidget {
  const _ScoreList({required this.maxHeight, required this.children});

  final double maxHeight;
  final List<Widget> children;

  @override
  State<_ScoreList> createState() => _ScoreListState();
}

class _ScoreListState extends State<_ScoreList> {
  final _controller = ScrollController();

  /// Whether there is anything below the fold, and so whether the bar is out.
  bool _scrolls = false;

  /// What the bar takes: its own track plus the breath either side of it.
  static const _gutter = 12.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The scrollbar is drawn over the list, not beside it, and what it lands on
  /// is the right-hand end of every row — which is where the scores are. So the
  /// rows give it a lane when there is a bar, and take the space back when
  /// there is not.
  ///
  /// Answered by the viewport rather than by counting rows: how tall a row is
  /// depends on the text size the player has chosen, and the only thing that
  /// has actually measured one is the layout that just ran. Applied after that
  /// frame, because this arrives mid-layout and nothing may be marked dirty
  /// from there.
  ///
  /// Settles in one pass: the lane is horizontal and the extent it feeds back
  /// is vertical, so widening the rows cannot change the answer.
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
            // Sized by its rows up to the ceiling above, rather than filling
            // whatever it is given.
            shrinkWrap: true,
            // This card is usually inside another scroll view, and two vertical
            // lists both claiming the PrimaryScrollController is an assertion at
            // runtime rather than a subtle bug.
            primary: false,
            padding: EdgeInsets.only(right: _scrolls ? _gutter : 0),
            children: widget.children,
          ),
        ),
      ),
    );
  }
}

/// Phones the session remembers that are not connected right now.
///
/// Read from the lobby broadcast on a joiner and from the roster on the host,
/// which are the same list — the host is a client of itself.
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

/// Everyone's character, from whichever roster this device happens to have.
///
/// Same source and same reasoning as [awayPhoneIds], which is why it lives
/// beside it: the host reads its own roster, a joiner reads the lobby
/// broadcast, and they are the same list because the host is a client of
/// itself. Taking whichever is to hand keeps every standings screen from having
/// to know which device it is on.
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
