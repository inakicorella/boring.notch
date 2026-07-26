//
//  NotificationsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct NotificationsView: View {
    @StateObject private var model = NotificationsViewModel.shared
    @Default(.enableNotificationsNotch) private var enableNotificationsNotch

    /// The stream can only run once the helper is Accessibility-trusted, so a
    /// stopped stream while the feature is on means the grant is missing.
    private var emptyStateText: LocalizedStringKey {
        guard enableNotificationsNotch else { return "Notification mirroring is off" }
        return model.streamRunning ? "No recent notifications" : "Accessibility permission needed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Notifications", systemImage: "bell.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if model.hasNotifications {
                    Button("Clear") {
                        model.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            if model.notifications.isEmpty {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.notifications) { notification in
                            NotificationRow(notification: notification) {
                                model.dismiss(notification.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct NotificationRow: View {
    let notification: NotchNotification
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !notification.appName.isEmpty {
                        Text(notification.appName.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(notification.postedAt, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Text(notification.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !notification.detail.isEmpty {
                    Text(notification.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            HoverButton(icon: "xmark", iconColor: .secondary, scale: .medium) {
                onDismiss()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
    }
}

/// Rich in-notch banner shown when a notification arrives and the notch opens.
struct NotificationBannerView: View {
    let notification: NotchNotification
    var onTap: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            appIcon
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(notification.appName.isEmpty ? "Notification" : notification.appName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(notification.postedAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Text(notification.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !notification.detail.isEmpty {
                    Text(notification.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = notification.appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: "bell.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// Compact closed-notch indicator for the most recent notification.
struct NotificationsLiveActivity: View {
    @StateObject private var model = NotificationsViewModel.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.white)
            if let latest = model.latest {
                VStack(alignment: .leading, spacing: 0) {
                    Text(latest.headline)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !latest.appName.isEmpty {
                        Text(latest.appName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
    }
}
