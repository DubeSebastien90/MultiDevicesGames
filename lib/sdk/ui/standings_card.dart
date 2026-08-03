import 'package:flutter/material.dart';

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
    this.onReset,
  });

  final ScoreView scores;
  final String? meId;

  /// Show each phone's change this round — the results screen wants it, the
  /// lobby does not.
  final bool showDeltas;

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
                      child: Text(
                        entry.phoneId == meId
                            ? '${entry.label} (you)'
                            : entry.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: entry.phoneId == meId
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
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
