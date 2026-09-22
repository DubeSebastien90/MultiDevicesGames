import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/player_color.dart';
import '../render/player_art.dart';
import '../score/scoreboard.dart';
import 'lobby_flow_style.dart';

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
      builder: (context, box) => Container(
        key: plateKey,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: LobbyFlowColors.field,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          // As tall as the heading and the names it actually has. Without this
          // the card fills whatever it is offered, which on a screen with room
          // to spare is a heading with an acre of white under it, and in the
          // lobby is the whole leftover slot for two names.
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Standings', style: LobbyText.label),
                ),
                if (onReset != null)
                  LobbyPillButton(
                    label: 'Reset',
                    onPressed: onReset,
                    background: LobbyFlowColors.paper,
                    foreground: LobbyFlowColors.ink,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(
                      vertical: 7,
                      horizontal: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (box.maxHeight.isFinite) Flexible(child: list) else list,
          ],
        ),
      ),
    );
  }
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
  /// looking for on the board all evening, and at this size it is recognisably
  /// that animal rather than a smudge of its colour.
  static const _art = 24.0;

  @override
  Widget build(BuildContext context) {
    final ink = away ? LobbyFlowColors.muted : LobbyFlowColors.ink;
    // Somebody who is not here is the grey character, whatever colour they
    // last wore: between rounds that colour has gone back to the palette and
    // may be on somebody else by now, and mid-round it is only being kept for
    // the game's sake.
    final art = away ? PlayerPalette.away : color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$place.',
              style: LobbyText.button.copyWith(
                color: LobbyFlowColors.muted,
                fontSize: 12,
              ),
            ),
          ),
          if (art != null) ...[
            PlayerArt.of(art, PlayerArtSlot.topdown).widget(size: _art),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              me ? '${entry.label} (you)' : entry.label,
              overflow: TextOverflow.ellipsis,
              style: LobbyText.label.copyWith(
                color: ink,
                fontSize: 14,
                fontWeight: me ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (away) ...[
            const Icon(
              Icons.cloud_off,
              size: 13,
              color: LobbyFlowColors.muted,
            ),
            const SizedBox(width: 4),
            Text(
              'away',
              style: LobbyText.body.copyWith(fontSize: 11),
            ),
            const SizedBox(width: 8),
          ],
          if (showDelta && entry.roundDelta != 0) ...[
            Text(
              // A negative number brings its own sign. Prefixing every delta
              // made a loss read '+-10'.
              entry.roundDelta > 0
                  ? '+${entry.roundDelta}'
                  : '${entry.roundDelta}',
              style: LobbyText.button.copyWith(
                fontSize: 12,
                color: entry.roundDelta > 0
                    ? LobbyFlowColors.shadeOf(LobbyFlowColors.green)
                    : LobbyFlowColors.shadeOf(LobbyFlowColors.coral),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            '${entry.total}',
            style: LobbyText.count.copyWith(
              color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
    return {for (final p in host.phones) if (!p.connected) p.phoneId};
  }
  return {
    for (final p in controller.client!.lobbyPhones)
      if (((p['connected'] as bool?) ?? true) == false)
        p['phoneId'] as String,
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
