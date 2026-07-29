//
//  NotificationWatcher.swift
//  BoringNotchXPCHelper
//
//  Watches macOS Notification Center banners via the Accessibility API and
//  reports each new notification. Runs inside the (non-sandboxed) helper, which
//  already owns the Accessibility permission.
//
//  The banner hierarchy on recent macOS is:
//    AXWindow "Notification Center"
//      └─ AXGroup  (AXDescription = "<App>, <title>, <body>")
//           ├─ AXStaticText <title>
//           └─ AXStaticText <body>
//

import AppKit
import ApplicationServices

/// A single observed notification, before it crosses the XPC boundary.
struct ObservedNotification {
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let postedAt: Date

    /// Content signature used to de-duplicate repeated reads of the same banner.
    var signature: String { "\(appName)\u{1}\(title)\u{1}\(subtitle)\u{1}\(body)" }
}

private let kNotificationCenterBundleID = "com.apple.notificationcenterui"
private let kNotificationBannerSubrole = "AXNotificationCenterBanner"

final class NotificationWatcher {
    private var appElement: AXUIElement?
    private var ncPID: pid_t = 0

    /// Dedicated serial queue + dispatch timer. The helper is an XPC service with
    /// no running main run loop, so a RunLoop Timer / AXObserver source would never
    /// fire. A DispatchSourceTimer needs no run loop; AX attribute reads are safe
    /// to perform synchronously from any thread.
    private let queue = DispatchQueue(label: "BoringNotchXPCHelper.notificationWatcher")
    private var pollTimer: DispatchSourceTimer?
    private let pollInterval: TimeInterval = 0.5

    /// Recently emitted signatures with the time first seen, for de-duplication.
    private var seen: [String: Date] = [:]
    private let dedupWindow: TimeInterval = 12
    private var isStarted = false

    /// Called for every newly observed notification (on the watcher's queue).
    var onNotification: ((ObservedNotification) -> Void)?

    /// Returns false if Accessibility isn't trusted or Notification Center isn't found.
    @discardableResult
    func start() -> Bool {
        var didStart = false
        queue.sync { didStart = self.startLocked() }
        return didStart
    }

    func stop() {
        queue.sync { self.stopLocked() }
    }

    // MARK: - Queue-isolated implementation

    private func startLocked() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard !isStarted else { return true }
        guard attachToNotificationCenter() else { return false }

        isStarted = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        pollTimer = timer
        return true
    }

    private func stopLocked() {
        isStarted = false
        pollTimer?.cancel()
        pollTimer = nil
        appElement = nil
        seen.removeAll()
        ncPID = 0
    }

    private func tick() {
        // Re-attach if Notification Center restarted (pid changed).
        if !isNotificationCenterAlive() {
            appElement = nil
            _ = attachToNotificationCenter()
        }
        scanAndEmit()
    }

    private func isNotificationCenterAlive() -> Bool {
        guard ncPID != 0 else { return false }
        return NSRunningApplication(processIdentifier: ncPID) != nil
    }

    private func attachToNotificationCenter() -> Bool {
        guard let ncApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: kNotificationCenterBundleID).first else {
            return false
        }
        let pid = ncApp.processIdentifier
        appElement = AXUIElementCreateApplication(pid)
        ncPID = pid
        return true
    }

    // MARK: - Reading

    /// Walk all banner windows, extract notifications, emit unseen ones. Safe to
    /// call repeatedly (idempotent via de-dup). Invoked from the AX callback and poll.
    func scanAndEmit() {
        guard let appElement else { return }
        pruneSeen()

        guard let windows = copyAttr(appElement, kAXWindowsAttribute) as? [AXUIElement] else { return }
        for window in windows {
            for group in notificationGroups(in: window) {
                guard let observed = parseGroup(group) else { continue }
                guard !observed.title.isEmpty || !observed.body.isEmpty else { continue }

                let now = Date()
                if let firstSeen = seen[observed.signature], now.timeIntervalSince(firstSeen) < dedupWindow {
                    continue
                }
                seen[observed.signature] = now
                onNotification?(observed)
            }
        }
    }

    /// Notification banners are AXGroups with subrole "AXNotificationCenterBanner".
    private func notificationGroups(in window: AXUIElement) -> [AXUIElement] {
        var groups: [AXUIElement] = []
        func walk(_ el: AXUIElement, depth: Int) {
            if depth > 12 { return }
            if str(el, kAXSubroleAttribute) == kNotificationBannerSubrole {
                groups.append(el)
                return // the banner is a leaf container; no need to descend further
            }
            if let children = copyAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for c in children { walk(c, depth: depth + 1) }
            }
        }
        walk(window, depth: 0)
        return groups
    }

    private func parseGroup(_ group: AXUIElement) -> ObservedNotification? {
        // Static texts carry stable AXIdentifiers ("title"/"subtitle"/"body").
        var byID: [String: String] = [:]
        var ordered: [String] = []
        func walk(_ el: AXUIElement, _ depth: Int) {
            if depth > 8 { return }
            if str(el, kAXRoleAttribute) == (kAXStaticTextRole as String) {
                let value = str(el, kAXValueAttribute) ?? str(el, kAXTitleAttribute) ?? ""
                if !value.isEmpty {
                    ordered.append(value)
                    let id = str(el, kAXIdentifierAttribute) ?? ""
                    if !id.isEmpty, byID[id] == nil { byID[id] = value }
                }
            }
            if let children = copyAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for c in children { walk(c, depth + 1) }
            }
        }
        walk(group, 0)

        let title = byID["title"] ?? ordered.first ?? ""
        let subtitle = byID["subtitle"] ?? ""
        let body = byID["body"] ?? (ordered.count > 1 ? Array(ordered.dropFirst()).joined(separator: "\n") : "")
        guard !title.isEmpty || !body.isEmpty else { return nil }

        // The group's description is "<App>, <title>, <subtitle>, <body>".
        let appName = extractAppName(desc: str(group, kAXDescriptionAttribute) ?? "", title: title)

        return ObservedNotification(
            appName: appName,
            title: title,
            subtitle: subtitle,
            body: body,
            postedAt: Date()
        )
    }

    private func extractAppName(desc: String, title: String) -> String {
        let raw = desc.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return "" }
        // Cut everything from ", <title>" onward, leaving the leading app name.
        if !title.isEmpty, let r = raw.range(of: ", \(title)") {
            return String(raw[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        // Fallback: first comma-separated component.
        if let comma = raw.range(of: ", ") {
            return String(raw[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return raw
    }

    private func pruneSeen() {
        let cutoff = Date().addingTimeInterval(-dedupWindow)
        seen = seen.filter { $0.value > cutoff }
    }

    // MARK: - AX helpers

    private func copyAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }

    private func str(_ el: AXUIElement, _ attr: String) -> String? {
        copyAttr(el, attr) as? String
    }
}
