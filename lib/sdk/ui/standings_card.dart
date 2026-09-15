import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../score/scoreboard.dart';

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
    this.showDeltas = false,
    this.offline = const {},
    this.onReset,
    this.maxListHeight = 156,
  });

  final ScoreView scores;
  final String? meId;

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

    final theme = Theme.of(context);
    final ranked = scores.ranked;

    final list = _ScoreList(
      maxHeight: maxListHeight,
      children: [
        for (final (i, entry) in ranked.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.phoneId == meId
                              ? '${entry.label} (you)'
                              : entry.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: entry.phoneId == meId
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: offline.contains(entry.phoneId)
                                ? theme.colorScheme.onSurfaceVariant
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (offline.contains(entry.phoneId)) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.cloud_off,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'away',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showDeltas && entry.roundDelta != 0) ...[
                  Text(
                    // A negative number brings its own sign. Prefixing
                    // every delta made a loss read '+-10'.
                    entry.roundDelta > 0
                        ? '+${entry.roundDelta}'
                        : '${entry.roundDelta}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: entry.roundDelta > 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  '${entry.total}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    // The card has to know whether it is being held to a height, and only the
    // thing holding it knows that.
    //
    // Given a ceiling, the names take what is left under the heading and no
    // more. That cannot be worked out from outside: the heading's height is not
    // a number anybody else can know — a host sees a Reset button in it and
    // nobody else does, and that button is a Material [TextButton] carrying a
    // minimum height of its own. The lobby used to guess it, twelve pixels
    // short, and the card overflowed its slot by exactly that as soon as a
    // fifth player made the list long enough to reach the cap.
    //
    // Unbounded — inside a scroll view, which is where the results screen and
    // the waiting room put it — there is nothing to fit under, and a flex child
    // in a Column with no ceiling is an assertion rather than a layout. So the
    // names fall back to their own [maxListHeight].
    return LayoutBuilder(
      builder: (context, box) => Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
                Icon(
                  Icons.leaderboard,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Standings', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (onReset != null)
                  TextButton(
                    onPressed: onReset,
                    child: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (box.maxHeight.isFinite) Flexible(child: list) else list,
          ],
        ),
      ),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
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
          padding: EdgeInsets.zero,
          children: widget.children,
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
