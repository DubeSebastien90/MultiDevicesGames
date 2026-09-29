import 'package:flutter/foundation.dart';
// NO-IAP: RevenueCat is out of the binary until in-app purchases ship. The
// real [PremiumStatus] is kept commented out below; the stub at the bottom of
// this file stands in for it. To restore: uncomment these imports and the
// real class, delete the stub, and put `purchases_flutter` back in pubspec.
// import 'package:flutter/services.dart' show PlatformException;
// import 'package:purchases_flutter/purchases_flutter.dart';

/// The RevenueCat entitlement identifier that unlocks the full catalogue and
/// the game-selection screen. Must match the entitlement created in the
/// RevenueCat dashboard exactly.
const String kPremiumEntitlementId = 'premium';

/// How a [PremiumStatus.restore] ended — one per message the player is shown.
enum RestoreOutcome {
  /// Premium was found on the store account and is now unlocked.
  restored,

  /// This device already had Premium before asking.
  alreadyActive,

  /// The store answered, and there is nothing on this account to restore.
  nothingFound,

  /// The store could not be reached: no network, or the SDK never configured.
  unreachable,

  /// Anything else. Deliberately carries no detail — the raw error is for the
  /// logs, not for the player.
  failed,
}

/// What to tell the player after a restore, in the same words wherever the
/// button was.
String restoreMessage(RestoreOutcome outcome) => switch (outcome) {
  RestoreOutcome.restored => 'Premium restored. All games are unlocked.',
  RestoreOutcome.alreadyActive => 'Premium is already active on this device.',
  RestoreOutcome.nothingFound =>
    'No previous purchase found for this App Store / Google Play account.',
  RestoreOutcome.unreachable =>
    "Couldn't reach the store. Check your connection and try again.",
  RestoreOutcome.failed => "Couldn't restore purchases. Please try again later.",
};

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

// NO-IAP: the real class, commented out.
/*
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

  /// Whether [Purchases.configure] has succeeded.
  ///
  /// Tracked because [retry] has to know which half failed. Configuring the SDK
  /// a second time is the thing this class's doc warns about — it works in
  /// development and misbehaves quietly in production — so a retry that has
  /// already configured must ask for customer info instead, and only a retry
  /// that never got that far may configure.
  bool _configured = false;

  /// Whether [Purchases.configure] has succeeded — false if the API key was
  /// missing or the store never answered.
  ///
  /// Screens that call into [Purchases] directly (the paywall, for its own
  /// offerings/purchase/restore calls) must check this first: the native SDK
  /// crashes rather than throwing a catchable error when it is asked to do
  /// anything before it has been configured.
  bool get isConfigured => debugUnlocked || _configured;

  /// How long to wait on the store before giving up and saying so.
  ///
  /// **Not an optimisation — the thing that stops "we are still checking" from
  /// becoming a permanent state.** [isReady] is what lets the games list
  /// decline to draw a padlock on a game the host may already own, and that
  /// restraint is only kind while it is temporary: a spinner that never stops
  /// tells a paying customer even less than a wrong padlock did, because at
  /// least a padlock comes with a Restore button.
  ///
  /// A network that hangs rather than refuses is the case this exists for. A
  /// refusal already lands in the catch below within moments; a black hole —
  /// captive-portal WiFi is the everyday one — returns nothing at all, and
  /// without a deadline the future simply never completes.
  ///
  /// On expiry the state is exactly the state of any other failure: not
  /// premium, [error] set, [isReady] true. Padlocks come back, but this time
  /// with a banner saying the check failed and a button to try again — which is
  /// the honest end state, and the one a customer can act on.
  static const Duration storeTimeout = Duration(seconds: 10);

  /// Whether this build hands out Premium without asking the store.
  ///
  /// [kDebugMode] is a compile-time constant, so in profile and release builds
  /// this folds to `false` before the tree shaker runs and every branch below
  /// it is dropped. There is no runtime path — and no flag anybody could flip
  /// on a shipped binary — that turns this on in the build customers get.
  ///
  /// `--dart-define=LOCK_PREMIUM=true` puts the real gate back while staying in
  /// debug: [isPremium] then falls through to whatever RevenueCat's servers
  /// actually say about the local anonymous customer. That is *not* the same
  /// as "not premium" — an anonymous ID that was ever granted the entitlement
  /// (a leftover sandbox purchase, most often) keeps answering "premium"
  /// forever, on every machine that shares that install's local identity,
  /// until it is revoked in the dashboard. Use [debugForcedLocked] to bypass
  /// RevenueCat's answer entirely instead of relying on account state.
  static const bool debugUnlocked =
      kDebugMode && !bool.fromEnvironment('LOCK_PREMIUM');

  /// Whether this build shows the locked/paywall state no matter what
  /// RevenueCat's servers say about the local customer.
  ///
  /// `--dart-define=FORCE_NOT_PREMIUM=true` sets this. Unlike [debugUnlocked]
  /// going `false`, this does not depend on the anonymous customer actually
  /// lacking the entitlement — it skips asking entirely, so a device that
  /// picked up `premium` once (a sandbox purchase, an old test) still shows
  /// every padlock. [kDebugMode]-gated for the same reason as
  /// [debugUnlocked]: folds away in release, no runtime path turns it on in a
  /// shipped binary.
  static const bool debugForcedLocked =
      kDebugMode && bool.fromEnvironment('FORCE_NOT_PREMIUM');

  /// Whether this build hands out Premium without asking the store, in *any*
  /// build mode — including release.
  ///
  /// `--dart-define=FORCE_PREMIUM=true` sets this. Unlike [debugUnlocked],
  /// this is **not** [kDebugMode]-gated, so it survives into a real release
  /// binary — deliberately, for installing a release build on your own
  /// devices before the App Store Connect / RevenueCat offering chain is
  /// fully wired up. That is also exactly why it is dangerous: whoever runs
  /// `flutter build`/`flutter run` controls this flag, an installed app's
  /// user never can (dart-define is baked in at compile time, there is no
  /// runtime way to set it), but a build made with this flag on must never
  /// be the one that reaches App Store Connect or a real customer. Leave it
  /// off for every archive/upload; only ever pass it for a build going
  /// straight onto a device you hold.
  static const bool forcedPremium = bool.fromEnvironment('FORCE_PREMIUM');

  /// True once [CustomerInfo] has been fetched at least once. Before that,
  /// [isPremium] is a guess (false) rather than an answer — screens that gate
  /// on Premium should treat "not ready" as "don't show a locked badge yet"
  /// where that distinction matters, and as "not premium" everywhere it is
  /// simpler not to.
  bool get isReady => debugUnlocked || debugForcedLocked || forcedPremium || _ready;

  bool get isPremium =>
      forcedPremium || (!debugForcedLocked && (debugUnlocked || _isPremium));

  /// Silent under [debugUnlocked]/[debugForcedLocked]/[forcedPremium]: with
  /// the state pinned either way there are no padlocks for a failure banner
  /// to caution about, and on a machine with no `env/revenuecat.json` the
  /// missing-key
  /// [StateError] would otherwise put a red banner over every debug run of
  /// the games sheet.
  String? get error =>
      (debugUnlocked || debugForcedLocked || forcedPremium) ? null : _error;

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
      // Bounded too, so that no path through this method can leave [isReady]
      // false forever. Worst case is two timeouts back to back, which is a long
      // spinner but still a spinner that ends.
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
      // Bounded for the same reason [initialize] is: this is what Retry runs,
      // and a Retry that hangs is worse than the failure it was offered for.
      final info = await Purchases.getCustomerInfo().timeout(storeTimeout);
      _apply(info);
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  /// Asks the store for purchases made on this store account, and says how it
  /// went.
  ///
  /// The one restore both the paywall and Settings use, so the two buttons can
  /// never disagree about what happened. Never throws: every way it can end is
  /// a [RestoreOutcome] the caller turns into a message.
  Future<RestoreOutcome> restore() async {
    final wasPremium = isPremium;
    // [_configured], not [isConfigured]: under [debugUnlocked] the latter is
    // true without the SDK ever being set up, and the native SDK crashes
    // rather than throws when called unconfigured.
    if (!_configured) {
      return wasPremium ? RestoreOutcome.alreadyActive : RestoreOutcome.unreachable;
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

  /// Ask again, after a failure, from wherever it failed.
  ///
  /// This is the button behind [error]. Somebody who has paid and is looking at
  /// a locked catalogue because their phone had no signal at launch needs a way
  /// to say "look again" that is not "uninstall the app" — and the ordinary
  /// [refresh] is not it, because if [initialize] never got as far as
  /// configuring the SDK then every call into it will keep failing the same way.
  ///
  /// Clears [error] and drops back to "not settled" first, so the UI can show
  /// that something is happening rather than leaving the old failure on screen
  /// while the network is retried behind it.
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
*/

/// NO-IAP: stands in for the real [PremiumStatus] while RevenueCat is out of
/// the binary. Never Premium, always settled, never an error, and never talks
/// to a store — the same public shape, so [HostSession] and the tests that
/// subclass it compile unchanged.
class PremiumStatus extends ChangeNotifier {
  bool get isConfigured => false;
  bool get isReady => true;
  bool get isPremium => false;
  String? get error => null;

  Future<void> initialize() async {}
  Future<void> refresh() async {}
  Future<RestoreOutcome> restore() async => RestoreOutcome.unreachable;
  Future<void> retry() async {}
}
