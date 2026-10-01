import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../audio/ui_audio.dart';
import '../contract/game.dart';
import '../host/host_session.dart';
import '../monetization/paywall_view.dart';
import '../monetization/premium_status.dart';
import 'sticker/sticker.dart';

Future<void> showGamesScreen(
  BuildContext context,
  HostSession host,
  PremiumStatus premium,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (context) => Scaffold(
      backgroundColor: St.bg,
      body: StickerBackground(
        shapes: pickerShapes,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: StickerHeader(
                      'Games in the run',
                      size: 30,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([host, premium]),
                      builder: (context, _) => GamePicker(
                        offers: host.offers,
                        selectionLocked: premium.isReady && !premium.isPremium,
                        premiumError: premium.error,
                        onRetryPremium: premium.retry,
                        onChoose: (game, chosen) =>
                            host.chooseGame(game, chosen: chosen),
                        onAll: host.chooseAllGames,
                        onNone: host.chooseNoGames,
                        onSelectionLockedTap: () =>
                            showPaywall(context, premium),
                        onLockedTap: (offer) => showPaywall(
                          context,
                          premium,
                          game: offer.manifest.title,
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
  ),
);

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

  final void Function(MultiscreenGame game, bool chosen) onChoose;

  final VoidCallback? onAll;
  final VoidCallback? onNone;
  final bool selectionLocked;
  final VoidCallback? onSelectionLockedTap;

  final void Function(GameOffer offer)? onLockedTap;

  final String? premiumError;

  final Future<void> Function()? onRetryPremium;

  static const _pad = 20.0;
  static const _gapX = 18.0;

  static int _columnsFor(double width) => width >= _tabletWidth ? 3 : 2;

  static const _tabletWidth = 600.0;

  static const _ribbon = 14.0;

  VoidCallback? _actionFor(GameOffer offer) {
    if (offer.lockPending) return null;
    if (offer.isLocked) {
      return onLockedTap == null ? null : () => onLockedTap!(offer);
    }
    if (selectionLocked) return onSelectionLockedTap;
    return () => onChoose(offer.game, !offer.chosen);
  }

  void _showInfo(BuildContext context, GameOffer offer, Color color) {
    HapticFeedback.mediumImpact();
    final action = _actionFor(offer);
    showStickerSheet<void>(
      context,
      builder: (sheet) => _GameInfoSheet(
        offer: offer,
        color: color,
        selectionLocked: selectionLocked,
        onPrimary: action == null
            ? null
            : () {
                Navigator.of(sheet).pop();
                action();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = offers.any((o) => o.lockPending);
    final inRun = offers
        .where((o) => o.chosen && !o.isLocked && !o.lockPending)
        .length;

    VoidCallback? end(VoidCallback? action) =>
        pending ? null : (selectionLocked ? onSelectionLockedTap : action);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pad),
          child: Row(
            children: [
              StickerPill('$inRun/${offers.length}', size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'in the run\n'),
                      TextSpan(
                        text: 'Hold a game for info',
                        style: St.body(13, weight: FontWeight.w500),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: St.body(13, color: St.muted, height: 1.15),
                ),
              ),
              _EndButton(label: 'All', onTap: end(onAll)),
              const SizedBox(width: 10),
              _EndButton(label: 'None', onTap: end(onNone)),
            ],
          ),
        ),
        if (premiumError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(_pad, 16, _pad, 0),
            child: _PremiumTrouble(onRetry: onRetryPremium),
          )
        else if (pending)
          Padding(
            padding: const EdgeInsets.fromLTRB(_pad, 12, _pad, 0),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: St.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Checking your purchase…',
                  style: St.body(14, color: St.muted),
                ),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final columns = _columnsFor(box.maxWidth);
                  final tile =
                      (box.maxWidth - _pad * 2 - _gapX * (columns - 1)) /
                      columns;
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      _pad,
                      10,
                      _pad,
                      40 + MediaQuery.paddingOf(context).bottom,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: _gapX,
                      mainAxisSpacing: 16,
                      childAspectRatio: tile / (tile + _ribbon),
                    ),
                    itemCount: offers.length,
                    itemBuilder: (context, i) {
                      final offer = offers[i];
                      final color = St.tileBands[i % St.tileBands.length];
                      return _Tile(
                        offer: offer,
                        color: color,
                        tiltRight: i.isOdd,
                        onTap: _actionFor(offer),
                        onLongPress: () => _showInfo(context, offer, color),
                      );
                    },
                  );
                },
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 40,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00FFD23F), St.bg],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => StickerButton(
    height: 42,
    radius: 14,
    shadow: 3,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    onTap: onTap,
    child: Text(label, style: St.display(18)),
  );
}

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
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      radius: 18,
      shadow: 4,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          const StIcon(Symbols.cloud_off_rounded, size: 22, color: St.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not check your purchase. If you have bought Premium, it '
              'will unlock once this device can reach the store.',
              style: St.body(13, weight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          if (_retrying)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: St.ink,
                ),
              ),
            )
          else
            _EndButton(
              label: 'Retry',
              onTap: widget.onRetry == null ? null : _retry,
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.offer,
    required this.color,
    required this.tiltRight,
    required this.onTap,
    required this.onLongPress,
  });

  final GameOffer offer;
  final Color color;
  final bool tiltRight;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  static const _fade = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final locked = offer.isLocked;
    final pending = offer.lockPending;
    final ticked = offer.chosen && !locked && !pending;
    final live = ticked && offer.fitsTable;

    final opacity = live
        ? 1.0
        : ticked
        ? .6
        : (locked || pending)
        ? .45
        : .6;
    final grey = live ? 0.0 : (ticked ? .3 : .7);

    return Semantics(
      button: true,
      selected: ticked,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: withButtonSound(onTap),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.only(top: GamePicker._ribbon),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: AnimatedContainer(
                  duration: St.quick,
                  decoration: St.sticker(radius: 24, shadow: ticked ? 5 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(21),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedOpacity(
                          duration: _fade,
                          opacity: opacity,
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              greyscaleMatrix(grey),
                            ),
                            child: _GameArt(manifest: offer.manifest),
                          ),
                        ),
                        if (locked) const Center(child: _LockBadge()),
                        if (pending)
                          const Center(
                            child: SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: St.ink,
                              ),
                            ),
                          ),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: _PlayersBadge(
                            manifest: offer.manifest,
                            short: !offer.fitsTable && !locked && !pending,
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: AnimatedScale(
                            scale: ticked ? 1 : 0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutBack,
                            child: ticked ? const _Check() : const SizedBox(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -GamePicker._ribbon,
                left: -6,
                right: -6,
                child: Center(
                  child: AnimatedRotation(
                    turns: ticked ? (tiltRight ? 4 : -4) / 360 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: AnimatedContainer(
                      duration: St.quick,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: St.sticker(
                        color: ticked
                            ? color
                            : (locked ? St.premiumTint : St.white),
                        radius: 10,
                        shadow: 2,
                        border: 2.5,
                      ),
                      child: ExcludeSemantics(
                        child: Text(
                          offer.manifest.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: St.display(
                            16,
                            color: ticked
                                ? St.white
                                : (locked ? St.lockedText : St.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (locked)
                const Positioned(right: -6, bottom: -10, child: _PremiumPill()),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameArt extends StatelessWidget {
  const _GameArt({required this.manifest});

  final GameManifest manifest;

  @override
  Widget build(BuildContext context) {
    final asset = manifest.icon;
    if (asset == null) {
      return ColoredBox(
        color: St.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              manifest.title,
              textAlign: TextAlign.center,
              style: St.display(16),
            ),
          ),
        ),
      );
    }
    return SvgPicture.asset(
      asset,
      fit: BoxFit.cover,
      semanticsLabel: manifest.title,
    );
  }
}

class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: const BoxDecoration(color: St.ink, shape: BoxShape.circle),
    child: const Center(
      child: StIcon(Symbols.check_rounded, size: 18, color: St.white),
    ),
  );
}

class _LockBadge extends StatelessWidget {
  const _LockBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: St.premium,
      shape: BoxShape.circle,
      border: Border.all(color: St.ink, width: 3),
      boxShadow: St.hard(3),
    ),
    child: const Center(
      child: StIcon(Symbols.lock_rounded, size: 22, color: St.white),
    ),
  );
}

class _PremiumPill extends StatelessWidget {
  const _PremiumPill();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
    decoration: BoxDecoration(
      color: St.premium,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: St.ink, width: 2),
    ),
    child: Text(
      'PREMIUM',
      style: St.display(
        10,
        color: St.white,
        height: 1,
      ).copyWith(letterSpacing: .4),
    ),
  );
}

class _PlayersBadge extends StatelessWidget {
  const _PlayersBadge({required this.manifest, this.short = false});

  final GameManifest manifest;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final fg = short ? St.white : St.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 7, 2),
      decoration: BoxDecoration(
        color: short ? St.back : St.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: St.ink, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StIcon(Symbols.group_rounded, size: 14, color: fg),
          const SizedBox(width: 3),
          Text(
            '${manifest.smallestTable}+',
            style: St.display(13, color: fg, height: 1),
          ),
          if (manifest.players.pairsOnly) ...[
            const SizedBox(width: 3),
            Semantics(
              label: 'even number of phones',
              child: StIcon(Symbols.counter_2_rounded, size: 14, color: fg),
            ),
          ],
        ],
      ),
    );
  }
}

class _GameInfoSheet extends StatelessWidget {
  const _GameInfoSheet({
    required this.offer,
    required this.color,
    required this.selectionLocked,
    required this.onPrimary,
  });

  final GameOffer offer;
  final Color color;
  final bool selectionLocked;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final manifest = offer.manifest;
    final locked = offer.isLocked;
    final pending = offer.lockPending;

    final sells = locked || (selectionLocked && !pending);

    final (label, icon, bg, fg) = pending
        ? ('Checking…', Symbols.hourglass_rounded, St.white, St.ink)
        : sells
        ? (
            'Unlock with Premium',
            Symbols.lock_open_rounded,
            St.premium,
            St.white,
          )
        : offer.chosen
        ? ('Remove from run', Symbols.remove_rounded, St.white, St.ink)
        : ('Add to run', Symbols.add_rounded, St.go, St.white);

    final players =
        '${manifest.smallestTable}+ phones'
        '${manifest.players.pairsOnly ? ', in pairs' : ''}';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: StickerSheetShell(
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: St.ink, width: 3)),
                  ),
                  child: _GameArt(manifest: manifest),
                ),
                const Positioned(top: 12, right: 12, child: SheetCloseButton()),
                Positioned(
                  left: 16,
                  right: 64,
                  bottom: -20,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.rotate(
                      angle: -3 * math.pi / 180,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: St.sticker(
                          color: color,
                          radius: 14,
                          shadow: 3,
                        ),
                        child: Text(
                          manifest.title,
                          style: St.display(26, color: St.white, height: 1),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 34, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StickerPill(
                        players,
                        icon: Symbols.group_rounded,
                        color: offer.fitsTable ? St.white : St.back,
                        textColor: offer.fitsTable ? St.ink : St.white,
                        size: 15,
                        border: 2.5,
                      ),
                      if (locked)
                        const StickerPill(
                          'Premium',
                          icon: Symbols.lock_rounded,
                          color: St.premium,
                          size: 15,
                          border: 2.5,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    manifest.tagline,
                    style: St.body(
                      17,
                      weight: FontWeight.w600,
                      color: const Color(0xFF222222),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    manifest.goal,
                    style: St.body(
                      16,
                      weight: FontWeight.w500,
                      color: const Color(0xFF444444),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StickerButton(
                    height: 62,
                    radius: 22,
                    shadow: 5,
                    color: bg,
                    onTap: onPrimary,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StIcon(icon, size: 28, color: fg),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: St.display(24, color: fg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
