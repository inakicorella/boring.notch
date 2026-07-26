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
        URL(fileURLWithPath: filePath).deletingLastPathComponent().path
    }
}

struct CursorEditPayload: Codable {
    let filePath: String?
    let path: String?
    let file_path: String?

    var resolvedPath: String? {
        filePath ?? path ?? file_path
    }
}
