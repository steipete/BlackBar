import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    private static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["TESTING_LIBRARY_VERSION"] != nil { return true }
        if env["SWIFT_TESTING"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }()

    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if isRunningTests { return }
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .enabled || service.status == .requiresApproval { return }
            try service.register()
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}
