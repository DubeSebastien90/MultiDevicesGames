import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/player_color.dart';
import '../score/scoreboard.dart';

/// The end of the run: who won the whole evening.
///
/// The results screen after each round answers "what just happened". This one
/// answers the only question left once the playlist is spent — and it is a
/// different question, so it gets its own screen rather than a bigger card at
/// the bottom of the last round's.
///
/// Every phone shows it at once, because the standings belong to the table
/// rather than to the device running the session. Only the host is given a way
/// off it: the way out is the same as everywhere else, one person deciding for
/// the room.
class ScoreboardView extends StatelessWidget {
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

  /// Each phone's colour, so a row is recognisable to somebody who has spent
  /// the evening being the green one. Missing entries simply get no dot.
  final Map<String, PlayerColor?> colors;

  /// Phones the session remembers that are not here any more. They keep their
  /// place — they played for it — and the row says where they went.
  final Set<String> offline;

  /// Wind the session back to the lobby, or null on a phone that cannot.
  final VoidCallback? onBackToLobby;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ranked = scores.ranked;

    // Ties share a place, so two people level on 40 are both second rather than
    // one of them being told they came third by the order of a list.
    final places = _places(ranked);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.emoji_events, size: 56, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    _headline(scores, meId),
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Final standings',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),

                  // Deliberately not a [StandingsCard]: that one draws nothing
                  // at all until somebody scores, which is right where it sits —
                  // beside other things — and wrong here, where it is the whole
                  // screen. A co-operative run that ended level still has to
                  // show the table its own names.
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Column(
                        children: [
                          for (final (i, entry) in ranked.indexed)
                            _Row(
                              place: places[i],
                              entry: entry,
                              me: entry.phoneId == meId,
                              away: offline.contains(entry.phoneId),
                              color: colors[entry.phoneId],
                              // Medals mean nothing on a board nobody scored on.
                              medals: scores.isUsed,
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  if (onBackToLobby != null)
                    FilledButton.icon(
                      onPressed: onBackToLobby,
                      icon: const Icon(Icons.meeting_room_outlined),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Back to lobby'),
                      ),
                    )
                  else
                    // Something to look at, so a phone with no button does not
                    // read as a phone that has frozen.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Waiting for the host…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The one line worth reading from across the table.
  static String _headline(ScoreView scores, String? meId) {
    if (!scores.isUsed) return 'That is the lot';

    final winner = scores.leader;
    // Null means the top two are level. Naming one of them would be a lie, and
    // naming neither is the actual result.
    if (winner == null) return 'It is a tie!';
    return winner.phoneId == meId ? 'You win!' : '${winner.label} wins!';
  }

  /// Standard competition ranking: 1, 2, 2, 4.
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

/// Everyone's colour, from whichever roster this device happens to have.
///
/// The host reads its own; a joiner reads the lobby broadcast. They are the
/// same list — the host is a client of itself — so taking whichever is to hand
/// keeps the screen from having to know which device it is on.
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

class _Row extends StatelessWidget {
  const _Row({
    required this.place,
    required this.entry,
    required this.me,
    required this.away,
    required this.color,
    required this.medals,
  });

  final int place;
  final ScoreEntry entry;
  final bool me;
  final bool away;
  final PlayerColor? color;
  final bool medals;

  /// Gold, silver, bronze. Deliberately fixed rather than themed: a medal that
  /// changes colour with the theme is not a medal.
  static const _medal = <int, Color>{
    1: Color(0xFFD4AF37),
    2: Color(0xFFAFB6BD),
    3: Color(0xFFB07B4F),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final badge = medals ? _medal[place] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge ?? scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$place',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: badge == null ? scheme.onSurfaceVariant : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (color != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color!.value,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              me ? '${entry.label} (you)' : entry.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: me ? FontWeight.w700 : FontWeight.w500,
                color: away ? scheme.onSurfaceVariant : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (away) ...[
            Icon(Icons.cloud_off, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
          ],
          Text(
            '${entry.total}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
