import Foundation
import Observation

@MainActor
@Observable
final class LowPowerModeMonitor {
    private(set) var isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    init() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                self?.isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
