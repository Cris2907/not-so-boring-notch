import Defaults
import SwiftUI
import AppKit

private let quickNotesOpenNotchHeightPadding: CGFloat = 26
private let quickNotesEditorMinimumLineCount = 3
private let quickNotesExpandedBottomMargin: CGFloat = 20

struct QuickNotesActivityView: View {
    @ObservedObject var manager: QuickNotesManager
    @State private var editorTextHeight: CGFloat = 54
    @State private var limitShakeTrigger = 0

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
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .disabled(manager.note.isEmpty)
                .help("Clear note")
                .accessibilityLabel("Clear note")
            }

            ZStack(alignment: .bottomLeading) {
                QuickNotesGrowingTextView(
                    text: noteBinding,
                    textHeight: $editorTextHeight,
                    onLimitExceeded: triggerLimitShake
                )
                    .frame(height: editorTextHeight)
                    .padding(.horizontal, 10)
                    .padding(.top, 9)
                    .padding(.bottom, 26)
                    .accessibilityLabel("Quick note")

                if manager.note.isEmpty {
                    Text("Write a quick note…")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                Text("\(manager.note.count)/\(QuickNotesManager.maximumCharacterCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(characterCounterColor)
                    .padding(.leading, 10)
                    .padding(.bottom, 7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            .modifier(QuickNotesLimitShakeEffect(trigger: limitShakeTrigger))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .padding(.bottom, quickNotesExpandedBottomMargin)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: OpenNotchHeightPreferenceKey.self,
                    value: clampedOpenNotchHeight(proxy.size.height + quickNotesOpenNotchHeightPadding)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { manager.note },
            set: manager.updateNote
        )
    }

    private var characterCounterColor: Color {
        let remainingCharacters = QuickNotesManager.maximumCharacterCount - manager.note.count
        switch remainingCharacters {
        case ...0:
            return .red
        case 1...20:
            return .orange
        default:
            return .secondary
        }
    }

    private func triggerLimitShake() {
        withAnimation(.linear(duration: 0.28)) {
            limitShakeTrigger += 1
        }
    }
}

private struct QuickNotesLimitShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    init(trigger: Int) {
        animatableData = CGFloat(trigger)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: sin(animatableData * .pi * 6) * 4,
                y: 0
            )
        )
    }
}

private struct QuickNotesGrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    let onLimitExceeded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> LimitedGrowingTextView {
        let textView = LimitedGrowingTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.string = text
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateNSView(_ textView: LimitedGrowingTextView, context: Context) {
        context.coordinator.parent = self
        textView.font = NSFont.systemFont(ofSize: 14)

        if textView.string != text {
            textView.string = text
        }

        context.coordinator.updateHeight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickNotesGrowingTextView

        init(_ parent: QuickNotesGrowingTextView) {
            self.parent = parent
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let replacement = replacementString ?? ""
            let proposedValue = (textView.string as NSString).replacingCharacters(
                in: affectedCharRange,
                with: replacement
            )
            let limitedValue = QuickNotesManager.limitedNote(proposedValue)

            guard limitedValue != proposedValue else { return true }

            textView.string = limitedValue
            parent.text = limitedValue
            parent.onLimitExceeded()
            textView.setSelectedRange(
                NSRange(
                    location: min(
                        (limitedValue as NSString).length,
                        affectedCharRange.location + (replacement as NSString).length
                    ),
                    length: 0
                )
            )
            updateHeight(for: textView)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let limitedValue = QuickNotesManager.limitedNote(textView.string)

            if textView.string != limitedValue {
                textView.string = limitedValue
                parent.onLimitExceeded()
            }

            parent.text = limitedValue
            updateHeight(for: textView)
        }

        func updateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            let width = max(1, textView.bounds.width)
            textContainer.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)

            let font = textView.font ?? NSFont.systemFont(ofSize: 14)
            let minimumHeight = font.ascender - font.descender + font.leading
            let targetHeight = ceil(max(
                minimumHeight * CGFloat(quickNotesEditorMinimumLineCount),
                layoutManager.usedRect(for: textContainer).height
            ))

            guard abs(parent.textHeight - targetHeight) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.textHeight = targetHeight
            }
        }
    }

    final class LimitedGrowingTextView: NSTextView {
        override func keyDown(with event: NSEvent) {
            if Self.isReturnKey(event) {
                guard event.modifierFlags.contains(.shift) else { return }
                insertText("\n", replacementRange: selectedRange())
                return
            }

            super.keyDown(with: event)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            textContainer?.containerSize = CGSize(width: max(1, newSize.width), height: .greatestFiniteMagnitude)
            invalidateIntrinsicContentSize()
        }

        private static func isReturnKey(_ event: NSEvent) -> Bool {
            event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == "\r"
        }
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
