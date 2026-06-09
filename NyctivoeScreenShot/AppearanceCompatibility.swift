//
//  AppearanceCompatibility.swift
//  NyctivoeScreenShot
//

import SwiftUI

extension View {
    @ViewBuilder
    func nyctivoeGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func nyctivoeGlassBackgroundEffect<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func nyctivoeGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    func nyctivoeWindowBackground() -> some View {
        if #available(macOS 26.0, *) {
            containerBackground(WindowBackgroundShapeStyle(), for: .window)
        } else {
            self
        }
    }
}
