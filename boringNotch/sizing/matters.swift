//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)
let bluetoothNotificationSideWidth: CGFloat = 182
let closedTimeActivityCompactTextWidth: CGFloat = 52
let closedTimeActivityMinimumTextWidth: CGFloat = 64
let closedActivityFullPresentationContentLeadingPadding: CGFloat = 8
let collapsedNotchContentWidth: CGFloat = 64

/// Keep a compact, stable footprint around the hardware cutout. Wider
/// activities use their minimal content rather than expanding the resting shell.
func collapsedNotchShellWidth(
    centerWidth: CGFloat,
    accessorySize: CGFloat,
    showsBluetoothNotification: Bool = false
) -> CGFloat {
    if showsBluetoothNotification {
        return centerWidth + 2 * bluetoothNotificationSideWidth + 2 * cornerRadiusInsets.closed.bottom
    }
    return centerWidth + closedActivityFullPresentationAdditionalWidth(
        contentWidth: collapsedNotchContentWidth,
        accessorySize: accessorySize
    )
}

/// Content must stay outside the hardware cutout, with eight points of clearance.
func protectedNotchCenterWidth(closedWidth: CGFloat, hardwareWidth: CGFloat?) -> CGFloat {
    max(closedWidth, hardwareWidth.map { $0 + 16 } ?? 0)
}

/// Equal side allocations keep the empty center over the physical notch even
/// when the two activities have different intrinsic widths.
struct NotchSafeZoneLayout: Layout {
    let centerWidth: CGFloat
    var spacing: CGFloat = 0
    var expandsToFit = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let sideProposal = ProposedViewSize(width: nil, height: proposal.height)
        let leading = subviews[0].sizeThatFits(sideProposal)
        let trailing = subviews[2].sizeThatFits(sideProposal)
        let width = 2 * max(leading.width, trailing.width) + centerWidth + 2 * spacing
        return CGSize(
            width: expandsToFit ? max(width, proposal.width ?? width) : width,
            height: proposal.height ?? max(leading.height, trailing.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let sideWidth = max(0, (bounds.width - centerWidth) / 2 - spacing)
        let sideProposal = ProposedViewSize(width: sideWidth, height: bounds.height)
        subviews[0].place(
            at: CGPoint(x: bounds.midX - centerWidth / 2 - spacing, y: bounds.midY),
            anchor: .trailing, proposal: sideProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center, proposal: ProposedViewSize(width: centerWidth, height: bounds.height)
        )
        subviews[2].place(
            at: CGPoint(x: bounds.midX + centerWidth / 2 + spacing, y: bounds.midY),
            anchor: .leading, proposal: sideProposal
        )
    }
}

func closedActivityNotchEdgeSpacing(accessorySize: CGFloat) -> CGFloat {
    min(4, max(0, accessorySize / 5))
}

func closedActivityFullPresentationSideWidth(
    contentWidth: CGFloat,
    accessorySize: CGFloat
) -> CGFloat {
    max(accessorySize, contentWidth + closedActivityFullPresentationContentLeadingPadding)
}

func closedActivityFullPresentationAdditionalWidth(
    contentWidth: CGFloat,
    accessorySize: CGFloat
) -> CGFloat {
    let sideWidth = closedActivityFullPresentationSideWidth(
        contentWidth: contentWidth,
        accessorySize: accessorySize
    )

    return (sideWidth * 2)
        + (2 * closedActivityNotchEdgeSpacing(accessorySize: accessorySize))
        + 2 * cornerRadiusInsets.closed.bottom
}

let floatingTabBarHeight: CGFloat = 48
let floatingTabBarGap: CGFloat = 8
let shadowPadding: CGFloat = 20
let openNotchSize: CGSize = .init(width: 640, height: 190)
let calendarOpenNotchHeight: CGFloat = openNotchSize.height + 20
let maximumOpenNotchHeight: CGFloat = 320
let windowSize: CGSize = .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

func clampedOpenNotchHeight(_ height: CGFloat) -> CGFloat {
    min(max(height, openNotchSize.height), maximumOpenNotchHeight)
}

func notchWindowHeight(for notchHeight: CGFloat) -> CGFloat {
    max(openNotchSize.height, clampedOpenNotchHeight(notchHeight)) + shadowPadding
}

func topAnchoredNotchWindowFrame(_ currentFrame: CGRect, height: CGFloat, screenFrame: CGRect?) -> CGRect {
    var frame = currentFrame
    let top = screenFrame?.maxY ?? currentFrame.maxY
    frame.size.height = height
    frame.origin.y = top - height
    return frame
}

struct OpenNotchHeightPreferenceKey: PreferenceKey {
    static let defaultValue = openNotchSize.height

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func preferredOpenNotchHeight(_ height: CGFloat) -> some View {
        preference(
            key: OpenNotchHeightPreferenceKey.self,
            value: clampedOpenNotchHeight(height)
        )
    }
}

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
