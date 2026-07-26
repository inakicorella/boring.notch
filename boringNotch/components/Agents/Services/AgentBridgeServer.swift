//
//  AgentBridgeServer.swift
//  boringNotch
//

import Foundation
import Network

/// Loopback HTTP bridge for Claude Code / Cursor hooks.
final class AgentBridgeServer: @unchecked Sendable {
    static let shared = AgentBridgeServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.boringNotch.agentBridge", qos: .userInitiated)
    private(set) var isRunning = false
    private(set) var port: UInt16 = 19642

    /// Called on the main actor whenever the listener's readiness changes.
    var onRunningStateChange: (@Sendable (Bool) -> Void)?

    private init() {}

    private func notifyRunningState(_ running: Bool) {
        guard let handler = onRunningStateChange else { return }
        DispatchQueue.main.async { handler(running) }
    }

    func start(port: UInt16) {
        queue.async { [weak self] in
            guard let self else { return }
            // Guard on `listener` rather than `isRunning`: readiness flips
            // asynchronously via the state handler, so two start() calls racing
            // at launch would both see isRunning == false, tear each other's
            // listener down, and rebind before the port is released (EADDRINUSE).
            // If a listener already exists for this port, this call is a no-op.
            if self.listener != nil, self.port == port { return }
            self.stopLocked()
            self.port = port

            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection: connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.notifyRunningState(true)
                    case .failed(let error):
                        NSLog("AgentBridgeServer failed: \(error)")
                        self?.isRunning = false
                        self?.notifyRunningState(false)
                    case .cancelled:
                        self?.isRunning = false
                        self?.notifyRunningState(false)
                    default:
                        break
                    }
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                NSLog("AgentBridgeServer could not start: \(error)")
                self.isRunning = false
                self.notifyRunningState(false)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("AgentBridgeServer receive error: \(error)")
                connection.cancel()
                return
            }

            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }

            if let request = HTTPRequest.parse(from: next) {
                let task = Task {
                    let response = await self.route(request)
                    self.send(response, on: connection)
                }
                // While the decision is pending, keep watching the socket. If
                // the client (Claude Code's hook) hangs up before we answer,
                // cancel the route so the pending prompt is dropped from the
                // notch immediately instead of lingering until timeout.
                self.watchForDisconnect(on: connection, cancelling: task)
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            // Keep reading until headers+body are complete
            if next.count > 2 * 1024 * 1024 {
                self.send(HTTPResponse(status: 413, body: Data("Payload too large".utf8)), on: connection)
                return
            }
            self.receive(on: connection, buffer: next)
        }
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            let body = Data(#"{"ok":true,"service":"boring-notch-agents"}"#.utf8)
            return HTTPResponse(status: 200, contentType: "application/json", body: body)

        case ("POST", "/claude/permission"):
            return await handleClaudePermission(body: request.body)

        case ("POST", "/cursor/edit"):
            return await handleCursorEdit(body: request.body)

        default:
            return HTTPResponse(status: 404, body: Data("Not found".utf8))
        }
    }

    private func handleClaudePermission(body: Data) async -> HTTPResponse {
        let decision = await AgentsStateViewModel.shared.awaitClaudeDecision(rawBody: body)
        let json = ClaudeHookResponse.make(decision: decision)
        return HTTPResponse(status: 200, contentType: "application/json", body: json)
    }

    private func handleCursorEdit(body: Data) async -> HTTPResponse {
        await AgentsStateViewModel.shared.recordCursorEdit(rawBody: body)
        return HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"ok":true}"#.utf8))
    }

    /// Watches an in-flight connection for the client hanging up. Our requests
    /// are one-shot, so any further read completing means the peer closed the
    /// socket (FIN -> isComplete) or reset it (error). Either way the client is
    /// gone, so cancel the routing task; that propagates to the awaiting
    /// decision and drops the stale prompt from the notch.
    private func watchForDisconnect(on connection: NWConnection, cancelling task: Task<Void, Never>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, isComplete, error in
            if isComplete || error != nil {
                task.cancel()
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

enum ClaudeHookResponse {
    static func make(decision: AgentDecision) -> Data {
        let behavior = decision.rawValue
        let message = decision == .allow ? "Approved from Boring Notch" : "Denied from Boring Notch"
        let json = """
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\(behavior)","message":"\(message)"}}}
        """
        return Data(json.utf8)
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(from data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = headerRange.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let available = data.count - bodyStart
        guard available >= contentLength else { return nil }

        let body = contentLength > 0
            ? data.subdata(in: bodyStart..<(bodyStart + contentLength))
            : Data()

        let pathPart = String(parts[1]).split(separator: "?").first.map(String.init) ?? String(parts[1])
        return HTTPRequest(method: String(parts[0]).uppercased(), path: pathPart, headers: headers, body: body)
    }
}

private struct HTTPResponse {
    let status: Int
    let contentType: String
    let body: Data

    init(status: Int, contentType: String = "text/plain", body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }

    func serialize() -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}
