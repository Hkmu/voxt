import SwiftUI
import AppKit

enum SettingsUIStyle {
    static let windowCornerRadius: CGFloat = 22
    static let panelCornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 10

    static var controlFillNSColor: NSColor {
        dynamicColor(light: NSColor.controlBackgroundColor, dark: NSColor(calibratedWhite: 0.185, alpha: 1))
    }

    static var controlFillColor: Color {
        Color(nsColor: controlFillNSColor)
    }

    static var groupedFillNSColor: NSColor {
        dynamicColor(light: NSColor.windowBackgroundColor, dark: NSColor(calibratedWhite: 0.15, alpha: 1))
    }

    static var groupedFillColor: Color {
        Color(nsColor: groupedFillNSColor)
    }

    static var subtleFillNSColor: NSColor {
        dynamicColor(light: NSColor.controlBackgroundColor, dark: NSColor(calibratedWhite: 0.20, alpha: 1))
    }

    static var subtleFillColor: Color {
        Color(nsColor: subtleFillNSColor)
    }

    static var subtleBorderNSColor: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.white.withAlphaComponent(0.10)
        )
    }

    static var subtleBorderColor: Color {
        Color(nsColor: subtleBorderNSColor)
    }

    static var panelBorderNSColor: NSColor {
        dynamicColor(
            light: NSColor.black.withAlphaComponent(0.06),
            dark: NSColor.white.withAlphaComponent(0.07)
        )
    }

    static var panelBorderColor: Color {
        Color(nsColor: panelBorderNSColor)
    }

    static var primaryButtonFillColor: Color {
        Color(nsColor: dynamicColor(
            light: NSColor.black.withAlphaComponent(0.92),
            dark: NSColor(calibratedWhite: 0.30, alpha: 1)
        ))
    }

    static var primaryButtonPressedFillColor: Color {
        Color(nsColor: dynamicColor(
            light: NSColor.black.withAlphaComponent(0.86),
            dark: NSColor(calibratedWhite: 0.36, alpha: 1)
        ))
    }

    static func resolvedSelectWidth(_ width: CGFloat) -> CGFloat {
        max(width - 16, 120)
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return dark
            default:
                return light
            }
        }
    }
}

struct SettingsPanelSurface: ViewModifier {
    var cornerRadius: CGFloat = SettingsUIStyle.panelCornerRadius
    var fillOpacity: CGFloat = 0.76
    var backgroundColor: Color = Color(nsColor: .windowBackgroundColor)

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(SettingsUIStyle.panelBorderColor, lineWidth: 1)
            )
    }
}

struct SettingsPanelGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCardSurface()
    }
}

struct SettingsSidebarSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(
                SettingsPanelSurface(
                    cornerRadius: SettingsUIStyle.panelCornerRadius,
                    fillOpacity: 0.74,
                    backgroundColor: Color(nsColor: .windowBackgroundColor)
                )
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
    }
}

struct SettingsFieldSurfaceModifier: ViewModifier {
    var width: CGFloat?
    var minHeight: CGFloat = 32
    var horizontalPadding: CGFloat = 10
    var alignment: Alignment = .leading

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .fill(SettingsUIStyle.controlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
    }
}

struct SettingsPromptEditorModifier: ViewModifier {
    var height: CGFloat
    var contentPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .frame(height: height)
            .scrollContentBackground(.hidden)
            .padding(contentPadding)
            .modifier(
                SettingsPanelSurface(
                    cornerRadius: SettingsUIStyle.compactCornerRadius,
                    fillOpacity: 1,
                    backgroundColor: SettingsUIStyle.controlFillColor
                )
            )
    }
}

extension View {
    func settingsPanelSurface(
        cornerRadius: CGFloat = SettingsUIStyle.panelCornerRadius,
        fillOpacity: CGFloat = 0.76
    ) -> some View {
        modifier(SettingsPanelSurface(cornerRadius: cornerRadius, fillOpacity: fillOpacity))
    }

    func settingsCardSurface(
        cornerRadius: CGFloat = SettingsUIStyle.panelCornerRadius,
        fillOpacity: CGFloat = 0.92
    ) -> some View {
        modifier(
            SettingsPanelSurface(
                cornerRadius: cornerRadius,
                fillOpacity: fillOpacity,
                backgroundColor: SettingsUIStyle.controlFillColor
            )
        )
    }

    func settingsSidebarSurface() -> some View {
        modifier(SettingsSidebarSurface())
    }

    func settingsFieldSurface(
        width: CGFloat? = nil,
        minHeight: CGFloat = 32,
        horizontalPadding: CGFloat = 10,
        alignment: Alignment = .leading
    ) -> some View {
        modifier(
            SettingsFieldSurfaceModifier(
                width: width,
                minHeight: minHeight,
                horizontalPadding: horizontalPadding,
                alignment: alignment
            )
        )
    }

    func settingsPromptEditor(height: CGFloat, contentPadding: CGFloat = 8) -> some View {
        modifier(SettingsPromptEditorModifier(height: height, contentPadding: contentPadding))
    }
}
