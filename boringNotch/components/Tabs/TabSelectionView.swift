//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Activities", icon: "timer", view: .activities),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }

    private var visibleTabs: [TabModel] {
        tabs.filter { $0.view != .shelf || Defaults[.boringShelf] }
    }
}

struct NotchPaginationDots: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) private var boringShelf

    private var pages: [NotchViews] {
        boringShelf ? [.home, .activities, .shelf] : [.home, .activities]
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(pages, id: \.self) { page in
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        coordinator.currentView = page
                    }
                } label: {
                    Circle()
                        .fill(page == coordinator.currentView ? Color.white : Color.gray.opacity(0.45))
                        .frame(width: page == coordinator.currentView ? 6 : 5, height: page == coordinator.currentView ? 6 : 5)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.accessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension NotchViews {
    var accessibilityLabel: String {
        switch self {
        case .home: return "Home page"
        case .activities: return "Activities page"
        case .shelf: return "Shelf page"
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
