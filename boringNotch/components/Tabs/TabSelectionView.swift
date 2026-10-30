//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
    let tint: Color
}

func visibleNotchViews(
    availableActivityIDs: [ActivityID],
    includesShelf: Bool
) -> [NotchViews] {
    var views: [NotchViews] = [.home]
    views.append(contentsOf: availableActivityIDs.map(NotchViews.activity))
    views.append(.activities)
    if includesShelf {
        views.append(.shelf)
    }
    return views
}

func resolvedNotchView(
    _ currentView: NotchViews,
    availableActivityIDs: [ActivityID],
    includesShelf: Bool
) -> NotchViews {
    visibleNotchViews(
        availableActivityIDs: availableActivityIDs,
        includesShelf: includesShelf
    )
        .contains(currentView) ? currentView : .home
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var activityRegistry = ActivityRegistry.shared
    @Default(.boringShelf) private var boringShelf
    @Default(.tintedTabIcons) private var tintedTabIcons
    var body: some View {
        FloatingTabBar(
            tabs: visibleTabs,
            selection: $coordinator.currentView,
            tintedIcons: tintedTabIcons
        )
    }

    private var visibleTabs: [TabModel] {
        visibleNotchViews(
            availableActivityIDs: activityRegistry.availableActivityIDs,
            includesShelf: boringShelf
        )
        .compactMap { tabModel(for: $0) }
    }

    private func tabModel(for view: NotchViews) -> TabModel? {
        switch view {
        case .home:
            return TabModel(label: String(localized: "Home"), icon: "house.fill", view: view, tint: .blue)
        case .activities:
            return TabModel(label: String(localized: "Activities"), icon: "timer", view: view, tint: .orange)
        case .shelf:
            return TabModel(label: String(localized: "Shelf"), icon: "tray.fill", view: view, tint: .blue)
        case .activity(let id):
            guard let activity = activityRegistry.activity(for: id),
                  activityRegistry.isActivityAvailable(id) else {
                return nil
            }
            return TabModel(
                label: activity.metadata.name,
                icon: activity.metadata.systemImage,
                view: view,
                tint: activity.metadata.tint
            )
        }
    }
}

/// A full-width, camera-safe dock. Keep its scroll state outside the selected
/// destination's identity so changing activities never resets the viewport.
struct FloatingTabBar: View {
    let tabs: [TabModel]
    @Binding var selection: NotchViews
    var tintedIcons = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectionAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.25) }
    private var contentWidth: CGFloat {
        FloatingTabBarMetrics.contentWidth(tabCount: tabs.count, selectedLabel: tabs.first { $0.view == selection }?.label)
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) { dock }
        } else {
            dock
        }
    }

    private var dock: some View {
        GeometryReader { geometry in
            let isOverflowing = contentWidth > geometry.size.width
            let viewportWidth = FloatingTabBarMetrics.viewportWidth(contentWidth: contentWidth, availableWidth: geometry.size.width)
            ScrollViewReader { proxy in
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tabs) { tab in
                                TabButton(
                                    label: tab.label,
                                    icon: tab.icon,
                                    selected: selection == tab.view,
                                    tint: tintedIcons ? tab.tint : .white
                                ) {
                                    withAnimation(selectionAnimation) { selection = tab.view }
                                }
                                .id(tab.view)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(width: viewportWidth, height: floatingTabBarHeight)
                    .scrollDisabled(!isOverflowing)
                    .excludesHorizontalTrackpadNavigation(isOverflowing)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                    if isOverflowing {
                        Menu {
                            ForEach(tabs) { tab in
                                Button {
                                    withAnimation(selectionAnimation) { selection = tab.view }
                                } label: {
                                    if selection == tab.view {
                                        Label(tab.label, systemImage: "checkmark")
                                    } else {
                                        Label(tab.label, systemImage: tab.icon)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .modifier(FloatingTabBubbleSurface(selected: false, tint: .white))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("All tabs")
                        .accessibilityLabel("All tabs")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, value in
                    withAnimation(selectionAnimation) { proxy.scrollTo(value, anchor: .center) }
                }
                .onChange(of: geometry.size.width) { _, _ in
                    proxy.scrollTo(selection, anchor: .center)
                }
                .onChange(of: tabs.map(\.id)) { _, _ in
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
        .frame(height: floatingTabBarHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch tabs")
    }
}

#Preview {
    TabSelectionView().padding(12)
}
