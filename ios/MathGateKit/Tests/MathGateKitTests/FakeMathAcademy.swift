import Foundation

/// A loopback stand-in for www.mathacademy.com.
///
/// The Android suite drives its real `HttpURLConnection` against a socket server for the same
/// reason: the parts most likely to break are `URLSession`'s own behaviour — folded `Set-Cookie`
/// headers, and a 302 surfacing instead of being followed — and a `URLProtocol` stub would
/// bypass exactly those.
final class FakeMathAcademy: @unchecked Sendable {
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: String
    }

    struct Reply {
        var status: Int = 200
        var headers: [(String, String)] = []
        var body: String = ""

        static func json(_ body: String) -> Reply {
            Reply(status: 200, headers: [("Content-Type", "application/json; charset=utf-8")], body: body)
        }

        static func html(_ body: String, status: Int = 200) -> Reply {
            Reply(status: status, headers: [("Content-Type", "text/html; charset=utf-8")], body: body)
        }
    }

    private let handler: @Sendable (Request) -> Reply
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var stopped = false
    private(set) var requests: [Request] = []

    private(set) var port: UInt16 = 0

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    init(handler: @escaping @Sendable (Request) -> Reply) {
        self.handler = handler
    }

    func recordedRequests() -> [Request] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func start() throws {
        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw Failure.socket("socket() failed") }
        var yes: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // ephemeral
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw Failure.socket("bind() failed") }

        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listenFD, $0, &len) }
        }
        port = actual.sin_port.byteSwapped

        guard listen(listenFD, 8) == 0 else { throw Failure.socket("listen() failed") }

        let fd = listenFD
        Thread.detachNewThread { [weak self] in
            while let self, !self.isStopped {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                self.serve(client)
                close(client)
            }
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    private func serve(_ client: Int32) {
        guard let head = readHead(client) else { return }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else { return }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where line.contains(":") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        var body = ""
        if let lengthText = headers["content-length"], let length = Int(lengthText), length > 0 {
            body = readExactly(client, length)
        }

        let request = Request(
            method: requestLine[0], path: requestLine[1], headers: headers, body: body
        )
        lock.lock(); requests.append(request); lock.unlock()

        let reply = handler(request)
        var out = "HTTP/1.1 \(reply.status) \(Self.reason(reply.status))\r\n"
        for (k, v) in reply.headers { out += "\(k): \(v)\r\n" }
        out += "Content-Length: \(reply.body.utf8.count)\r\n"
        out += "Connection: close\r\n\r\n"
        out += reply.body
        let bytes = Array(out.utf8)
        _ = bytes.withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count) }
    }

    /// Reads until the blank line that ends the headers.
    private func readHead(_ client: Int32) -> String? {
        var data = Data()
        var byte: UInt8 = 0
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let n = read(client, &byte, 1)
            if n <= 0 { return nil }
            data.append(byte)
            if data.count > 64 * 1024 { return nil }
        }
        return String(data: data, encoding: .utf8)
    }

    private func readExactly(_ client: Int32, _ length: Int) -> String {
        var buf = [UInt8](repeating: 0, count: length)
        var got = 0
        while got < length {
            let n = buf.withUnsafeMutableBufferPointer {
                read(client, $0.baseAddress! + got, length - got)
            }
            if n <= 0 { break }
            got += n
        }
        return String(decoding: buf[0..<got], as: UTF8.self)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 302: return "Found"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }

    enum Failure: Error { case socket(String) }
}
