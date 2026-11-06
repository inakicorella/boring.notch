//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

// MARK: - Standardized Animations
/// Centralized animation definitions for consistent UI behavior across the app.
enum StandardAnimations {
    /// Interactive spring for responsive UI (used for notch interactions)
    static let interactive = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    
    /// Instant open/close when the user turned the animation off or enabled
    /// System Settings › Accessibility › Display › Reduce motion.
    private static var notchMotionOff: Bool {
        !Defaults[.enableOpeningAnimation] || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Spring animation for opening the notch
    static var open: Animation {
        guard !notchMotionOff else {
            return Animation.linear(duration: 0)
        }
        return Animation.spring(response: 0.42 / Defaults[.animationSpeedMultiplier], dampingFraction: 0.8, blendDuration: 0)
    }

    /// Spring animation for closing the notch
    static var close: Animation {
        guard !notchMotionOff else {
            return Animation.linear(duration: 0)
        }
        return Animation.spring(response: 0.45 / Defaults[.animationSpeedMultiplier], dampingFraction: 1.0, blendDuration: 0)
    }
    
    /// Bouncy spring for playful animations
    @available(macOS 14.0, *)
    static var bouncy: Animation {
        Animation.spring(.bouncy(duration: 0.4))
    }
    
    /// Smooth animation for general transitions
    static let smooth = Animation.smooth
    
    /// Timing curve fallback for older macOS versions
    static let timingCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
}

public class BoringAnimations {
    @Published var notchStyle: Style = .notch
        
    var animation: Animation {
        if #available(macOS 14.0, *), notchStyle == .notch {
            StandardAnimations.bouncy
        } else {
            StandardAnimations.timingCurve
        }
    }
}
