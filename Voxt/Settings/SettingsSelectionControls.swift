import AppKit
import SwiftUI

struct SettingsMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: AnyHashable { AnyHashable(value) }
}

struct SettingsMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]
    let selectedTitle: String
    let width: CGFloat

    private var resolvedWidth: CGFloat {
        SettingsUIStyle.resolvedSelectWidth(width)
    }

    var body: some View {
        SettingsNativeMenuPicker(
            selection: $selection,
            options: options,
            selectedTitle: selectedTitle,
            preferredWidth: resolvedWidth
        )
        .frame(width: resolvedWidth, height: 34)
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[VerticalAlignment.center]
        }
        .alignmentGuide(.lastTextBaseline) { dimensions in
            dimensions[VerticalAlignment.center]
        }
    }
}

struct SettingsSelectionButton<Label: View>: View {
    let width: CGFloat
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    private var resolvedWidth: CGFloat {
        SettingsUIStyle.resolvedSelectWidth(width)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SettingsSelectLikeButtonStyle())
        .frame(width: resolvedWidth)
    }
}

struct SettingsSelectLikeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .fill(SettingsUIStyle.controlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsUIStyle.controlCornerRadius, style: .continuous)
                    .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct SettingsDialogActionRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .padding(.top, 4)
    }
}

private struct SettingsNativeMenuPicker<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [SettingsMenuOption<Value>]
    let selectedTitle: String
    let preferredWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SettingsMenuHostView {
        let hostView = SettingsMenuHostView()
        hostView.onSelectIndex = { [weak coordinator = context.coordinator] index in
            coordinator?.selectionDidChange(index: index)
        }
        return hostView
    }

    func updateNSView(_ nsView: SettingsMenuHostView, context: Context) {
        context.coordinator.parent = self
        nsView.onSelectIndex = { [weak coordinator = context.coordinator] index in
            coordinator?.selectionDidChange(index: index)
        }
        context.coordinator.update(nsView)
    }

    final class Coordinator: NSObject {
        var parent: SettingsNativeMenuPicker

        init(parent: SettingsNativeMenuPicker) {
            self.parent = parent
        }

        func update(_ hostView: SettingsMenuHostView) {
            let titles = parent.options.map(\.title)
            if let selectedIndex = parent.options.firstIndex(where: { $0.value == parent.selection }) {
                hostView.toolTip = parent.options[selectedIndex].title
                hostView.updateMenu(
                    titles: titles,
                    selectedIndex: selectedIndex,
                    fallbackTitle: parent.options[selectedIndex].title,
                    preferredWidth: parent.preferredWidth
                )
            } else if let firstOption = parent.options.first {
                hostView.toolTip = firstOption.title
                hostView.updateMenu(
                    titles: titles,
                    selectedIndex: 0,
                    fallbackTitle: firstOption.title,
                    preferredWidth: parent.preferredWidth
                )
                if parent.selection != firstOption.value {
                    DispatchQueue.main.async {
                        self.parent.selection = firstOption.value
                    }
                }
            } else {
                hostView.toolTip = parent.selectedTitle
                hostView.updateMenu(
                    titles: [],
                    selectedIndex: nil,
                    fallbackTitle: parent.selectedTitle,
                    preferredWidth: parent.preferredWidth
                )
            }
        }

        func selectionDidChange(index: Int) {
            guard parent.options.indices.contains(index) else { return }
            let selectedValue = parent.options[index].value
            if parent.selection != selectedValue {
                parent.selection = selectedValue
            }
        }
    }
}

private final class SettingsMenuHostView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let indicatorView = NSImageView()
    private let popupMenu = NSMenu()
    private var selectedIndex: Int?
    private var currentMenuWidth: CGFloat = 0
    var onSelectIndex: ((Int) -> Void)?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        popupMenu.autoenablesItems = false
        popupMenu.showsStateColumn = false

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.image = NSImage(
            systemSymbolName: "chevron.up.chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        indicatorView.contentTintColor = .secondaryLabelColor

        addSubview(titleField)
        addSubview(indicatorView)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: indicatorView.leadingAnchor, constant: -8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            indicatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorView.widthAnchor.constraint(equalToConstant: 14),
            indicatorView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = SettingsUIStyle.controlCornerRadius
        layer?.backgroundColor = SettingsUIStyle.controlFillNSColor.cgColor
        layer?.borderColor = SettingsUIStyle.subtleBorderNSColor.cgColor
        layer?.borderWidth = 1
    }

    func updateMenu(titles: [String], selectedIndex: Int?, fallbackTitle: String, preferredWidth: CGFloat) {
        let menuWidth = max(ceil(preferredWidth), 1)
        let needsRebuild = popupMenu.items.map(\.title) != titles || abs(currentMenuWidth - menuWidth) > 0.5

        if needsRebuild {
            popupMenu.removeAllItems()
            for (index, title) in titles.enumerated() {
                let item = NSMenuItem(title: title, action: #selector(selectMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.view = SettingsPopupMenuItemView(
                    title: title,
                    width: menuWidth,
                    isSelected: index == selectedIndex
                )
                popupMenu.addItem(item)
            }
            currentMenuWidth = menuWidth
        }

        self.selectedIndex = selectedIndex
        for item in popupMenu.items {
            let isSelected = item.tag == selectedIndex
            (item.view as? SettingsPopupMenuItemView)?.update(
                title: item.title,
                width: menuWidth,
                isSelected: isSelected
            )
        }

        popupMenu.minimumWidth = menuWidth
        titleField.stringValue = fallbackTitle
    }

    override func mouseDown(with event: NSEvent) {
        guard !popupMenu.items.isEmpty else { return }
        let selectedItem = selectedIndex.flatMap { index in
            popupMenu.items.first(where: { $0.tag == index })
        }
        _ = popupMenu.popUp(positioning: selectedItem, at: NSPoint(x: 0, y: bounds.height + 8), in: self)
    }

    @objc
    private func selectMenuItem(_ sender: NSMenuItem) {
        onSelectIndex?(sender.tag)
    }
}

private final class SettingsPopupMenuItemView: NSView {
    private let checkView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var itemWidth: CGFloat
    private var isSelected: Bool

    override var isFlipped: Bool {
        true
    }

    init(title: String, width: CGFloat, isSelected: Bool) {
        self.itemWidth = width
        self.isSelected = isSelected
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 34))
        wantsLayer = true

        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.imageScaling = .scaleProportionallyDown

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(checkView)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            checkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 12),
            checkView.heightAnchor.constraint(equalToConstant: 12),
            titleField.leadingAnchor.constraint(equalTo: checkView.trailingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        update(title: title, width: width, isSelected: isSelected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: itemWidth, height: 34)
    }

    override func draw(_ dirtyRect: NSRect) {
        let isHighlighted = enclosingMenuItem?.isHighlighted ?? false
        if isHighlighted {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 6, dy: 2),
                xRadius: 10,
                yRadius: 10
            ).fill()
        }
        super.draw(dirtyRect)
        applyAppearance(isHighlighted: isHighlighted)
    }

    func update(title: String, width: CGFloat, isSelected: Bool) {
        itemWidth = width
        self.isSelected = isSelected
        frame = NSRect(x: 0, y: 0, width: width, height: 34)
        invalidateIntrinsicContentSize()
        titleField.stringValue = title
        needsDisplay = true
    }

    private func applyAppearance(isHighlighted: Bool) {
        let textColor = isHighlighted ? NSColor.white : NSColor.labelColor
        titleField.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        titleField.textColor = textColor
        checkView.image = isSelected
            ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            : nil
        checkView.contentTintColor = textColor
    }
}
