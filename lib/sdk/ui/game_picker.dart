import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../audio/ui_audio.dart';
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
/// Games this table cannot play stay in the list, faded and saying what they
/// need. "Hot Potato, 3+ phones" tells you to fetch another person; a game
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
/// for a picture the reader was already looking at — a bright icon with a tick
/// on it is in the run, a faded one saying '3+' is not, and counting them is
/// something you do by looking rather than by reading.
///
/// So the games are icons in a grid, and nothing else: no plate under each one
/// and no tagline beside it. The picture says which game; the tick, the fade
/// and the tag under it say everything this screen has to say about it.
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
        // The grid, and only the grid, is what moves. Everything above it is a
        // control, and a control that scrolls away is one you have to go and
        // find again.
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            // Two across on a phone, three on anything wider: big enough that
            // the picture is the game's name.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: offers.length,
            itemBuilder: (context, i) => _Tile(
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

/// One game, as its icon and nothing else.
///
/// Bright with a tick on its corner means it is in the run; faded means it is
/// not. The corner says whether it is ticked, and the tag under it, when there
/// is one, says why a ticked game still is not going to be played. That is the
/// whole state of this screen, which is why there is no plate under the icon,
/// no line of prose under the heading and no tally under the grid.
class _Tile extends StatelessWidget {
  const _Tile({
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

  /// How far the icon sits in from its cell, which is how far the corner mark
  /// and the tag under it hang off the icon without leaving the cell.
  static const _inset = 10.0;

  static const _animation = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    final locked = offer.isLocked;
    final pending = offer.lockPending;

    // Ticked *and* playable is the only state that gets the full colour. A game
    // the table is the wrong size for is not going to be played tonight, and a
    // bright icon promising otherwise is the lie the old footer went out of its
    // way to correct in words.
    final live = offer.chosen && offer.fitsTable && !locked && !pending;
    // Unticked, rather than merely unplayable, also steps back: a tap on a
    // game already faded because the table is short still visibly does
    // something.
    final unticked = !offer.chosen && !locked && !pending;
    final tag = _tag();

    return GestureDetector(
      // The whole cell, not just the picture: the gaps around a big icon are
      // where a thumb lands half the time.
      behavior: HitTestBehavior.opaque,
      onTap: withButtonSound(
        pending
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
      ),
      child: Padding(
        padding: const EdgeInsets.all(_inset),
        child: AnimatedScale(
          scale: unticked ? 0.9 : 1,
          duration: _animation,
          curve: Curves.easeOut,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              AnimatedOpacity(
                opacity: live ? 1 : 0.4,
                duration: _animation,
                child: _GameIcon(manifest: offer.manifest),
              ),
              Positioned(
                top: -_inset,
                right: -_inset,
                child: _Mark(offer: offer),
              ),
              if (tag != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -_inset,
                  child: Center(child: tag),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _tag() {
    if (offer.lockPending) return null;
    if (offer.isLocked) return const _PremiumTag();
    // Only on a game that does not fit: on every other one it would be twelve
    // repetitions of a number nobody is currently blocked by.
    if (offer.fitsTable) return null;
    return _NeedsTag(phones: offer.manifest.smallestTable);
  }
}

/// The game's icon, rounded the way a home screen rounds one.
///
/// Labelled with the title, so a screen reader still says the game's name.
/// A game nobody has drawn yet is its title on the same shape, so it takes the
/// same place in the grid.
class _GameIcon extends StatelessWidget {
  const _GameIcon({required this.manifest});

  final GameManifest manifest;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final radius = BorderRadius.circular(
        constraints.biggest.shortestSide * 0.22,
      );
      final asset = manifest.icon;
      if (asset == null) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: LobbyFlowColors.field,
            borderRadius: radius,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                manifest.title,
                textAlign: TextAlign.center,
                style: LobbyText.label.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        );
      }
      return ClipRRect(
        borderRadius: radius,
        child: SvgPicture.asset(
          asset,
          fit: BoxFit.cover,
          semanticsLabel: manifest.title,
        ),
      );
    },
  );
}

/// The tick, the ring, the padlock, or the spinner — whichever this game has
/// earned — as a disc on the icon's corner.
///
/// Rimmed in the page's white, so it reads as sitting on the icon rather than
/// as a spot painted into the picture.
class _Mark extends StatelessWidget {
  const _Mark({required this.offer});

  final GameOffer offer;

  static const _size = 32.0;
  static const _rim = BorderSide(color: LobbyFlowColors.paper, width: 3);

  @override
  Widget build(BuildContext context) {
    // Says nothing about money, because nothing is known about money yet. No
    // padlock, no tick and no ring: an inert game that is plainly not ready,
    // rather than a claim that turns out to be wrong half a second later.
    if (offer.lockPending) {
      return _disc(
        color: LobbyFlowColors.paper,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: LobbyFlowColors.muted,
          ),
        ),
      );
    }

    // A locked game has nothing a tap could toggle, so it gets no tick to
    // toggle. The padlock and the tag are its whole answer.
    //
    // The padlock means Premium and nothing else. A free game on a host that
    // cannot customise the run keeps its tick — the tap is what sends that
    // host to the paywall, not the icon.
    if (offer.isLocked) {
      return _disc(
        color: LobbyFlowColors.purple,
        child: const Icon(
          Icons.lock_outline,
          size: 16,
          color: LobbyFlowColors.ink,
        ),
      );
    }

    if (offer.chosen) {
      return _disc(
        color: LobbyFlowColors.ink,
        child: const Icon(Icons.check, size: 18, color: LobbyFlowColors.paper),
      );
    }

    return _disc(
      color: LobbyFlowColors.paper,
      border: const BorderSide(color: LobbyFlowColors.muted, width: 2.5),
    );
  }

  Widget _disc({
    required Color color,
    BorderSide border = _rim,
    Widget? child,
  }) => Container(
    width: _size,
    height: _size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.fromBorderSide(border),
    ),
    child: child,
  );
}

/// A small pill hung off the bottom of an icon, rimmed like [_Mark].
class _Tag extends StatelessWidget {
  const _Tag({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(LobbyMetrics.pillRadius),
      border: Border.all(color: LobbyFlowColors.paper, width: 3),
    ),
    child: child,
  );
}

class _PremiumTag extends StatelessWidget {
  const _PremiumTag();

  @override
  Widget build(BuildContext context) => _Tag(
    color: LobbyFlowColors.purple,
    child: Text(
      'PREMIUM',
      style: LobbyText.button.copyWith(fontSize: 10, letterSpacing: 0.4),
    ),
  );
}

/// The fewest phones a game needs, on a game this table is too small for.
///
/// A phone and a number rather than the sentence: "3+" alone could be players
/// or rounds, and the whole requirement would not fit under an icon.
class _NeedsTag extends StatelessWidget {
  const _NeedsTag({required this.phones});

  final int phones;

  @override
  Widget build(BuildContext context) => _Tag(
    color: LobbyFlowColors.field,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.smartphone, size: 12, color: LobbyFlowColors.ink),
        const SizedBox(width: 2),
        Text('$phones+', style: LobbyText.button.copyWith(fontSize: 12)),
      ],
    ),
  );
}
