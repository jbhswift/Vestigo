import Foundation
import PostHog
import Sentry

// MARK: - Events

enum AnalyticsEvent {
    case tabViewed(AppTab)
    case pickForMeStarted(format: String)
    case pickForMeCompleted(resultCount: Int, durationSeconds: Int)
    case describeItUsed
    case cinemaSearchUsed
    case searchPerformed(type: String)
    case itemDetailViewed(mediaType: String)
    case itemAdded(mediaType: String, action: String)
    case itemRated(rating: Double)
    case friendAdded
    case friendProfileViewed
    case collectionBrowsed
    case trailerOpened
    case streamingChecked
    case externalRatingFetched
    case apiCallMade(service: String)
}

private extension AnalyticsEvent {
    var payload: (name: String, props: [String: Any]?) {
        switch self {
        case .tabViewed(let tab):
            return ("tab_viewed", ["tab": tab.rawValue])
        case .pickForMeStarted(let format):
            return ("pick_for_me_started", ["format": format])
        case .pickForMeCompleted(let count, let duration):
            return ("pick_for_me_completed", ["result_count": count, "duration_seconds": duration])
        case .describeItUsed:
            return ("describe_it_used", nil)
        case .cinemaSearchUsed:
            return ("cinema_search_used", nil)
        case .searchPerformed(let type):
            return ("search_performed", ["search_type": type])
        case .itemDetailViewed(let type):
            return ("item_detail_viewed", ["media_type": type])
        case .itemAdded(let type, let action):
            return ("item_added", ["media_type": type, "action": action])
        case .itemRated(let rating):
            return ("item_rated", ["rating": rating])
        case .friendAdded:
            return ("friend_added", nil)
        case .friendProfileViewed:
            return ("friend_profile_viewed", nil)
        case .collectionBrowsed:
            return ("collection_browsed", nil)
        case .trailerOpened:
            return ("trailer_opened", nil)
        case .streamingChecked:
            return ("streaming_checked", nil)
        case .externalRatingFetched:
            return ("external_rating_fetched", nil)
        case .apiCallMade(let service):
            return ("api_call", ["service": service])
        }
    }
}

// MARK: - Remote config

private struct AppRemoteConfig: Decodable {
    let ok: Bool
    let posthogKey: String
    let posthogHost: String
    let sentryDsn: String
}

// MARK: - Service

final class AnalyticsService: @unchecked Sendable {
    static let shared = AnalyticsService()
    private init() {}

    // Events that arrive before PostHog is ready are queued and flushed on init.
    private let lock = NSLock()
    private var isReady = false
    private var pendingEvents: [(name: String, props: [String: Any]?)] = []

    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var distribution: String {
        #if DEBUG
        return "development"
        #else
        return isTestFlight ? "testflight" : "appstore"
        #endif
    }

    func setup() {
        guard !isSimulator else {
            print("[Analytics] Simulator detected — analytics disabled")
            return
        }
        Task { await fetchConfigAndSetup() }
    }

    private func fetchConfigAndSetup() async {
        let supabaseBase = VestigoBackendConfiguration.baseURL.deletingLastPathComponent()
        let configURL = supabaseBase.appending(path: "get-app-config")

        print("[Analytics] Fetching config from \(configURL)")

        do {
            let (data, response) = try await URLSession.shared.data(from: configURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Analytics] Config response status: \(status)")

            guard status == 200 else {
                print("[Analytics] Bad status — events will not be tracked")
                return
            }

            let config = try JSONDecoder().decode(AppRemoteConfig.self, from: data)
            guard config.ok, !config.posthogKey.isEmpty else {
                print("[Analytics] Config ok=\(config.ok) key=\(config.posthogKey.isEmpty ? "EMPTY" : "set") — aborting")
                return
            }

            print("[Analytics] Config loaded. Setting up PostHog + Sentry.")
            setupPostHog(key: config.posthogKey, host: config.posthogHost)
            setupSentry(dsn: config.sentryDsn)
            flushPendingEvents()

        } catch {
            print("[Analytics] Config fetch failed: \(error)")
        }
    }

    private func setupPostHog(key: String, host: String) {
        let config = PostHogConfig(apiKey: key, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register([
            "distribution": distribution,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        ])
        print("[Analytics] PostHog ready ✓")
    }

    private func setupSentry(dsn: String) {
        guard !dsn.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 0.1
            options.environment = self.isTestFlight ? "testflight" : "production"
            options.attachViewHierarchy = false
        }
        print("[Analytics] Sentry ready ✓")
    }

    private func flushPendingEvents() {
        lock.lock()
        let events = pendingEvents
        pendingEvents.removeAll()
        isReady = true
        lock.unlock()

        print("[Analytics] Flushing \(events.count) queued event(s)")
        for (name, props) in events {
            PostHogSDK.shared.capture(name, properties: props)
        }
    }

    func identify(cloudKitID: String, name: String) {
        guard !cloudKitID.isEmpty else { return }
        PostHogSDK.shared.identify(cloudKitID, userProperties: [
            "name": name.isEmpty ? "Unknown" : name,
            "distribution": distribution,
        ])
    }

    func track(_ event: AnalyticsEvent) {
        let (name, props) = event.payload
        lock.lock()
        if isReady {
            lock.unlock()
            PostHogSDK.shared.capture(name, properties: props)
        } else {
            pendingEvents.append((name: name, props: props))
            lock.unlock()
        }
    }

    func captureError(_ error: Error, context: [String: Any] = [:]) {
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context { scope.setExtra(value: value, key: key) }
        }
    }

    func captureMessage(_ message: String, context: [String: Any] = [:]) {
        SentrySDK.capture(message: message) { scope in
            for (key, value) in context { scope.setExtra(value: value, key: key) }
        }
    }
}
