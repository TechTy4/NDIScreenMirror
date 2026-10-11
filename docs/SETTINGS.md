# Settings reference

Open the menu-bar icon → **Settings…**. Settings is a normal native window; the app shows a Dock icon while Settings or the startup wizard is open, then returns to menu-bar-only operation.

Most changes save immediately for the current macOS user. The projector source name and password are draft fields with the additional commit behavior described below. There is no configuration-file editing required.

## General

| Setting | Default | Effect and persistence |
| --- | --- | --- |
| Configure Screens menu label | Configure Screens | Renames the menu item and Settings button that reopen the wizard. Saves while editing. Leading/trailing whitespace is trimmed for display; blank uses the default. |
| Input monitor label | Left/Projector Monitor | Friendly name shown in the wizard. Does not rename the NDI source or change a physical monitor. Saves immediately. |
| Launch Sanctuary NDI at login | On | Uses native SMAppService registration. macOS may require approval in Login Items; the stored preference alone does not prove registration is approved. |

Current session fields show what the projector shows, each feed's status with its live receiver count, and confidence-mirror state. They are read-only. The Login item row shows macOS's actual registration status (for example, “Requires approval”) with an **Open Login Items…** button. The Configure Screens button opens the same wizard as the menu item.

## Displays

| Setting | Default | Effect and persistence |
| --- | --- | --- |
| Input monitor | No saved selection | Physical screen published by the projector-monitor feed. With exactly one connected display and no prior selection, the app can select it automatically. Multiple displays require an explicit choice. |
| Confidence monitor | Not selected | Destination for the optional fullscreen duplicate of the input monitor. Can be cleared. Must differ from the input monitor for mirroring. |
| User screen (operator) | Main display on initial configuration | Physical screen published as Sanctuary User Screen. Its identity is saved; changing which display macOS calls “main” later does not automatically move this feed. |
| Projector NDI source name | Sanctuary Projector Screen | Editable network source name. Press Return, click Rename, or close Settings to commit a nonempty trimmed name. It cannot equal the User feed name. Recreates the sender, and updates Monitor source contains when that contained the old name. |
| User NDI source name | Sanctuary User Screen | Fixed read-only name, not an editable preference. |
| Frame rate | 60 fps | Select 60 or 30 fps. Saves immediately and applies to both screen feeds. |
| Show mouse pointer | On | Saves immediately and applies to both screen feeds. |

**Identify Screens** shows a large label on every connected monitor for a few seconds with its number, name, and assigned roles. Monitors are numbered main first, then left to right, so two identical models can still be told apart. **Refresh Connected Monitors** refreshes the available display list. Saved roles whose monitor is not connected are listed with a warning. The feed detail fields report the selected monitor and video dimensions when broadcasting.

Selections are physical-display identities, not list positions or desktop coordinates. They include UUID, vendor/model/serial information, name, and native dimensions for matching. If a saved screen is absent or cannot be matched safely, its feed pauses rather than switching to an unrelated screen. Choose the replacement manually.

The input and User roles may refer to the same physical screen if that is deliberately selected; they remain separate NDI sources. The confidence role is an output window, not a third NDI sender. Selecting it does not itself enable mirroring: the current wizard session controls that.

## Projector

| Setting | Default | Effect and persistence |
| --- | --- | --- |
| Let Sanctuary NDI choose the projector source | On | Enables Magewell control when completing the wizard. Turn off to use the screen feeds without automatic receiver switching. |
| Receiver address or IP | Empty | Local receiver address, saved in UserDefaults. Configure for the actual sanctuary network. |
| Username | Admin | Saved in UserDefaults. Change to the receiver's actual account. |
| Password | Empty until configured | Stored in this Mac user's Keychain, not UserDefaults or the app bundle. Press Return, use Save Password & Test, or close Settings to save the draft. |
| ProPresenter source contains | ProPresenter | Distinctive text used to identify the receiver's discovered ProPresenter NDI source. |
| Monitor source contains | Sanctuary Projector Screen | Distinctive text used to identify the projector-monitor source. This is separate from the editable source name above. |

Renaming the projector NDI source updates **Monitor source contains** automatically when the match text is the old name or a host-qualified name ending in `(old name)`, such as `HOST (old name)`; the hostname part is never changed. A custom match that does not contain the old name is left alone; check it after a rename.

**Save Password & Test** saves the password, authenticates to the receiver, and lists discovered NDI sources under **Sources the receiver can see**. It does not change the projector's source. Each source has **Use for ProPresenter** / **Use for Monitor** buttons that copy its full name into the matching setting, and each match setting then shows what it matches (or why it is ambiguous).

**Switch the projector now → Show ProPresenter / Show (input label)** routes the receiver immediately without the wizard. This is a troubleshooting tool; it updates the menu's “Projector shows” line and, like the wizard, hides the confidence output when switching to ProPresenter. These buttons are disabled while the wizard is connecting.

Source matching ignores capitalization, prefers an exact full-name match, and otherwise requires one substring match. Use a more distinctive name when several sources contain the same text. ProPresenter must have NDI output enabled; opening the application alone does not create a usable NDI source.

## Support

| Action | What it does |
| --- | --- |
| Screen Recording status | Shows whether macOS currently allows capture. |
| Request Permission | Invokes macOS's permission request. |
| Open Screen Recording Settings | Opens the relevant system privacy settings. |
| Recheck Availability | Refreshes connected screens and requests recovery of failed local feeds; does not switch the Magewell source. |
| Restart Both NDI Broadcasts | Forces both capture/sender pipelines to restart without resetting preferences. |
| Relaunch Sanctuary NDI | Quits and reopens the app, e.g. after granting Screen Recording. |
| Copy Diagnostics | Copies configuration, every connected display and its roles, receiver settings (password presence only), discovered sources, and status for support; never includes passwords or captured screen contents. |
| Copy Recent Log | Copies up to 400 of this app's own log entries from the last six hours. |
| Reset All Settings… | After confirmation, restores every setting to its default, deletes the saved receiver password, clears the session's projector mode, and reopens the startup wizard. Screen Recording permission is unaffected. |

See [troubleshooting](TROUBLESHOOTING.md) for the wizard's Recheck & Retry and Stop Checking controls.

## What is saved, and what is not

Preferences are per-user UserDefaults under the app's bundle identity, `org.sanctuary.SanctuaryNDI`. Display identities are JSON-encoded preference values. The password is a generic Keychain item with service `org.sanctuary.SanctuaryNDI.magewell` and account `receiver-password`, accessible after first unlock.

The current room mode, whether confidence mirroring is currently enabled, current tasks, API login cookies, and runtime errors are session state. The last *successful* wizard choice (mode and confidence duplication) is saved only to pre-select the answers next time; the app still asks at every launch and changes nothing until Start is clicked.

The older friendly label “Left / Projector Monitor” is migrated to “Left/Projector Monitor.” Settings → Support → Reset All Settings… restores defaults. Reinstalling the app normally preserves the user's settings and Keychain item. Moving the app to a different Mac does not transfer those settings or the password; configure and grant permissions there.

A local `.env` file was supplied for future church testing. The application does not load it, the release does not include it, and it must remain untracked. Enter receiver credentials through Settings.
