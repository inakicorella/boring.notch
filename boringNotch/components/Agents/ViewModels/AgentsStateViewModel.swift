//
//  AgentsStateViewModel.swift
//  boringNotch
//

import AppKit
import Defaults
import Foundation

@MainActor
final class AgentsStateViewModel: ObservableObject {
    static let shared = AgentsStateViewModel()

    @Published private(set) var pendingPrompts: [PendingClaudePrompt] = []
    @Published private(set) var cursorEdits: [CursorEditEvent] = []
    @Published private(set) var bridgeRunning = false

    private let maxCursorEdits = 30
    private let decisionTimeout: TimeInterval = 120

    var pendingPromptCount: Int { pendingPrompts.count }
    var hasPendingPrompts: Bool { !pendingPrompts.isEmpty }

    private init() {
        AgentBridgeServer.shared.onRunningStateChange = { [weak self] running in
            // Delivered on the main queue by AgentBridgeServer.
            MainActor.assumeIsolated {
                self?.bridgeRunning = running
            }
        }
    }

    func startBridgeIfNeeded() {
        guard Defaults[.enableAgentsNotch] else {
            stopBridge()
            return
        }
        let port = UInt16(clamping: Defaults[.agentsBridgePort])
        // bridgeRunning is driven by the server's real readiness callback.
        AgentBridgeServer.shared.start(port: port)
    }

    func stopBridge() {
        AgentBridgeServer.shared.stop()
        // Resolve any waiting prompts as deny so Claude hooks don't hang
        for prompt in pendingPrompts {
            prompt.resolve(.deny)
        }
        pendingPrompts.removeAll()
        // bridgeRunning will flip to false via the server's state callback,
        // but set it eagerly so the UI reflects the intent immediately.
        bridgeRunning = false
    }

    func awaitClaudeDecision(rawBody: Data) async -> AgentDecision {
        let payload = (try? JSONDecoder().decode(ClaudePermissionPayload.self, from: rawBody))
            ?? ClaudePermissionPayload(toolName: nil, hookEventName: nil, toolInput: nil, sessionId: nil, cwd: nil)

        let promptID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AgentDecision, Never>) in
                let prompt = PendingClaudePrompt(id: promptID, payload: payload, continuation: continuation)
                pendingPrompts.insert(prompt, at: 0)

                if Defaults[.autoOpenAgentsOnPrompt] {
                    NotificationCenter.default.post(name: .openAgentsPanel, object: nil)
                }

                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(self?.decisionTimeout ?? 120))
                    guard let self else { return }
                    if let stillPending = self.pendingPrompts.first(where: { $0.id == promptID }), !stillPending.isResolved {
                        self.resolve(promptID: promptID, decision: .deny)
                    }
                }
            }
        } onCancel: {
            // Claude Code hung up before a decision (session ended, request
            // withdrawn, or the hook process was killed). Drop the stale prompt
            // so it disappears from the notch instead of lingering as fake
            // "approval history" until the timeout. resolve() is idempotent and
            // resumes the continuation exactly once.
            Task { @MainActor [weak self] in
                self?.resolve(promptID: promptID, decision: .deny)
            }
        }
    }

    func resolve(promptID: UUID, decision: AgentDecision) {
        guard let index = pendingPrompts.firstIndex(where: { $0.id == promptID }) else { return }
        let prompt = pendingPrompts.remove(at: index)
        prompt.resolve(decision)
    }

    /// Answers the newest request (the one shown first in the panel).
    func resolveNewest(_ decision: AgentDecision) {
        guard let newest = pendingPrompts.first else { return }
        resolve(promptID: newest.id, decision: decision)
    }

    func recordCursorEdit(rawBody: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: rawBody) as? [String: Any],
              let path = (object["file_path"] as? String) ?? (object["filePath"] as? String) ?? (object["path"] as? String)
        else { return }

        cursorEdits.removeAll { $0.filePath == path }
        cursorEdits.insert(CursorEditEvent(filePath: path), at: 0)
        if cursorEdits.count > maxCursorEdits {
            cursorEdits = Array(cursorEdits.prefix(maxCursorEdits))
        }
    }

    func clearCursorEdits() {
        cursorEdits.removeAll()
    }

    func openInCursor(path: String? = nil) {
        if let path, !path.isEmpty {
            let fileURL = URL(fileURLWithPath: path)
            let cursorURL = URL(fileURLWithPath: "/usr/local/bin/cursor")
            let homebrewCursor = URL(fileURLWithPath: "/opt/homebrew/bin/cursor")
            let executable = FileManager.default.isExecutableFile(atPath: homebrewCursor.path)
                ? homebrewCursor
                : (FileManager.default.isExecutableFile(atPath: cursorURL.path) ? cursorURL : nil)

            if let executable {
                let process = Process()
                process.executableURL = executable
                process.arguments = ["-g", path]
                try? process.run()
                return
            }

            NSWorkspace.shared.open(fileURL)
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cursorops.Cursor") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(string: "cursor://")!)
        }
    }

    // MARK: - Hook installation

    /// Done by the non-sandboxed helper: from inside the sandbox, "home" is the app
    /// container, so ~/.claude and ~/.cursor would be unreachable.
    func installHooks() async throws {
        let port = Defaults[.agentsBridgePort]
        if let message = await XPCHelperClient.shared.installAgentHooks(port: port) {
            throw NSError(domain: "AgentHooks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
