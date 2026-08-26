# Getting Glassy onto an iPhone, free, without a Mac

Personal use, one device, no Apple Developer Program, no Mac purchase.

## Why it takes this shape

Two hard constraints drive everything below.

1. **The iOS SDK is Mac-only and closed-source.** No amount of tooling compiles
   an iPhone binary on Windows. A Mac has to exist somewhere in the chain.
2. **Installing on a device requires a signed app.** Signing is free with an
   ordinary Apple ID, but a free-tier certificate **expires after 7 days** and
   has to be re-signed.

The free answers: GitHub's macOS runners for (1), and on-device re-signing for
(2). Neither costs anything.

## One-time setup

### 1. Make the repository public

GitHub Actions is free with **unlimited minutes on standard runners for public
repositories**, macOS included. On a private repo, macOS minutes bill against a
small monthly free quota at a **10x multiplier**, which a few builds a week will
exhaust.

If the repo has to stay private, the workflow still works — you are just on a
budget. Nothing in this repo is a credential (see `.gitignore`: the Stormglass
key never enters source control, and the CI build has no signing secrets), so
making it public is safe.

### 2. Get a build

`.github/workflows/ios.yml` runs on every push and can be triggered by hand from
the **Actions** tab. It runs the SurfCore suite, generates the Xcode project
from `project.yml`, builds unsigned, and uploads `Glassy-unsigned-ipa`.

Download the artifact and unzip it once — GitHub wraps artifacts in a zip, so
you end up with `Glassy.ipa` inside.

### 3. Install SideStore on the iPhone

SideStore is the AltStore fork built specifically so that **refreshing does not
need a computer on the network**. Set up once, then it renews the 7-day
certificate on-device over WiFi — which is what makes "anytime, anywhere" hold
rather than tethering you to a laptop every week.

Setup needs, once:

- a free Apple ID (use a throwaway, not your main one — it gets an app-specific
  password and is tied to the signing)
- a **pairing file** for the phone, generated from Windows
- the SideStore app itself, installed via that pairing

Follow the current official instructions at **<https://sidestore.io>** rather
than any steps written here — this part of the ecosystem changes with iOS
releases, and a stale walkthrough is worse than none.

Once SideStore is on the phone, installing `Glassy.ipa` is a file-picker away,
and every future CI build is: download artifact → open in SideStore → replace.

## What the free tier costs you

| Limit | Value | Consequence |
|---|---|---|
| Certificate lifetime | 7 days | SideStore re-signs on-device; you do nothing |
| Apps sideloaded at once | 3 | Fine for one app |
| New App IDs per 7 days | 10 | Only matters if you keep changing the bundle ID |
| App Store distribution | not possible | Personal use only, which is the plan |

The $99/yr Apple Developer Program buys 1-year certificates and TestFlight. It
buys nothing else you need here.

## Known gaps on device

- **The buoy strip may show "no buoy reporting".** ISRAMAR is scraped JSON over
  a server we do not control, and iOS App Transport Security is stricter than
  WSL's curl. If ground truth never appears on device but works in the smoke
  test, a narrowly-scoped ATS exception for `isramar.ocean.org.il` is the fix.
  The forecast is unaffected by design — a dead buoy degrades its own section.
- **No model confidence.** Stormglass's free tier is ~10 requests/day, which
  cannot be called from a device. Confidence stays absent rather than invented.
- **Accessibility sizes are unverified.** Dynamic Type is wired up, but AX5
  reflow has not been seen on a real screen. Check it once the app is on the
  phone.
