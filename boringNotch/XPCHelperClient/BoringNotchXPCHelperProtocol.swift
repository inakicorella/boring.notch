//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperLunarListener {
    func lunarEventDidUpdate(_ event: BNLunarBrightnessEvent)
    func lunarStreamDidStop(_ reason: String?)
}

/// Callback interface for streamed system notifications observed by the helper.
@objc protocol BoringNotchXPCHelperNotificationListener {
    func notificationDidPost(_ event: BNNotificationEvent)
    func notificationStreamDidStop(_ reason: String?)
}

/// Combined listener interface used as the connection's remoteObjectInterface so
/// the helper can vend proxies for either callback protocol over one interface.
@objc protocol BoringNotchXPCHelperListener: BoringNotchXPCHelperLunarListener, BoringNotchXPCHelperNotificationListener {}

@objc(BNNotificationEvent)
final class BNNotificationEvent: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let postedAt: Date

    init(appName: String, title: String, subtitle: String, body: String, postedAt: Date) {
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.postedAt = postedAt
        super.init()
    }

    required init?(coder: NSCoder) {
        appName = coder.decodeObject(of: NSString.self, forKey: "appName") as String? ?? ""
        title = coder.decodeObject(of: NSString.self, forKey: "title") as String? ?? ""
        subtitle = coder.decodeObject(of: NSString.self, forKey: "subtitle") as String? ?? ""
        body = coder.decodeObject(of: NSString.self, forKey: "body") as String? ?? ""
        postedAt = coder.decodeObject(of: NSDate.self, forKey: "postedAt") as Date? ?? Date()
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(appName as NSString, forKey: "appName")
        coder.encode(title as NSString, forKey: "title")
        coder.encode(subtitle as NSString, forKey: "subtitle")
        coder.encode(body as NSString, forKey: "body")
        coder.encode(postedAt as NSDate, forKey: "postedAt")
    }
}

@objc(BNLunarBrightnessEvent)
final class BNLunarBrightnessEvent: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let brightness: Double
    let display: Int

    init(brightness: Double, display: Int) {
        self.brightness = brightness
        self.display = display
        super.init()
    }

    required init?(coder: NSCoder) {
        brightness = coder.decodeDouble(forKey: "brightness")
        display = coder.decodeInteger(forKey: "display")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(brightness, forKey: "brightness")
        coder.encode(display, forKey: "display")
    }
}

@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    // returns the displayID that will be used for built-in brightness operations (main or internal fallback)
    func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    func adjustScreenBrightness(by value: Float, with reply: @escaping (Bool) -> Void)
    // Lunar brightness events (performed by the helper)
    func isLunarAvailable(with reply: @escaping (Bool) -> Void)
    func startLunarEventStream(with reply: @escaping (Bool) -> Void)
    func stopLunarEventStream()
    /// Write Lunar's hideOSD preference (disable/enable Lunar's OSD when we replace it).
    func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void)
    // System notification mirroring (performed by the helper via Accessibility)
    func startNotificationStream(with reply: @escaping (Bool) -> Void)
    func stopNotificationStream()
}
