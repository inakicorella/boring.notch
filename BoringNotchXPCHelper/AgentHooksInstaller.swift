//
//  AgentHooksInstaller.swift
//  BoringNotchXPCHelper
//
//  Writes the Claude Code / Cursor hook scripts and registers them in the
//  user's config. Lives in the (non-sandboxed) helper so it reaches the real
//  ~/.claude and ~/.cursor rather than the app's sandbox container.
//

import Foundation

enum AgentHooksInstaller {
    private static var hooksInstallDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".boring-notch", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
    }

    static func install(port: Int) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: hooksInstallDirectory, withIntermediateDirectories: true)

        let claudeScript = hooksInstallDirectory.appendingPathComponent("claude-permission.sh")
        let cursorScript = hooksInstallDirectory.appendingPathComponent("cursor-after-edit.sh")

        try claudePermissionScript(port: port).write(to: claudeScript, atomically: true, encoding: .utf8)
        try cursorAfterEditScript(port: port).write(to: cursorScript, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudeScript.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cursorScript.path)

        try mergeClaudeSettings(scriptPath: claudeScript.path)
        try mergeCursorHooks(scriptPath: cursorScript.path)
    }

    private static func claudePermissionScript(port: Int) -> String {
        """
        #!/bin/bash
        # Boring Notch ↔ Claude Code PermissionRequest bridge.
        # No output (app not running / bridge off) lets Claude Code show its own prompt.
        set -euo pipefail
        INPUT="$(cat)"
        curl -sf -X POST "http://127.0.0.1:\(port)/claude/permission" \
          -H "Content-Type: application/json" \
          --data-binary "$INPUT" \
          --max-time 300 || true
        exit 0
        """
    }

    private static func cursorAfterEditScript(port: Int) -> String {
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

    private static func mergeClaudeSettings(scriptPath: String) throws {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        var root = try readJSONObject(at: settingsURL)

        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        var permissionHooks = (hooks["PermissionRequest"] as? [[String: Any]]) ?? []
        // Replace only our own entry; keep any PermissionRequest hooks the user already has.
        permissionHooks.removeAll { entry in
            let commands = (entry["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
            return commands.contains { $0.contains("boring-notch") }
        }
        permissionHooks.append(["hooks": [["type": "command", "command": scriptPath]]])
        hooks["PermissionRequest"] = permissionHooks
        root["hooks"] = hooks

        try writeJSONObject(root, to: settingsURL)
    }

    private static func mergeCursorHooks(scriptPath: String) throws {
        let hooksURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json")
        var root = try readJSONObject(at: hooksURL)
        if root["version"] == nil {
            root["version"] = 1
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

        try writeJSONObject(root, to: hooksURL)
    }

    /// Missing file → empty object. A file that exists but isn't a JSON object
    /// throws, so we never overwrite (and wipe) a config we couldn't read.
    private static func readJSONObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return object
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
