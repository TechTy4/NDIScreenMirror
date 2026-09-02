// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SanctuaryCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SanctuaryCore", targets: ["SanctuaryCore"])],
    targets: [
        .target(
            name: "SanctuaryCore",
            path: "NDIScreenMirror",
            exclude: [
                "AppState.swift", "Assets.xcassets", "CaptureManager.swift",
                "DisplayManager.swift", "LoginItemManager.swift", "MenuBarView.swift",
                "Info.plist",
                "NDIBridge.c", "NDIBridge.h", "NDIScreenMirror-Bridging-Header.h",
                "NDISender.swift", "Resources", "SanctuaryNDI.entitlements",
                "SanctuaryNDIApp.swift", "SettingsView.swift", "SettingsWindowController.swift"
            ],
            sources: ["Models.swift", "Preferences.swift"]
        ),
        .testTarget(name: "SanctuaryCoreTests", dependencies: ["SanctuaryCore"])
    ]
)
