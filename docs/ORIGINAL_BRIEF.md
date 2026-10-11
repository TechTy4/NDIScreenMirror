> Historical specification supplied by the user at the start of this project. The original text below is preserved unchanged; later requests in the [conversation record](CONVERSATION.md) supersede several requirements. In particular, the current app has two screen feeds, a startup wizard, Magewell API control, and display choices in Settings rather than the original menu picker. Current behavior and limitations are documented in [Architecture](ARCHITECTURE.md) and [Testing](TESTING.md).

---

Build a complete, production-quality native macOS application called **Sanctuary NDI**.

Do not just scaffold the project or give me instructions. Implement the application as fully as reasonably possible, build it, test the parts that can be tested locally, fix build errors, and leave the repository in a working state.

The end goal is a normal self-contained macOS `.app` bundle that can be placed in `/Applications` and used by nontechnical users without needing Terminal, Xcode, config-file editing, or source-code changes.

## Purpose

This will be used on a Mac that is used in a church sanctuary. (This current mac is my personal mac for development)

It has multiple physical displays. One specific display needs to be mirrored over NDI to a Magewell Pro Convert for NDI to HDMI connected to a projector.

On Sundays, ProPresenter places its presentation output on this display.

During the week, a school uses the same Mac and needs ordinary desktop/web content shown on that same display.

Sometimes other content is displayed but it shouldn't matter because this screen is being mirred.

Therefore, this application should simply capture one selected physical macOS display and continuously publish it as a standard NDI source.

There should be no distinction between "church mode" and "school mode." Whatever appears on the selected display should appear in the NDI feed.

This app replaces the functionality we previously had with NDI Screen Capture/Scan Converter on Windows, where an individual physical monitor could be exposed as an NDI source.

## Core architecture

Use native macOS technologies wherever practical.

Preferred stack:

- Swift
- SwiftUI where appropriate
- AppKit where useful for menu-bar behavior
- ScreenCaptureKit for screen/display capture
- Current official NDI SDK for NDI transmission
- ServiceManagement / `SMAppService` for Launch at Login
- `UserDefaults` or another appropriate native preferences mechanism for persistent settings

Do not use OBS, FFmpeg, Electron, a browser wrapper, Python, a local web server, or shell scripts for the core application.

This should feel like a real native Mac utility.

Target Apple Silicon first. Universal support for Intel + Apple Silicon is welcome if straightforward with the installed NDI SDK, but do not compromise the Apple Silicon implementation merely to support Intel.

Use the newest stable APIs available on the development Mac, while choosing a reasonable deployment target. macOS 13+ is acceptable if that materially simplifies the implementation. If newer ScreenCaptureKit functionality requires a newer target and provides a meaningful benefit, make a reasonable engineering decision and document it.

## NDI SDK

Use the current official NDI SDK installed on or obtainable for macOS.

Before implementing the NDI integration:

1. Inspect the development machine and repository for an existing NDI SDK installation.
2. Determine the current header/framework/dylib layout rather than assuming paths.
3. Read the relevant SDK headers and bundled examples.
4. Follow the current official NDI SDK API rather than relying on old example code from memory.
5. Integrate the required runtime libraries into the `.app` bundle where licensing and SDK packaging permit so the application does not depend on arbitrary development-machine paths.
6. Set runtime search paths appropriately.
7. Verify the finished `.app` can locate its NDI dependencies outside Xcode.

Use normal High Bandwidth NDI output. We do not need NDI HX encoding.

The NDI source name should default to:

`Sanctuary Projector Screen`

and should be editable from the application's settings.

Use the NDI sender API correctly and destroy/recreate or reconfigure the sender cleanly if the NDI name changes.

Review the current NDI SDK license/readme and comply with any attribution/link requirements that apply to applications using the SDK. If NDI requires an ndi.video link near NDI-related settings or in an About window, implement that appropriately.

Do not commit proprietary SDK binaries to source control if their license prohibits doing so. If they cannot legally live in the repository, make the build process detect the locally installed SDK and clearly document the required setup.

## Screen capture

Use **ScreenCaptureKit**, not deprecated screen-grabbing APIs.

Use `SCShareableContent` to enumerate captureable displays and `SCDisplay` / `SCContentFilter` / `SCStream` to capture exactly one physical display.

The application must support Macs with several displays.

Capture only the selected display. Do not stitch displays together.

The captured NDI video should accurately represent the selected display.

Aim for:

- 60 fps when reasonable
- fallback/configuration for 30 fps
- native display aspect ratio
- good visual quality
- low latency
- efficient CPU/GPU usage

Do not perform unnecessary image copies or format conversions.

Inspect the NDI SDK's preferred supported pixel formats and ScreenCaptureKit/CoreVideo output formats. Choose an efficient path, preferably YCbCr if it avoids unnecessary conversions and is practical with the APIs involved.

If a conversion is required, implement it efficiently using native Apple frameworks such as CoreVideo, Accelerate, Metal, or VideoToolbox where appropriate rather than a CPU-heavy hand-written pixel loop.

Correctly handle:

- Retina/backing scale
- display resolution changes
- display sleep/wake
- monitor disconnect/reconnect
- Mac sleep/wake
- ScreenCaptureKit stream interruption
- NDI sender failure/restart
- network temporarily disappearing
- user switching the selected display

The application should recover automatically wherever reasonable.

Do not send audio unless there is a compelling reason to do so. This application's primary requirement is display video. Keep audio disabled by default.

## Screen recording permission

Handle macOS Screen Recording permission properly.

Include the appropriate usage description in the application metadata.

On first run, if screen recording permission has not been granted:

- explain clearly that Screen Recording permission is needed to mirror the chosen display over NDI
- trigger or guide the user through the native macOS permission process as appropriate
- provide an obvious way to open the relevant System Settings page if possible
- detect when permission is unavailable
- show a useful status instead of simply failing

If macOS requires the app to restart after initial permission is granted, explain this clearly and provide a convenient Quit/Reopen or equivalent path if feasible.

Do not repeatedly nag once permission is configured.

## Menu-bar-only application

This should primarily be a **menu-bar utility**.

Normal operation should not show a Dock icon or leave a normal application window open.

The menu-bar icon should communicate basic state where practical.

A menu approximately like this would be good:

Sanctuary NDI
──────────────
● Broadcasting
NDI: Sanctuary Projector

Mirror Display
  ✓ Dell P2422H
    Built-in Display
    Samsung Display

Restart Broadcast

Settings...
About Sanctuary NDI
Quit

The exact SwiftUI/AppKit presentation can differ, but keep it clean, native, understandable, and minimal.

If broadcasting is healthy, show a normal status.

If something is wrong, make that visually evident through the menu-bar item and menu status text.

Possible states include:

- Broadcasting
- Starting
- Screen Permission Required
- Selected Display Missing
- NDI Error
- Capture Error

Do not spam modal dialogs for transient errors.

## Display selection

This part is especially important.

The user must be able to choose which connected physical display is mirrored directly from the menu bar.

The application must enumerate the currently connected/captureable displays and present them in a readable list.

When a display is selected:

1. save the selection persistently
2. switch ScreenCaptureKit to that display
3. restart/update the NDI stream as necessary
4. indicate the newly selected display with a checkmark

Changing monitors should NEVER require:

- editing a source file
- editing JSON/plist manually
- changing a hardcoded constant
- using Terminal
- reopening Xcode
- rebuilding the application

It must be ordinary UI configuration.

## Persisting display identity

Do not simply persist "Display 1", "Display 2", an array index, or monitor coordinates.

The selected physical display should survive reboots and typical display rearrangement.

Investigate what stable identifying data macOS exposes for a physical display.

Use the best persistent identity practical, potentially using some combination of:

- Core Graphics display UUID
- vendor ID
- product/model ID
- serial number when available
- display name
- EDID-derived identity if accessible through supported APIs
- resolution as a final fallback

Design a small `DisplayIdentity` model rather than scattering matching logic around the code.

At startup:

1. enumerate connected displays
2. attempt to find the previously selected display using its persisted identity
3. if found, automatically start capturing it
4. if not found, do NOT silently choose a different display unless there is only one display and that behavior is clearly safe
5. set status to something like `Selected Display Missing`
6. allow the user to choose a replacement directly from the menu bar
7. save the replacement as the new default

If the selected monitor is unplugged and later plugged back in during the same session, automatically recognize it and resume broadcasting if practical.

A monitor being replaced months later must be easy to fix: open menu bar → select new monitor → done.

## Human-readable display names

Try to show useful names rather than only numbers.

Examples:

- `DELL P2422H`
- `Samsung S24E450`
- `Built-in Retina Display`

If macOS does not provide a perfect marketing name through one API, derive the best useful display name from supported display APIs.

It is acceptable to append information for disambiguation, for example:

`DELL P2422H — 1920×1080`

or:

`DELL P2422H (Left)`

Do not make "left/right" based on physical assumptions unless computed from current display geometry.

## Automatic startup

Implement **Launch at Login** using the current native macOS mechanism, preferably `SMAppService`.

This should be configurable in Settings with a checkbox/toggle:

`Launch Sanctuary NDI at login`

Default this to ON if that can be done without violating macOS expectations; otherwise make the initial setup obvious.

When the app launches at login it should:

1. start silently
2. locate the saved display
3. initialize ScreenCaptureKit
4. initialize the NDI sender
5. begin broadcasting
6. require no user action during normal operation

Do not use a hand-installed LaunchAgent plist if `SMAppService` is appropriate.

## Auto-start broadcasting

Broadcast automatically whenever the app runs and the required conditions are satisfied.

There should not normally be a separate "Start" button that volunteers must remember to press.

Normal desired state:

Mac login
→ Sanctuary NDI launches
→ saved display is found
→ NDI broadcast starts

If something fails temporarily, retry intelligently.

Avoid aggressive tight retry loops. Use reasonable backoff.

## Restart Broadcast

Include a menu command named something like:

`Restart Broadcast`

It should cleanly tear down and recreate the capture and NDI sender.

This is intended as a simple troubleshooting button for volunteers.

It should not reset preferences.

## Settings

Provide a small native Settings window.

At minimum include:

General:
- NDI source name
- Launch at Login
- selected display, if useful here in addition to menu bar

Video:
- frame rate: ideally Auto / 60 / 30, or a similarly sensible design
- resolution behavior if configuration is actually useful

Advanced:
Only add settings that genuinely help. Avoid exposing dozens of NDI tuning knobs merely because the SDK contains them.

The default configuration should work well without opening Settings.

Persist preferences.

Changing the NDI source name should take effect without requiring an application restart.

## Cursor behavior

Add a setting for whether the mouse pointer is included in the NDI output if ScreenCaptureKit allows this cleanly.

Default to whatever most closely resembles ordinary display mirroring. Including the pointer is likely appropriate for school desktop use.

Call the setting:

`Show mouse pointer`

Persist it.

## Notifications and overlays

The NDI output should mirror the selected physical display faithfully.

Do not intentionally suppress ordinary applications, notifications, dialogs, or desktop content unless ScreenCaptureKit requires explicit behavior.

This application is conceptually replacing a physical display cable: what is visible on the selected display is what should be sent.

Do not capture the menu-bar application's own UI from a different display unnecessarily, but don't introduce complex window filtering unless needed.

## Status and diagnostics

Keep routine operation simple for volunteers, but make troubleshooting possible.

Add an optional diagnostics/logging facility.

Use Apple's logging infrastructure (`Logger` / `OSLog`) rather than random `print()` statements for production logging.

Log useful lifecycle events such as:

- app launch
- display enumeration
- persisted display match
- selected display change
- ScreenCaptureKit start/stop/error
- NDI sender creation/destruction/error
- sleep/wake
- display disconnect/reconnect
- automatic retry
- broadcast restart

Never log sensitive user screen content.

It would be helpful for the menu to include:

`Copy Diagnostics`

which copies a concise textual diagnostic summary to the clipboard, for example:

Sanctuary NDI 1.0
macOS: ...
Architecture: arm64
Status: Broadcasting
Selected display: DELL P2422H
Display ID: ...
Resolution: 1920×1080
Frame rate: 60
NDI source: Sanctuary Projector
NDI sender: active
Screen recording permission: granted

Do not include huge logs in this clipboard action.

## Application lifecycle

Handle macOS lifecycle events robustly.

If the machine sleeps, stop/pause resources as appropriate and resume after wake.

If the selected display's resolution or refresh characteristics change, reconfigure capture without requiring the user to restart the application.

If ScreenCaptureKit reports that a stream stopped unexpectedly, attempt recovery.

If no matching saved display exists, continue running in the menu bar rather than quitting.

If no network exists, the app should remain healthy and become available over NDI when networking returns rather than crashing.

## Performance

This will run alongside ProPresenter, so resource efficiency matters.

The application should not consume substantial CPU while simply forwarding one display over NDI.

Avoid:

- unnecessary frame copies
- rendering frames through SwiftUI
- converting every pixel with Swift loops
- retaining old sample buffers
- unbounded queues
- blocking ScreenCaptureKit callback threads
- allocating large frame buffers every frame when they can be reused

Use a bounded frame pipeline and drop stale frames rather than allowing latency to build.

Real-time output is more important than delivering every captured frame.

Structure the capture/output pipeline clearly so performance can be profiled later.

## Threading/concurrency

Use Swift concurrency where it improves correctness, but do not force every piece of code into actors unnecessarily.

Clearly separate:

- UI state
- display discovery
- preference storage
- ScreenCaptureKit capture
- pixel conversion, if required
- NDI sender
- lifecycle/recovery logic

Ensure the NDI SDK is called in a thread-safe manner according to its documentation.

Avoid races when a monitor is changed while frames are still arriving from the previous `SCStream`.

## Suggested architecture

You may improve these names, but something along these lines would be clean:

`SanctuaryNDIApp`
- application entry point
- menu-bar UI

`AppState`
- observable application status/state
- coordinates services

`DisplayManager`
- discovers displays
- human-readable naming
- stable display identity matching
- reacts to display changes

`DisplayIdentity`
- Codable persisted physical-display identity

`CaptureManager`
- owns `SCStream`
- configures selected display
- emits captured frames
- handles restart/reconfiguration

`NDISender`
- owns NDI SDK initialization and sender lifetime
- converts/sends frames
- exposes sender health

`BroadcastController`
- coordinates CaptureManager and NDISender
- start/stop/restart
- recovery/backoff

`Preferences`
- typed persistence layer

`LoginItemManager`
- wraps `SMAppService`

`Diagnostics`
- current status snapshot / clipboard information

Keep ownership and teardown explicit. Avoid giant god objects.

## Error handling

Use typed errors where appropriate.

User-facing messages should be useful to nontechnical users.

Examples:

Bad:
`SCStreamErrorDomain -3802`

Better:
`Screen capture stopped unexpectedly. Sanctuary NDI is trying to reconnect.`

Bad:
`nil display`

Better:
`The previously selected display is not connected. Choose another display from Mirror Display.`

Keep underlying technical errors in OSLog for diagnostics.

## Security and sandboxing

Investigate whether App Sandbox is appropriate with the NDI SDK and ScreenCaptureKit/network requirements.

Do not blindly enable or disable sandboxing.

Use the minimum necessary entitlements.

The application needs to:

- capture a display with user-granted permission
- send NDI traffic over the LAN
- store preferences
- optionally register as a login item

If hardened runtime/library-validation settings are required by the exact NDI runtime being used, determine that from the current NDI SDK documentation and implement the minimum required configuration.

Document any security-related tradeoff.

## Build and packaging

Create a proper Xcode project/workspace that can produce:

`Sanctuary NDI.app`

The final build should not require launching from Xcode.

Configure:

- application name: `Sanctuary NDI`
- a sensible reverse-DNS bundle identifier; if none exists, use something clearly placeholder/customizable such as `org.sanctuary.SanctuaryNDI`
- semantic version starting at `1.0.0`
- release and debug configurations
- correct Info.plist keys
- required entitlements
- NDI runtime embedding/search paths
- Apple Silicon support

Create an app icon if practical using a simple original design that visually suggests a display/network/broadcast utility. If generating proper icon artwork is outside the coding environment, create the icon asset structure and document what remains rather than blocking the application.

Do not make the user manually run `install_name_tool` after builds. Fix dylib/runtime paths in the build process correctly.

After building Release, inspect the `.app` bundle with tools such as:

- `file`
- `otool -L`
- `codesign`
- appropriate dependency inspection

Verify no required dylib points to a developer-specific path that will break when the `.app` moves to `/Applications`.

If a local signing identity is available, use it appropriately.

If no Apple Developer certificate exists, make an ad-hoc signed development build and document how signing/notarization would be added later.

Do not make notarization a requirement for testing this app on the local sanctuary Mac.

## Optional convenience build script

Provide a simple script such as:

`scripts/build-release.sh`

that:

1. locates/checks required NDI SDK dependencies
2. builds the Release app
3. verifies key embedded dependencies
4. outputs the location of `Sanctuary NDI.app`

The script should fail with clear errors rather than silently producing a broken bundle.

Do not replace the Xcode project with a shell-script-only build.

## README

Write a useful README covering:

### What Sanctuary NDI does

Explain simply:

`Sanctuary NDI mirrors one selected Mac display to the local network as an NDI source.`

### Installation

How to install the resulting `.app`.

### First Run

Explain Screen Recording permission.

### Choosing a Monitor

Explain that the selected monitor is remembered automatically.

### Replacing a Monitor

Explain:

1. connect the new display
2. click Sanctuary NDI in the menu bar
3. choose the new display under Mirror Display
4. the new choice becomes the default

No code/config editing should be necessary.

### NDI Receiver Setup

Explain that an NDI receiver such as the existing Magewell decoder should select:

`Sanctuary Projector`

or whatever source name the user configured.

Do not make the application itself responsible for configuring the Magewell.

### Launch at Login

Explain behavior.

### Troubleshooting

Cover:

- no NDI source visible
- Screen Recording permission
- selected display missing
- NDI/network unavailable
- Restart Broadcast
- Copy Diagnostics

### Development

Explain:

- Xcode requirement
- NDI SDK requirement
- where it is expected/discovered
- how to build Debug
- how to build Release

### Signing

Briefly explain ad-hoc/local builds versus Developer ID signing/notarization.

## Tests

Add meaningful tests for logic that can be tested without actual screen capture hardware.

Especially test:

- `DisplayIdentity` persistence
- display matching/scoring/fallback behavior
- preference persistence/serialization where feasible
- recovery/backoff state logic
- status transitions

Do not waste time trying to unit-test Apple's ScreenCaptureKit internals.

If practical, abstract NDI sending behind a small protocol so app-state logic can be tested with a fake sender, but do not overengineer the project.

## Acceptance criteria

Consider the project successful only when all of the following are true:

1. The project builds successfully.
2. A normal `Sanctuary NDI.app` bundle is produced.
3. Launching the app places an icon in the macOS menu bar.
4. It does not require a persistent Dock icon during normal operation.
5. The app can enumerate multiple connected displays.
6. The user can select a display from the menu bar.
7. The selected display is remembered after quitting/relaunching.
8. Reordering monitors does not ordinarily lose the selection.
9. If the monitor disappears, the app does not silently stream the wrong screen.
10. A replacement monitor can be chosen through the menu bar without editing any file.
11. ScreenCaptureKit captures only the selected display.
12. Frames are transmitted through an official NDI SDK sender.
13. The NDI source has a configurable name and defaults to `Sanctuary Projector`.
14. NDI transmission begins automatically when the app launches and the selected display is available.
15. The app handles missing Screen Recording permission gracefully.
16. Launch at Login is implemented through native macOS APIs.
17. `Restart Broadcast` works without resetting preferences.
18. Sleep/wake and display changes do not permanently break the app.
19. The application uses bounded buffering and does not accumulate video latency.
20. Moving the built `.app` to `/Applications` does not break its NDI runtime dependencies.
21. The repository contains documentation sufficient for another developer to build it later.
22. Normal use does not require Terminal, Xcode, Codex, or editing configuration files.

## Scope boundaries

For version 1, DO NOT add:

- Magewell HTTP API control
- ProPresenter API integration
- Stream Deck integration
- NDI receiving
- audio mixing
- recording
- streaming to the internet
- RTMP/SRT
- remote web interfaces
- cloud services
- user accounts
- analytics
- update frameworks
- elaborate onboarding

Those can be future features.

Version 1 should do one job extremely well:

**Take one user-selected Mac display and continuously make it available as a reliable NDI source.**

## Engineering workflow

Work autonomously through the implementation.

Before writing large amounts of code:

1. inspect the repository
2. inspect installed Xcode/toolchain versions
3. inspect macOS/CPU architecture
4. locate or determine the status of the NDI SDK
5. inspect current NDI headers/examples
6. confirm relevant ScreenCaptureKit APIs available for the deployment target
7. then choose the exact implementation

Do not ask me to choose between minor implementation details. Make sensible engineering decisions.

If an external prerequisite is genuinely unavailable — for example the NDI SDK itself is not installed and cannot be downloaded automatically — implement everything that can be implemented, create a clear dependency integration point, and tell me exactly what prerequisite remains.

Do not fake NDI functionality with placeholder implementations and then claim the application is finished.

Continuously compile as you work instead of writing the entire project blindly and only compiling at the end.

When you encounter compiler/linker/runtime errors, diagnose and fix them.

Run tests.

Build a Release version.

Inspect the final `.app` bundle and linked libraries.

If the environment permits launching GUI apps, smoke-test the built application.

## Final response

When you finish, give me a concise implementation report containing:

- what was built
- architecture used
- deployment target
- NDI SDK version found/used
- where the Release `.app` is located
- whether it is signed and how
- what tests/build verification passed
- any remaining manual first-run steps such as granting Screen Recording permission
- any known limitations
- the exact command to rebuild the Release app later

Do not finish by merely telling me what I should implement.

Implement it.
