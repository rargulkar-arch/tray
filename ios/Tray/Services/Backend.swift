import Foundation

enum BackendError: LocalizedError {
    case notConfigured
    case notSignedIn
    case server(String)
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Tray has no backend yet. Fill in Secrets.xcconfig and rebuild."
        case .notSignedIn:
            return "You are signed out."
        case .server(let message):
            return message
        case .http(let code, let body):
            return body.isEmpty ? "Request failed (\(code))." : body
        case .badResponse:
            return "The server sent something unexpected."
        }
    }
}

struct AuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String

    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

/// A small, deliberate Supabase client: auth, table reads, and RPC.
///
/// Written by hand rather than pulled in as a package so that the whole network
/// surface of the app is about two hundred readable lines, and so there is no
/// SDK version to chase. Everything the app does is an RPC defined in
/// `supabase/migrations`, which is where the access rules live too.
actor Backend {
    static let shared = Backend()

    private var tokens: AuthTokens?
    private var refreshTask: Task<AuthTokens, Error>?
    private let tokenKey = "session"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {
        if let data = Keychain.get(tokenKey) {
            tokens = try? Self.decoder.decode(AuthTokens.self, from: data)
        }
    }

    // MARK: - Session

    var isSignedIn: Bool { tokens != nil }
    var currentUserID: String? { tokens?.userId }

    private func store(_ new: AuthTokens?) {
        tokens = new
        if let new, let data = try? Self.encoder.encode(new) {
            Keychain.set(data, for: tokenKey)
        } else {
            Keychain.delete(tokenKey)
        }
    }

    /// Returns a usable access token, refreshing first if it is about to expire.
    /// Concurrent callers share one refresh rather than racing each other.
    private func accessToken() async throws -> String {
        guard let current = tokens else { throw BackendError.notSignedIn }
        if current.isFresh { return current.accessToken }

        if let existing = refreshTask {
            return try await existing.value.accessToken
        }
        let task = Task { try await self.performRefresh(current.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            return try await task.value.accessToken
        } catch {
            // A refresh token that the server rejects is never coming back.
            store(nil)
            throw BackendError.notSignedIn
        }
    }

    private func performRefresh(_ refreshToken: String) async throws -> AuthTokens {
        let body: [String: Any] = ["refresh_token": refreshToken]
        let data = try await raw(path: "/auth/v1/token",
                                 query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                 method: "POST", body: body, authorized: false)
        let new = try Self.parseTokens(data)
        store(new)
        return new
    }

    // MARK: - Phone auth

    /// Ask Supabase to send a six digit code.
    func sendCode(toPhone phone: String) async throws {
        _ = try await raw(path: "/auth/v1/otp", method: "POST",
                          body: ["phone": phone, "create_user": true], authorized: false)
    }

    @discardableResult
    func verifyCode(phone: String, code: String) async throws -> AuthTokens {
        let data = try await raw(path: "/auth/v1/verify", method: "POST",
                                 body: ["phone": phone, "token": code, "type": "sms"],
                                 authorized: false)
        let new = try Self.parseTokens(data)
        store(new)
        return new
    }

    func signOut() async {
        if tokens != nil {
            _ = try? await raw(path: "/auth/v1/logout", method: "POST", body: [:], authorized: true)
        }
        store(nil)
    }

    // MARK: - Data

    /// Call a Postgres function. This is how the app does everything.
    func rpc<T: Decodable>(_ name: String, _ args: [String: Any] = [:], as type: T.Type) async throws -> T {
        let data = try await raw(path: "/rest/v1/rpc/\(name)", method: "POST",
                                 body: args, authorized: true)
        return try decode(T.self, from: data)
    }

    /// Call a Postgres function whose result does not matter.
    func rpc(_ name: String, _ args: [String: Any] = [:]) async throws {
        _ = try await raw(path: "/rest/v1/rpc/\(name)", method: "POST",
                          body: args, authorized: true)
    }

    /// Straight table read, used only for reference data like the hall list.
    func select<T: Decodable>(_ table: String, query: [URLQueryItem], as type: T.Type) async throws -> T {
        let data = try await raw(path: "/rest/v1/\(table)", query: query,
                                 method: "GET", body: nil, authorized: true)
        return try decode(T.self, from: data)
    }

    // MARK: - Transport

    private func raw(path: String,
                     query: [URLQueryItem] = [],
                     method: String,
                     body: [String: Any]?,
                     authorized: Bool) async throws -> Data {
        guard Config.isConfigured else { throw BackendError.notConfigured }

        guard var components = URLComponents(string: "https://\(Config.host)\(path)") else {
            throw BackendError.notConfigured
        }
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(Config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authorized {
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(Config.anonKey)", forHTTPHeaderField: "Authorization")
        }

        if let body, method != "GET" {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }

        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server(Self.readableError(from: data, status: http.statusCode))
        }
        return data
    }

    /// Postgres raises real sentences — "that username is taken" — and they are
    /// better than anything the app could invent, so surface them as they are.
    private static func readableError(from data: Data, status: Int) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Request failed (\(status))."
        }
        for key in ["message", "error_description", "msg", "error", "hint", "details"] {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return "Request failed (\(status))."
    }

    private static func parseTokens(_ data: Data) throws -> AuthTokens {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String,
              let refresh = object["refresh_token"] as? String else {
            throw BackendError.badResponse
        }
        let lifetime = (object["expires_in"] as? Double) ?? 3600
        let user = object["user"] as? [String: Any]
        let id = (user?["id"] as? String) ?? ""
        return AuthTokens(accessToken: access,
                          refreshToken: refresh,
                          expiresAt: Date().addingTimeInterval(lifetime),
                          userId: id)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // PostgREST answers a void function with an empty body.
        if data.isEmpty, let empty = "null".data(using: .utf8) {
            return try Self.decoder.decode(T.self, from: empty)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    // MARK: - Coding

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.parseTimestamp(text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Bad timestamp: \(text)"))
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Postgres timestamps come back with or without fractional seconds, and
    /// with the zone written as "+00:00" or "Z" depending on the column.
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseTimestamp(_ text: String) -> Date? {
        isoFractional.date(from: text) ?? isoPlain.date(from: text)
    }
}
