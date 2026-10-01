import Foundation

/// Calls the Postgres `SECURITY DEFINER` RPCs added in
/// VestigoBackend/supabase/migrations/002_friends_system.sql (create_invite,
/// get_invite_preview, accept_invite, and later stages' functions) directly via
/// PostgREST's `/rest/v1/rpc/<function>` endpoint — matching the existing house style of
/// plain URLSession clients rather than the official supabase-swift SDK.
///
/// Every call requires a valid Supabase session; enforcement of *who* is allowed to do
/// *what* lives entirely server-side (RLS + each function's own auth.uid() checks), not
/// here — this client is just transport.
actor SupabaseRPCClient {
    private let baseURL = URL(string: "https://mtttuyvpjyugudkevchj.supabase.co")!
    private let publishableKey = "sb_publishable_nOkOgaVe9J8x6GbcqvR5cQ_Qkr_MkWP"
    private let auth: SupabaseAuthClient

    init(auth: SupabaseAuthClient) {
        self.auth = auth
    }

    enum RPCError: LocalizedError {
        case notAuthenticated
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "You need to sign in with Apple first."
            case .server(let message):
                return message
            }
        }
    }

    /// Calls a Postgres function declared `RETURNS TABLE(...)`, which PostgREST always
    /// returns as a JSON array of row objects — one element per call site's own `Row` type.
    func callTable<Params: Encodable, Row: Decodable>(_ function: String, params: Params) async throws -> [Row] {
        let body = try JSONEncoder().encode(params)
        let data = try await post(function, body: body)
        return try JSONDecoder().decode([Row].self, from: data)
    }

    /// Same as above, for functions that take no parameters (PostgREST still expects a
    /// JSON body, just an empty object).
    func callTable<Row: Decodable>(_ function: String) async throws -> [Row] {
        let data = try await post(function, body: Data("{}".utf8))
        return try JSONDecoder().decode([Row].self, from: data)
    }

    private func post(_ function: String, body: Data) async throws -> Data {
        guard let token = await auth.currentAccessToken() else {
            throw RPCError.notAuthenticated
        }
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RPCError.server("The server sent back something unexpected.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw RPCError.server(message)
        }
        return data
    }
}
