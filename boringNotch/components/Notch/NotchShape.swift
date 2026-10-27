//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import AppKit
import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

/// One shared surface for every expanded destination. Content stays transparent
/// so the preference changes the whole panel rather than just its outer border.
struct NotchPanelBackground<PanelShape: Shape>: View {
    let shape: PanelShape
    let style: NotchSurfaceStyle
    let isOpen: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if style.usesGlass(isOpen: isOpen, reduceTransparency: reduceTransparency) {
            glassSurface
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black.opacity(0.9), location: 0.34),
                        .init(color: .black.opacity(0.64), location: 0.6),
                        .init(color: .black.opacity(contrast == .increased ? 0.74 : 0.38), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .overlay {
                    shape.stroke(.white.opacity(contrast == .increased ? 0.3 : 0.13), lineWidth: 0.75)
                        .mask(LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private var glassSurface: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear.tint(.black.opacity(0.12)), in: shape)
        } else {
            NotchBackdropMaterial()
        }
    }
}

/// Behind-window blending samples the desktop instead of the panel's own views
/// on systems that predate the native Liquid Glass API.
private struct NotchBackdropMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
