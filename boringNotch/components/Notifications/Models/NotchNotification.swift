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

    /// Best-effort icon for the source app, resolved from its name. Falls back to
    /// a matching running app, then a Spotlight/bundle lookup, else nil.
    var appIcon: NSImage? {
        guard !appName.isEmpty else { return nil }
        let workspace = NSWorkspace.shared
        if let running = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        })?.icon {
            return running
        }
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.\(appName.replacingOccurrences(of: " ", with: ""))"
        ) {
            return workspace.icon(forFile: url.path)
        }
        return nil
    }
}
