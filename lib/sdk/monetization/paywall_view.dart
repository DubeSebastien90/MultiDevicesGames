import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../audio/ui_audio.dart';
import '../catalog.dart';
import '../contract/game.dart';
import '../ui/sticker/sticker.dart';
import 'premium_status.dart';

/// Opens the paywall as a sheet over whatever locked something the tap.
///
/// [game] is the title of the Premium game that was tapped, if one was. The
/// sheet leads with it, so it answers the question the tap actually asked —
/// "unlock Hot Potato" reads differently from "unlock the game list" even
/// though both end at the same purchase.
Future<void> showPaywall(
  BuildContext context,
  PremiumStatus premium, {
  String? game,
}) => showStickerSheet<void>(
  context,
  builder: (sheet) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheet).height * .9,
    ),
    child: PaywallSheet(premium: premium, game: game),
  ),
);

/// The pitch, the price, and the button. Everything a host needs to decide,
/// nothing they have to scroll a store page to find.
///
/// Framed around the table rather than the phone: a host who buys Premium is
/// not buying something for themselves, they are buying the rest of the
/// catalogue for everyone who scans in tonight — so the copy says "your whole
/// party", not "you".
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key, required this.premium, this.game});

  final PremiumStatus premium;
  final String? game;

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  Offerings? _offerings;
  bool _loadingOfferings = true;
  bool _purchasing = false;
  String? _error;

  /// Kept apart from [_error]: that one belongs to the offer and the buy
  /// button, and a restore failing must not take over the place where the
  /// price would be.
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    // The native SDK crashes rather than throwing a catchable error when
    // asked for anything before [Purchases.configure] has succeeded — this
    // sheet can be reached even when it never did (missing API key, or the
    // store timing out at launch), so it must check before calling in.
    if (!widget.premium.isConfigured) {
      setState(() {
        _error = widget.premium.error ?? "Couldn't reach the store.";
        _loadingOfferings = false;
      });
      return;
    }
    try {
      final offerings = await Purchases.getOfferings();
      if (!mounted) return;
      setState(() {
        _offerings = offerings;
        _loadingOfferings = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't reach the store: $e";
        _loadingOfferings = false;
      });
    }
  }

  Package? get _lifetimePackage {
    final current = _offerings?.current;
    if (current == null) return null;
    // Lifetime is a non-consumable, so RevenueCat surfaces it as the
    // "lifetime" package type on whichever offering is marked current in the
    // dashboard — no product identifier hardcoded here, so renaming the
    // product in App Store Connect never breaks this screen.
    for (final pkg in current.availablePackages) {
      if (pkg.packageType == PackageType.lifetime) return pkg;
    }
    return current.availablePackages.isEmpty
        ? null
        : current.availablePackages.first;
  }

  Future<void> _buy(Package package) async {
    if (!widget.premium.isConfigured) {
      setState(() => _error = "Couldn't reach the store.");
      return;
    }
    setState(() {
      _purchasing = true;
      _error = null;
    });
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      final unlocked = result.customerInfo.entitlements.active.containsKey(
        kPremiumEntitlementId,
      );
      await widget.premium.refresh();
      if (!mounted) return;
      if (unlocked) {
        Navigator.of(context).pop();
      } else {
        setState(() => _purchasing = false);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      final cancelled =
          PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError;
      setState(() {
        _purchasing = false;
        if (!cancelled) _error = "That didn't go through: ${e.message}";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "That didn't go through: $e";
        _purchasing = false;
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _purchasing = true;
      _restoreError = null;
    });
    final outcome = await widget.premium.restore();
    if (!mounted) return;
    if (outcome == RestoreOutcome.restored ||
        outcome == RestoreOutcome.alreadyActive) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _purchasing = false;
      _restoreError = restoreMessage(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = GameCatalog.playlist
        .where((g) => g.manifest.tier == GameTier.premium)
        .toList();
    final package = _lifetimePackage;
    final game = widget.game;

    return StickerSheetShell(
      children: [
        _Header(
          line: game != null
              ? '$game is a premium game. Unlock it and every premium game '
                    'for your whole party.'
              : "Pick tonight's lineup and unlock every premium game for "
                    'your whole party.',
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // What the money buys: every Premium game, and the right to
                // choose the lineup at all.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in locked)
                      _Chip(
                        icon: Symbols.lock_open_rounded,
                        label: g.manifest.title,
                      ),
                    const _Chip(
                      icon: Symbols.tune_rounded,
                      label: 'Pick the lineup',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "One purchase on the host's phone unlocks it for everyone "
                  'who joins — nobody else has to buy anything.',
                  textAlign: TextAlign.center,
                  style: St.body(13, weight: FontWeight.w500, color: _grey),
                ),
                const SizedBox(height: 18),
                if (_loadingOfferings)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          color: St.ink,
                        ),
                      ),
                    ),
                  )
                else if (package == null)
                  Text(
                    _error ?? 'Nothing to buy yet — check back shortly.',
                    style: _troubleStyle,
                    textAlign: TextAlign.center,
                  )
                else
                  Center(
                    child: _PriceSticker(
                      price: package.storeProduct.priceString,
                    ),
                  ),
                const SizedBox(height: 16),
                StickerButton(
                  height: 66,
                  radius: 22,
                  shadow: 5,
                  color: St.go,
                  onTap: _purchasing || package == null
                      ? null
                      : () => _buy(package),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_purchasing) ...[
                        const StIcon(
                          Symbols.lock_open_rounded,
                          size: 30,
                          color: St.white,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _purchasing ? 'Working…' : 'Unlock Premium',
                        style: St.display(26, color: St.white),
                      ),
                    ],
                  ),
                ),
                if (_error != null && package != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: _troubleStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: withButtonSound(
                        () => Navigator.of(context).pop(),
                      ),
                      style: TextButton.styleFrom(foregroundColor: _grey),
                      child: Text(
                        'Maybe later',
                        style: St.body(14, color: _grey),
                      ),
                    ),
                    TextButton(
                      onPressed: withButtonSound(_purchasing ? null : _restore),
                      style: TextButton.styleFrom(foregroundColor: _grey),
                      child: Text(
                        'Restore purchase',
                        style: St.body(
                          14,
                          color: _grey,
                        ).copyWith(decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
                if (_restoreError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _restoreError!,
                    style: _troubleStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _grey = Color(0xFF555555);

  /// Bad news in the back button's red — plainly not the colour of the rest.
  static final _troubleStyle = St.body(14, color: St.back);
}

/// The purple band: the crown wiggling, the headline, and why it opened.
class _Header extends StatelessWidget {
  const _Header({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: St.ink, width: 3)),
    ),
    child: ColoredBox(
      color: St.premium,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: DotsPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              children: [
                Wiggle(
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: St.sticker(
                      color: St.gold,
                      radius: 22,
                      shadow: 4,
                    ),
                    child: const Center(
                      child: StIcon(
                        Symbols.workspace_premium_rounded,
                        size: 44,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Go Premium!',
                  textAlign: TextAlign.center,
                  style: St.display(34, color: St.white, height: 1).copyWith(
                    shadows: const [
                      Shadow(color: St.ink, offset: Offset(3, 3)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: St.body(15, color: St.white, height: 1.35),
                ),
              ],
            ),
          ),
          const Positioned(top: 12, right: 12, child: SheetCloseButton()),
        ],
      ),
    ),
  );
}

/// One thing Premium buys, as a lilac pill.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF1E6FF),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: St.ink, width: 2),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StIcon(icon, size: 15, color: St.premium),
        const SizedBox(width: 4),
        Text(label, style: St.display(14, height: 1)),
      ],
    ),
  );
}

/// The store's own price, on a gold sticker. Never a number of our own: the
/// store localises it, and a hardcoded "€3.99" is wrong in every other
/// country.
class _PriceSticker extends StatelessWidget {
  const _PriceSticker({required this.price});

  final String price;

  @override
  Widget build(BuildContext context) => StickerCard(
    color: St.gold,
    radius: 20,
    shadow: 4,
    tiltDeg: -1.5,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(price, style: St.display(34, height: 1)),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'One-time payment',
                style: St.body(13, color: St.muted, height: 1.2),
              ),
              Text(
                'Yours forever, no subscription',
                style: St.body(
                  13,
                  weight: FontWeight.w500,
                  color: St.muted,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
