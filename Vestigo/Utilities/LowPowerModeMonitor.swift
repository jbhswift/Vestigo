import Foundation

@MainActor
final class LowPowerModeMonitor: ObservableObject {
    @Published private(set) var isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

    init() {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                self?.isEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}
