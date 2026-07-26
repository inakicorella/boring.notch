//
//  NotificationsSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct NotificationsSettings: View {
    @Default(.enableNotificationsNotch) private var enableNotificationsNotch
    @Default(.notificationLiveActivity) private var notificationLiveActivity
    @Default(.notificationBannerInNotch) private var notificationBannerInNotch
    @StateObject private var model = NotificationsViewModel.shared
    @State private var accessibilityGranted: Bool?

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableNotificationsNotch) {
                    Text("Mirror notifications in the notch")
                }
                .onChange(of: enableNotificationsNotch) { _, enabled in
                    if enabled {
                        model.startStreamIfNeeded()
                        Task { await refreshAccessibility(prompt: true) }
                    } else {
                        model.stopStream()
                    }
                }

                Defaults.Toggle(key: .notificationBannerInNotch) {
                    Text("Drop a banner from the notch on arrival")
                }
                .disabled(!enableNotificationsNotch)

                Defaults.Toggle(key: .notificationLiveActivity) {
                    Text("Otherwise, peek on the closed notch")
                }
                .disabled(!enableNotificationsNotch || notificationBannerInNotch)
            } header: {
                Text("General")
            } footer: {
                Text("Notifications are read from macOS Notification Center as their banners appear. Ones fully suppressed by a Focus mode won't be captured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Stream status") {
                    Text(model.streamRunning ? "Listening" : "Stopped")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Accessibility permission") {
                    Text(accessibilityStatusText)
                        .foregroundStyle(accessibilityGranted == false ? .red : .secondary)
                }
                if accessibilityGranted == false {
                    Button("Grant Accessibility access") {
                        Task { await refreshAccessibility(prompt: true) }
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Mirroring uses Accessibility to read notification banners. Grant access in System Settings › Privacy & Security › Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Notifications")
        .onAppear {
            if enableNotificationsNotch {
                model.startStreamIfNeeded()
            }
            Task { await refreshAccessibility(prompt: false) }
        }
    }

    private var accessibilityStatusText: String {
        switch accessibilityGranted {
        case .some(true): return "Granted"
        case .some(false): return "Not granted"
        case .none: return "Checking…"
        }
    }

    private func refreshAccessibility(prompt: Bool) async {
        let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: prompt)
        await MainActor.run { accessibilityGranted = granted }
    }
}
