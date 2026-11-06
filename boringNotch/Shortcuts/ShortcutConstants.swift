//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))

    // Agents. No defaults: a global "allow" key should be a deliberate choice.
    static let showAgents = Self("showAgents")
    static let allowAgentRequest = Self("allowAgentRequest")
    static let denyAgentRequest = Self("denyAgentRequest")
}
