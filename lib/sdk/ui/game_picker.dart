import 'package:flutter/material.dart';

import '../contract/game.dart';
import '../host/host_session.dart';
import '../monetization/paywall_view.dart';
import '../monetization/premium_status.dart';

/// Open the run's game list, as a sheet over the lobby.
///
/// Host-only by construction — it takes a [HostSession], and joiners do not
/// have one. Choosing is not a democracy: whoever set the table decides what
/// the evening consists of, and everyone else is told where to put their phone.
///
/// Rebuilt from the session rather than from a copy of it, so a tick lands on
/// the sheet and in the Play button's caption underneath at the same instant.
///
/// Also the one place a non-Premium host runs into the paywall by picking
/// games at all: choosing the lineup is itself a Premium feature, so a locked
/// row's tap opens [showPaywall] instead of ticking a box that [HostSession]
/// would have refused anyway.
Future<void> showGamesSheet(
  BuildContext context,
  HostSession host,
  PremiumStatus premium,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheet).height * 0.85,
    ),
    child: ListenableBuilder(
      listenable: Listenable.merge([host, premium]),
      builder: (_, _) => SafeArea(
        child: SingleChildScrollView(
          child: GamePicker(
            offers: host.offers,
            selectionLocked: !premium.isPremium,
            onChoose: (game, chosen) => host.chooseGame(game, chosen: chosen),
            onAll: host.chooseAllGames,
            onNone: host.chooseNoGames,
            blockedReason: host.blockedReason,
            onSelectionLockedTap: () =>
                showPaywall(context, premium, trigger: 'Unlock game selection'),
            onLockedTap: (game) => showPaywall(
              context,
              premium,
              trigger: 'Unlock ${game.manifest.title}',
            ),
          ),
        ),
      ),
    ),
  ),
);

/// Which games the evening consists of: tick the ones you want, in the order
/// they will be played.
///
/// Everything starts ticked. A table that never opens this plays the whole
/// catalogue, which is exactly what it did before there was anything to open.
///
/// Games this table cannot play stay in the list, greyed and saying what they
/// need. "Hot Potato needs 3+ phones" tells you to fetch another person; a game
/// silently missing from the list tells you nothing at all.
///
/// They stay tickable, though, and the greying is not a refusal. Two reasons:
/// the list is usually opened while people are still arriving — with nobody
/// calibrated yet *every* row is the wrong size, and a settings screen where
/// nothing can be set is not a settings screen — and a tick is about the
/// evening rather than about this minute, so it survives a phone going flat.
/// Playing a game that does not fit is refused where it matters, at the
/// session: the run steps over it and [HostSession.startGame] declines it.
class GamePicker extends StatelessWidget {
  const GamePicker({
    super.key,
    required this.offers,
    required this.onChoose,
    this.onAll,
    this.onNone,
    this.blockedReason,
    this.selectionLocked = false,
    this.onSelectionLockedTap,
    this.onLockedTap,
  });

  final List<GameOffer> offers;

  /// Put [game] in the run, or take it out.
  final void Function(MultiscreenGame game, bool chosen) onChoose;

  final VoidCallback? onAll;
  final VoidCallback? onNone;
  final bool selectionLocked;
  final VoidCallback? onSelectionLockedTap;

  /// Why nothing can start yet — phones still calibrating, nothing ticked.
  /// Applies to every entry, so it is shown once at the top rather than on each
  /// row.
  final String? blockedReason;

  /// A locked Premium row was tapped. Opens the paywall — the row itself has
  /// no checkbox to toggle, since [HostSession.chooseGame] refuses the tick
  /// anyway.
  final void Function(GameOffer offer)? onLockedTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Ticked and in the run are not the same number, and the footer counts the
    // second one. A game the table is the wrong size for is not going to be
    // played, so it is not in the run — saying "12 of 12" over a table of two
    // that can play three of them would be counting the ticks and calling it a
    // playlist.
    final inRun = offers.where((o) => o.chosen && o.fitsTable).length;
    final wrongSize = offers.where((o) => o.chosen && !o.fitsTable).length;
    final locked = offers.where((o) => o.isLocked).length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
            child: Row(
              children: [
                Icon(
                  Icons.sports_esports,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Games in the run',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                // Twelve taps to play one game is not a choice anybody makes
                // twice, so the two ends of the list are one tap each.
                TextButton(
                  onPressed: selectionLocked ? onSelectionLockedTap : onAll,
                  child: const Text('All'),
                ),
                TextButton(
                  onPressed: selectionLocked ? onSelectionLockedTap : onNone,
                  child: const Text('None'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              blockedReason ??
                  'Play runs these in order, skipping any the table is the '
                      'wrong size for at the time.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final offer in offers)
            _Row(
              offer: offer,
              selectionLocked: selectionLocked,
              onChoose: onChoose,
              onSelectionLockedTap: onSelectionLockedTap,
              onLockedTap: onLockedTap,
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              [
                wrongSize == 0
                    ? '$inRun of ${offers.length} in the run'
                    : '$inRun of ${offers.length} in the run · $wrongSize '
                          'ticked but the wrong size for this table',
                if (locked > 0) '$locked locked behind Premium',
              ].join(' · '),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.offer,
    required this.selectionLocked,
    required this.onChoose,
    this.onSelectionLockedTap,
    this.onLockedTap,
  });

  final GameOffer offer;
  final bool selectionLocked;
  final void Function(MultiscreenGame game, bool chosen) onChoose;
  final VoidCallback? onSelectionLockedTap;
  final void Function(GameOffer offer)? onLockedTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locked = offer.isLocked;
    final fits = offer.fitsTable;
    final faded = scheme.onSurfaceVariant.withValues(alpha: 0.55);

    if (locked) {
      // No checkbox: a locked row has nothing a tap could toggle, and a
      // greyed-out checkbox sitting next to a lock icon would be saying the
      // same thing twice. The whole row is the tap target for the paywall.
      return ListTile(
        onTap: onLockedTap == null ? null : () => onLockedTap!(offer),
        leading: Icon(Icons.lock_outline, size: 20, color: faded),
        title: Text(
          offer.manifest.title,
          style: theme.textTheme.titleSmall?.copyWith(color: faded),
        ),
        subtitle: Text(
          offer.manifest.tagline,
          style: theme.textTheme.bodySmall?.copyWith(color: faded),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'PREMIUM',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        dense: true,
      );
    }

    return CheckboxListTile(
      value: offer.chosen,
      onChanged: (on) {
        if (selectionLocked) {
          onSelectionLockedTap?.call();
          return;
        }
        onChoose(offer.game, on ?? false);
      },
      // The tick reads as a list, so it goes where a list's bullets would.
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        offer.manifest.title,
        style: theme.textTheme.titleSmall?.copyWith(color: fits ? null : faded),
      ),
      subtitle: Text(
        // The requirement replaces the tagline when it is the reason you cannot
        // play — that is the more useful sentence at that moment.
        offer.reason ?? offer.manifest.tagline,
        style: theme.textTheme.bodySmall?.copyWith(
          color: fits ? theme.colorScheme.onSurfaceVariant : faded,
          fontStyle: offer.reason == null ? null : FontStyle.italic,
        ),
      ),
      // Only on a row that does not fit: on every other row it would be twelve
      // repetitions of a number nobody is currently blocked by.
      secondary: selectionLocked
          ? Icon(Icons.lock_outline, size: 18, color: faded)
          : fits
          ? null
          : Text(
              '${offer.manifest.smallestTable}+',
              style: theme.textTheme.labelSmall?.copyWith(color: faded),
            ),
      dense: true,
    );
  }
}
