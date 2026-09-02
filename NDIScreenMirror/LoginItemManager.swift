import Foundation
import ServiceManagement

@MainActor
enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .requiresApproval: "Requires approval in System Settings"
        case .notRegistered: "Not registered"
        case .notFound: "Unavailable"
        @unknown default: "Unknown"
        }
    }
}
