import Foundation
import ServiceManagement

@MainActor
final class LoginItemService {
    private let defaultAttemptKey = "didAttemptDefaultLoginItemRegistration"

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enableByDefaultIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: defaultAttemptKey) else { return }
        UserDefaults.standard.set(true, forKey: defaultAttemptKey)

        guard SMAppService.mainApp.status == .notRegistered else { return }
        try? SMAppService.mainApp.register()
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }
}
