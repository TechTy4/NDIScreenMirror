# Conversation and decision record

This document records the Sanctuary NDI development conversation supplied with this task, from the blank Xcode project through the October 11, 2026 documentation request.

**Record type:** user-message record plus summarized implementation outcomes, not a complete verbatim chat export. User quotations below preserve the supplied wording except normalized whitespace, escaped punctuation, and application mentions rendered as plain names. Long requirements are quoted where available; assistant outcomes are explicitly summaries. Earlier assistant/tool turns are not all available as a verbatim export and have not been invented. Release dates and implementation commits are checked against repository/GitHub history; individual early message timestamps are unavailable.

The [original attached build brief](ORIGINAL_BRIEF.md) is preserved separately. This record omits credentials, local environment-file contents, signing-account information, private paths, and captured screen content. The public repository is [TechTy4/NDIScreenMirror](https://github.com/TechTy4/NDIScreenMirror).

## 1. Blank project, SDK, and initial authorization

User:

> I created this blank project in Xcode and feel free to use Xcode or Computer as needed. Here is the prompt from the AI I discussed this with about what I want you to build. Build and document then package it when complete. You can test to see if it's working using the NDI admin interface in Chrome and you can set this mac as the source.

The attached brief requested a native menu-bar app called Sanctuary NDI, a selected physical-display feed using the official NDI SDK, saved display selection, login support, permission handling, recovery, tests, documentation, and a relocatable deployment package. It originally excluded Magewell HTTP control and elaborate onboarding. Those exclusions were later explicitly superseded.

Follow-up user messages, in order:

> you can submit details and download/install whatever SDK you need

> I signed up for and installed the SDK

> Continue

Implementation outcome summary: the application uses the official installed NDI SDK, not a placeholder NDI implementation. The current repository documents SDK 6.3.2, keeps the proprietary runtime out of Git, and embeds the redistributable library privately inside the built application.

## 2. Screen Recording permission loop

User messages, in order:

> Look at settings, screen recording is on but it keeps asking me Computer

> I think I did it

> Yes

> Yes allow and continue

> allowed

Outcome summary: Screen Recording remained a first-run system permission. Release packaging uses a stable certificate-backed signature instead of relying on a changing ad-hoc signature for deployments. Settings includes permission-request and privacy-panel actions. Those short approval messages are preserved as part of the sequence; they are not treated as proof that every subsequent build or the eventual sanctuary Mac has permissions.

Current guidance is in [Troubleshooting](TROUBLESHOOTING.md#screen-recording-is-enabled-but-the-app-keeps-asking).

## 3. Initial picker, Settings, and deployment feedback

User:

> A handful of things:
>
> 1. the mirror display picker doesn't work
> 2. when I click settings... nothing happens. I expect a settings app to open and maybe a dock icon?
> 3. make sure it's 100% ready (I'm not paying for apple developer, I am ok trusting it) for deploying to the sanctuary Mac

Follow-up:

> ok so the settings screen works now, the mirror display picker still doesn't do anything

Outcome summary: native Settings/window behavior and display selection were revised during development. The current application uses normal-window pickers in Settings → Displays and temporarily displays a Dock icon while Settings or the wizard is open. Normal operation remains menu-bar-only.

The user's willingness to trust a locally signed app is reflected in [Deployment](../DEPLOYMENT.md). The package does not require a paid Apple Developer membership on the sanctuary Mac. It is not notarized; local trust and permissions are still required. “100% ready” was a requested standard, not evidence that unavailable church hardware had passed testing.

## 4. Public GitHub repository and first release

User:

> Commit/Push any pending changes and Publish this as a Public Repo on TechTy4 Github

Then:

> Can you add a proper release as well?

Outcome summary: published the public repository and the [v1.0.2 release](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.0.2). Main implementation commit: [3ff85d3](https://github.com/TechTy4/NDIScreenMirror/commit/3ff85d3), September 2, 2026. The release includes an Apple Silicon deployment DMG and install/trust instructions. No separately published v1.0.0 or v1.0.1 is asserted by this record.

## 5. Simplified menu, startup wizard, confidence monitor, and Magewell

User request (formatting normalized):

> I'm not at church currently so I won't be able to test these changes but here is what I want you to do:
>
> I want to clean up the menu icon and put almost all the settings in the settings menu except for the following:
>
> (status pretty much like it is right now, can stay the same unless you have an idea to make it better)
>
> Startup Wizard
>
> Settings…
>
> About
>
> Quit
>
> I also want you to interface with the Magewell API to set which source it chooses from based on either a setting or what the user selects in the Startup Wizard which I will give more details on next.
>
> I want you to create a wizard that starts on startup that asks the following questions (as user friendly and non-technical as possible with technical details available for more technical users):
>
> 1. Input Source:
>
> Should the Projector choose the ProPresenter NDI feed or the input monitor (the monitor chooses to be streamed over NDI) feed as it’s source (In the settings I want a label for what to call this monitor, by default call it “Left/Projector Monitor” for our use case)
>
> 2. Mirror?
>
> Should the NDI stream be duplicated on the other screen? (The screen to be mirrored to should be selectable in settings as well, in our case it will be the right screen)
>
> For the Mirroring I want it to either create a window on the selected (generally the right one) screen and then go full screen or do some sort of full screen duplication of the input monitor as like a secondary output (we use the right monitors as the confidence monitors so if the school or whoever else is displaying content on the left monitor using the monitor mirroring mode instead of proPresenter, and wants to also use the confidence monitors duplicated, then they would select the mirror option.
>
> Again the whole point of this pass is to make everything as user friendly as possible, and because we turn the computer off everytime we are done with it, on startup, which will start this app, we want to ask the user how they plan on using it and then adjust accordingly (for example if it is the school they will probably be selecting Screen Mirror mode, unless they are using proPresenter (which they do occasionally) and then they would select ProPresenter mode. If they select screen mirroring mode they would be asked if they want to mirror on the confidence monitor as well)
>
> Selecting screen mirroring vs Pro presenter mode would use the Magewell API to control the input source (pro presenter has to be running first so I guess if propresenter is selected, then check to make sure ProPresenter is open, otherwise prompt to open pro presenter before selecting the ProPresenter NDI feed on the Magewell)
>
> If screen Mirror mode is selected then make sure the NDI stream is running and then change to that input in the magewell.
>
> I want the wizard to be non-closable (like where the red button is disabled and they can minimize it but really they have to go through it to close it)
>
> I created a .env file with the magewell credentials in it, although you won't be able to do anything with that right now as I am not on the church network, but I guess it would be good to configure the magewell IP/credentials in the settings of the app because I don't really want to package that into the app. I just put it there so you had a copy of the current credentials for testing when I am at church next.

Outcome summary: [v1.1.0](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.1.0), commit [762f719](https://github.com/TechTy4/NDIScreenMirror/commit/762f719), September 3, 2026:

- Minimal status/configuration/settings/about/quit menu with separators.
- Startup wizard on every launch; red close button disabled, minimizing allowed.
- ProPresenter/input-monitor choice and ProPresenter running/open check.
- Optional borderless fullscreen input-monitor duplication on a saved confidence display.
- Receiver settings, Keychain password storage, current/legacy Magewell API support, source discovery/matching/selection.
- Native Settings display-role pickers and temporary Dock presence.
- Ten logic tests, Debug/Release builds, local UI/confidence checks, and deployment packaging were recorded as passing.
- Actual receiver switching was not tested off the church network. No credentials were embedded in the app or committed.

Historical behavior: v1.1.0 stopped the app's monitor sender in ProPresenter mode. The next request superseded that.

## 6. Two continuous screen feeds independent of projector mode

User:

> I didn't look to see if this is the case already, but Even when it's in ProPresenter mode, can you have the Projector monitor NDI stream running? Also, can you create an NDI screen for the "User" Screen which is going to be the main screen that the computer operator uses, add a selector for that in the settings, and of course save all the settings. Both of those NDI streams should run all the time, the input prompt for the setup wizard should only control which one the Magewell/projector is pointed at. We have a livestream computer that is irrelevant to the user and use in the Sanctuary but it would be helpful to be able to see the User screen via NDI back there, and also the option to stream left monitor if needed at any point.

Outcome summary: [v1.2.0](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.2.0), commit [582d2f3](https://github.com/TechTy4/NDIScreenMirror/commit/582d2f3), September 6, 2026:

- Two independently owned capture/sender pairs: configurable Sanctuary Projector Screen and fixed-name Sanctuary User Screen.
- Saved User-screen selector initially chooses the main physical display.
- Both feeds start before wizard completion and remain running in ProPresenter mode.
- Wizard mode controls Magewell routing, not whether local senders run.
- Frame rate and cursor preferences apply to both.
- Recorded checks included ten tests, UI selection/persistence, local User-feed reception at 1800×1168, builds, and packaging.
- Only one display was connected locally; simultaneous two-screen isolation and sanctuary receiver operation remained on-site items.

Interpretation: “both run all the time” excludes sleep, missing selected displays, absent capture permission, or unrecovered errors. The User feed is not an additional projector choice in the wizard; it exists independently for livestream receivers.

## 7. Configure Screens menu label

User:

> change the menu item "Startup Wizard..." to "Configure Screens" and put an option to change that label in settings

Outcome summary: [v1.2.1](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.2.1), commit [6f0fb52](https://github.com/TechTy4/NDIScreenMirror/commit/6f0fb52), September 6, 2026:

- Default menu label is Configure Screens.
- Settings → General saves a custom label.
- Blank/whitespace label falls back to Configure Screens.
- The corresponding Settings button uses the same displayed label.
- Built, packaged, and published.

## 8. Startup availability and User feed showing three monitors

User:

> ok, two things I need you to address (I'm not on the church network so I'll just have to test eventually (when done, push to github so I can download and try at church, I'm leaving my mac on at home):
>
> 1. On startup, if the NDI isn't fully started up (or unavailable for some reason) it throws an error, I want it to either recheck availability or have a recheck button of some sort
> 2. The User screen being served over NDI is streaming all three monitors back to the livestream computer and not just the main screen

Outcome summary: [v1.2.2](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.2.2), commit [2fe63eb](https://github.com/TechTy4/NDIScreenMirror/commit/2fe63eb), October 11, 2026:

- Added Recheck Availability, Recheck & Retry, and Stop Checking.
- Wait for actual video before treating a local feed as ready.
- Retry transient receiver/network/source-discovery failures; do not endlessly retry bad credentials.
- Allow failed first NDI initialization to recover and periodically refresh missing screens.
- Bound capture to the selected physical screen's local rectangle; validate output dimensions, reject stale callbacks, and check single-display filters on macOS 15.2+.
- Report selected display and video dimensions per feed.
- Preserve prior settings and independent continuous feeds.

Recorded evidence: 15 logic tests and an isolated runtime regression passed; Debug/Release and package checks passed; release UI recheck was exercised; a direct local receive obtained User video at 1800×1168. A discovery-based probe did not discover the source in that development session.

Important limitation: the three-screen symptom could not be reproduced on the one-display development setup. These capture changes are defensive hardening, not a confirmed root-cause diagnosis. Church LAN discovery, actual three-monitor isolation, and physical Magewell switching still require testing. The [testing guide](TESTING.md) preserves both the successful evidence and outstanding acceptance items.

## 9. Repository documentation, including this conversation

User:

> Please make sure everything is documented on this Repo including this conversation please

Outcome summary of this documentation pass:

- Added the [documentation index](README.md), [settings reference](SETTINGS.md), [troubleshooting guide](TROUBLESHOOTING.md), [architecture/security notes](ARCHITECTURE.md), [testing/release/acceptance guide](TESTING.md), and [changelog](../CHANGELOG.md).
- Preserved the [original attached brief](ORIGINAL_BRIEF.md) and this user-request/decision record.
- Linked the new references from the main README and deployment guide.
- Kept receiver credentials, environment-file contents, signing-account details, and frame contents out of public documentation.
- Documentation-only changes do not constitute a new application version, retest the hardware, or replace the v1.2.2 release asset.

## 10. Usability, stability, and troubleshooting pass

User:

> Can you please look through everything in this folder, understand the context, make sure everything is correct and then make improvements to help user usability and stability to make this as easy to use as possible while still achieving everything we are trying to accomplish and having options for me to troubleshoot/perform more technical actions. When finished, have ChatGPT 6.1 sol review. Address anything it brings up then when finished build test and push to github

Outcome summary: [v1.3.0](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.3.0), October 11, 2026. See the [changelog](../CHANGELOG.md#130--2026-10-11) for the full list. Highlights: remembered wizard choice, automatic ProPresenter opening, inline monitor pickers, Identify Screens, richer menu status, single-instance handling, debounced display refreshes, and Settings tools for receiver discovery, manual switching, logs, relaunch, and reset.

The mandatory every-launch wizard, the two always-on feeds, and the minimal menu structure were deliberately kept. The previous choice is only pre-selected; nothing is routed until Start is clicked.

GPT-6.1-Sol (via the Codex CLI) reviewed the change and reported four issues: concurrent wizard/Settings receiver operations, host-qualified match names not following a rename, Reset leaving session state and pending tasks, and identical monitors being indistinguishable. All four were fixed before release. On-site hardware acceptance remains pending.

## Decisions that supersede the original brief

| Original request | Later decision / current result |
| --- | --- |
| One selected-display NDI feed | Two continuous independent feeds, projector/input plus User. |
| No separate room-mode workflow | Mandatory friendly routing wizard at every launch. |
| No Magewell HTTP API control | Explicit later request added authenticated modern/legacy receiver selection. |
| Display selection directly in menu | Simplified menu; physical roles live in native Settings. |
| Silent startup with no onboarding | Streams still start immediately, but room routing requires the wizard. |
| Startup Wizard… label | Configure Screens by default, user-customizable. |
| Prefer native pixels/efficient YCbCr | Current capture sends BGRA at bounded logical display dimensions; SDK converts internally. Retina backing-pixel transmission is not guaranteed. |
| Ad-hoc signing acceptable initially | Stable certificate-backed local signing used to reduce permission churn; manual trust remains required. |
| Fully verified deployment | Builds/local checks/package verified; actual sanctuary network and hardware acceptance remain pending. |

## Remaining handoff

Install the latest release on the sanctuary Mac and complete the [on-site acceptance checklist](TESTING.md#on-site-acceptance-checklist). Record actual results instead of inferring them from development checks. In particular, verify the User stream visually excludes the other two screens and confirm both routing choices change the real Magewell/projector while the two local feeds continue.
