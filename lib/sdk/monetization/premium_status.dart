import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

const String kPremiumEntitlementId = 'premium';

enum RestoreOutcome {
  restored,
  alreadyActive,
  nothingFound,
  unreachable,
  failed,
}

String restoreMessage(RestoreOutcome outcome) => switch (outcome) {
  RestoreOutcome.restored => 'Premium restored. All games are unlocked.',
  RestoreOutcome.alreadyActive => 'Premium is already active on this device.',
  RestoreOutcome.nothingFound =>
    'No previous purchase found for this App Store / Google Play account.',
  RestoreOutcome.unreachable =>
    "Couldn't reach the store. Check your connection and try again.",
  RestoreOutcome.failed =>
    "Couldn't restore purchases. Please try again later.",
};

class RevenueCatKeys {
  const RevenueCatKeys._();

  static const String apple = String.fromEnvironment('REVENUECAT_APPLE_KEY');
  static const String google = String.fromEnvironment('REVENUECAT_GOOGLE_KEY');
}

class PremiumStatus extends ChangeNotifier {
  bool _isPremium = false;
  bool _ready = false;
  String? _error;

  bool _configured = false;

  bool get isConfigured => debugUnlocked || _configured;

  static const Duration storeTimeout = Duration(seconds: 10);

  static const bool debugUnlocked =
      kDebugMode && !bool.fromEnvironment('LOCK_PREMIUM');

  static const bool debugForcedLocked =
      kDebugMode && bool.fromEnvironment('FORCE_NOT_PREMIUM');

  static const bool forcedPremium = bool.fromEnvironment('FORCE_PREMIUM');

  bool get isReady =>
      debugUnlocked || debugForcedLocked || forcedPremium || _ready;

  bool get isPremium =>
      forcedPremium || (!debugForcedLocked && (debugUnlocked || _isPremium));

  String? get error =>
      (debugUnlocked || debugForcedLocked || forcedPremium) ? null : _error;

  Future<void> initialize() async {
    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);

      final apiKey =
          defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
          ? RevenueCatKeys.apple
          : RevenueCatKeys.google;

      if (apiKey.isEmpty) {
        throw StateError(
          'No RevenueCat API key was compiled in. Run with '
          '--dart-define-from-file=env/revenuecat.json (see '
          'env/revenuecat.example.json).',
        );
      }

      final configuration = PurchasesConfiguration(apiKey);

      await Purchases.configure(configuration).timeout(storeTimeout);
      _configured = true;

      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);

      final info = await Purchases.getCustomerInfo().timeout(storeTimeout);
      _apply(info);
    } catch (e) {
      _error = '$e';
      _ready = true;
      notifyListeners();
    }
  }

  void _onCustomerInfo(CustomerInfo info) => _apply(info);

  void _apply(CustomerInfo info) {
    _isPremium = info.entitlements.active.containsKey(kPremiumEntitlementId);
    _ready = true;
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final info = await Purchases.getCustomerInfo().timeout(storeTimeout);
      _apply(info);
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  Future<RestoreOutcome> restore() async {
    final wasPremium = isPremium;

    if (!_configured) {
      return wasPremium
          ? RestoreOutcome.alreadyActive
          : RestoreOutcome.unreachable;
    }
    try {
      _apply(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      return code == PurchasesErrorCode.networkError ||
              code == PurchasesErrorCode.offlineConnectionError
          ? RestoreOutcome.unreachable
          : RestoreOutcome.failed;
    } catch (_) {
      return RestoreOutcome.failed;
    }
    if (!isPremium) return RestoreOutcome.nothingFound;
    return wasPremium ? RestoreOutcome.alreadyActive : RestoreOutcome.restored;
  }

  Future<void> retry() async {
    _error = null;
    _ready = false;
    notifyListeners();
    if (_configured) {
      await refresh();
      _ready = true;
      notifyListeners();
      return;
    }
    await initialize();
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    super.dispose();
  }
}
