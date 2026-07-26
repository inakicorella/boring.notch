//
//  AgentPrompt.swift
//  boringNotch
//

import Foundation

enum AgentDecision: String, Codable {
    case allow
    case deny
}

struct ClaudePermissionPayload: Codable {
    let toolName: String?
    let hookEventName: String?
    let toolInput: [String: AnyCodableValue]?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case hookEventName = "hook_event_name"
        case toolInput = "tool_input"
        case sessionId = "session_id"
    }

    var displayTitle: String {
        toolName ?? "Permission request"
    }

    var displayDetail: String {
        guard let toolInput else { return "Claude Code is waiting for approval" }
        if let filePath = toolInput["file_path"]?.stringValue {
            return filePath
        }
        if let path = toolInput["path"]?.stringValue {
            return path
        }
        if let command = toolInput["command"]?.stringValue {
            return command
        }
        if let pattern = toolInput["pattern"]?.stringValue {
            return pattern
        }
        return "Claude Code is waiting for approval"
    }
}

/// Minimal AnyCodable for loosely-typed Claude hook payloads.
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: AnyCodableValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([AnyCodableValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

@MainActor
final class PendingClaudePrompt: Identifiable, ObservableObject {
    let id: UUID
    let payload: ClaudePermissionPayload
    let rawBody: Data
    let createdAt: Date
    private let continuation: CheckedContinuation<AgentDecision, Never>
    private(set) var isResolved = false

    init(
        id: UUID = UUID(),
        payload: ClaudePermissionPayload,
        rawBody: Data,
        continuation: CheckedContinuation<AgentDecision, Never>
    ) {
        self.id = id
        self.payload = payload
        self.rawBody = rawBody
        self.createdAt = Date()
        self.continuation = continuation
    }

    func resolve(_ decision: AgentDecision) {
        guard !isResolved else { return }
        isResolved = true
        continuation.resume(returning: decision)
    }
}
