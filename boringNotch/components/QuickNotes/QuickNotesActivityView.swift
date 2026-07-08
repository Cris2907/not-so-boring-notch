import Defaults
import SwiftUI

struct QuickNotesActivityView: View {
    @ObservedObject var manager: QuickNotesManager
    @FocusState private var editorIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Notes")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Changes are saved automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive, action: manager.clear) {
                    Label("Clear note", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(manager.note.isEmpty)
                .help("Clear note")
            }

            ZStack(alignment: .topLeading) {
                if manager.note.isEmpty {
                    Text("Write a quick note…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextEditor(text: noteBinding)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .focused($editorIsFocused)
                    .accessibilityLabel("Quick note")
            }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .onAppear { editorIsFocused = true }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { manager.note },
            set: manager.updateNote
        )
    }
}

struct QuickNotesLivePresentationView: View {
    @ObservedObject var manager: QuickNotesManager
    @Default(.quickNotesShowContentInLivePreview) private var showsContent

    var body: some View {
        Text(displayedText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.orange)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel(accessibilityText)
    }

    private var displayedText: String {
        showsContent
            ? manager.singleLinePreview()
            : String(localized: "Note saved")
    }

    private var accessibilityText: String {
        showsContent
            ? String(localized: "Quick Note: \(manager.singleLinePreview())")
            : String(localized: "Quick Note saved; content hidden")
    }
}

struct QuickNotesMinimalLivePresentationView: View {
    @ObservedObject var manager: QuickNotesManager

    var body: some View {
        if manager.hasMeaningfulContent {
            Text("Saved")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .accessibilityLabel("Quick Note saved")
        }
    }
}

struct QuickNotesSettingsView: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .quickNotesShowContentInLivePreview) {
                    Text("Show note content when the notch is closed")
                }
            } header: {
                Text("Closed notch")
            } footer: {
                Text("This change takes effect immediately. When off, the full presentation shows only that a note is saved. The minimal presentation never displays note content.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Quick Notes")
    }
}
