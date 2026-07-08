import SwiftUI

@MainActor
final class ExampleActivity: NotchActivity {
    static let activityID = ActivityID("example")

    let id = activityID
    let metadata = ActivityMetadata(
        name: "Example",
        systemImage: "sparkles",
        tint: .blue
    )

    @Published var isAvailable = true
    @Published var isActive = false

    var supportsCompactPresentation: Bool { true }

    func makeExpandedView() -> some View {
        VStack(spacing: 8) {
            Image(systemName: metadata.systemImage)
                .font(.title)
                .foregroundStyle(metadata.tint)
            Text("Example Activity")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func makeCompactView() -> some View {
        Image(systemName: metadata.systemImage)
            .foregroundStyle(metadata.tint)
            .accessibilityLabel("Example Activity")
    }
}
