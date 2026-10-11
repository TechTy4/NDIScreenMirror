# Changelog

Release dates below use the published GitHub release dates. This history describes shipped changes; hardware acceptance limitations are recorded separately in [Testing](docs/TESTING.md).

## [1.3.0](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.3.0) — 2026-10-11

Ease of use, stability, and troubleshooting.

Easier everyday use:
- The wizard pre-selects the last successful choice, so routine startup is just Start (Next → Start in monitor mode).
- ProPresenter mode opens ProPresenter automatically when it is not running (**Open ProPresenter & Start**) and waits longer for its NDI output.
- Inline monitor pickers in the wizard when a role is unset or disconnected, plus a Screen Recording permission banner with Open System Settings / Relaunch.
- **Identify Screens** labels every physical monitor with its number, name, and role; monitors are numbered so identical models can be told apart.
- The menu shows what the projector is showing and each feed's status, and offers Allow Screen Recording when it is missing.
- Reopening the app (or launching a second copy) brings up Settings instead of creating duplicate NDI sources.

Stability:
- Display reconfiguration events are debounced; the confidence window no longer flickers on each refresh and is not re-shown while asleep.
- The confidence output is hidden only after ProPresenter routing succeeds.
- Receiver operations from the wizard and Settings are serialized.
- Renaming the projector feed keeps the receiver match in sync and rejects a name equal to the User feed.
- Fixed a data race on the NDI sender frame rate.

Technical options:
- Receiver test lists discovered sources with Use for ProPresenter / Use for Monitor, and each match shows what it finds.
- Switch the projector now (manual routing), live receiver counts, Login Items status with a shortcut, Relaunch, Copy Recent Log, richer diagnostics, and Reset All Settings….
- The DMG name now follows the built app version.

Validation: 21 core tests, runtime retry regression, Debug/Release builds, and an independent model review. On-site hardware acceptance remains pending.

## Documentation update — 2026-10-11

Added a documentation index, complete settings reference, troubleshooting, architecture/security notes, testing and on-site acceptance checklist, original brief, and conversation/decision record. No application behavior or release asset changes.

## [1.2.2](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.2.2) — 2026-10-11

Commit: [2fe63eb](https://github.com/TechTy4/NDIScreenMirror/commit/2fe63eb).

- Recheck Availability in the startup wizard and Support settings.
- Recheck & Retry after setup errors and Stop Checking during connection attempts.
- First-video-frame readiness instead of treating sender creation as success.
- Bounded retries for transient receiver/network and source-discovery failures.
- Retryable NDI runtime initialization and periodic missing-screen refresh.
- Explicit selected-screen local capture rectangle, even video dimensions, stale-callback rejection, frame-size validation, and single-display filter validation on macOS 15.2+.
- Feed detail includes selected screen and video size.
- Preserved saved settings and both independent continuous feeds.

Validation: 15 core tests, isolated runtime retry regression, Debug/Release builds, release UI recheck, direct local User-feed receive, and package checks passed. Church three-screen behavior, LAN discovery, and Magewell switching remain pending. The reported all-three-monitors issue was not reproduced locally; these changes harden capture rather than establish its original cause.

## [1.2.1](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.2.1) — 2026-09-06

Commit: [6f0fb52](https://github.com/TechTy4/NDIScreenMirror/commit/6f0fb52).

- Renamed the menu action from Startup Wizard… to Configure Screens.
- Added a saved General setting for its label, with blank-label fallback.
- Used the configured label on the corresponding Settings button.

Built and packaged for deployment; no new church-network acceptance was recorded.

## [1.2.0](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.2.0) — 2026-09-06

Commit: [582d2f3](https://github.com/TechTy4/NDIScreenMirror/commit/582d2f3).

- Kept the projector-monitor NDI feed running even in ProPresenter mode.
- Added independent Sanctuary User Screen capture/sender and saved operator-display selector.
- Started both local feeds before completing the wizard.
- Made wizard choice affect receiver routing instead of stopping local senders.
- Shared frame-rate/cursor preferences across both feeds.

Recorded validation included 10 logic tests, build/package checks, UI selection/persistence, and local User-feed receive. Only one display was attached locally; the full room configuration remained untested.

## [1.1.0](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.1.0) — 2026-09-03

Commit: [762f719](https://github.com/TechTy4/NDIScreenMirror/commit/762f719).

- Reduced the menu to status, startup wizard, Settings, About, and Quit.
- Added a mandatory minimizable room-startup wizard with ProPresenter or input-monitor choice.
- Added optional fullscreen confidence-monitor duplication in monitor mode.
- Added Magewell source selection, current/legacy API support, settings, and Keychain password storage.
- Added ProPresenter running check and open action.
- Moved display choices into native Settings and improved window/Dock behavior.

Recorded validation included 10 logic tests, build/package checks, and local confidence-output/UI checks. Actual Magewell switching was not tested off the church network.

Historical note: this release stopped the local monitor sender in ProPresenter mode. Version 1.2.0 superseded that behavior with two independent always-running feeds.

## [1.0.2](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.0.2) — 2026-09-02

Commit: [3ff85d3](https://github.com/TechTy4/NDIScreenMirror/commit/3ff85d3).

- Initial shipped Sanctuary NDI implementation: selected-display ScreenCaptureKit capture and official NDI SDK sending.
- Persistent display identity, video preferences, native settings, login support, diagnostics, and lifecycle recovery.
- Certificate-backed local signing and deployable app/DMG with install-and-trust instructions.
- Addressed early Settings/picker and repeated privacy-permission concerns during initial development.
- Published the project as the public TechTy4/NDIScreenMirror repository and a downloadable release.

The release history contains v1.0.2 as the first published release; it does not assert separately published v1.0.0 or v1.0.1 packages.
