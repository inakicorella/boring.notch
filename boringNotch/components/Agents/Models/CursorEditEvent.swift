//
//  CursorEditEvent.swift
//  boringNotch
//

import Foundation

struct CursorEditEvent: Identifiable, Equatable, Codable {
    let id: UUID
    let filePath: String
    let createdAt: Date

    init(id: UUID = UUID(), filePath: String, createdAt: Date = Date()) {
        self.id = id
        self.filePath = filePath
        self.createdAt = createdAt
    }

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var directoryHint: String {
        abbreviatingHome(URL(fileURLWithPath: filePath).deletingLastPathComponent().path)
    }
}
