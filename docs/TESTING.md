# Testing, acceptance, and release verification

This guide separates repeatable procedures from historical results. The documentation update on October 11, 2026 does not itself rebuild or retest the application. The recorded application evidence below belongs to the v1.2.2 implementation/release work.

## Automated checks

From the repository root:

```sh
swift test
zsh scripts/test-ndi-runtime-retry.sh
```

The Swift package tests core logic without starting live capture or requiring the proprietary runtime. The 15 tests cover:

- local single-monitor capture geometry, including negative/offset desktop origins;
- even video dimensions for a scaled monitor;
- delayed receiver/source availability, non-retryable authentication, exhaustion, and cancellation;
- Magewell exact/substring matching, ambiguity, and modern source-list shapes;
- display identity serialization, UUID/serial matching, ambiguous weak matches, and no unrelated fallback;
- capped/reset recovery backoff and saved preferences, including the User display.

The shell regression uses an isolated fake NDI library to check recovery after failed first initialization. It is not evidence of real hardware transmission.

Current gaps: ScreenCaptureKit, native-window pickers, Keychain, login approval, the real decoder, three-display output isolation, and sustained two-feed performance need integration/manual checks. Status/lifecycle behavior is not exhaustively unit-tested. A passing Swift suite does not prove those parts work.

## Build and package

See [README](../README.md#development) for prerequisites and Debug commands. The recommended default SDK location is `/Library/NDI SDK for Apple`.

```sh
./scripts/build-release.sh
./scripts/package-dmg.sh
```

The release script requires a usable signing identity, builds arm64, checks the embedded runtime, signs library then app, and checks signatures and dependencies. It outputs `build/Release/Sanctuary NDI.app`. The packaging script includes the app, Applications shortcut, and DEPLOYMENT.md as “Install & Trust.md,” then verifies and hashes the image.

Maintainer notes:

- App version is stored in the Xcode project's build configurations. The DMG filename is currently hard-coded in package-dmg.sh; update both when releasing another version.
- NDI_SDK_DIR changes the release script's dependency checks and default runtime path. The Xcode project also has explicit HEADER_SEARCH_PATHS and NDI_RUNTIME_PATH settings. An alternate SDK installation must update/override those build settings too; environment variables alone are not a complete header-path override.
- Keep the existing signing identity for updates where possible. Do not publish signing-account information in logs or docs.
- Release assets are versioned snapshots. Later repository documentation changes do not modify the already published DMG.
- Review NDI SDK redistribution terms and the bundled notice before distributing the runtime. There is no root project LICENSE file declaring a general open-source license; a public repository is not by itself a license grant.

Useful read-only checks after building:

```sh
codesign --verify --deep --strict "build/Release/Sanctuary NDI.app"
file "build/Release/Sanctuary NDI.app/Contents/MacOS/Sanctuary NDI"
file "build/Release/Sanctuary NDI.app/Contents/Frameworks/libndi.dylib"
otool -L "build/Release/Sanctuary NDI.app/Contents/MacOS/Sanctuary NDI"
hdiutil verify "build/Sanctuary-NDI-1.2.2-arm64.dmg"
shasum -a 256 "build/Sanctuary-NDI-1.2.2-arm64.dmg"
```

Mount the candidate image read-only for inspection, verify app version and contents, and detach that image after inspection. Do not detach unrelated mounted volumes if a helper briefly keeps the new image busy. The packaging script retries verification.

## Live NDI receive probe

The repository includes [verify-ndi-feeds.cpp](../scripts/verify-ndi-feeds.cpp). Build it using the installed official SDK:

```sh
clang++ -std=c++17 -I"/Library/NDI SDK for Apple/include" scripts/verify-ndi-feeds.cpp \
  -L"/Library/NDI SDK for Apple/lib/macOS" -lndi \
  -Wl,-rpath,"/Library/NDI SDK for Apple/lib/macOS" -o /tmp/verify-ndi-feeds
/tmp/verify-ndi-feeds
```

With no arguments it lists sources discovered during approximately three seconds. Then use the exact names it returned, replacing HOST with the actual host prefix:

```sh
/tmp/verify-ndi-feeds "HOST (Sanctuary Projector Screen)" "HOST (Sanctuary User Screen)"
```

With arguments, it attempts video reception for each source for up to approximately 25 seconds and reports dimensions; it does not save screen contents. Exit 1 means one or more specified sources did not produce video in that run. Discovery and video transport are separate failure points: no discovered source does not establish a capture failure.

Run with the wizard open, after monitor-mode selection, and after ProPresenter selection. The two local sources should remain available in all three cases. This helper verifies frames/dimensions, not that the visual content is the intended screen; perform the visual isolation check below too.

## Recorded v1.2.2 evidence

Implementation commit: [2fe63eb](https://github.com/TechTy4/NDIScreenMirror/commit/2fe63eb). Release: [v1.2.2](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.2.2), published October 11, 2026.

| Check | Recorded result |
| --- | --- |
| Swift core suite | 15 tests passed. |
| Isolated NDI initialization regression | Passed; a failed first initialize call can recover later. |
| Debug and Release build | Passed. |
| Release UI Recheck Availability | Exercised. |
| Direct local NDI video receive | User feed received at 1800×1168, matching the selected built-in screen's bounded output. |
| Discovery-based probe in that development session | Did not discover the source; direct loopback receive was a separate check. Church-LAN discovery is not established. |
| Package inspection | DMG mount, version, signature, and checksum checks passed. |
| Three-monitor sanctuary layout | Not available locally; pending. |
| Real Magewell source switching | Not available off the church network; pending. |
| Simultaneous two-screen visual isolation/load | Requires the room display layout; pending. |

Published asset: [Sanctuary-NDI-1.2.2-arm64.dmg](https://github.com/TechTy4/NDIScreenMirror/releases/download/v1.2.2/Sanctuary-NDI-1.2.2-arm64.dmg).

SHA-256 of that published v1.2.2 image:

```text
d05a0f3857e7f763f6918c1f0303e28d9872d4f31ef2c93f0f353c5a802ef13a
```

A later local repackage can have a different hash. Compare against the release asset you actually downloaded.

## On-site acceptance checklist

These are unchecked because no church-network validation has been recorded for v1.2.2. Use harmless test content and avoid altering live service routing during testing.

- [ ] Save a known-working installer and note existing monitor roles, source names, and receiver input before updating.
- [ ] Install/trust the Applications copy; grant Screen Recording and any Local Network prompt.
- [ ] Confirm Settings opens, each native display picker works, and all three physical roles can be identified.
- [ ] Assign input = left/projector monitor, User = operator monitor, confidence = right/confidence monitor (or the actual intended room layout).
- [ ] Quit/relaunch: verify physical selections, labels, video preferences, receiver settings, and saved password persist.
- [ ] Put distinct test labels/content on all three screens. Receive Sanctuary User Screen from the livestream computer and confirm it shows only the operator screen.
- [ ] Receive Sanctuary Projector Screen and confirm it shows only the chosen input screen, not a desktop union.
- [ ] With the wizard still open, verify both local feeds are available.
- [ ] Start ProPresenter and enable its NDI output. Complete ProPresenter mode and verify the physical Magewell/projector switches to the correct source.
- [ ] Confirm both local screen feeds still run in ProPresenter mode.
- [ ] Complete monitor mode with confidence duplication off: verify Magewell/projector shows the input monitor.
- [ ] Repeat with duplication on: verify only the selected confidence monitor receives the fullscreen input duplicate.
- [ ] Switch back to ProPresenter: verify this app's confidence output hides.
- [ ] Delay receiver/network/ProPresenter availability during a safe test. Confirm automatic retries, Recheck & Retry, and Stop Checking behave understandably.
- [ ] Verify an incorrect password produces an actionable error, not an endless successful-looking setup.
- [ ] Disconnect one selected monitor: its feed pauses without capturing a different monitor; the other feed remains available. Reconnect and recheck.
- [ ] Rearrange monitor positions, including left/above the main display: saved identities and single-screen bounds remain correct.
- [ ] Sleep/wake: feeds resume on the correct screens and confidence behavior is checked.
- [ ] Approve Launch at Login, restart/login, and confirm both feed startup and the mandatory wizard.
- [ ] Observe sustained two-feed performance, network load, latency, and usable image quality at 60 fps; try 30 fps if needed.
- [ ] Verify manual Magewell selection as the fallback, and document the tested rollback installer.

For each result record date, tester, app version, macOS version, decoder model/firmware, receiver software, display sizes/scaling/roles, and pass/fail notes. Redact network identifiers and credentials before committing publicly. Do not mark a failed or unperformed item as complete merely because the build succeeded.
