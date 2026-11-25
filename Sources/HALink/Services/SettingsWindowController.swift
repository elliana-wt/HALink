import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let fixedContentSize = NSSize(width: 800, height: 650)
    private var awaitingActivation = false
    private let navigation: SettingsNavigation
    init(model: AppModel) {
        navigation = SettingsNavigation(selection: model.address.isEmpty ? .settings : .devices)
        let host = NSHostingController(rootView: SettingsRootView(model: model, navigation: navigation))
        host.sceneBridgingOptions = .all
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.fixedContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = host
        window.title = "HALink"
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.contentMinSize = Self.fixedContentSize
        window.contentMaxSize = Self.fixedContentSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        let restoredFrame = window.setFrameUsingName("HALink.Settings")
        window.setContentSize(Self.fixedContentSize)
        if !restoredFrame { window.center() }
        window.setFrameAutosaveName("HALink.Settings")
        super.init(window: window)
        window.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: NSApplication.didBecomeActiveNotification, object: NSApp)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    func present(page: SettingsPage? = nil) {
        if let page { navigation.selection = page }
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeMain(); window?.makeKeyAndOrderFront(nil)
        awaitingActivation = !NSApp.isActive
        NSApp.activate()
    }
    @objc private func becameActive() {
        guard awaitingActivation, window?.isVisible == true else { return }
        awaitingActivation = false
        window?.makeMain(); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        awaitingActivation = false
        NSApp.setActivationPolicy(.accessory)
    }
}
