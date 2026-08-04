import 'package:flutter/material.dart';

import '../contract/game.dart';
import '../host/host_session.dart';

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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.sports_esports,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('Pick a game', style: theme.textTheme.titleSmall),
                ],
              ),
            ),
            if (blockedReason != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Text(
                  blockedReason!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final offer in offers) _Row(offer: offer, onPick: onPick),
          ],
        ),
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
    final faded = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55);

    return ListTile(
      enabled: enabled,
      onTap: enabled ? () => onPick(offer.game) : null,
      leading: Icon(
        enabled ? Icons.play_circle_fill : Icons.block,
        color: enabled ? theme.colorScheme.primary : faded,
      ),
      title: Text(
        offer.manifest.title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: enabled ? null : faded,
        ),
      ),
      subtitle: Text(
        // The requirement replaces the tagline when it is the reason you cannot
        // play — that is the more useful sentence at that moment.
        offer.reason ?? offer.manifest.tagline,
        style: theme.textTheme.bodySmall?.copyWith(
          color: enabled ? theme.colorScheme.onSurfaceVariant : faded,
          fontStyle: offer.reason == null ? null : FontStyle.italic,
        ),
      ),
      trailing: enabled
          ? const Icon(Icons.chevron_right, size: 20)
          : Text(
              '${offer.manifest.smallestTable}+',
              style: theme.textTheme.labelSmall?.copyWith(color: faded),
            ),
      dense: true,
    );
  }
}
