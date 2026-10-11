# Releasing SimCam Lite

SimCam Lite updates itself with [Sparkle](https://sparkle-project.org). The appcast and update archives are served from
the Cloudflare R2 bucket `simcamlite-downloads` at `https://simcamupdates.ifateam.dev`.

## One-time setup

1. Copy `Config/Environment.example.xcconfig` to `Config/Environment.xcconfig` (gitignored) and fill in:
   - `SIMCAM_DEVELOPMENT_TEAM`: the Apple Developer team ID that signs the app, `simcam` and the inject framework.
   - `SIMCAM_SU_PUBLIC_ED_KEY`: printed by Sparkle's `generate_keys --account simcamlite` (found next to `generate_appcast` in
     DerivedData under `SourcePackages/artifacts/sparkle/Sparkle/bin/`). The private key stays in the login Keychain.
   - `SIMCAM_NOTARY_*`: an App Store Connect API key for `notarytool`; put the `.p8` in `Config/`.
2. Create the R2 bucket, attach the custom domain, and log in with `wrangler login`.
3. Install `gh` and `wrangler`, and `gh auth login`.

Without `Environment.xcconfig` the app still builds; the feed URL is empty and the updater stays off.

## Each release

1. In `project.yml`, bump `MARKETING_VERSION` and **always increase `CURRENT_PROJECT_VERSION`**: Sparkle compares
   `CFBundleVersion`.
2. Rewrite `.github/RELEASE_NOTES.md`. The first line must be `# SimCam Lite <MARKETING_VERSION>`. The same file is
   embedded in the appcast (Sparkle's update window), shown in the app's What's New sheet, and used as the GitHub
   Release body.
3. Run `xcodegen generate`, commit, and push to `main`. The *Release Notes* workflow checks the heading and creates the
   draft release `v<version>`.
4. Run `scripts/release-from-archive.sh`. It archives, exports with Developer ID, notarizes and staples the app and the
   DMG, signs the Sparkle zip, regenerates `appcast.xml` from `build/sparkle-releases/`, uploads everything to R2 and
   GitHub, and publishes the release.

Keep `build/sparkle-releases/`: it is the history the appcast is generated from.

## Testing an update locally

1. Build and install the current version into `/Applications`.
2. Bump the versions, then build a Release app (`scripts/build.sh`).
3. Point `SIMCAM_UPDATE_BASE_URL` at `http:/$()/localhost:8000` in `Environment.xcconfig` for both builds, and create
   the update with a scratch history folder:

   ```bash
   scripts/make-sparkle-update.sh --app build/SimCamLite.app --archives-dir /tmp/simcam-updates \
     --download-url-prefix http://localhost:8000/releases/ --allow-http --skip-gatekeeper-check
   ```

   Move the zip into `/tmp/simcam-updates/releases/` and serve the folder with `python3 -m http.server 8000`.
4. Choose **Check for Updates…**. To test the notification instead, run
   `defaults delete dev.ifateam.simcamlite SULastCheckTime` and relaunch with `--background`.
