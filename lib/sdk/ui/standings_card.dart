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

  @override
  Widget build(BuildContext context) {
    if (!scores.isUsed) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final ranked = scores.ranked;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        '+${entry.roundDelta}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
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
