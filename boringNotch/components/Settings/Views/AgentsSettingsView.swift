//
//  AgentsSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct AgentsSettings: View {
    @Default(.enableAgentsNotch) private var enableAgentsNotch
    @Default(.autoOpenAgentsOnPrompt) private var autoOpenAgentsOnPrompt
    @Default(.agentsBridgePort) private var agentsBridgePort
    @StateObject private var agents = AgentsStateViewModel.shared
    @State private var installMessage: String?
    @State private var installDidFail = false

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableAgentsNotch) {
                    Text("Enable Agents tab")
                }
                .onChange(of: enableAgentsNotch) { _, enabled in
                    if enabled {
                        agents.startBridgeIfNeeded()
                    } else {
                        agents.stopBridge()
                    }
                }

                Defaults.Toggle(key: .autoOpenAgentsOnPrompt) {
                    Text("Open notch when Claude asks for approval")
                }
                .disabled(!enableAgentsNotch)

                HStack {
                    Text("Bridge port")
                    Spacer()
                    TextField("Port", value: $agentsBridgePort, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .disabled(!enableAgentsNotch)
                }
                .onChange(of: agentsBridgePort) { _, _ in
                    if enableAgentsNotch {
                        agents.startBridgeIfNeeded()
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Claude Code permissions are approved from the notch. Cursor edits are shown for review; Keep All still happens in Cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Bridge status") {
                    Text(agents.bridgeRunning && enableAgentsNotch ? "Listening on 127.0.0.1:\(agentsBridgePort)" : "Stopped")
                        .foregroundStyle(.secondary)
                }

                Button("Install Claude & Cursor hooks") {
                    do {
                        try agents.installHooks()
                        installDidFail = false
                        installMessage = "Hooks installed. Restart Claude Code / Cursor agent sessions to pick them up."
                    } catch {
                        installDidFail = true
                        installMessage = error.localizedDescription
                    }
                }
                .disabled(!enableAgentsNotch)

                if let installMessage {
                    Text(installMessage)
                        .font(.caption)
                        .foregroundStyle(installDidFail ? .red : .secondary)
                }
            } header: {
                Text("Hooks")
            } footer: {
                Text("Writes scripts to ~/.boring-notch/hooks and registers them in ~/.claude/settings.json and ~/.cursor/hooks.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Agents")
        .onAppear {
            if enableAgentsNotch {
                agents.startBridgeIfNeeded()
            }
        }
    }
}
