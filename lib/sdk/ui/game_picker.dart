import 'package:flutter/material.dart';

import '../contract/game.dart';
import '../host/host_session.dart';
import 'theme/app_colors.dart';
import 'theme/app_dimens.dart';
import 'widgets/section_card.dart';

/// The host's list of games, with the ones this table cannot play greyed out.
///
/// Host-only by construction — it takes a [HostSession], and joiners do not
/// have one. Choosing is not a democracy: whoever set the table starts the
/// round, and everyone else is told where to put their phone.
///
/// Ineligible games stay visible rather than being hidden. "Hot Potato needs
/// 3+ phones" tells you to fetch another person; a game silently missing from
/// the list tells you nothing at all.
class GamePicker extends StatelessWidget {
  const GamePicker({
    super.key,
    required this.offers,
    required this.onPick,
    this.blockedReason,
  });

  final List<GameOffer> offers;
  final void Function(MultiscreenGame game) onPick;

  /// Why nothing can start yet — phones still calibrating, say. Applies to
  /// every entry, so it is shown once at the top rather than on each row.
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'Pick a game',
      icon: Icons.sports_esports,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blockedReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(blockedReason!, style: theme.textTheme.bodySmall),
            ),
          for (final offer in offers) _Row(offer: offer, onPick: onPick),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.offer, required this.onPick});

  final GameOffer offer;
  final void Function(MultiscreenGame game) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = offer.playable;
    final faded = AppColors.inkSoft.withValues(alpha: 0.55);

    // A tile with its own fill rather than a dense ListTile: eight rows of
    // bare text ran together, and the row is a target worth showing the edges
    // of.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: enabled ? AppColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: enabled ? () => onPick(offer.game) : null,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: enabled ? AppColors.yellow : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    enabled ? Icons.play_arrow_rounded : Icons.lock_outline,
                    size: 21,
                    color: enabled ? AppColors.onYellow : faded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.manifest.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: enabled ? null : faded,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        // The requirement replaces the tagline when it is the
                        // reason you cannot play — that is the more useful
                        // sentence at that moment.
                        offer.reason ?? offer.manifest.tagline,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: enabled ? AppColors.inkSoft : faded,
                          fontStyle:
                              offer.reason == null ? null : FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (enabled)
                  const Icon(Icons.chevron_right,
                      size: 20, color: AppColors.inkSoft)
                else
                  Text(
                    '${offer.manifest.smallestTable}+',
                    style: theme.textTheme.labelSmall?.copyWith(color: faded),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
