# Citolex iOS App — Setup Guide

This folder is a real native iOS project shell (Capacitor) wrapped around your
existing citolex.com code, plus two pieces of custom native Swift we wrote:

- **Native on-device text-to-speech** (`ios-plugin/NativeTtsPlugin.swift`) —
  replaces the browser's `speechSynthesis` with Apple's `AVSpeechSynthesizer`,
  so it works offline and can keep reading with the screen locked.
- **A Share Extension** (`ios-share-extension/`) — adds "Read in Citolex" to
  the iOS share sheet, so people can send an article straight from Safari (or
  Mail, Notes, etc.) into the reader.

`www/index.html` is your site's code with small additions that detect when
it's running inside the native app (`window.Capacitor.isNativePlatform()`)
and switch over to the native TTS / shared-text handling. **It still works
completely normally as a website too** — none of this touches the plain web
version at citolex.com.

## Cheapest path: GitHub Actions ($0, no Mac ever)

This repo now includes `.github/workflows/ios-testflight.yml`, which builds,
signs, and uploads Citolex to TestFlight entirely on GitHub's free macOS
runners — no rented or owned Mac at any point.

1. **Make the GitHub repo public.** Standard GitHub-hosted runners, including
   macOS, are unlimited-free for public repositories. (No app secrets live in
   the repo itself — signing keys go into GitHub's encrypted Actions secrets,
   covered below.) If you'd rather keep it private, it still works, you just
   have a limited number of free macOS-runner minutes per month before small
   per-minute charges kick in.

2. **Push this project to that repo:**
   ```
   git init
   git add .
   git commit -m "Citolex iOS app"
   git remote add origin <your-repo-url>
   git push -u origin main
   ```

3. **Follow `SIGNING.md`** to generate your signing certificate, App IDs, App
   Group, provisioning profiles, and App Store Connect API key — all done
   through openssl and Apple's websites, no Xcode. Add the resulting values
   as GitHub Actions secrets (also detailed in `SIGNING.md`).

4. **Push again** (or re-run the workflow from the Actions tab) and it
   builds automatically: adds the iOS platform, wires in the native TTS
   plugin and Share Extension via `scripts/configure_ios_project.rb`, signs,
   archives, and uploads to TestFlight.

The one piece of this that's scripted rather than clicked-through in Xcode —
and so the one part worth keeping an eye on — is
`scripts/configure_ios_project.rb`, which creates the Share Extension target
programmatically. It's written against Capacitor's documented project
layout, but if it errors in a CI run (Capacitor's template shifts
occasionally between versions), paste the error back here and it can be
patched, or as a last resort a single ~$1-2 rented Mac hour (see below) lets
you fix that one step by hand in Xcode and commit the result.

From here on: edit `www/index.html` or anything else on Windows, `git push`,
and the workflow builds and ships a new TestFlight build automatically.

---

## Alternative: rent a Mac for a one-time setup, then use Xcode Cloud

You don't need to own a Mac. The only genuinely Mac-only step is signing and
compiling the app in Xcode, and Apple's **Xcode Cloud** gives every Apple
Developer Program member **25 free build-hours per month at no extra cost** —
that's already included in the $99/year you paid, nothing more to buy.

The catch: linking your project to Xcode Cloud for the very first time has to
be done from inside the actual Xcode app, which only runs on macOS. So the
plan is one short, cheap rented Mac session to do that one-time setup, and
free Xcode Cloud builds after that, triggered automatically every time you
push code — including code you edit right here on Windows.

**Step-by-step:**

1. **Rent a Mac by the hour.** [MacinCloud](https://www.macincloud.com)'s
   Pay-As-You-Go plan runs about $1/hour with no subscription — you only pay
   for the time you use. Budget 1-2 hours for the initial setup below. Total
   cost: roughly $2-5.

2. **Push this project to a private GitHub repo** (free). From this folder on
   Windows:
   ```
   git init
   git add .
   git commit -m "Citolex iOS shell"
   git remote add origin <your-new-github-repo-url>
   git push -u origin main
   ```

3. **On the rented Mac**, clone the repo, then:
   ```
   npm install
   npx cap add ios
   npx cap sync ios
   npx cap open ios
   ```
   This opens the real Xcode project.

4. **Add the native plugin files.** In Xcode, right-click the `App` group in
   the file navigator → *Add Files to "App"* → select
   `ios-plugin/NativeTtsPlugin.swift` and `ios-plugin/SharedTextPlugin.swift`
   from this repo. Make sure "Copy items if needed" and the App target are
   checked.

5. **Add the Share Extension target.** File → New → Target → *Share
   Extension* → name it `CitolexShare`. Xcode generates its own
   `ShareViewController.swift`, `Info.plist`, and storyboard — replace the
   generated `ShareViewController.swift` with ours
   (`ios-share-extension/ShareViewController.swift`), and merge the
   `NSExtensionActivationRule` block from our `ios-share-extension/Info.plist`
   into the generated one (so it accepts shared text and URLs, not just
   images).

6. **Turn on the App Group** (lets the main app and the share extension pass
   text to each other). Select the `App` target → *Signing & Capabilities* →
   `+ Capability` → *App Groups* → add `group.com.citolex.app`. Repeat the
   same for the `CitolexShare` extension target, adding the **same** group ID.

7. **Leave Background Modes off.** Read-aloud is meant to stop when the app
   is backgrounded or the screen locks — don't add the *Audio, AirPlay, and
   Picture in Picture* background mode under *Signing & Capabilities*. (The
   CI pipeline actively strips this key from `Info.plist` even if a future
   Capacitor template starts setting it — see `scripts/configure_ios_project.rb`.)

8. **Set your Bundle ID and signing team.** `App` target → *Signing &
   Capabilities* → set your Team (your Apple Developer account) and confirm
   the bundle identifier matches what you'll register in App Store Connect
   (defaults to `com.citolex.app` — change it in `capacitor.config.json`
   first if you want something else, then re-run `npx cap sync ios`).

9. **App icon.** `AppIcon/icon-1024.png` in this repo is the real logo, and
   the CI pipeline already copies it into every icon slot on every build —
   nothing to do by hand. If you're doing a one-off manual Archive (step 11
   below) instead of a CI build, open `Assets.xcassets/AppIcon` in Xcode and
   drop it in yourself (Xcode will generate the other sizes for you).

10. **Link Xcode Cloud.** Product menu → *Xcode Cloud* → *Create Workflow*.
    Follow the prompts to connect your GitHub repo and your App Store Connect
    app record. Accept the default "build on every push to main" workflow.

11. **Do one manual Archive → Upload to App Store Connect** (Product →
    Archive) to get the first TestFlight build in and confirm signing works
    end-to-end. After this, you're done with the Mac.

From here on, every future code change — new features, tweaks to
`www/index.html`, anything that doesn't touch native Swift files or Xcode
project settings — you make on Windows, `git push`, and Xcode Cloud
automatically builds it and can hand it to TestFlight, using your free 25
monthly hours. You'd only need to rent a Mac again for something that
requires Xcode itself: adding another native plugin, changing signing, or
similar.

## What's in this folder

```
www/index.html                    Your site's code + native-app wiring
capacitor.config.json             App ID, name, colors
package.json                      Capacitor dependencies
ios-plugin/                       Native TTS + Share Extension bridge (Swift + TS)
ios-share-extension/               The "Read in Citolex" share sheet extension
scripts/configure_ios_project.rb  Scripts the Share Extension target + entitlements into the Xcode project
.github/workflows/ios-testflight.yml  The free GitHub Actions build/sign/upload pipeline
SIGNING.md                        Headless (no-Xcode) signing setup, step by step
AppIcon/icon-1024.png             App icon, applied to every build by CI
```

## Cost summary

| Item | Cost |
|---|---|
| Apple Developer Program | $99/year (already paid) |
| GitHub Actions builds (public repo) | $0, unlimited |
| Rented Mac fallback, only if the scripted target-creation step needs a hand fix | ~$1-2, one-time, if ever needed |
| **Total to get a real build in TestFlight** | **$99/year — nothing else, in the common case** |
