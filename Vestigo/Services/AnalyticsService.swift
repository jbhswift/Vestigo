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
    case trailerOpened
    case streamingChecked
    case externalRatingFetched
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
        case .trailerOpened:
            return ("trailer_opened", nil)
        case .streamingChecked:
            return ("streaming_checked", nil)
        case .externalRatingFetched:
            return ("external_rating_fetched", nil)
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

    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    // Fires a Task to fetch keys from Supabase secrets, then initialises SDKs.
    // Called synchronously from AppDelegate — the Task completes within a few
    // hundred ms, well before the user interacts with any feature that tracks.
    func setup() {
        Task { await fetchConfigAndSetup() }
    }

    private func fetchConfigAndSetup() async {
        // Derive the config URL from the same Supabase project as the backend
        let supabaseBase = VestigoBackendConfiguration.baseURL
            .deletingLastPathComponent() // strip "vestigo-api"
        let configURL = supabaseBase.appending(path: "get-app-config")

        guard let (data, response) = try? await URLSession.shared.data(from: configURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let config = try? JSONDecoder().decode(AppRemoteConfig.self, from: data),
              config.ok,
              !config.posthogKey.isEmpty
        else { return }

        setupPostHog(key: config.posthogKey, host: config.posthogHost)
        setupSentry(dsn: config.sentryDsn)
    }

    private func setupPostHog(key: String, host: String) {
        let config = PostHogConfig(apiKey: key, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register([
            "distribution": isTestFlight ? "testflight" : "appstore",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        ])
    }

    private func setupSentry(dsn: String) {
        guard !dsn.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 0.1
            options.environment = self.isTestFlight ? "testflight" : "production"
            options.attachViewHierarchy = false
        }
    }

    func identify(cloudKitID: String, name: String) {
        guard !cloudKitID.isEmpty else { return }
        PostHogSDK.shared.identify(cloudKitID, userProperties: [
            "name": name.isEmpty ? "Unknown" : name,
            "distribution": isTestFlight ? "testflight" : "appstore",
        ])
    }

    func track(_ event: AnalyticsEvent) {
        let (name, props) = event.payload
        PostHogSDK.shared.capture(name, properties: props)
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
