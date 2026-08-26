# Getting Glassy onto an iPhone, free, without a Mac

Personal use, one device, no Apple Developer Program, no Mac purchase.

| | |
|---|---|
| Artifact | `Glassy-unsigned-ipa` from any green CI run |
| Size | ~505 KB |
| Requires | **iOS 17.0 or later** |
| Bundle ID | `com.orieltech.glassy` |
| Signing | none — the `.ipa` ships unsigned by design |

## Why it takes this shape

Two hard constraints drive everything below.

1. **The iOS SDK is Mac-only and closed-source.** No amount of tooling compiles
   an iPhone binary on Windows. A Mac has to exist somewhere in the chain.
2. **Installing on a device requires a signed app.** Signing is free with an
   ordinary Apple ID, but a free-tier certificate **expires after 7 days**.

The free answers: GitHub's macOS runners for (1), and a sideloader plus a
throwaway Apple ID for (2). Neither costs anything.

## 1. Get a build

`.github/workflows/ios.yml` runs on every push and can be triggered by hand from
the Actions tab. It runs the SurfCore suite, generates the Xcode project from
`project.yml`, builds unsigned, and uploads the artifact.

```
gh run download --name Glassy-unsigned-ipa --dir dist
```

Or download it from the run page and unzip once.

The repo is public, which is what makes the macOS runner minutes free — GitHub
gives public repositories unlimited standard-runner minutes. On a private repo,
macOS bills at a **10x multiplier** against a small monthly quota. Nothing here
is a credential: the Stormglass key never enters source control, and the CI build
has no signing secrets at all.

## 2. Prepare the PC

- **Apple device drivers.** Install *Apple Devices* from the Microsoft Store, or
  *iTunes*. Sideloadly's site says which one your Windows build needs — having
  the wrong one is the usual cause of "device not found".
- **[Sideloadly](https://sideloadly.io)** — free, and the shortest path from an
  `.ipa` to a working app.
- **A throwaway Apple ID** from [account.apple.com](https://account.apple.com).
  Signing means typing Apple ID credentials into a third-party tool and burning
  App IDs against that account, so don't use your main one. No payment method
  required.

## 3. Sideload

Plug the phone in, unlock it, tap **Trust** if asked. In Sideloadly: drag the
`.ipa` in, pick the device, enter the throwaway Apple ID, press **Start**.

Then on the phone: **Settings → General → VPN & Device Management →** tap the
Apple ID under *Developer App* → **Trust**.

Be online for the first launch — iOS verifies a free-signed certificate against
Apple's servers, and offline it fails with a misleading "Unable to Verify App".

## 4. Check the things CI cannot

The build is green and the engine has 147 passing tests, but no part of the UI
has been seen on a real screen. Worth verifying once:

- Layout is right-to-left; the beach name renders in Hebrew.
- The spot picker lists all eleven beaches and switching reloads.
- Wave height always appears with its slang — `0.8 מ׳ · מותן עד חזה`.
- **The buoy strip at Hadera.** See "Known gaps" below.
- SUP + beginner on an offshore-wind day: the safety banner sits *above* the
  score and cannot be dismissed.
- Larger Text at maximum: the hero card reflows rather than clipping.
- Airplane Mode + pull to refresh: the forecast stays with an age label instead
  of becoming an error screen.

## 5. Living with the 7-day certificate

Repeat step 3 weekly, or move to **[SideStore](https://sidestore.io)**, which
renews the certificate on-device over WiFi and removes the PC from the loop
entirely. Follow SideStore's own current instructions rather than a snapshot —
setup involves a pairing file and a helper networking app, and the steps change
between releases. Do it *after* the app is confirmed working, so you are not
debugging two things at once.

| Free-tier limit | Value |
|---|---|
| Certificate life | 7 days |
| Apps signed at once | 3 |
| New App IDs | 10 per week |
| App Store distribution | not possible |

The $99/yr Apple Developer Program buys year-long certificates and TestFlight,
and nothing else needed here.

## Known gaps on device

- **The buoy strip may show "אין מצוף בקרבת החוף".** ISRAMAR is scraped JSON
  over a server we do not control, and iOS App Transport Security is stricter
  than WSL's curl. If ground truth never appears on device but works in the
  smoke test, a narrowly-scoped ATS exception for `isramar.ocean.org.il` is the
  fix. The forecast is unaffected by design — a dead buoy degrades its own
  section only.
- **No model confidence.** Stormglass's free tier is ~10 requests/day, which
  cannot be called from a device. Confidence stays absent rather than invented.
- **`CFBundleShortVersionString` reads `1.0`,** not the `0.1.0` in `project.yml`
  — XcodeGen's generated Info.plist does not pick up `MARKETING_VERSION`.
  Cosmetic; updates work regardless, since replacement keys off the bundle ID.

## Troubleshooting

| Symptom | Cause |
|---|---|
| "Unable to Verify App" | Trust step skipped, or offline on first launch |
| Stops opening after a week | Certificate expired — re-sign |
| "Device not found" | Wrong Apple driver package on Windows |
| "Maximum number of apps" | Three free-signed apps already installed |
| Will not install at all | Phone is on iOS 16 or older |
