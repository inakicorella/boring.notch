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
                NotchEmptyState(icon: model.streamRunning ? "bell" : "bell.slash", text: emptyStateText)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.notifications) { notification in
                            NotificationRow(notification: notification) {
                                model.dismiss(notification.id)
                            }
                            .onTapGesture { model.openSourceApp(of: notification) }
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
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            NotificationAppIcon(notification: notification)
                .frame(width: 26, height: 26)
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
            .opacity(isHovering ? 1 : 0)
            .accessibilityLabel("Dismiss")
        }
        .padding(8)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) { isHovering = hovering }
        }
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
            NotificationAppIcon(notification: notification)
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
}

/// The source app's icon, or a bell when the app can't be resolved.
struct NotificationAppIcon: View {
    let notification: NotchNotification

    var body: some View {
        if let icon = notification.appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                Image(systemName: "bell.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
        }
    }
}

/// Empty-panel message in the shelf's style (hierarchical symbol + rounded gray text).
struct NotchEmptyState: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .symbolVariant(.fill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)
            Text(text)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
