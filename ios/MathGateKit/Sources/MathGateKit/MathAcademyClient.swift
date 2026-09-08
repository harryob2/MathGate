import Foundation

/// Minimal Math Academy web client: form login, two session cookies, one JSON endpoint.
/// Never logs cookie values or the password.
///
/// Ported from the Android `MathAcademyClient.kt`, with one deliberate difference: cookies are
/// split out with `HTTPCookie.cookies(withResponseHeaderFields:)` rather than a hand-written
/// parser, because `URLSession` folds repeated `Set-Cookie` headers into one comma-separated
/// string and the `expires=Sat, 03 Oct ...` value contains a comma of its own.
public actor MathAcademyClient {
    public static let defaultBaseURL = URL(string: "https://www.mathacademy.com")!
    /// The session cookie records the user agent it was issued to, so this must not vary.
    public static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
    public static let requestTimeout: TimeInterval = 15
    public static let reloginMargin: TimeInterval = 2 * 24 * 60 * 60
    public static let loginBackoff: TimeInterval = 10 * 60
    public static let maxBodyBytes = 4 * 1024 * 1024

    public enum ClientError: Error, Equatable {
        case authFailed(String)
        case unexpectedResponse(String)
        case offline(String)
    }

    public enum LoginResult: Equatable, Sendable {
        case success
        case badCredentials(String)
    }

    struct Response {
        let code: Int
        let contentType: String?
        let location: String?
        let body: Data
    }

    private let session: SessionStore
    private let baseURL: URL
    private let urlSession: URLSession
    private let now: @Sendable () -> Date

    public init(
        session: SessionStore,
        baseURL: URL = MathAcademyClient.defaultBaseURL,
        urlSession: URLSession? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.now = now
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            // Cookies are handled by hand, exactly as on Android, so the two clients behave
            // identically and neither picks up anything the site sets that we did not ask for.
            config.httpCookieAcceptPolicy = .never
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.timeoutIntervalForRequest = MathAcademyClient.requestTimeout
            self.urlSession = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    /// POSTs the login form. Throws `.offline` when the network is unreachable.
    public func login(_ creds: Credentials) async throws -> LoginResult {
        session.clearCookies()
        let form = "usernameOrEmail=\(formEncode(creds.username))"
            + "&password=\(formEncode(creds.password))"
            + "&submit=LOGIN"
        let resp = try await request(method: "POST", path: "/login", form: form)
        MGLog.debug("login -> HTTP \(resp.code) location=\(resp.location ?? "-")")

        if (300..<400).contains(resp.code) {
            let loc = resp.location?.lowercased() ?? ""
            if loc.contains("login") || loc.contains("session-expired") {
                return .badCredentials("redirected to \(resp.location ?? loc)")
            }
            guard session.hasCookies else {
                return .badCredentials("no session cookie after login")
            }
            session.lastLogin = now()
            return .success
        }
        if resp.code == 200 {
            let detail = extractLoginError(resp.body) ?? "login page returned (HTTP 200)"
            return .badCredentials(detail)
        }
        throw ClientError.unexpectedResponse("login HTTP \(resp.code)")
    }

    /// Logs in only when there is no session or it is about to expire.
    public func ensureSession(_ creds: Credentials) async throws {
        let t = now()
        let fresh = session.hasCookies
            && (session.cookieExpires.map { $0.timeIntervalSince(t) > Self.reloginMargin } ?? true)
        if fresh { return }
        try await loginOrThrow(creds, at: t)
    }

    /// The most recent completed tasks. Re-logs in once if the session turns out to be dead.
    public func fetchRecentTasks(
        _ creds: Credentials,
        calendar: Calendar = .autoupdatingCurrent
    ) async throws -> [MathAcademyTask] {
        try await ensureSession(creds)

        // The cursor is tomorrow in the user's own zone. The site omits the (mis-spelled)
        // "minumum" query param when it wants the default of 25, so this is byte-for-byte the
        // request a logged-in browser makes.
        let cursor = calendar.date(byAdding: .day, value: 1, to: now()) ?? now()
        let path = "/api/previous-tasks/" + MaDateFormat.pathSegment(cursor, calendar: calendar)

        var resp = try await request(method: "GET", path: path)
        MGLog.debug("previous-tasks -> HTTP \(resp.code) type=\(resp.contentType ?? "-")")

        if looksExpired(resp) {
            MGLog.debug("session looks expired; re-logging in")
            try await loginOrThrow(creds, at: now())
            resp = try await request(method: "GET", path: path)
            MGLog.debug("previous-tasks (retry) -> HTTP \(resp.code) type=\(resp.contentType ?? "-")")
        }
        if looksExpired(resp) {
            throw ClientError.unexpectedResponse(
                "previous-tasks HTTP \(resp.code) (\(resp.contentType ?? "no content-type")) after re-login"
            )
        }
        do {
            return try TaskSummariser.parseArray(resp.body)
        } catch {
            throw ClientError.unexpectedResponse("previous-tasks is not a JSON array: \(error)")
        }
    }

    // MARK: - Internals

    private func loginOrThrow(_ creds: Credentials, at t: Date) async throws {
        if let until = session.loginBackoffUntil, t < until {
            let secs = Int(until.timeIntervalSince(t))
            throw ClientError.authFailed("login_backoff (\(secs)s left after a failed sign-in)")
        }
        switch try await login(creds) {
        case .success:
            session.loginBackoffUntil = nil
        case .badCredentials(let detail):
            session.loginBackoffUntil = t.addingTimeInterval(Self.loginBackoff)
            throw ClientError.authFailed("bad_credentials (\(detail))")
        }
    }

    private func looksExpired(_ resp: Response) -> Bool {
        if (300..<400).contains(resp.code) { return true }
        if [401, 403, 404].contains(resp.code) { return true }
        return !(resp.contentType?.lowercased().contains("json") ?? false)
    }

    private func request(method: String, path: String, form: String? = nil) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw ClientError.unexpectedResponse("bad path \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = Self.requestTimeout
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("en-GB,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if path.hasPrefix("/api/") {
            req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            req.setValue(baseURL.appendingPathComponent("learn").absoluteString,
                         forHTTPHeaderField: "Referer")
        } else {
            req.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        }
        if let cookie = cookieHeader() {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let form {
            req.httpBody = Data(form.utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
            req.setValue(baseURL.appendingPathComponent("login").absoluteString,
                         forHTTPHeaderField: "Referer")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: req, delegate: NoRedirectDelegate())
        } catch let error as URLError {
            throw ClientError.offline(error.localizedDescription)
        } catch {
            throw ClientError.offline("\(error)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.unexpectedResponse("non-HTTP response")
        }
        absorbCookies(from: http, url: url)
        return Response(
            code: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            location: http.value(forHTTPHeaderField: "Location"),
            body: data.count > Self.maxBodyBytes ? data.prefix(Self.maxBodyBytes) : data
        )
    }

    private func absorbCookies(from http: HTTPURLResponse, url: URL) {
        guard let fields = http.allHeaderFields as? [String: String] else { return }
        for cookie in Self.parseCookies(fields: fields, for: url) {
            switch cookie.name {
            case "session":
                session.cookieSession = cookie.value.isEmpty ? nil : cookie.value
                if let exp = cookie.expiresDate { session.cookieExpires = exp }
            case "session.sig":
                session.cookieSig = cookie.value.isEmpty ? nil : cookie.value
            default:
                break
            }
        }
    }

    /// Math Academy's cookies carry `Secure`, and `HTTPCookie` refuses to build those from an
    /// `http://` URL — which would silently drop every cookie when running against the local
    /// fake server. Parsing is therefore done against an https URL. That is safe because these
    /// cookies are only ever sent back to `baseURL`, which is https in any release build.
    static func parseCookies(fields: [String: String], for url: URL) -> [HTTPCookie] {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.scheme = "https"
        let parseURL = components?.url ?? url
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: parseURL)
    }

    private func cookieHeader() -> String? {
        guard let s = session.cookieSession, let sig = session.cookieSig,
              !s.isEmpty, !sig.isEmpty
        else { return nil }
        return "session=\(s); session.sig=\(sig)"
    }

    private func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let encoded = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    private func extractLoginError(_ body: Data) -> String? {
        guard let html = String(data: body, encoding: .utf8),
              let range = html.range(
                of: "<div id=\"errorMessage\">(.*?)</div>",
                options: [.regularExpression, .caseInsensitive]
              )
        else { return nil }
        let text = String(html[range])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Math Academy signals a dead session with a redirect, so redirects must surface rather than
/// be followed silently.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
