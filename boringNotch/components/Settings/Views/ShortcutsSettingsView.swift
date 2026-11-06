//
//  ShortcutsSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import KeyboardShortcuts
import SwiftUI

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
            Section {
                KeyboardShortcuts.Recorder("Show Agents:", name: .showAgents)
                KeyboardShortcuts.Recorder("Allow newest request:", name: .allowAgentRequest)
                KeyboardShortcuts.Recorder("Deny newest request:", name: .denyAgentRequest)
            } header: {
                Text("Agents")
            } footer: {
                Text("Answers the Claude Code request shown at the top of the Agents panel.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }
}
