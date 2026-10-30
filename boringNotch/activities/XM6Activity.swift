import Combine
import SwiftUI

extension ActivityID {
    static let xm6 = ActivityID("builtin.xm6")
}

@MainActor
final class XM6Activity: NotchActivity {
    static let activityID = ActivityID.xm6
    let id = activityID
    let metadata = ActivityMetadata(
        name: String(localized: "XM6"),
        systemImage: "headphones",
        tint: .white,
        preferredExpandedHeight: 388,
        summary: String(localized: "Control your Sony WH-1000XM6 headphones.")
    )
    let livePresentationSizing = LiveActivityPresentationSizing(
        fullContentWidth: .fixed(108), minimalContentWidth: .fixed(44)
    )
    private let manager: XM6Manager
    private var observation: AnyCancellable?

    init(manager: XM6Manager? = nil) {
        self.manager = manager ?? .shared
        observation = self.manager.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var isActive: Bool { manager.isConnected }
    var livePresentationState: ActivityLivePresentationState {
        manager.isConnected ? .visible(priority: .normal) : .hidden
    }
    var supportsConfiguration: Bool { true }

    func makeExpandedView() -> some View { XM6ActivityView(manager: manager) }
    func makeLivePresentationView() -> some View { XM6ChinView(manager: manager, minimal: false) }
    func makeMinimalLivePresentationView() -> some View { XM6ChinView(manager: manager, minimal: true) }
    func makeConfigurationView() -> some View { XM6SettingsView(manager: manager) }
}
