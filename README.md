# Sanctuary NDI

Sanctuary NDI is a native macOS room-startup utility for a shared sanctuary/school Mac. At every login, a friendly wizard asks whether the projector should show ProPresenter or a selected physical monitor, optionally duplicates the monitor feed on a confidence display, and selects the matching NDI source on a configured Magewell receiver.

NDI® is a registered trademark of Vizrt NDI AB. Learn more at [ndi.video](https://ndi.video).

## Installation

1. Build the Release app with `./scripts/build-release.sh`, or open the packaged DMG.
2. Drag Sanctuary NDI.app onto the Applications shortcut.
3. Open it once from Applications. Its status icon appears in the menu bar and the Startup Wizard opens. A Dock icon is present while the wizard or Settings is open and disappears during normal menu-bar-only operation.

The packaged build is signed with the first available Apple Development certificate so macOS can retain Screen Recording permission across rebuilds. It is intended for this controlled Mac and does not require a paid developer membership. Control-click the installed app and choose Open the first time; see [DEPLOYMENT.md](DEPLOYMENT.md). Public distribution would require a Developer ID Application certificate and notarization.

## Startup Wizard

The non-closable (but minimizable) wizard appears on every launch and asks:

1. Should the projector show ProPresenter or the configured input monitor?
2. In monitor mode, should the feed also be duplicated fullscreen on the configured confidence monitor?

Both monitor feeds start automatically as soon as the app launches and their saved displays and Screen Recording permission are available, even while the wizard is open. ProPresenter mode requires ProPresenter to be running and leaves both feeds running. Monitor mode waits for the projector-monitor feed before asking the Magewell to switch. Errors remain in the wizard with actionable recovery instead of silently selecting another source.

## Display configuration

Settings → Displays assigns the input monitor, confidence monitor, and **User screen (operator)**. The User screen initially selects the Mac's main display, then remembers your chosen physical monitor across launches. Two independent NDI feeds run in every projector mode: **Sanctuary Projector Screen** (the existing configurable input-feed name) and **Sanctuary User Screen**. The livestream computer can view either without changing the projector. Frame rate and mouse-pointer settings apply to both feeds. A disconnected monitor pauses only its own feed; reconnecting it restores that feed. The friendly input label defaults to **Left/Projector Monitor** and can be changed in General. Display choices are saved using the Core Graphics display UUID plus vendor, model, serial, name, and native-resolution fallbacks.

To replace a monitor:

1. Connect the new display.
2. Open Sanctuary NDI Settings → Displays.
3. Choose the new input, User, or confidence monitor.
4. The new choice becomes the default immediately.

No source edits, Terminal commands, or rebuild are needed for normal display changes.

## Magewell receiver control

Settings → Projector stores the receiver's local address, username, and NDI source-match text. The password is stored only in macOS Keychain. The client supports both the current authenticated JSON API (`/api/user/login`, `/api/source/list`, `/api/source/select`) and legacy Pro Convert firmware (`/mwapi` login, discovery, and `set-channel`). Source matching prefers an exact name and otherwise requires one unambiguous case-insensitive substring match.

For security, receiver credentials are sent only to private/link-local IP addresses, `.local` hosts, or local unqualified hostnames. HTTP is supported because the receiver's local management API uses it. See Magewell's official [current decoder API](https://www.magewell.com/api-docs/pro-convert-ip-decoder-api/latest/) and [legacy decoder API](https://www.magewell.com/api-docs/pro-convert-decoder-api/).

## Settings and launch at login

Settings opens a normal native tabbed window. It configures monitor roles, the friendly monitor label, NDI video, Magewell control and credentials, source matching, permissions, diagnostics, and Launch at Login. Launch at Login uses Apple SMAppService; macOS may require approval in System Settings → General → Login Items.

At login, the wizard asks for the day's mode. Sleep, wake, display changes, capture interruption, and transient capture errors use clean recovery with capped exponential backoff.

## Troubleshooting

- Projector connection failed: confirm the receiver is on the same LAN, verify its address and credentials in Settings → Projector, then run Save Password & Test.
- Source not found: start ProPresenter or the monitor broadcast, then make the configured source-match text more distinctive.
- No monitor NDI source: verify the input display in Settings → Displays and use Restart Both NDI Broadcasts under Support.
- Screen Permission Required: grant Screen Recording access, then quit and reopen if macOS requests it.
- Selected Display Missing: reconnect it or choose its replacement in Settings → Displays.
- NDI Error: use Copy Diagnostics and verify libndi.dylib exists in the app Contents/Frameworks folder.
- Network temporarily unavailable: leave the app running; the sender remains available when the LAN returns.
- Support snapshot: Copy Diagnostics includes version, OS/architecture, display identity, resolution, frame rate, runtime version, receiver count, permission, and login-item state. Screen content is never logged.

## Architecture

- AppState coordinates projector routing, lifecycle, status, preferences, and sleep/wake.
- Two MonitorBroadcast instances independently own capture, NDI senders, serialized configuration changes, and capped retry backoff. Changing wizard mode never stops either sender.
- DisplayManager and DisplayIdentity provide ScreenCaptureKit discovery and persistent physical-display matching.
- CaptureManager owns a bounded SCStream (queue depth 3) capturing only one SCDisplay.
- NDISender and NDIBridge use the official NDI SDK sender through a small dynamically loaded C boundary.
- MagewellClient authenticates, discovers, matches, and selects NDI sources across both Magewell API generations.
- ConfidenceMirrorController presents captured sample buffers fullscreen on a separately selected monitor.
- KeychainStore keeps the receiver password out of UserDefaults and the app bundle.
- Preferences provides typed UserDefaults persistence.
- LoginItemManager wraps SMAppService.mainApp.
- SwiftUI supplies MenuBarExtra and Settings UI; AppKit is used for native lifecycle/menu behavior.

ScreenCaptureKit outputs its native packed BGRA format, which the NDI sender accepts directly. Frames are submitted from the locked CVPixelBuffer without an application-side full-frame copy or Swift pixel loop; the NDI runtime performs its optimized internal color conversion and compression. The synchronous send runs on ScreenCaptureKit dedicated bounded output queue, allowing stale frames to drop instead of accumulating latency.

The app uses the hardened runtime and a stable code signature. It is distributed outside the Mac App Store without App Sandbox so the bundled NDI runtime can publish multicast/local-network traffic and the app can control a local HTTP receiver. It has no audio capture, recording, web server, cloud service, or analytics.

## Development

Requirements:

- macOS 13 or newer (Apple Silicon)
- Xcode 15 or newer; developed/tested with Xcode 26.6
- Current NDI SDK for Apple, installed at /Library/NDI SDK for Apple

The project compiles against the official include/Processing.NDI.Lib.h and bundles lib/macOS/libndi.dylib inside the app. The proprietary runtime is intentionally not committed. Set NDI_SDK_DIR and/or NDI_RUNTIME_PATH if your SDK is elsewhere.

Debug build command:

    NDI_RUNTIME_PATH="/Library/NDI SDK for Apple/lib/macOS/libndi.dylib" xcodebuild -project NDIScreenMirror.xcodeproj -scheme NDIScreenMirror -configuration Debug -destination "platform=macOS,arch=arm64" build

Logic tests:

    swift test

For a live receive check, compile `scripts/verify-ndi-feeds.cpp` using the command at the top of that file. Run it without arguments to list discovered source names, then pass the exact projector and User source names to check video from both. It never saves screen contents. Run it with the wizard open and again after choosing ProPresenter; both feeds should remain available. Test disconnect/reconnect and sleep/wake with the room displays attached.

Release build:

    ./scripts/build-release.sh

The script checks the SDK and signing identity, builds an arm64 Release app, embeds the NDI runtime, applies a stable certificate-backed hardened-runtime signature to the library and app, and verifies code signing and Mach-O dependencies. Output: build/Release/Sanctuary NDI.app.

## Signing

scripts/build-release.sh creates a relocatable Apple Development-signed build suitable for local testing and manual deployment to a controlled Mac. It uses the first Apple Development identity found in Keychain, or the identity supplied in `SIGNING_IDENTITY`. For wider distribution, use a Developer ID Application identity, archive, sign, notarize, and staple the result. The NDI runtime must be signed with the same identity before the containing app is sealed.

Create the complete deployment disk image after building:

    ./scripts/package-dmg.sh

## NDI SDK licensing

This project uses NDI SDK 6.3.2 and follows the SDK documented redistribution pattern by keeping its redistributable library private to the app bundle. Review the installed SDK license before redistributing. The repository excludes the proprietary dylib; each developer obtains it from [NDI for Developers](https://ndi.video/for-developers/).
