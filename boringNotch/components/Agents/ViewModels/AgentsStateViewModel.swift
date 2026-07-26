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
    var hasActivity: Bool { hasPendingPrompts || !cursorEdits.isEmpty }

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
            ?? ClaudePermissionPayload(toolName: nil, hookEventName: nil, toolInput: nil, sessionId: nil)

        let decision = await withCheckedContinuation { (continuation: CheckedContinuation<AgentDecision, Never>) in
            let prompt = PendingClaudePrompt(payload: payload, rawBody: rawBody, continuation: continuation)
            pendingPrompts.insert(prompt, at: 0)

            if Defaults[.autoOpenAgentsOnPrompt] {
                NotificationCenter.default.post(name: .openAgentsPanel, object: nil)
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(self?.decisionTimeout ?? 120))
                guard let self else { return }
                if let stillPending = self.pendingPrompts.first(where: { $0.id == prompt.id }), !stillPending.isResolved {
                    self.resolve(promptID: prompt.id, decision: .deny)
                }
            }
        }
        return decision
    }

    func resolve(promptID: UUID, decision: AgentDecision) {
        guard let index = pendingPrompts.firstIndex(where: { $0.id == promptID }) else { return }
        let prompt = pendingPrompts.remove(at: index)
        prompt.resolve(decision)
    }

    func recordCursorEdit(rawBody: Data) {
        let path: String
        if let payload = try? JSONDecoder().decode(CursorEditPayload.self, from: rawBody),
           let resolved = payload.resolvedPath {
            path = resolved
        } else if let object = try? JSONSerialization.jsonObject(with: rawBody) as? [String: Any],
                  let resolved = (object["file_path"] as? String)
                    ?? (object["filePath"] as? String)
                    ?? (object["path"] as? String) {
            path = resolved
        } else {
            return
        }

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

    var hooksInstallDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".boring-notch", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
    }

    func installHooks() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: hooksInstallDirectory, withIntermediateDirectories: true)

        let claudeScript = hooksInstallDirectory.appendingPathComponent("claude-permission.sh")
        let cursorScript = hooksInstallDirectory.appendingPathComponent("cursor-after-edit.sh")
        let port = Defaults[.agentsBridgePort]

        try claudePermissionScript(port: port).write(to: claudeScript, atomically: true, encoding: .utf8)
        try cursorAfterEditScript(port: port).write(to: cursorScript, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudeScript.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cursorScript.path)

        try mergeClaudeSettings(scriptPath: claudeScript.path)
        try mergeCursorHooks(scriptPath: cursorScript.path)
    }

    private func claudePermissionScript(port: Int) -> String {
        """
        #!/bin/bash
        # Boring Notch ↔ Claude Code PermissionRequest bridge
        set -euo pipefail
        INPUT="$(cat)"
        RESPONSE="$(curl -sS -X POST "http://127.0.0.1:\(port)/claude/permission" \
          -H "Content-Type: application/json" \
          --data-binary "$INPUT" \
          --max-time 300 || true)"
        if [ -z "$RESPONSE" ]; then
          printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Boring Notch bridge unavailable"}}}'
          exit 0
        fi
        printf '%s' "$RESPONSE"
        exit 0
        """
    }

    private func cursorAfterEditScript(port: Int) -> String {
        """
        #!/bin/bash
        # Boring Notch ↔ Cursor afterFileEdit bridge (notify only)
        set -euo pipefail
        INPUT="$(cat)"
        curl -sS -X POST "http://127.0.0.1:\(port)/cursor/edit" \
          -H "Content-Type: application/json" \
          --data-binary "$INPUT" \
          --max-time 2 >/dev/null 2>&1 || true
        exit 0
        """
    }

    private func mergeClaudeSettings(scriptPath: String) throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }

        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        let entry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": scriptPath
                ]
            ]
        ]
        hooks["PermissionRequest"] = [entry]
        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private func mergeCursorHooks(scriptPath: String) throws {
        let hooksURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any] = ["version": 1]
        if let data = try? Data(contentsOf: hooksURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
            if root["version"] == nil {
                root["version"] = 1
            }
        }

        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        var afterFileEdit = (hooks["afterFileEdit"] as? [[String: Any]]) ?? []
        afterFileEdit.removeAll { entry in
            if let command = entry["command"] as? String {
                return command.contains("boring-notch") || command.contains("cursor-after-edit")
            }
            return false
        }
        afterFileEdit.append([
            "command": scriptPath
        ])
        hooks["afterFileEdit"] = afterFileEdit
        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hooksURL, options: .atomic)
    }
}
