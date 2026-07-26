//
//  AgentsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var agents = AgentsStateViewModel.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            claudePanel
            cursorPanel
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var claudePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Claude Code", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if agents.pendingPromptCount > 0 {
                    Text("\(agents.pendingPromptCount)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                        .foregroundStyle(.black)
                }
            }

            if agents.pendingPrompts.isEmpty {
                Text("No pending approvals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(agents.pendingPrompts) { prompt in
                            ClaudePromptRow(prompt: prompt) { decision in
                                agents.resolve(promptID: prompt.id, decision: decision)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var cursorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Cursor", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !agents.cursorEdits.isEmpty {
                    Button("Clear") {
                        agents.clearCursorEdits()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                HoverButton(icon: "arrow.up.forward.app", iconColor: .white, scale: .medium) {
                    agents.openInCursor()
                }
            }

            if agents.cursorEdits.isEmpty {
                Text("No recent agent edits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(agents.cursorEdits) { edit in
                            CursorEditRow(edit: edit) {
                                agents.openInCursor(path: edit.filePath)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
    }
}

private struct ClaudePromptRow: View {
    @ObservedObject var prompt: PendingClaudePrompt
    let onDecide: (AgentDecision) -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.payload.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(prompt.payload.displayDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            HoverButton(icon: "xmark", iconColor: .red.opacity(0.9), scale: .medium) {
                onDecide(.deny)
            }
            HoverButton(icon: "checkmark", iconColor: .green, scale: .medium) {
                onDecide(.allow)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.35))
        )
    }
}

private struct CursorEditRow: View {
    let edit: CursorEditEvent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(edit.fileName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(edit.directoryHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Compact closed-notch indicator for pending Claude approvals.
struct AgentsLiveActivity: View {
    @StateObject private var agents = AgentsStateViewModel.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            Text(agents.pendingPromptCount == 1 ? "1 agent approval" : "\(agents.pendingPromptCount) agent approvals")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
    }
}
