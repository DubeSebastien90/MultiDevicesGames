import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../catalog.dart';
import '../contract/game.dart';
import '../ui/lobby_flow_style.dart';
import 'premium_status.dart';

/// Opens the paywall as a sheet over whatever locked something the tap.
///
/// [trigger] is why it opened, shown as the top line so the sheet answers the
/// question the tap actually asked — "unlock Hot Potato" reads differently
/// from "unlock the game list" even though both end at the same purchase.
Future<void> showPaywall(
  BuildContext context,
  PremiumStatus premium, {
  String? trigger,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  // The flow's paper, and its big radius: the sheet slides up over the games
  // list, and half a screen of the app's dark [ThemeData] arriving over a white
  // list is the seam this whole pass exists to remove.
  backgroundColor: LobbyFlowColors.paper,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(LobbyMetrics.bigRadius),
    ),
  ),
  builder: (sheet) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(sheet).height * 0.9,
    ),
    child: PaywallSheet(premium: premium, trigger: trigger),
  ),
);

/// The pitch, the price, and the button. Everything a host needs to decide,
/// nothing they have to scroll a store page to find.
///
/// Framed around the table rather than the phone: a host who buys Premium is
/// not buying something for themselves, they are buying the rest of the
/// catalogue for everyone who scans in tonight — so the copy says "the
/// table", not "you".
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key, required this.premium, this.trigger});

  final PremiumStatus premium;
  final String? trigger;

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  Offerings? _offerings;
  bool _loadingOfferings = true;
  bool _purchasing = false;
  String? _error;

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
    if (!widget.premium.isConfigured) {
      setState(() => _error = "Couldn't reach the store.");
      return;
    }
    setState(() {
      _purchasing = true;
      _error = null;
    });
    try {
      await Purchases.restorePurchases();
      await widget.premium.refresh();
      if (!mounted) return;
      if (widget.premium.isPremium) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _purchasing = false;
          _error = 'No previous purchase found on this account.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't restore: $e";
        _purchasing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = GameCatalog.playlist
        .where((g) => g.manifest.tier == GameTier.premium)
        .toList();
    final package = _lifetimePackage;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // The cup on yellow: the same disc the results screen hands a
                // winner, at the size a header can carry.
                const LobbyMark(
                  icon: Icons.emoji_events,
                  color: LobbyFlowColors.yellow,
                  size: 52,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trigger == null ? 'Bring the full party' : trigger!,
                        style: LobbyText.title.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Unlock every game for the whole table, forever.',
                        style: LobbyText.body,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              "One purchase on the host's phone unlocks these for everyone "
              'who joins — nobody else has to buy anything.',
              style: LobbyText.body,
            ),
            const SizedBox(height: 16),

            // What the money buys, on the flow's grey plate instead of a
            // Material card full of ListTiles.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              decoration: BoxDecoration(
                color: LobbyFlowColors.field,
                borderRadius: BorderRadius.circular(LobbyMetrics.bigRadius),
              ),
              child: Column(
                children: [
                  for (final game in locked)
                    _Unlocked(
                      icon: Icons.lock_open,
                      title: game.manifest.title,
                      subtitle: game.manifest.tagline,
                    ),
                  const _Unlocked(
                    icon: Icons.tune,
                    title: "Choosing what's in the run",
                    subtitle:
                        "Pick tonight's lineup instead of playing the free "
                        'set',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_loadingOfferings)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: LobbySpinner()),
              )
            else if (package == null)
              Text(
                _error ?? 'Nothing to buy yet — check back shortly.',
                style: _troubleStyle,
                textAlign: TextAlign.center,
              )
            else ...[
              LobbyPillButton(
                onPressed: _purchasing ? null : () => _buy(package),
                label: _purchasing
                    ? 'Working…'
                    : 'Unlock everything · '
                          '${package.storeProduct.priceString}',
                background: LobbyFlowColors.green,
                foreground: LobbyFlowColors.ink,
                fontSize: 17,
                radius: LobbyMetrics.bigRadius,
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'One-time purchase. No subscription, no ads, ever.',
                style: LobbyText.body,
                textAlign: TextAlign.center,
              ),
            ],
            if (_error != null && package != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: _troubleStyle, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 12),
            LobbyPillButton(
              onPressed: _purchasing ? null : _restore,
              label: 'Restore purchase',
              background: LobbyFlowColors.field,
              foreground: LobbyFlowColors.ink,
              fontSize: 15,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            ),
          ],
        ),
      ),
    );
  }

  /// Bad news, in the flow's coral rather than Material's error red — dark
  /// enough to read on paper, and still plainly not the colour of the rest.
  static final _troubleStyle = LobbyText.label.copyWith(
    color: LobbyFlowColors.shadeOf(LobbyFlowColors.coral),
  );

  String? get trigger => widget.trigger;
}

/// One line of what Premium buys: an icon, a name, and what it is.
class _Unlocked extends StatelessWidget {
  const _Unlocked({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: LobbyFlowColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LobbyText.label),
                Text(
                  subtitle,
                  style: LobbyText.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
