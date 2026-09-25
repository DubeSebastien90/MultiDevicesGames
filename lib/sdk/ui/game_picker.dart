import 'package:flutter/material.dart';

import '../contract/game.dart';
import '../host/host_session.dart';
import '../monetization/paywall_view.dart';
import '../monetization/premium_status.dart';
import 'lobby_flow_style.dart';

/// Open the run's game list, as a screen of its own.
///
/// It was a bottom sheet, and a dozen games is a screen's worth of list: the
/// sheet spent its height pretending to be one, and a drag down its middle
/// closed it instead of scrolling it — a modal sheet reads that gesture as
/// dismissal, which is exactly the gesture somebody makes to see game eleven.
/// Find Lobby and Settings are full screens with a back pill on them, so this
/// is one too, and the heading and the All/None pair stay put while the list
/// moves under them.
///
/// Host-only by construction — it takes a [HostSession], and joiners do not
/// have one. Choosing is not a democracy: whoever set the table decides what
/// the evening consists of, and everyone else is told where to put their phone.
///
/// Rebuilt from the session rather than from a copy of it, so a tick lands on
/// this screen and on the lobby underneath at the same instant.
///
/// Also the one place a non-Premium host runs into the paywall by picking
/// games at all: choosing the lineup is itself a Premium feature, so a locked
/// row's tap opens [showPaywall] instead of ticking a box that [HostSession]
/// would have refused anyway.
Future<void> showGamesScreen(
  BuildContext context,
  HostSession host,
  PremiumStatus premium,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Builder(
                  builder: (context) => LobbyHeader(
                    title: 'Games in the run',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([host, premium]),
                    builder: (context, _) => GamePicker(
                      offers: host.offers,
                      // Not `!premium.isPremium`: that reads an unanswered
                      // fetch as a refusal, and sends somebody who has paid to
                      // the paywall.
                      selectionLocked: premium.isReady && !premium.isPremium,
                      premiumError: premium.error,
                      onRetryPremium: premium.retry,
                      onChoose: (game, chosen) =>
                          host.chooseGame(game, chosen: chosen),
                      onAll: host.chooseAllGames,
                      onNone: host.chooseNoGames,
                      onSelectionLockedTap: () => showPaywall(
                        context,
                        premium,
                        trigger: 'Unlock game selection',
                      ),
                      onLockedTap: (game) => showPaywall(
                        context,
                        premium,
                        trigger: 'Unlock ${game.manifest.title}',
                      ),
                    ),
                  ),
                ),
              ],
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
/// The body of [showGamesScreen], and sized like one: the controls hold still
/// and the rows scroll, so this wants a bounded height rather than a place in
/// somebody else's scroll view.
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
///
/// The list says all of this by how it looks. It used to say it again in words:
/// a line under the heading explaining what Play would do and why it would not,
/// and a tally under the rows counting what was in the run. Both were a caption
/// for a picture the reader was already looking at — a green row with a tick in
/// it is in the run, a grey one saying '3+' is not, and counting them is
/// something you do by looking rather than by reading.
class GamePicker extends StatelessWidget {
  const GamePicker({
    super.key,
    required this.offers,
    required this.onChoose,
    this.onAll,
    this.onNone,
    this.selectionLocked = false,
    this.onSelectionLockedTap,
    this.onLockedTap,
    this.premiumError,
    this.onRetryPremium,
  });

  final List<GameOffer> offers;

  /// Put [game] in the run, or take it out.
  final void Function(MultiscreenGame game, bool chosen) onChoose;

  final VoidCallback? onAll;
  final VoidCallback? onNone;
  final bool selectionLocked;
  final VoidCallback? onSelectionLockedTap;

  /// A locked Premium row was tapped. Opens the paywall — the row itself has
  /// no tick to toggle, since [HostSession.chooseGame] refuses it anyway.
  final void Function(GameOffer offer)? onLockedTap;

  /// Why the Premium state could not be established, if it could not.
  ///
  /// Shown as a banner above the list, because the padlocks underneath it may
  /// be wrong: a host who bought Premium last week and opened the app somewhere
  /// with no signal sees exactly what a host who never paid sees, and only one
  /// of them is being told the truth. Saying so costs a line and turns "my
  /// purchase vanished" into "it will check again in a moment".
  final String? premiumError;

  /// Look again. Wired to [PremiumStatus.retry].
  final Future<void> Function()? onRetryPremium;

  @override
  Widget build(BuildContext context) {
    // Still waiting on the store. Derived from the rows rather than passed
    // alongside them, so the sheet and its rows cannot disagree about it.
    final pending = offers.any((o) => o.lockPending);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Row(
            children: [
              // A free host cannot pick, so telling them to tap one to add it
              // promises something the tap will not do.
              Expanded(
                child: Text(
                  selectionLocked
                      ? 'Games included in the run'
                      : 'Tap a game to add it',
                  style: LobbyText.body,
                ),
              ),
              // Twelve taps to play one game is not a choice anybody makes
              // twice, so the two ends of the list are one tap each. Disabled
              // rather than sent to the paywall while pending: we do not yet
              // know whether this host would need one.
              _EndButton(
                label: 'All',
                onPressed: pending
                    ? null
                    : (selectionLocked ? onSelectionLockedTap : onAll),
              ),
              const SizedBox(width: 8),
              _EndButton(
                label: 'None',
                onPressed: pending
                    ? null
                    : (selectionLocked ? onSelectionLockedTap : onNone),
              ),
            ],
          ),
        ),
        if (premiumError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PremiumTrouble(onRetry: onRetryPremium),
          )
        else if (pending)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: LobbyFlowColors.muted,
                  ),
                ),
                SizedBox(width: 10),
                Text('Checking your purchase…', style: LobbyText.body),
              ],
            ),
          ),
        // The list, and only the list, is what moves. Everything above it is a
        // control, and a control that scrolls away is one you have to go and
        // find again.
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: offers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _Row(
              offer: offers[i],
              selectionLocked: selectionLocked,
              onChoose: onChoose,
              onSelectionLockedTap: onSelectionLockedTap,
              onLockedTap: onLockedTap,
            ),
          ),
        ),
      ],
    );
  }
}

/// All, None — the two ends of the list, as small gray pills.
class _EndButton extends StatelessWidget {
  const _EndButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => LobbyPillButton(
    label: label,
    onPressed: onPressed,
    background: LobbyFlowColors.field,
    foreground: LobbyFlowColors.ink,
    fontSize: 13,
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
  );
}

/// Shown when the store could not be reached, above rows that may be lying.
///
/// The wording is the point. "Couldn't check your purchase" says the app failed
/// at something; "you have not bought this" — which is what a padlock says
/// without this banner — accuses the reader of something, and is the sentence
/// that turns a flaky network into a refund request and a one-star review.
///
/// The retry is not decoration either: without it, the only remedies a paying
/// customer can think of are reinstalling the app and asking for their money
/// back, and one of those makes the problem worse.
class _PremiumTrouble extends StatefulWidget {
  const _PremiumTrouble({required this.onRetry});

  final Future<void> Function()? onRetry;

  @override
  State<_PremiumTrouble> createState() => _PremiumTroubleState();
}

class _PremiumTroubleState extends State<_PremiumTrouble> {
  bool _retrying = false;

  Future<void> _retry() async {
    final onRetry = widget.onRetry;
    if (onRetry == null) return;
    setState(() => _retrying = true);
    try {
      await onRetry();
    } finally {
      // The sheet rebuilds off PremiumStatus, so a success simply replaces this
      // widget; this only matters when it failed again.
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: LobbyFlowColors.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: LobbyFlowColors.muted),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              // Deliberately not the exception text. "PlatformException(23, …)"
              // tells the reader nothing they can act on and reads like the
              // purchase itself broke.
              'Could not check your purchase. If you have bought Premium, it '
              'will unlock once this device can reach the store.',
              style: LobbyText.body,
            ),
          ),
          const SizedBox(width: 8),
          if (_retrying)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LobbyFlowColors.ink,
                ),
              ),
            )
          else
            _EndButton(
              label: 'Retry',
              onPressed: widget.onRetry == null ? null : _retry,
            ),
        ],
      ),
    );
  }
}

/// One game, as a plate you tap.
///
/// Green with a filled tick means it is in the run; gray with an empty ring
/// means it is not. That pair is the whole state of this screen, which is why
/// there is no longer a line of prose under the heading explaining it or a
/// tally under the rows counting it.
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
    final locked = offer.isLocked;
    final pending = offer.lockPending;
    final fits = offer.fitsTable;

    // Ticked *and* playable is the only state that gets the colour. A game the
    // table is the wrong size for is not going to be played tonight, and a
    // green plate promising otherwise is the lie the old footer went out of its
    // way to correct in words.
    final live = offer.chosen && fits && !locked && !pending;
    final ink = fits && !locked && !pending
        ? LobbyFlowColors.ink
        : LobbyFlowColors.muted;

    return GestureDetector(
      onTap: pending
          ? null
          : locked
          ? (onLockedTap == null ? null : () => onLockedTap!(offer))
          : () {
              if (selectionLocked) {
                onSelectionLockedTap?.call();
                return;
              }
              onChoose(offer.game, !offer.chosen);
            },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: live ? LobbyFlowColors.green : LobbyFlowColors.field,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            _Mark(offer: offer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    offer.manifest.title,
                    style: LobbyText.label.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // The requirement replaces the tagline when it is the
                    // reason you cannot play — that is the more useful
                    // sentence at that moment.
                    offer.reason ?? offer.manifest.tagline,
                    style: LobbyText.body.copyWith(
                      color: live
                          ? LobbyFlowColors.ink.withValues(alpha: 0.7)
                          : LobbyFlowColors.muted,
                      fontStyle: offer.reason == null ? null : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            ..._trailing(),
          ],
        ),
      ),
    );
  }

  List<Widget> _trailing() {
    if (offer.lockPending) return const [];
    if (offer.isLocked) {
      return const [SizedBox(width: 10), _PremiumTag()];
    }
    // Only on a row that does not fit: on every other row it would be twelve
    // repetitions of a number nobody is currently blocked by.
    if (offer.fitsTable) return const [];
    return [
      const SizedBox(width: 10),
      Text(
        '${offer.manifest.smallestTable}+',
        style: LobbyText.button.copyWith(
          color: LobbyFlowColors.muted,
          fontSize: 12,
        ),
      ),
    ];
  }
}

/// The tick, the padlock, or the spinner — whichever this row has earned.
class _Mark extends StatelessWidget {
  const _Mark({required this.offer});

  final GameOffer offer;

  static const _size = 24.0;

  @override
  Widget build(BuildContext context) {
    // Says nothing about money, because nothing is known about money yet. No
    // padlock, no tick and no ring: an inert row that is plainly not ready,
    // rather than a claim that turns out to be wrong half a second later.
    if (offer.lockPending) {
      return const SizedBox(
        width: _size,
        height: _size,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: LobbyFlowColors.muted,
          ),
        ),
      );
    }

    // A locked row has nothing a tap could toggle, so it gets no tick to
    // toggle. The padlock and the badge are the row's whole answer.
    //
    // The padlock means Premium and nothing else. A free game on a host that
    // cannot customise the run keeps its tick — the tap is what sends that
    // host to the paywall, not the icon.
    if (offer.isLocked) {
      return const SizedBox(
        width: _size,
        height: _size,
        child: Icon(
          Icons.lock_outline,
          size: 19,
          color: LobbyFlowColors.muted,
        ),
      );
    }

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: offer.chosen ? LobbyFlowColors.ink : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: offer.chosen ? LobbyFlowColors.ink : LobbyFlowColors.muted,
          width: 2,
        ),
      ),
      child: offer.chosen
          ? const Icon(Icons.check, size: 15, color: LobbyFlowColors.paper)
          : null,
    );
  }
}

class _PremiumTag extends StatelessWidget {
  const _PremiumTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: LobbyFlowColors.purple,
      borderRadius: BorderRadius.circular(LobbyMetrics.pillRadius),
    ),
    child: Text(
      'PREMIUM',
      style: LobbyText.button.copyWith(fontSize: 10, letterSpacing: 0.4),
    ),
  );
}
