# Google Play — Setup for Live + License-Test Payments

Application ID: `com.reallifecorp.bubblegames` (from `android/app/build.gradle.kts`)
Currently signed with the **debug keystore even in release** — this must be
fixed before anything can be uploaded to Play (step 2).
Entitlement code already expects: entitlement id `premium`, a single
non-consumable "lifetime" package — same RevenueCat entitlement the Apple
side uses (see `docs/apple_payments_setup.md`), so no app code changes are
needed here beyond what's noted in step 2.

---

## 1. Google Play Developer account

- [ ] Register at play.google.com/console — one-time $25 fee (no yearly
      renewal, unlike Apple).

## 2. Fix release signing (blocking — do this first)

Play will not accept an app signed with the debug key.

- [ ] Generate an upload keystore:
      ```
      keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias upload
      ```
      Store the resulting `.jks` file and its passwords somewhere durable —
      losing it means you can never update this app listing again.
- [ ] Create `android/key.properties` (must be gitignored — add it if not
      already covered):
      ```
      storePassword=<password>
      keyPassword=<password>
      keyAlias=upload
      storeFile=/absolute/path/to/upload-keystore.jks
      ```
- [ ] Update `android/app/build.gradle.kts`: load `key.properties`, add a
      `release` signing config using it, and change
      `signingConfig = signingConfigs.getByName("debug")` (currently line 37)
      to point at the new `release` config instead.
- [ ] Enroll in **Play App Signing** when first uploading (Google's
      recommended default) — Google then re-signs your upload key with its
      own app signing key for distribution; your upload keystore only needs
      to keep authorizing new uploads, not protect the final distribution
      key.

## 3. Create the app in Play Console

- [ ] Play Console → Create app. Application ID must match
      `com.reallifecorp.bubblegames` exactly (set at app creation, cannot
      change later).
- [ ] Play requires more store-listing content up front than Apple does
      before some features unlock: short/full description, icon, at least
      2 phone screenshots, a privacy policy URL, and content rating
      questionnaire — fill these in even for internal testing only.

## 4. Build and upload once (required before in-app products fully work)

Play ties in-app product testing to having at least one uploaded build.

```
flutter build appbundle --release --dart-define-from-file=env/revenuecat.json
```

- [ ] Play requires `.aab` (App Bundle), not `.apk`, for new apps.
- [ ] Play Console → your app → Testing → Internal testing → Create release
      → upload the `.aab` from `build/app/outputs/bundle/release/`.
- [ ] Add yourself as an internal tester (email list) and roll out — no
      review wait for internal testing.

## 5. Create the in-app product

- [ ] Play Console → your app → Monetize → Products → In-app products → Create.
- [ ] Product type here is just called "in-app product" (Play's one-time
      purchase type — equivalent to Apple's non-consumable).
- [ ] Product ID: e.g. `premium_lifetime`. Write this down for step 7.
- [ ] Set a price, set status to Active.

## 6. Service account for RevenueCat (server-side verification)

- [ ] Play Console → Setup → API access → link a Google Cloud project (or
      create one).
- [ ] Create a Service Account from that linked GCP project, grant it
      "Financial data, orders, and cancellation survey responses" +
      "View app information" permissions back in Play Console's API access
      screen.
- [ ] Generate a JSON key for that service account and download it — treat
      it like any other credential, do not commit it.

## 7. RevenueCat: connect the Google Play app

- [ ] RevenueCat dashboard → Project → Apps → + New → Google Play.
- [ ] Package name: `com.reallifecorp.bubblegames`.
- [ ] Upload the service account JSON from step 6.
- [ ] Products → the Play product from step 5 should sync in (may need the
      app to have at least one closed/internal testing release live first);
      attach it to the **same `premium` entitlement** already created for
      Apple — one entitlement, both stores feed it, no extra app code.
- [ ] Add it to the same default Offering as a **Lifetime** package (same
      Offering RevenueCat entry as the Apple side, just a second package
      under it for the Play store).
- [ ] Copy the **public Google API key** (starts with `goog_`) from
      Project Settings → API Keys.

## 8. Wire the real key into the app

- [ ] Edit `env/revenuecat.json` (gitignored — see
      `env/revenuecat.example.json` for the shape) and set
      `REVENUECAT_GOOGLE_KEY` to the `goog_...` key from step 7.
- [ ] Same warning as Apple: never ship a `test_` key — Play Billing testing
      should go through License Testing (step 9), not RevenueCat's
      Test Store mode.

## 9. Add a license tester (for your own real-device testing)

- [ ] Play Console → Setup → License testing → add your Google account's
      email to the tester list.
- [ ] That account's purchases on this app are then free/simulated but go
      through the **real Play Billing UI** — the equivalent of Apple
      Sandbox.
- [ ] The device just needs to be signed into that Google account normally;
      no separate "sandbox mode" toggle like iOS.

## 10. Test the full purchase flow locally

```
flutter run --profile --dart-define-from-file=env/revenuecat.json
```

- [ ] `--profile` disables the app's `debugUnlocked` dev bypass (see
      `lib/sdk/monetization/premium_status.dart`), so the real paywall gate
      is active, while still installing as a standalone build for
      multi-device testing.
- [ ] Tap a locked game / "Unlock everything" → real Play Billing sheet
      should appear → confirm as the license tester account (no real
      charge) → entitlement unlocks.
- [ ] Test **Restore Purchase** from the paywall sheet too.

## 11. Roll out for real

- [ ] Once verified, promote the same (or a new) release from Internal
      Testing → Closed Testing / Production track as you're ready.
- [ ] Unlike Apple, Google does not pre-review in-app products against a
      specific submitted version the same way — the product just needs to
      be Active, and it becomes purchasable as soon as the app version using
      it is live on whichever track testers/users are on.

## Common pitfalls specific to this codebase

- The debug-signing issue in step 2 is a real blocker today — `flutter
  build appbundle --release` right now produces a bundle Play will reject
  outright, not just a testing inconvenience.
- Same `debugUnlocked`/`isConfigured` notes as the Apple doc apply
  identically here — the paywall code is shared between both stores, see
  `docs/apple_payments_setup.md`'s "Common pitfalls" section.
