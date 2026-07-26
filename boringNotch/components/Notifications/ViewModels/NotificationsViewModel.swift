//
//  NotificationsViewModel.swift
//  boringNotch
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {
    static let shared = NotificationsViewModel()

    @Published private(set) var notifications: [NotchNotification] = []
    @Published private(set) var streamRunning = false
    /// Transiently true right after a notification arrives, to drive the closed-notch peek.
    @Published private(set) var showLiveActivity = false
    /// The notification currently being presented as an in-notch banner (nil = none).
    @Published private(set) var presentingBanner: NotchNotification?

    private let maxNotifications = 40
    private let liveActivityDuration: TimeInterval = 5
    private var listener: NotificationEventListener?
    private var liveActivityTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    var latest: NotchNotification? { notifications.first }
    var hasNotifications: Bool { !notifications.isEmpty }
    var unreadCount: Int { notifications.count }

    private init() {}

    func startStreamIfNeeded() {
        guard Defaults[.enableNotificationsNotch] else {
            stopStream()
            return
        }
        guard listener == nil else { return }
        let listener = NotificationEventListener(viewModel: self)
        self.listener = listener
        Task {
            let started = await XPCHelperClient.shared.startNotificationStream(listener: listener)
            await MainActor.run {
                self.streamRunning = started
                if !started {
                    // Reset so a later retry can re-establish the stream.
                    self.listener = nil
                }
            }
        }
    }

    func stopStream() {
        guard listener != nil else {
            streamRunning = false
            return
        }
        listener = nil
        streamRunning = false
        Task {
            await XPCHelperClient.shared.stopNotificationStream()
        }
    }

    func clear() {
        notifications.removeAll()
    }

    func dismiss(_ id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    // MARK: - Ingestion (called from the XPC listener, hopped to main)

    fileprivate func ingest(_ event: BNNotificationEvent) {
        let notification = NotchNotification(
            appName: event.appName,
            title: event.title,
            subtitle: event.subtitle,
            body: event.body,
            postedAt: event.postedAt
        )
        notifications.insert(notification, at: 0)
        if notifications.count > maxNotifications {
            notifications = Array(notifications.prefix(maxNotifications))
        }
        NotificationCenter.default.post(name: .newNotchNotification, object: nil)

        // Preferred presentation: briefly open the notch to show a banner.
        if Defaults[.notificationBannerInNotch] {
            presentBanner(notification)
        } else if Defaults[.notificationLiveActivity] {
            // Fallback: a compact peek on the closed notch.
            showLiveActivity = true
            liveActivityTask?.cancel()
            liveActivityTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.liveActivityDuration ?? 5))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.showLiveActivity = false }
            }
        }
    }

    /// The notch's open/close animation runs ~0.4s; hold the banner past the close
    /// so the collapse shows the banner, not the underlying tab, then clear it.
    private let bannerCloseSettle: TimeInterval = 0.55

    private func presentBanner(_ notification: NotchNotification) {
        withAnimation(.smooth) { presentingBanner = notification }
        NotificationCenter.default.post(name: .presentNotificationBanner, object: nil)
        bannerTask?.cancel()
        let duration = max(2.0, Defaults[.notificationBannerDuration]) + bannerCloseSettle
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.presentingBanner = nil }
        }
    }

    /// Dismiss the presenting banner immediately (e.g. user interaction).
    func dismissBanner() {
        bannerTask?.cancel()
        presentingBanner = nil
    }

    fileprivate func handleStreamStopped(_ reason: String?) {
        streamRunning = false
        listener = nil
    }
}

/// Bridge object exported over XPC; forwards helper callbacks to the view model.
@objc final class NotificationEventListener: NSObject, BoringNotchXPCHelperNotificationListener {
    weak var viewModel: NotificationsViewModel?

    init(viewModel: NotificationsViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func notificationDidPost(_ event: BNNotificationEvent) {
        Task { @MainActor [weak self] in
            self?.viewModel?.ingest(event)
        }
    }

    func notificationStreamDidStop(_ reason: String?) {
        Task { @MainActor [weak self] in
            self?.viewModel?.handleStreamStopped(reason)
        }
    }
}
