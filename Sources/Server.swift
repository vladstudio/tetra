import Foundation
import Network

final class TetraServer: @unchecked Sendable {
    private var listener: NWListener?

    /// Returns nil on success, or an error message on failure.
    @discardableResult
    func start(port: UInt16) -> String? {
        dispatchPrecondition(condition: .onQueue(.main))
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                let msg = "Invalid port: \(port)"
                print("[Tetra] \(msg)")
                return msg
            }
            listener = try NWListener(using: .tcp, on: nwPort)
        } catch {
            let msg = "Failed to start server: \(error.localizedDescription)"
            print("[Tetra] \(msg)")
            return msg
        }
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener?.start(queue: .global(qos: .userInitiated))
        print("[Tetra] Server listening on port \(port)")
        return nil
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ conn: NWConnection) {
        guard isLocalConnection(conn) else {
            conn.cancel()
            return
        }
        conn.start(queue: .global(qos: .userInitiated))

        nonisolated(unsafe) let timeout = DispatchWorkItem { conn.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)

        final class Buffer: @unchecked Sendable { var data = Data() }
        let buffer = Buffer()

        @Sendable func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data = data { buffer.data.append(data) }
                guard buffer.data.count < 10_000_000 else { timeout.cancel(); conn.cancel(); return }

                if let req = self?.parseHTTP(buffer.data), self?.hasFullBody(buffer.data) == true {
                    timeout.cancel()
                    self?.route(req, conn)
                } else if !isComplete && error == nil {
                    readMore()
                } else {
                    timeout.cancel()
                    conn.cancel()
                }
            }
        }
        readMore()
    }

    private func isLocalConnection(_ conn: NWConnection) -> Bool {
        guard case .hostPort(let host, _) = conn.endpoint else { return false }
        switch host {
        case .ipv4(let addr): return addr == IPv4Address.loopback
        case .ipv6(let addr): return addr == IPv6Address.loopback
        default: return false
        }
    }

    // MARK: - HTTP parsing

    private struct HTTPRequest: Sendable {
        let method: String
        let path: String
        let body: Data?
    }

    private static let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    private func parseHTTP(_ data: Data) -> HTTPRequest? {
        guard let sepRange = data.range(of: Self.headerSeparator) else { return nil }

        let headerData = data[data.startIndex..<sepRange.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let tokens = requestLine.split(separator: " ", maxSplits: 2)
        guard tokens.count >= 2 else { return nil }

        let bodyStart = sepRange.upperBound
        let body = bodyStart < data.endIndex ? Data(data[bodyStart...]) : nil

        return HTTPRequest(method: String(tokens[0]), path: String(tokens[1]), body: body)
    }

    private func hasFullBody(_ data: Data) -> Bool {
        guard let sepRange = data.range(of: Self.headerSeparator) else { return false }

        let headerData = data[data.startIndex..<sepRange.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return false }

        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let lenStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                if let expected = Int(lenStr) {
                    return data.endIndex - sepRange.upperBound >= expected
                }
            }
        }
        return true
    }

    // MARK: - Routing

    private func route(_ req: HTTPRequest, _ conn: NWConnection) {
        // Handle CORS preflight
        if req.method == "OPTIONS" {
            respond(conn, status: 204, json: [:] as [String: String])
            return
        }

        switch (req.method, req.path) {
        case ("GET", "/commands"):
            let names = CommandRunner.shared.listCommands()
            respond(conn, json: names)

        case ("POST", "/transform"):
            guard let body = req.body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let command = json["command"] as? String,
                  let text = json["text"] as? String else {
                respond(conn, status: 400, json: ["error": "Missing 'command' or 'text'"])
                return
            }
            let args = json["args"] as? [String: String] ?? [:]
            Task { @MainActor in
                CommandState.shared.isRunning = true
                CommandState.shared.runningCommand = command
                do {
                    let result = try await CommandRunner.shared.run(command: command, input: text, args: args, source: .api)
                    self.respond(conn, json: ["result": result])
                } catch {
                    self.respond(conn, status: 500, json: ["error": error.localizedDescription])
                }
                CommandState.shared.isRunning = false
                CommandState.shared.runningCommand = nil
            }

        default:
            respond(conn, status: 404, json: ["error": "Not found"])
        }
    }

    // MARK: - Response

    private func respond(_ conn: NWConnection, status: Int = 200, json: any Sendable) {
        let statusText: String = switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Error"
        }

        let body = status == 204 ? Data() :
            ((try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)) ?? Data())

        var headers = "HTTP/1.1 \(status) \(statusText)\r\n"
        headers += "Content-Type: application/json\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        headers += "Access-Control-Allow-Headers: Content-Type\r\n"
        headers += "Connection: close\r\n\r\n"

        var response = headers.data(using: .utf8)!
        response.append(body)

        conn.send(content: response, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
