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

private let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Calendar", icon: "calendar", view: .calendar),
    TabModel(label: "Activities", icon: "timer", view: .activities),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

func visibleNotchViews(showCalendar: Bool, includesShelf: Bool) -> [NotchViews] {
    var views: [NotchViews] = [.home]
    if showCalendar {
        views.append(.calendar)
    }
    views.append(.activities)
    if includesShelf {
        views.append(.shelf)
    }
    return views
}

func resolvedNotchView(
    _ currentView: NotchViews,
    showCalendar: Bool,
    includesShelf: Bool
) -> NotchViews {
    visibleNotchViews(showCalendar: showCalendar, includesShelf: includesShelf)
        .contains(currentView) ? currentView : .home
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.showCalendar) private var showCalendar
    @Default(.boringShelf) private var boringShelf
    @Default(.tintedTabIcons) private var tintedTabIcons
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
                    .foregroundStyle(iconColor(for: tab.view))
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
        visibleNotchViews(showCalendar: showCalendar, includesShelf: boringShelf)
            .compactMap { view in tabs.first { $0.view == view } }
    }

    private func iconColor(for view: NotchViews) -> Color {
        guard view == coordinator.currentView else { return .gray }
        return tintedTabIcons ? view.tabTintColor : .white
    }
}

struct NotchPaginationDots: View {
    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) private var boringShelf
    @Default(.showCalendar) private var showCalendar

    private var pages: [NotchViews] {
        visibleNotchViews(showCalendar: showCalendar, includesShelf: boringShelf)
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
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }
}

private extension NotchViews {
    var tabTintColor: Color {
        switch self {
        case .home, .shelf: return .blue
        case .calendar: return .red
        case .activities: return .orange
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .home: return "Home page"
        case .calendar: return "Calendar page"
        case .activities: return "Activities page"
        case .shelf: return "Shelf page"
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
