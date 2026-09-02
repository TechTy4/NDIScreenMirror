# Deploying Sanctuary NDI

This build is intended for an Apple Silicon sanctuary Mac running macOS 13 or newer. It does not require a paid Apple Developer membership, the NDI SDK, Xcode, or Terminal on that Mac.

## Install and trust

1. Open `Sanctuary-NDI-1.0.2-arm64.dmg`.
2. Drag **Sanctuary NDI** onto the **Applications** shortcut.
3. In Applications, Control-click **Sanctuary NDI**, choose **Open**, then confirm **Open**. This explicitly trusts the locally signed app.
4. If macOS still blocks it, open **System Settings → Privacy & Security**, scroll to Security, and choose **Open Anyway** for Sanctuary NDI.

Do not re-sign or modify the installed app. Its stable signature lets macOS remember Screen Recording permission.

## First-run permissions

1. Open Sanctuary NDI from Applications. Its icon appears in the menu bar.
2. Allow **Screen Recording** when prompted. If macOS asks to quit the app, reopen it afterward.
3. Allow **Local Network** access when prompted.
4. Click the menu-bar icon and choose the projector/output display under **Mirror Display**.
5. Confirm the menu reports **Broadcasting** and shows the expected NDI source name.
6. Open **Settings…** and leave **Launch Sanctuary NDI at login** enabled. The Settings window temporarily gives the app a Dock icon; the icon disappears when Settings closes.

## If Control-click Open is unavailable

As an administrator, remove only the downloaded-file quarantine marker, then open the app again:

    xattr -dr com.apple.quarantine "/Applications/Sanctuary NDI.app"

This fallback is not normally necessary. It does not change the app's signature.

## Receiver verification

The default receiver entry is shown as `<MAC-NAME> (Sanctuary Projector Screen)`. The Mac and receiver must be on the same local network. Sanctuary NDI does not change the receiver's selected source.

## Updating later

Quit Sanctuary NDI, replace the existing app in Applications with the new build, and reopen it. Builds made with the same signing identity should retain privacy permissions; if macOS requests permission again, approve it once.
