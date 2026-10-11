# Troubleshooting

Start with Settings → General and Displays: check each feed's status, selected physical monitor, and output resolution. “Broadcasting” means capture reached video output; it does not prove the livestream computer or projector is receiving it.

## Startup says NDI or the receiver is unavailable

Allow a little time for displays, the network, ProPresenter, and the decoder to become available.

The app automatically retries local capture/NDI startup failures with increasing delays. It periodically refreshes missing screens. During wizard setup, transient receiver/network and source-discovery failures have a finite retry sequence with progress messages; invalid credentials or configuration require correction.

Choose the recovery action appropriate to the problem:

| Control | Location | Meaning |
| --- | --- | --- |
| Recheck Availability | Wizard and Settings → Support | Refresh screens and failed local feeds. Does not change the receiver source. |
| Recheck & Retry | Wizard after a connection error | Repeats the selected setup, including source selection on the receiver if automatic control is enabled. |
| Stop Checking | Wizard during setup | Cancels this connection attempt. Both independent screen feeds remain running when available. |
| Restart Both NDI Broadcasts | Settings → Support | Restarts both capture/sender pipelines, keeping saved preferences. |
| Refresh Connected Monitors | Settings → Displays | Refreshes just the available monitor list. |

If the receiver is unreachable because you are away from church, that is expected. You can turn off automatic projector control to test local screen streaming; turn it back on and verify the address and credentials before deploying.

See [architecture](ARCHITECTURE.md#recovery-and-readiness) for retry timing. Retry duration is not a fixed 30-second timeout: individual network requests and capture startup also take time.

## Screen Recording is enabled but the app keeps asking

1. Quit Sanctuary NDI.
2. Check that the installed copy in Applications is the one you launch—not a Debug build, an older copy, or the copy inside a mounted DMG.
3. In System Settings → Privacy & Security → Screen Recording (wording varies with macOS), enable Sanctuary NDI.
4. Reopen the installed app, following any macOS restart instruction.
5. If permission is still unavailable, use Settings → Support to open the privacy panel and copy diagnostics.

The packaged Release build uses a stable certificate-backed code signature to avoid treating every rebuild as a different application. Ad-hoc builds, changing signing identity, modifying the bundle, or launching multiple differently signed copies can invalidate prior approval. Do not re-sign the installed app as a routine troubleshooting step.

Screen Recording applies to both feeds, even in ProPresenter mode. Grant Local Network access if macOS prompts.

## Settings or a display picker seems unresponsive

Settings should open a normal window and temporarily show a Dock icon. Click that Dock icon or use application/window switching if the window is behind another app. In Displays, click Refresh Connected Monitors.

A missing previously selected display may appear unselected even though its saved identity still exists. Choose a connected replacement. Input and User picker placeholder rows are not reset commands; only the confidence role supports clearing its selection.

If using an old build from before the native-window picker changes, install the current release. Collect diagnostics if a current picker still fails.

## Selected Display Missing

Reconnect the intended screen and use Recheck Availability. If the hardware was replaced, choose the new screen in Settings → Displays.

The app intentionally avoids unrelated-display fallback. Matching cannot guarantee identity when identical displays lack useful serials or UUIDs, so ambiguous matches require a manual choice. Rearranging screens should not ordinarily change their roles.

## The User feed shows all three monitors or the wrong monitor

1. In Settings → Displays, explicitly choose the operator's physical screen for User screen (operator).
2. Check the User feed's reported monitor and video size.
3. On the livestream computer, select the full source name ending in **(Sanctuary User Screen)** from the intended Mac, not another sender or a composite scene.
4. Display visibly different test content on each screen. Use harmless content because it will be transmitted on the LAN.
5. Restart both broadcasts if the receiver retains an old image or dimensions.
6. If it persists, record the app version, macOS version, monitor arrangement/scaling, feed dimensions, receiver software/version, exact source name, and diagnostics.

v1.2.2 bounds capture to the selected screen's local rectangle, rejects stale stream callbacks and unexpected frame dimensions, and validates single-display filters on macOS 15.2+. The prior code also used a single-display filter; the reported three-screen problem was not reproduced locally. Treat this as hardening awaiting the actual sanctuary test, not a confirmed diagnosis of the original root cause.

macOS itself can mirror displays, and receiver software can compose multiple sources. Check those configurations separately; Sanctuary NDI does not intentionally stitch the desktop together.

## No NDI source on the livestream computer or Magewell

- Confirm the intended local feed says Broadcasting and has the correct physical screen.
- Make sure the sender and receiver are on a network that permits NDI discovery and transport. Check Wi-Fi/client isolation, VLAN/firewall boundaries, and Local Network approval; do not assume internet access proves LAN reachability.
- Check that the receiver is selecting the correct host-prefixed full source name.
- For ProPresenter, enable its NDI output and wait for the receiver to discover it.
- Use the developer [receive probe](TESTING.md#live-ndi-receive-probe) to separate discovery from video reception if needed.

The v1.2.2 development session successfully received video by a direct loopback connection, but its discovery-based probe did not find the source. Neither result proves discovery on the church LAN. Do not call the network verified based solely on a local capture status.

## Magewell login or source selection fails

Open Settings → Projector and confirm automatic control, local address, account, saved password, and both source-match strings. Use Save Password & Test first.

- Authentication failure: correct the username/password. Recheck does not repair credentials.
- No matching source: ensure the sender exists and has started. Rename the match to a distinctive portion of the actual discovered name.
- Multiple possible sources: use the full name or a unique substring.
- Monitor source renamed: update Monitor source contains as well.
- Unsupported API/firmware response: collect diagnostics and firmware/model information. Current and legacy APIs are implemented, but actual decoder behavior still requires on-site validation.

Never paste passwords, cookie values, or your `.env` into a public issue. Prefer a redacted diagnostics report.

## Confidence monitor is blank or wrong

Confidence mirroring is optional and available in monitor mode. Choose a confidence display different from the input display, reopen Configure Screens, and enable the duplicate. The input feed must have video.

This is a borderless fullscreen output window showing the input monitor—not macOS display mirroring and not the User feed. ProPresenter mode hides this app's confidence output. Sleep pauses it. Check that the selected output screen is connected.

## Login, sleep, or wake problems

Launch at Login needs macOS Login Items approval. Start the installed Applications copy once, enable the preference, and check system approval.

Both feeds pause during sleep. Wake refreshes screens after a short delay and recovers captures. If a display reconnects late, Recheck Availability refreshes it without changing saved roles.

For a repeatable problem, include whether it happened after login, wake, monitor unplugging, a source-name change, or a network change. See the [acceptance checklist](TESTING.md#on-site-acceptance-checklist).

## Support and safe fallback

Copy Diagnostics includes configuration/status metadata but no passwords or frame contents. It can still contain identifying display or local-network information; review and redact it before posting publicly.

Before a service, retain a known-working app installer and note current monitor roles/source matches. If automatic routing cannot be verified, disable it and select the intended source manually on the Magewell. This fallback still requires an actual working NDI source and receiver; it does not bypass a failed capture or network.
