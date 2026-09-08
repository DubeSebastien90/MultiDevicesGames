import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../catalog.dart';
import '../contract/game.dart';
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
      final result =
          await Purchases.purchase(PurchaseParams.package(package));
      final unlocked = result.customerInfo.entitlements.active
          .containsKey(kPremiumEntitlementId);
      await widget.premium.refresh();
      if (!mounted) return;
      if (unlocked) {
        Navigator.of(context).pop();
      } else {
        setState(() => _purchasing = false);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      final cancelled = PurchasesErrorHelper.getErrorCode(e) ==
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.emoji_events, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trigger == null
                            ? 'Bring the full party'
                            : trigger!,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Unlock every game for the whole table, forever.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'One purchase on the host\'s phone unlocks these for everyone '
              'who joins — nobody else has to buy anything.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 4,
                ),
                child: Column(
                  children: [
                    for (final game in locked)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.lock_open,
                          size: 18,
                          color: scheme.primary,
                        ),
                        title: Text(game.manifest.title),
                        subtitle: Text(
                          game.manifest.tagline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.tune,
                        size: 18,
                        color: scheme.primary,
                      ),
                      title: const Text('Choosing what\'s in the run'),
                      subtitle: const Text(
                        'Pick tonight\'s lineup instead of playing the free '
                        'set',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_loadingOfferings)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (package == null)
              Text(
                _error ?? 'Nothing to buy yet — check back shortly.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
                textAlign: TextAlign.center,
              )
            else ...[
              FilledButton(
                onPressed: _purchasing ? null : () => _buy(package),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _purchasing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(
                        'Unlock everything · ${package.storeProduct.priceString}',
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                'One-time purchase. No subscription, no ads, ever.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (_error != null && package != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _purchasing ? null : _restore,
              child: const Text('Restore purchase'),
            ),
          ],
        ),
      ),
    );
  }

  String? get trigger => widget.trigger;
}
