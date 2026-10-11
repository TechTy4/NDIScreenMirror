import AppKit
import SwiftUI

/// Briefly labels every physical screen with its name and assigned roles so
/// people can tell which monitor is which before choosing roles in Settings.
@MainActor
final class ScreenIdentifier {
    private var windows: [NSWindow] = []
    private var dismissal: Task<Void, Never>?

    func show(displays: [DisplayDescriptor], roles: (DisplayDescriptor) -> [String], duration: Duration = .seconds(6)) {
        hide()
        for display in displays {
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
            }) else { continue }
            let size = CGSize(width: min(760, screen.frame.width - 80), height: 240)
            let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                               width: size.width, height: size.height)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(rootView: ScreenLabel(name: display.displayName, roles: roles(display)))
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private struct ScreenLabel: View {
    let name: String
    let roles: [String]

    var body: some View {
        VStack(spacing: 12) {
            Text(name).font(.system(size: 34, weight: .bold)).multilineTextAlignment(.center)
            Text(roles.isEmpty ? "No role assigned" : roles.joined(separator: " · "))
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(roles.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.accentColor, lineWidth: 4))
        .environment(\.colorScheme, .dark)
    }
}
