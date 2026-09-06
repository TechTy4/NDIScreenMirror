# Deploying Sanctuary NDI

This build is intended for an Apple Silicon sanctuary Mac running macOS 13 or newer. It does not require a paid Apple Developer membership, the NDI SDK, Xcode, or Terminal on that Mac.

## Install and trust

1. Open `Sanctuary-NDI-1.2.1-arm64.dmg`.
2. Drag **Sanctuary NDI** onto the **Applications** shortcut.
3. In Applications, Control-click **Sanctuary NDI**, choose **Open**, then confirm **Open**. This explicitly trusts the locally signed app.
4. If macOS still blocks it, open **System Settings → Privacy & Security**, scroll to Security, and choose **Open Anyway** for Sanctuary NDI.

Do not re-sign or modify the installed app. Its stable signature lets macOS remember Screen Recording permission.

## First-run configuration

1. Open Sanctuary NDI from Applications. Its icon appears in the menu bar.
2. The Startup Wizard opens automatically and cannot be closed until a room mode is successfully started. It can be minimized.
3. Click **Settings…** in the wizard and configure the **Displays** tab:
   - Input monitor: the left/projector-output monitor to publish as NDI.
   - User screen (operator): the main/operator monitor, published as **Sanctuary User Screen** for the livestream computer. The first launch defaults to the Mac's main display; your selection is saved.
   - Confidence monitor: the right monitor that may show a fullscreen duplicate.
4. Configure the **Projector** tab with the Magewell receiver's local IP address, username, password, and distinctive portions of the two NDI source names. The password is saved in macOS Keychain, not the app bundle.
5. On the church network, click **Save Password & Test**. Resolve any connection or source-name message before relying on automatic switching.
6. Leave **Launch Sanctuary NDI at login** enabled in General.
7. Return to the Startup Wizard and choose the room mode.

Both screen feeds need Screen Recording access in every projector mode. Allow it in System Settings and reopen the app if macOS requests a restart. Allow **Local Network** access when prompted.

## Daily startup

- **ProPresenter** selects the configured ProPresenter NDI source on the Magewell. ProPresenter must be open first; the wizard offers an Open ProPresenter button when needed.
- **Left/Projector Monitor** waits for the continuously running monitor feed to be available, then selects it on the Magewell.
- Monitor mode optionally duplicates the feed fullscreen on the configured confidence monitor.

Both **Sanctuary Projector Screen** and **Sanctuary User Screen** stream whenever the app is running and the displays and permission are available, including before the wizard is completed and while ProPresenter is selected. Sleep pauses both; wake resumes them. The User feed is for the livestream computer and is not a projector choice in the wizard. Monitor selections persist across restarts.

The wizard appears at every app launch so each group explicitly chooses how the room should work that day.

## If Control-click Open is unavailable

As an administrator, remove only the downloaded-file quarantine marker, then open the app again:

    xattr -dr com.apple.quarantine "/Applications/Sanctuary NDI.app"

This fallback is not normally necessary. It does not change the app's signature.

## Receiver verification

The default monitor receiver entry is shown as `<MAC-NAME> (Sanctuary Projector Screen)`. The Mac and receiver must be on the same local network. Version 1.1 supports both current `/api/source/select` Magewell firmware and legacy `/mwapi` source selection automatically.

## Updating later

Quit Sanctuary NDI, replace the existing app in Applications with the new build, and reopen it. Builds made with the same signing identity should retain privacy permissions; if macOS requests permission again, approve it once.
