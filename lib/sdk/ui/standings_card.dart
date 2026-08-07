import 'package:flutter/material.dart';

import '../score/scoreboard.dart';
import 'theme/app_colors.dart';
import 'widgets/section_card.dart';

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

    return SectionCard(
      title: 'Standings',
      icon: Icons.leaderboard,
      trailing: onReset == null
          ? null
          : TextButton(onPressed: onReset, child: const Text('Reset')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, entry) in ranked.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  // The leader gets the accent; everyone else gets a grey
                  // number. A podium the same colour as the rest of the list
                  // is not a podium.
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0 ? AppColors.yellow : AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: i == 0 ? AppColors.onYellow : AppColors.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.phoneId == meId
                          ? '${entry.label} (you)'
                          : entry.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: entry.phoneId == meId
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showDeltas && entry.roundDelta != 0) ...[
                    Text(
                      '+${entry.roundDelta}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
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
    );
  }
}
