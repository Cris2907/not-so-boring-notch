//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import AppKit
import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    var tint: Color = .white
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)
                if selected {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(width: FloatingTabBarMetrics.labelWidth(label))
                }
            }
                .foregroundStyle(selected ? tint : .white.opacity(0.75))
                .padding(.horizontal, selected ? 12 : 0)
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Capsule())
                .modifier(FloatingTabBubbleSurface(selected: selected, tint: tint))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(label)
    }
}

struct FloatingTabBubbleSurface: ViewModifier {
    let selected: Bool
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(selected ? Color(white: 0.3) : Color(white: 0.14), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(selected ? 0.6 : 0.3), lineWidth: 1) }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(
                selected ? .regular.tint(tint.opacity(0.22)).interactive() : .regular.interactive(),
                in: Capsule()
            )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().fill(selected ? tint.opacity(0.15) : .clear) }
                .overlay {
                    Capsule().strokeBorder(.white.opacity(contrast == .increased ? 0.65 : selected ? 0.35 : 0.15), lineWidth: 1)
                }
        }
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}


/// Fixed bubble dimensions make overflow independent of preference propagation
/// through native glass rendering and preserve space for the overflow control.
@MainActor
struct FloatingTabBarMetrics {
    static func labelWidth(_ label: String) -> CGFloat {
        min(100, ceil((label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width))
    }

    static func viewportWidth(contentWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        min(contentWidth, max(0, availableWidth - (contentWidth > availableWidth ? 48 : 0)))
    }

    static func contentWidth(tabCount: Int, selectedLabel: String?) -> CGFloat {
        guard tabCount > 0 else { return 0 }
        let selectedExtra: CGFloat = selectedLabel.map { labelWidth($0) + 11 } ?? 0
        let bubblesWidth: CGFloat = CGFloat(tabCount) * 40
        let gapsWidth: CGFloat = CGFloat(tabCount - 1) * 8
        return bubblesWidth + gapsWidth + 8 + selectedExtra
    }
}
