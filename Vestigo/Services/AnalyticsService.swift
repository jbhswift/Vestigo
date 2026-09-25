import Foundation
import PostHog
import SentrySwift
import StoreKit

// MARK: - Events

enum AnalyticsEvent {
    case tabViewed(AppTab)
    case pickForMeStarted(format: String)
    case pickForMeCompleted(resultCount: Int, durationSeconds: Int)
    case describeItUsed
    case cinemaSearchUsed
    case searchPerformed(type: String)
    case itemAdded(mediaType: String, action: String)
    case itemRated(rating: Double)
    case friendAdded
    case friendProfileViewed
    case collectionBrowsed
    case trailerOpened
    case streamingChecked
    case externalRatingFetched(keySource: String)
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
        case .externalRatingFetched(let keySource):
            return ("external_rating_fetched", ["key_source": keySource])
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
    let sentryAppHangTimeoutSeconds: TimeInterval?
    let sentryReportNonFullyBlockingAppHangs: Bool?
}

// MARK: - Service

final class AnalyticsService: @unchecked Sendable {
    static let shared = AnalyticsService()
    private init() {}

    // Events that arrive before PostHog is ready are queued and flushed on init.
    private let lock = NSLock()
    private var isReady = false
    private var pendingEvents: [(name: String, props: [String: Any]?)] = []

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var cachedDistribution: String?

    private func resolveDistribution() async -> String {
        #if DEBUG
        return "development"
        #else
        if let cachedDistribution { return cachedDistribution }
        let resolved = await isSandboxEnvironment() ? "testflight" : "appstore"
        cachedDistribution = resolved
        return resolved
        #endif
    }

    private func isSandboxEnvironment() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction.environment == .sandbox
        }
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
            let distribution = await resolveDistribution()
            setupPostHog(key: config.posthogKey, host: config.posthogHost, distribution: distribution)
            setupSentry(config: config, distribution: distribution)
            flushPendingEvents()

        } catch {
            print("[Analytics] Config fetch failed: \(error)")
        }
    }

    private func setupPostHog(key: String, host: String, distribution: String) {
        let config = PostHogConfig(projectToken: key, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register([
            "distribution": distribution,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        ])
        print("[Analytics] PostHog ready ✓")
    }

    private func setupSentry(config: AppRemoteConfig, distribution: String) {
        guard !config.sentryDsn.isEmpty else { return }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        SentrySDK.start { options in
            options.dsn = config.sentryDsn
            options.tracesSampleRate = 0.1
            options.environment = distribution
            options.releaseName = "vestigo@\(appVersion)+\(buildNumber)"
            options.attachViewHierarchy = false
            if let appHangTimeout = config.sentryAppHangTimeoutSeconds, appHangTimeout > 0 {
                options.appHangTimeoutInterval = appHangTimeout
            }
            if let reportNonFullyBlocking = config.sentryReportNonFullyBlockingAppHangs {
                options.enableReportNonFullyBlockingAppHangs = reportNonFullyBlocking
            }
        }
        SentrySDK.configureScope { scope in
            scope.setTag(value: distribution, key: "distribution")
            scope.setTag(value: appVersion, key: "app_version")
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

    func identify(cloudKitID: String, name: String) async {
        guard !cloudKitID.isEmpty else { return }
        let distribution = await resolveDistribution()
        PostHogSDK.shared.identify(cloudKitID, userProperties: [
            "name": name.isEmpty ? "Unknown" : name,
            "distribution": distribution,
        ])
        let sentryUser = User(userId: cloudKitID)
        sentryUser.username = name.isEmpty ? nil : name
        SentrySDK.setUser(sentryUser)
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
}
