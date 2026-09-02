# Sanctuary NDI

Sanctuary NDI mirrors one selected Mac display to the local network as an NDI® source. It is a native, menu-bar-only macOS utility built for a shared sanctuary/school Mac: whatever is visible on the chosen physical display is sent as High Bandwidth NDI video.

NDI® is a registered trademark of Vizrt NDI AB. Learn more at [ndi.video](https://ndi.video).

## Installation

1. Build the Release app with `./scripts/build-release.sh`, or open the packaged DMG.
2. Drag Sanctuary NDI.app onto the Applications shortcut.
3. Open it once from Applications. Its radiowave/display icon appears in the menu bar; no Dock icon or normal window remains open.

The packaged build is signed with the first available Apple Development certificate so macOS can retain Screen Recording permission across rebuilds. It is intended for this controlled Mac and does not require a paid developer membership. Control-click the installed app and choose Open the first time; see [DEPLOYMENT.md](DEPLOYMENT.md). Public distribution would require a Developer ID Application certificate and notarization.

## First run

Screen Recording permission is required because the app reads the pixels of the selected display. Open the menu-bar item, choose Request Screen Recording Permission, then enable Sanctuary NDI in System Settings → Privacy & Security → Screen Recording. If macOS requests it, quit and reopen the app.

The menu shows a useful status while permission or a selected display is missing; it does not silently broadcast another screen.

## Choosing or replacing a monitor

Open the menu-bar item and select the physical display with the Mirror Display picker. The selection changes immediately and restarts the sender on that display. The choice is saved using the Core Graphics display UUID plus vendor, model, serial, name, and native resolution fallbacks, so ordinary monitor rearrangement does not lose it.

To replace a monitor:

1. Connect the new display.
2. Click Sanctuary NDI in the menu bar.
3. Choose the new display under Mirror Display.
4. The new choice becomes the default immediately.

No source edits, Terminal commands, or rebuild are needed for normal display changes.

## Receiver setup

On the Magewell or another NDI receiver, select Sanctuary Projector Screen (shown by receivers with the Mac host name) or the source name configured in Settings. This app deliberately does not configure the receiver.

## Settings and launch at login

Settings opens a normal native window and temporarily shows Sanctuary NDI in the Dock so it behaves like a foreground app while being configured. Closing Settings returns it to menu-bar-only mode. Settings controls the source name, 60/30 fps, cursor visibility, and Launch Sanctuary NDI at login. Source-name and video changes restart the pipeline cleanly. Launch at Login uses Apple SMAppService; macOS may require approval in System Settings → General → Login Items.

At login, the saved display is found and broadcasting starts automatically. Sleep, wake, display changes, capture interruption, and transient startup errors trigger clean recovery with capped exponential backoff.

## Troubleshooting

- No NDI source: confirm both devices are on the same LAN, verify the selected display, and choose Restart Broadcast.
- Screen Permission Required: grant Screen Recording access, then quit and reopen if macOS requests it.
- Selected Display Missing: reconnect it or choose its replacement from Mirror Display.
- NDI Error: use Copy Diagnostics and verify libndi.dylib exists in the app Contents/Frameworks folder.
- Network temporarily unavailable: leave the app running; the sender remains available when the LAN returns.
- Support snapshot: Copy Diagnostics includes version, OS/architecture, display identity, resolution, frame rate, runtime version, receiver count, permission, and login-item state. Screen content is never logged.

## Architecture

- AppState coordinates lifecycle, status, preference changes, retries, and sleep/wake.
- DisplayManager and DisplayIdentity provide ScreenCaptureKit discovery and persistent physical-display matching.
- CaptureManager owns a bounded SCStream (queue depth 3) capturing only one SCDisplay.
- NDISender and NDIBridge use the official NDI SDK sender through a small dynamically loaded C boundary.
- Preferences provides typed UserDefaults persistence.
- LoginItemManager wraps SMAppService.mainApp.
- SwiftUI supplies MenuBarExtra and Settings UI; AppKit is used for native lifecycle/menu behavior.

ScreenCaptureKit outputs its native packed BGRA format, which the NDI sender accepts directly. Frames are submitted from the locked CVPixelBuffer without an application-side full-frame copy or Swift pixel loop; the NDI runtime performs its optimized internal color conversion and compression. The synchronous send runs on ScreenCaptureKit dedicated bounded output queue, allowing stale frames to drop instead of accumulating latency.

The app uses the hardened runtime and a stable code signature. It is distributed outside the Mac App Store without App Sandbox so the bundled NDI runtime can publish multicast/local-network traffic reliably. It has no audio capture, recording, web server, cloud service, or analytics.

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

Release build:

    ./scripts/build-release.sh

The script checks the SDK and signing identity, builds an arm64 Release app, embeds the NDI runtime, applies a stable certificate-backed hardened-runtime signature to the library and app, and verifies code signing and Mach-O dependencies. Output: build/Release/Sanctuary NDI.app.

## Signing

scripts/build-release.sh creates a relocatable Apple Development-signed build suitable for local testing and manual deployment to a controlled Mac. It uses the first Apple Development identity found in Keychain, or the identity supplied in `SIGNING_IDENTITY`. For wider distribution, use a Developer ID Application identity, archive, sign, notarize, and staple the result. The NDI runtime must be signed with the same identity before the containing app is sealed.

Create the complete deployment disk image after building:

    ./scripts/package-dmg.sh

## NDI SDK licensing

This project uses NDI SDK 6.3.2 and follows the SDK documented redistribution pattern by keeping its redistributable library private to the app bundle. Review the installed SDK license before redistributing. The repository excludes the proprietary dylib; each developer obtains it from [NDI for Developers](https://ndi.video/for-developers/).
