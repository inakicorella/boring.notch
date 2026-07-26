//
//  NotchNotification.swift
//  boringNotch
//

import AppKit
import Foundation

/// A system notification mirrored into the notch.
struct NotchNotification: Identifiable, Equatable {
    let id: UUID
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let postedAt: Date

    init(
        id: UUID = UUID(),
        appName: String,
        title: String,
        subtitle: String,
        body: String,
        postedAt: Date
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.postedAt = postedAt
    }

    /// Best available single-line headline (title, else app name).
    var headline: String {
        title.isEmpty ? appName : title
    }

    /// Combined subtitle + body for the detail line.
    var detail: String {
        [subtitle, body]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }

    /// The source app's real icon (the one the native banner shows), resolved from
    /// its name. nil only when the app can't be located, so the UI shows a fallback.
    var appIcon: NSImage? {
        AppIconResolver.icon(forAppNamed: appName)
    }
}

/// Resolves app icons by display name and caches results (including misses), so
/// the per-render `appIcon` lookup doesn't rescan running apps and disk each time.
enum AppIconResolver {
    private static var cache: [String: NSImage] = [:]
    private static var misses: Set<String> = []
    private static let lock = NSLock()

    static func icon(forAppNamed name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[name] { return hit }
        if misses.contains(name) { return nil }

        var resolved: NSImage?
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == name })?.icon {
            resolved = running
        } else if let path = NSWorkspace.shared.fullPath(forApplication: name) {
            // Deprecated but the only name→bundle lookup that works without a bundle
            // id, and it resolves apps that aren't currently running.
            resolved = NSWorkspace.shared.icon(forFile: path)
        }

        if let resolved {
            cache[name] = resolved
        } else {
            misses.insert(name)
        }
        return resolved
    }
}
