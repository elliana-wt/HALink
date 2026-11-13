import AppKit
import SwiftUI

enum MenuBarLayout {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 24
}

final class MenuBarController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let showSettings: (SettingsPage) -> Void
    private let item: NSStatusItem
    private var panel: MenuBarPanel?
    private var preferredHeight: CGFloat = 240
    private lazy var controller = makeWindowController()

    init(model: AppModel, showSettings: @escaping (SettingsPage) -> Void) {
        self.model = model
        self.showSettings = showSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let icon = NSImage(systemSymbolName: "house", accessibilityDescription: "HALink")
        icon?.isTemplate = true
        item.button?.image = icon
        item.button?.toolTip = "HALink"
        item.button?.target = self
        item.button?.action = #selector(toggleWindow)
    }

    func closeWindow() {
        panel?.orderOut(nil)
        item.button?.highlight(false)
    }

    @objc private func toggleWindow() {
        guard let window = controller.window else { return }
        if window.isVisible { closeWindow(); return }
        window.contentView?.layoutSubtreeIfNeeded()
        positionWindow()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        item.button?.highlight(true)
        Task { await model.refresh() }
    }

    func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.panel?.isKeyWindow == false else { return }
            self.closeWindow()
        }
    }

    private func makeWindowController() -> NSWindowController {
        let host = NSHostingController(rootView: MenuBarView(
            model: model,
            showSettings: { [weak self] page in
                guard let self else { return }
                self.closeWindow()
                self.showSettings(page)
            },
            contentHeightChanged: { [weak self] height in
                guard let self, height > 0 else { return }
                self.preferredHeight = ceil(height)
                self.positionWindow()
            }
        ))
        host.sceneBridgingOptions = .all
        host.sizingOptions = []
        host.view.wantsLayer = true
        host.view.layer?.cornerRadius = MenuBarLayout.cornerRadius
        host.view.layer?.cornerCurve = .continuous
        host.view.layer?.masksToBounds = true
        let panel = MenuBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: preferredHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        self.panel = panel
        panel.contentViewController = host
        panel.title = "HALink"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        panel.tabbingMode = .disallowed
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closeWindow() }
        return NSWindowController(window: panel)
    }

    private func positionWindow() {
        guard let button = item.button, let anchorWindow = button.window,
              let visible = (anchorWindow.screen ?? NSScreen.main)?.visibleFrame,
              let window = panel else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let margin: CGFloat = 8
        let width = MenuBarLayout.width
        let x = min(max(anchor.midX - width / 2, visible.minX + margin), max(visible.minX + margin, visible.maxX - width - margin))
        let top = min(anchor.minY - 6, visible.maxY - margin)
        let height = min(preferredHeight, max(1, top - visible.minY - margin), 660)
        let frame = NSRect(x: x, y: top - height, width: width, height: height)
        if window.frame != frame { window.setFrame(frame, display: window.isVisible) }
    }
}

private final class MenuBarPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
