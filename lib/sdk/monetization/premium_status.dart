import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The RevenueCat entitlement identifier that unlocks the full catalogue and
/// the game-selection screen. Must match the entitlement created in the
/// RevenueCat dashboard exactly.
const String kPremiumEntitlementId = 'premium';

/// The public RevenueCat API keys for this app, one per store.
///
/// These are safe to ship in the client — they only ever authorise *reading*
/// offerings and *making* purchases as the current user, never RevenueCat
/// account access. Kept out of the committed source anyway, as a matter of
/// habit rather than because leaking one would be a real incident: every
/// build (local run, archive, CI) must pass
/// `--dart-define-from-file=env/revenuecat.json`, or these are empty strings
/// and [PremiumStatus.initialize] fails loudly rather than configuring the
/// SDK with a key that was never real. See `env/revenuecat.example.json`.
class RevenueCatKeys {
  const RevenueCatKeys._();

  static const String apple = String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const String google =
      String.fromEnvironment('REVENUECAT_GOOGLE_KEY');
}

/// Whether this device currently has Premium, and the single place that asks
/// RevenueCat.
///
/// A [ChangeNotifier] rather than a stream: everything that reads
/// [isPremium] today is a widget tree that already rebuilds off a
/// [ChangeNotifier] ([AppController], [HostSession]), so this fits the same
/// shape instead of introducing a second reactive pattern next to it.
///
/// Lives for the app's whole life, created once in `main.dart` — the SDK is
/// configured exactly once per process, and re-configuring it on every
/// paywall visit would be the kind of thing that works in development and
/// silently misbehaves in production.
class PremiumStatus extends ChangeNotifier {
  bool _isPremium = false;
  bool _ready = false;
  String? _error;

  /// True once [CustomerInfo] has been fetched at least once. Before that,
  /// [isPremium] is a guess (false) rather than an answer — screens that gate
  /// on Premium should treat "not ready" as "don't show a locked badge yet"
  /// where that distinction matters, and as "not premium" everywhere it is
  /// simpler not to.
  bool get isReady => _ready;

  bool get isPremium => _isPremium;

  String? get error => _error;

  /// Configures the RevenueCat SDK and loads the current entitlement state.
  /// Call once, before the first frame that might ask [isPremium].
  ///
  /// Failure is not fatal — a phone with no network at launch should still
  /// open to the lobby. It is surfaced on [error] rather than thrown, and
  /// [isPremium] simply stays false until the next successful fetch.
  Future<void> initialize() async {
    try {
      await Purchases.setLogLevel(
        kDebugMode ? LogLevel.debug : LogLevel.warn,
      );

      final apiKey = defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
          ? RevenueCatKeys.apple
          : RevenueCatKeys.google;

      if (apiKey.isEmpty) {
        // Configuring the SDK with an empty key would fail inside the plugin
        // with a much less obvious error, on every launch, forever — so this
        // stops here and says exactly what is missing instead.
        throw StateError(
          'No RevenueCat API key was compiled in. Run with '
          '--dart-define-from-file=env/revenuecat.json (see '
          'env/revenuecat.example.json).',
        );
      }

      final configuration = PurchasesConfiguration(apiKey);
      await Purchases.configure(configuration);

      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);

      final info = await Purchases.getCustomerInfo();
      _apply(info);
    } catch (e) {
      _error = '$e';
      _ready = true;
      notifyListeners();
    }
  }

  void _onCustomerInfo(CustomerInfo info) => _apply(info);

  void _apply(CustomerInfo info) {
    _isPremium =
        info.entitlements.active.containsKey(kPremiumEntitlementId);
    _ready = true;
    _error = null;
    notifyListeners();
  }

  /// Re-reads entitlement state from RevenueCat's cache/servers. The paywall
  /// calls this right after a purchase or restore completes, on top of the
  /// listener, so the UI updates even if the update event is briefly delayed.
  Future<void> refresh() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _apply(info);
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    super.dispose();
  }
}
