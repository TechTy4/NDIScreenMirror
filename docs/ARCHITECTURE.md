# Architecture and implementation notes

Current behavior: v1.3.0, reviewed October 11, 2026. This reference describes implementation, not a guarantee of on-site hardware acceptance.

## Independent feeds and projector routing

| Source | Origin | Consumers | Controlled by wizard? |
| --- | --- | --- | --- |
| Sanctuary Projector Screen (renameable) | Saved input physical display | Magewell/projector, livestream receivers, optional confidence output | Sender stays running; wizard can point Magewell at it. |
| Sanctuary User Screen (fixed name) | Saved operator physical display | Livestream receivers | No; always independent of the room mode. |
| ProPresenter's NDI output | ProPresenter, not this application's capture | Magewell/projector | Wizard selects it after checking ProPresenter is open. |

Both local screen feeds start before the wizard completes. “Always running” means while the app is awake, the selected display is available, and macOS grants capture access. Sleep pauses them; missing hardware or startup errors trigger recovery rather than capturing another screen.

Confidence mirroring consumes projector-monitor sample buffers and presents them in a fullscreen window on a separate display. It is neither a third NDI feed nor a duplication of the User feed.

## Source map

| Component | Responsibility |
| --- | --- |
| [SanctuaryNDIApp.swift](../NDIScreenMirror/SanctuaryNDIApp.swift) / [MenuBarView.swift](../NDIScreenMirror/MenuBarView.swift) | SwiftUI app entry, menu/status, Settings/About/Quit. |
| [AppState.swift](../NDIScreenMirror/AppState.swift) | Main-actor orchestration, wizard routing, lifecycle, feed configuration, diagnostics. |
| [MonitorBroadcast.swift](../NDIScreenMirror/MonitorBroadcast.swift) | One independently recoverable capture/sender pair; two instances. |
| [CaptureManager.swift](../NDIScreenMirror/CaptureManager.swift) | ScreenCaptureKit stream, selected-display bounds, frame validation, first-frame readiness. |
| [NDISender.swift](../NDIScreenMirror/NDISender.swift) / [NDIBridge.c](../NDIScreenMirror/NDIBridge.c) | Official NDI SDK video sender through a small C boundary and dynamic runtime loading. |
| [DisplayManager.swift](../NDIScreenMirror/DisplayManager.swift) / [Models.swift](../NDIScreenMirror/Models.swift) | Display enumeration, physical identity matching, capture regions, status/backoff models. |
| [ConfidenceMirrorController.swift](../NDIScreenMirror/ConfidenceMirrorController.swift) | AVSampleBufferDisplayLayer in a borderless output window. |
| [MagewellClient.swift](../NDIScreenMirror/MagewellClient.swift) / [AvailabilityRetry.swift](../NDIScreenMirror/AvailabilityRetry.swift) | Authenticated decoder API, discovery/matching/selection, bounded startup retries. |
| [Preferences.swift](../NDIScreenMirror/Preferences.swift) / [KeychainStore.swift](../NDIScreenMirror/KeychainStore.swift) | Non-secret settings and receiver password, respectively. |
| [LoginItemManager.swift](../NDIScreenMirror/LoginItemManager.swift) | SMAppService login registration. |
| [SettingsView.swift](../NDIScreenMirror/SettingsView.swift) / window controllers / [StartupWizardView.swift](../NDIScreenMirror/StartupWizardView.swift) | Native settings and mandatory, minimizable startup workflow. |
| [ScreenIdentifier.swift](../NDIScreenMirror/ScreenIdentifier.swift) | Temporary on-screen labels showing each monitor's number, name, and assigned roles. |
| [RecentLog.swift](../NDIScreenMirror/RecentLog.swift) | Reads this process's unified-log entries for Copy Recent Log. |

See [settings](SETTINGS.md) for defaults and persistence.

## Capture and send pipeline

Each MonitorBroadcast owns one SCStream and one NDI sender. The ScreenCaptureKit filter targets one SCDisplay, with no excluded windows. It is not a desktop-union capture.

CaptureRegion uses the selected display's Core Graphics bounds size, resetting its source rectangle to local origin (0, 0). Negative or offset global desktop origins never expand the region. Video width/height are rounded down to even dimensions, with a minimum of two pixels. Output follows Core Graphics logical display size; it is not a promise to transmit the full Retina backing-pixel resolution. This differs from the initial brief's native-pixel preference.

The stream uses packed BGRA, a queue depth of three, 60 or 30 fps, Rec.709 color-space configuration, optional cursor, and no audio capture. Scale-to-fit is disabled. On macOS 15.2+, the included-display list must contain exactly the requested display.

Only complete frames from the active stream with valid expected dimensions are accepted. A lock protects active-stream/region/first-frame state; callbacks from stopped or replaced streams are discarded.

The output callback locks the CVPixelBuffer and submits width, height, stride, and presentation time through the bridge. Sending is synchronous on the dedicated output queue; there is no application-side full-frame copy or Swift pixel conversion loop. The official NDI runtime performs internal conversion/compression. This is high-bandwidth NDI, not NDI HX. Queueing is bounded rather than an unbounded latency accumulator, but frame rate/performance under two-feed room load still needs measurement.

The NDI bridge dynamically loads the private bundled runtime first, checks required symbols, and initializes the SDK. Development fallback paths exist. Failed initialization is retryable; it is not permanently latched after the first failed attempt. Each sender owns its resources. SIGPIPE is ignored so receiver disconnects do not terminate the process.

## Display identity and matching

Saved identities use display UUID, vendor ID, model ID, serial number, name, and native dimensions. Current matching scores:

| Evidence | Score |
| --- | --- |
| Same UUID | 10,000 |
| Same nonzero vendor | 600 |
| Same nonzero model | 700 |
| Same nonzero serial | 2,000 |
| Same name | 250 |
| Same native dimensions | 100 |

A candidate must reach 1,000. Equal top-scoring weak candidates are rejected rather than arbitrarily selected; a matching UUID wins. This is a heuristic, not a hardware identity guarantee for indistinguishable screens.

The input role can initially auto-select the only connected display. The User role initially chooses the main display. After saving, neither role silently falls back to another unrelated physical display.

ScreenCaptureKit supplies shareable displays, NSScreen supplies user-facing names, and Core Graphics display reconfiguration triggers refreshes. Reconfiguration events are coalesced (begin events ignored, ~0.6 s debounce) so one physical change causes one enumeration. Missing displays are also polled during startup/recovery.

Displays are numbered (main first, then left-to-right) so identical monitors can be told apart in pickers and Identify Screens. The number is display-only: it is not saved and is excluded from equality, so renumbering never restarts a feed. The confidence window is kept as-is when a refresh leaves its target screen unchanged, avoiding flicker, and is not re-shown while the Mac is asleep.

## Recovery and readiness

Local feed recovery and wizard receiver retries are different mechanisms:

- MonitorBroadcast serializes configuration changes using a worker and revision tracking. Changing configuration stops the old capture/sender before applying the new configuration.
- A feed stays Starting until an actual accepted video frame arrives, rather than merely creating a sender. First-frame waiting polls up to 80 times at 100 ms intervals (roughly eight seconds per capture attempt).
- Capture/NDI failures retry with exponential delays starting at one second and capped at 60 seconds. Success resets backoff.
- AppState rechecks missing/unavailable screen enumeration every five seconds while awake and permission is granted.
- Screen-mode wizard startup has up to five local readiness attempts, with two-second pauses.
- Magewell startup operations use up to 15 attempts by default, with two-second pauses. Retryable cases include source-not-found, selected transient URLError values, HTTP 408/429, and HTTP 5xx. Authentication/configuration errors do not automatically retry.
- Individual receiver requests have a six-second request timeout and twelve-second resource timeout. Login, source list, selection, and fallback may involve several requests. Overall elapsed time is therefore not simply the pause budget.
- Stop Checking cancels the wizard operation, not both independent broadcasts.
- ProPresenter mode opens ProPresenter when it is installed but not running, waits up to 90 seconds for it, and then allows 30 receiver attempts (instead of 15) for its NDI output to appear. The confidence output is hidden only after routing succeeds.
- Receiver work is serialized: Settings' test/manual-switch actions are disabled while the wizard runs, and the wizard waits for any in-progress Settings receiver action before starting. Reset All Settings cancels both.
- Renaming the projector feed rewrites the monitor match only when it equals the old name or contains `(old name)`.
- Only one copy of the app runs. A second copy (different path, same bundle identifier) posts a distributed notification asking the running copy to open Settings, then quits. Reopening the running app from Finder also opens Settings.
- Sleep stops feed capture/senders and hides confidence output. Wake waits approximately two seconds, refreshes, and resumes.

Recheck Availability refreshes screens and local feeds without choosing a Magewell source. Recheck & Retry repeats the wizard's selected workflow and can change the receiver input. Restart Both NDI Broadcasts forces recreation while preserving preferences.

## Wizard and window behavior

The menu contains status, Configure Screens (custom label supported), Settings…, About, and Quit separated into groups. Settings and wizard show a temporary Dock icon; normal operation is an accessory/menu-bar application.

The startup wizard cannot be closed through its red window button; it can be minimized. Successful configuration dismisses it. Quitting the application is still possible. Screen mode can optionally enable confidence output; ProPresenter mode checks for the running app and offers to open it first. The app does not configure ProPresenter's own NDI output.

When automatic receiver control is disabled, the wizard configures local behavior without issuing receiver selection commands.

## Magewell API compatibility

The actor-based client uses an ephemeral URLSession with cookies kept in memory. Credentials come from Settings/Keychain, never the local development `.env`.

Current API path:

1. POST `/api/user/login`: username and password hash; SHA-256 first, with MD5 compatibility fallback on authentication failure.
2. GET `/api/source/list?type=ndi`: parse supported NDI source shapes.
3. Match exact case-insensitive name first, otherwise one case-insensitive substring.
4. POST `/api/source/select` with the selected source ID.

Legacy path:

1. GET `/mwapi?method=login&id=<username>&pass=<md5>`.
2. Query `get-ndi-sources`.
3. Select through `set-channel` with `ndi-name=true` and the encoded source name.

Unsupported modern responses (including HTTP 404/405) can trigger legacy fallback. Authentication errors remain actionable errors. Source matches with zero or multiple substring results include available names in the error. Duplicate exact names are not specially disambiguated; use unique actual source names.

Official references: [current IP decoder API](https://www.magewell.com/api-docs/pro-convert-ip-decoder-api/latest/) and [legacy Pro Convert decoder API](https://www.magewell.com/api-docs/pro-convert-decoder-api/). Actual sanctuary firmware/network interaction remains an on-site acceptance item.

## Security, privacy, and deployment boundaries

- Password: generic macOS Keychain item; other preferences: UserDefaults. Settings are per local user, not a cloud account.
- The development `.env` is ignored and not part of the bundle or tracked documentation.
- Receiver address validation permits private/link-local/loopback IPs, localhost, .local names, and unqualified local names. This is an intended local-address restriction, not an audited DNS/redirect isolation boundary.
- Local HTTP is supported, with App Transport Security exceptions. Password hashing does not make an HTTP session equivalent to TLS; use a trusted local management network.
- The app is not App Sandboxed; it uses the hardened runtime and a stable certificate-backed signature. The receiver and NDI runtime require local-network access.
- The current package is Apple Development signed, not Developer ID notarized. Manual trust is required on a deployment Mac. Stable signing helps privacy permissions persist but cannot guarantee macOS never asks again.
- Bundled libndi.dylib is signed before the containing app is sealed. SDK headers/runtime are externally installed for development; the runtime is private to the shipped app.
- Diagnostics/logging do not save pixels or passwords, but may identify displays, hosts, and configuration. Review before sharing publicly.
- No recording, audio capture/mixing, internet streaming, web server, analytics, cloud service, remote accounts, or automatic updater is implemented.
- Current packages target Apple Silicon, macOS 13+. Intel support is not validated or packaged.

See [README development/signing instructions](../README.md#development) and [deployment guide](../DEPLOYMENT.md). The NDI runtime remains proprietary; see [SDK licensing](../README.md#ndi-sdk-licensing) and the bundled [third-party notice](<../NDIScreenMirror/Resources/NDI Third-Party Licenses.txt>).
