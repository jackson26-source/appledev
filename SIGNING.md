# Signing setup — all done from a web browser, no Xcode required

This is the part that replaces what Xcode's "Automatic Signing" checkbox
normally does for you. It's a one-time setup (about 20-30 minutes), done
entirely through openssl (works fine on Windows) and the Apple Developer /
App Store Connect websites. Once it's done, every future GitHub Actions
build reuses it automatically.

## 1. Generate a Certificate Signing Request (CSR)

On Windows, in a terminal with OpenSSL available (Git Bash includes it):

```
openssl genrsa -out citolex_dist.key 2048
openssl req -new -key citolex_dist.key -out citolex_dist.csr -subj "/emailAddress=you@example.com, CN=Your Name, C=US"
```

Keep `citolex_dist.key` — you'll need it in step 3.

## 2. Create a Distribution Certificate

1. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list)
2. Click **+**, choose **Apple Distribution**, upload `citolex_dist.csr`
3. Download the resulting `.cer` file

## 3. Convert to a .p12 (what GitHub Actions actually needs)

```
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
openssl pkcs12 -export -inkey citolex_dist.key -in distribution.pem -out citolex_dist.p12 -passout pass:SOME_PASSWORD_YOU_PICK
```

Then base64-encode it for GitHub:

```
certutil -encode citolex_dist.p12 citolex_dist_base64.txt
```

(On Windows, `certutil -encode` is the equivalent of `base64` — just strip
the `-----BEGIN CERTIFICATE-----` / `-----END-----` lines it adds before
pasting into the GitHub secret, or use `openssl base64 -in citolex_dist.p12
-out citolex_dist_base64.txt` in Git Bash instead, which doesn't add those.)

## 4. Register both App IDs

Go to [Identifiers](https://developer.apple.com/account/resources/identifiers/list):

1. Create `com.citolex.app` (the main app) — under Capabilities, check **App Groups**
2. Create `com.citolex.app.share` (the share extension) — check **App Groups** here too

## 5. Create the App Group

Go to [App Groups](https://developer.apple.com/account/resources/identifiers/list/applicationGroup):

1. Create a group with the identifier `group.com.citolex.app`
2. Edit both App IDs from step 4 and attach this group to each

## 6. Create two Provisioning Profiles

Go to [Profiles](https://developer.apple.com/account/resources/profiles/list):

1. **App Store** distribution profile for `com.citolex.app` → select your
   distribution certificate → name it exactly **Citolex App Store**
   (the workflow file references this exact name)
2. **App Store** distribution profile for `com.citolex.app.share` → name it
   exactly **Citolex Share App Store**

Download both `.mobileprovision` files, then base64-encode each the same way
as step 3.

## 7. Register the app in App Store Connect

Go to [App Store Connect](https://appstoreconnect.apple.com) → My Apps → **+** →
New App. Platform iOS, name "Citolex", bundle ID `com.citolex.app` (pick it
from the dropdown — it'll be there from step 4), any SKU. This creates the
app record the upload step needs to find.

## 8. Create an App Store Connect API key (for the automated upload)

Go to [Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/api)

1. Click **+** to generate a key, role **App Manager**
2. Download the `.p8` file **immediately** — Apple only lets you download it once
3. Note the **Key ID** and **Issuer ID** shown on that page
4. Base64-encode the `.p8` file the same way as before

## 9. Find your Team ID

[developer.apple.com/account](https://developer.apple.com/account) → scroll to
**Membership details** → **Team ID** (a 10-character code).

## 10. Add everything as GitHub secrets

In your repo: **Settings → Secrets and variables → Actions → New repository secret**.
Add each of these (paste the base64 text for the `_BASE64` ones):

| Secret name | Value |
|---|---|
| `IOS_DIST_CERT_P12_BASE64` | base64 of `citolex_dist.p12` |
| `IOS_DIST_CERT_PASSWORD` | the password you picked in step 3 |
| `IOS_APP_PROVISION_PROFILE_BASE64` | base64 of the App target's `.mobileprovision` |
| `IOS_SHARE_PROVISION_PROFILE_BASE64` | base64 of the Share extension's `.mobileprovision` |
| `APPSTORE_API_KEY_ID` | Key ID from step 8 |
| `APPSTORE_API_ISSUER_ID` | Issuer ID from step 8 |
| `APPSTORE_API_PRIVATE_KEY_BASE64` | base64 of the `.p8` file |
| `APPLE_TEAM_ID` | Team ID from step 9 |

That's it — push to `main` and the `ios-testflight.yml` workflow should
build, sign, and upload a build to TestFlight automatically, entirely on
GitHub's free macOS runners.

## If a build fails

Open the failed run in the **Actions** tab and read the step that went red —
these builds fail loudly and specifically (wrong bundle ID, expired profile,
missing secret, etc.), it won't be a silent mystery. Paste the error back and
it can be diagnosed from there; almost everything at this stage is a signing
mismatch (a name or bundle ID that doesn't line up exactly) rather than a
real code problem.
