import Foundation
import CryptoKit

/// Handles Sign in with Apple → Supabase session exchange, and keeps the resulting
/// session refreshed. This is the only Supabase Auth concern in the app — it does not
/// know about invites/friends/RPCs, which are Stage 3+.
///
/// Deliberately implemented with plain URLSession rather than the official
/// supabase-swift package, matching the existing house style (VestigoBackendClient
/// talks to the backend the same way) rather than adding a new dependency for
/// functionality a lightweight client already covers.
nonisolated struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userId: String
}

enum SupabaseAuthError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server sent back something unexpected."
        case .server(let message):
            return message
        }
    }
}

actor SupabaseAuthClient {
    // The publishable ("anon") key — meant to be embedded in a client, protected by RLS,
    // not a secret. Never put the service_role key here.
    private let baseURL = URL(string: "https://mtttuyvpjyugudkevchj.supabase.co")!
    private let publishableKey = "sb_publishable_nOkOgaVe9J8x6GbcqvR5cQ_Qkr_MkWP"
    private let keychainAccount = "session"

    private var cachedSession: SupabaseSession?

    init() {
        cachedSession = Self.loadSession()
    }

    /// A fresh, unhashed nonce for the Apple ID request. Pass the SHA256 hash of this
    /// value to `ASAuthorizationAppleIDRequest.nonce`, and this raw value to
    /// `signInWithApple(idToken:rawNonce:)` — Supabase re-hashes it server-side to
    /// verify against the nonce claim embedded in Apple's identity token.
    nonisolated static func makeRawNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var hasSession: Bool {
        cachedSession != nil
    }

    var currentUserId: String? {
        cachedSession?.userId
    }

    @discardableResult
    func signInWithApple(idToken: String, rawNonce: String) async throws -> SupabaseSession {
        var request = URLRequest(url: baseURL.appending(path: "auth/v1/token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "id_token"),
        ]))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "provider": "apple",
            "id_token": idToken,
            "nonce": rawNonce,
            "client_id": "com.jojovestigo",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let session = try Self.parseTokenResponse(data: data, response: response)
        store(session)
        return session
    }

    /// Returns a currently-valid access token, transparently refreshing if expired.
    /// Returns nil if there's no session at all (caller should treat as signed out).
    func currentAccessToken() async -> String? {
        guard let session = cachedSession else { return nil }
        if session.expiresAt > Date().addingTimeInterval(60) {
            return session.accessToken
        }
        do {
            let refreshed = try await refresh(using: session.refreshToken)
            return refreshed.accessToken
        } catch {
            return nil
        }
    }

    func signOut() {
        cachedSession = nil
        KeychainStore.delete(account: keychainAccount)
    }

    /// Calls the vestigo-friends Edge Function's delete-account endpoint, the one
    /// operation in this system that genuinely needs the service-role Admin API
    /// (auth.admin.deleteUser(), which cascades through every FK-referencing table) rather
    /// than being expressible as a plain client-callable RPC. Signs out locally on success,
    /// since the session the Edge Function just invalidated server-side is no longer usable.
    func deleteAccount() async throws {
        guard let token = await currentAccessToken() else {
            throw SupabaseAuthError.server("You need to be signed in to delete your account.")
        }
        var request = URLRequest(url: URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-friends/delete-account")!)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SupabaseAuthError.server(message)
        }
        signOut()
    }

    /// Syncs Vestigo's existing `settings.name` into the `profiles.display_name` row
    /// created for this user on first sign-in — used instead of Apple's fullName, which
    /// Apple only ever shares on the very first authorization and never again.
    func updateDisplayName(_ name: String) async {
        guard !name.isEmpty else { return }
        nonisolated struct Body: Encodable { let display_name: String }
        await patchOwnProfile(Body(display_name: name))
    }

    /// Featured/Excited-For are always visible to confirmed friends (see migration 005),
    /// so they're synced here the same way display_name is — a direct self-scoped PATCH
    /// against the `profiles_update_own` RLS policy, not an RPC.
    func updateProfileFields(featuredItems: [MediaItem], excitedForItems: [MediaItem]) async {
        nonisolated struct Body: Encodable { let featured_items: [MediaItem]; let excited_for_items: [MediaItem] }
        await patchOwnProfile(Body(featured_items: featuredItems, excited_for_items: excitedForItems))
    }

    private func patchOwnProfile<Body: Encodable>(_ body: Body) async {
        guard let token = await currentAccessToken() else { return }
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/profiles").appending(queryItems: [
            URLQueryItem(name: "user_id", value: "eq.\(cachedSession?.userId ?? "")"),
        ]))
        request.httpMethod = "PATCH"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Private

    private func refresh(using refreshToken: String) async throws -> SupabaseSession {
        var request = URLRequest(url: baseURL.appending(path: "auth/v1/token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
        ]))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        let session = try Self.parseTokenResponse(data: data, response: response)
        store(session)
        return session
    }

    private func store(_ session: SupabaseSession) {
        cachedSession = session
        if let encoded = try? JSONEncoder().encode(session) {
            KeychainStore.save(encoded, account: keychainAccount)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let user: TokenUser

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }

        struct TokenUser: Decodable {
            let id: String
        }
    }

    private static func parseTokenResponse(data: Data, response: URLResponse) throws -> SupabaseSession {
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw SupabaseAuthError.server(message)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SupabaseSession(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn)),
            userId: decoded.user.id
        )
    }

    private static func loadSession() -> SupabaseSession? {
        guard let data = KeychainStore.load(account: "session") else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }
}
