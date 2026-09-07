# Apple App Store — Setup for Live + Sandbox Payments

Bundle ID: `com.reallifecorp.bubblegames`
Version: `1.0.0+1` (pubspec.yaml)
Entitlement code already expects: entitlement id `premium`, a single
non-consumable "lifetime" package (see `lib/sdk/monetization/premium_status.dart`
and `paywall_view.dart`).

No app code changes are required for anything below — this is dashboard
configuration plus one local signing/config step.

---

## 1. Apple Developer account

- [ ] Enroll in the Apple Developer Program ($99/year) if not already done,
      under the account that owns team `SG55TPQLVN` (already referenced by
      the Xcode project's automatic signing).

## 2. App Store Connect: create the app

- [ ] App Store Connect → Apps → New App.
- [ ] Bundle ID: `com.reallifecorp.bubblegames` (must already exist under
      Certificates, Identifiers & Profiles — create it there first if it
      doesn't).
- [ ] Platform: iOS. Name, primary language, SKU (any internal string).

## 3. Create the in-app purchase

- [ ] App Store Connect → your app → Monetization → In-App Purchases → +.
- [ ] Type: **Non-Consumable** (matches `PackageType.lifetime` in
      `paywall_view.dart`).
- [ ] Reference name: internal only, e.g. "Premium Lifetime".
- [ ] Product ID: e.g. `com.reallifecorp.bubblegames.premium_lifetime`.
      Write this down — you'll paste it into RevenueCat in step 5.
- [ ] Set a price tier.
- [ ] Add the required "Review Notes" + a screenshot of the unlocked state
      (Apple requires this before an IAP can go to review).
- [ ] Status should reach "Ready to Submit" (it can stay there — it does not
      need to be submitted with a build yet to be testable in Sandbox).

## 4. App Store Connect API key (for RevenueCat to read your products)

- [ ] Users and Access → Integrations → App Store Connect API → +.
- [ ] Role: at least "App Manager". Download the `.p8` key file — **only
      downloadable once**, store it securely (do not commit it).
- [ ] Note the Key ID and Issuer ID shown alongside it.

## 5. RevenueCat: connect the Apple app

- [ ] RevenueCat dashboard → Project → Apps → + New → App Store.
- [ ] Bundle ID: `com.reallifecorp.bubblegames`.
- [ ] Upload the `.p8` key + Key ID + Issuer ID from step 4, so RevenueCat can
      sync products automatically instead of manual entry.
- [ ] Entitlements → create one named exactly `premium` (must match
      `kPremiumEntitlementId` in `lib/sdk/monetization/premium_status.dart:7`
      — a typo here silently breaks unlock detection with no error).
- [ ] Products → the App Store Connect product from step 3 should sync in;
      attach it to the `premium` entitlement.
- [ ] Offerings → default offering → Packages → add the product as a
      **Lifetime** package type. Mark this offering "Current".
- [ ] Copy the **public Apple API key** (starts with `appl_`) from
      Project Settings → API Keys.

## 6. Wire the real key into the app

- [ ] Edit `env/revenuecat.json` (gitignored, not committed — see
      `env/revenuecat.example.json` for the shape) and set
      `REVENUECAT_APPLE_KEY` to the `appl_...` key from step 5.
- [ ] Never use a RevenueCat key starting with `test_` for anything beyond
      throwaway CI — Test Store mode fakes purchases without StoreKit and is
      known to break/freeze when its alert tries to present over Flutter's
      view hierarchy on iOS. **Apple also rejects any submission built with
      a Test Store key.**

## 7. Release signing (needed to archive/upload at all)

- [ ] Confirm Xcode's automatic signing (team `SG55TPQLVN`) has a valid
      Distribution certificate and provisioning profile — Xcode can
      generate these automatically the first time you Archive, as long as
      you're logged into the right Apple ID in Xcode's Accounts settings.

## 8. Create a Sandbox tester (for your own real-device testing)

- [ ] App Store Connect → Users and Access → Sandbox → Testers → +.
- [ ] Any email you control works (does not need to be verifiable/real).
- [ ] On the test iPhone: Settings → App Store → Sandbox Account (near the
      bottom) → sign in with the tester. **Do not sign out of your real
      Apple ID anywhere** — sandbox account is a separate slot since
      iOS 17/18.

## 9. Test the full purchase flow locally

```
flutter run --profile --dart-define-from-file=env/revenuecat.json
```

- [ ] `--profile`, not `--release` or debug, for day-to-day multi-device
      testing: profile mode disables the app's `debugUnlocked` dev bypass
      (see `premium_status.dart`) so the real paywall gate is active, while
      still installing as a standalone build across multiple phones without
      staying tethered to `flutter run`.
- [ ] Tap a locked game / "Unlock everything" → real StoreKit sheet should
      appear (not a RevenueCat Test Store alert) → confirm with Face ID/Touch
      ID prompt (sandbox, no real charge) → entitlement should unlock
      immediately.
- [ ] Test **Restore Purchase** too, from the paywall sheet's bottom button —
      sign out/back in on a fresh install to confirm restoring works.

## 10. Build and upload for TestFlight / App Review

```
flutter build ipa --release --dart-define-from-file=env/revenuecat.json
```

- [ ] Confirm the key baked in is the **real `appl_...` key**, not the test
      key — this flag must be passed to every release build, or the app
      silently ships with no RevenueCat key at all (empty string) and the
      paywall will show "Couldn't reach the store" for every real user.
- [ ] Upload the resulting `.ipa` via Xcode Organizer or
      `xcrun altool` / Transporter.
- [ ] Add the build to a version in App Store Connect, attach the IAP from
      step 3 to that version submission (App Review will not test an IAP
      that isn't attached to the version being reviewed).
- [ ] In "App Review Information" notes, explain the unlock is host-side and
      one-time (not per-player, not a subscription) so the reviewer knows
      what to look for — unclear unlock behavior is a common rejection
      reason for one-off apps like this.

## 11. What Apple's reviewers actually test with

- [ ] Nothing further needed from you: once the IAP is attached to the
      submitted version, App Review's own devices purchase against Apple's
      Sandbox automatically — same StoreKit UI, same code path you tested
      in step 9, just using Apple's own test accounts instead of yours.

## Common pitfalls specific to this codebase

- `premium_status.dart`'s `debugUnlocked` is `true` in **debug** builds only
  (compiles away in profile/release) — if you can't reproduce a paywall bug,
  you're probably running plain `flutter run` in debug. Add
  `--dart-define=LOCK_PREMIUM=true` to force the real gate while still
  keeping a debugger attached.
- `PaywallSheet` (`paywall_view.dart`) now checks
  `PremiumStatus.isConfigured` before calling into `Purchases` — if you see
  "Couldn't reach the store" instead of a crash, that's this guard working
  as intended; check that `env/revenuecat.json` was actually passed to the
  build.
