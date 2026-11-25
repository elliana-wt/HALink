import AppKit
import Observation
import QuartzCore
import SwiftUI

enum MenuBarLayout {
    static let width: CGFloat = 460
    static let cornerRadius: CGFloat = 24
    static let horizontalPadding: CGFloat = 16

    enum PanelShadowInsets {
        static let leading: CGFloat = 32
        static let trailing: CGFloat = 32
        static let top: CGFloat = 16
        static let bottom: CGFloat = 44
        static var horizontal: CGFloat { leading + trailing }
        static var vertical: CGFloat { top + bottom }
    }
    static let maxVisibleSceneCards = 4
    static let sceneCardSpacing: CGFloat = 10
    static var sceneCardWidth: CGFloat {
        let availableWidth = width - horizontalPadding * 2
        return (availableWidth - sceneCardSpacing * CGFloat(maxVisibleSceneCards - 1)) / CGFloat(maxVisibleSceneCards)
    }
    static let maxUnscrolledControlRowsWithHomePhoto = 4
    static let maxUnscrolledControlRowsWithoutHomePhoto = 8
    static let controlRowSpacing: CGFloat = 12

    static func maxUnscrolledControlRows(usesHomePhoto: Bool) -> Int {
        usesHomePhoto ? maxUnscrolledControlRowsWithHomePhoto : maxUnscrolledControlRowsWithoutHomePhoto
    }

    static func preferredHeight(
        contentHeight: CGFloat,
        overflowHeight: CGFloat,
        rowSpacing: CGFloat = controlRowSpacing
    ) -> CGFloat {
        guard contentHeight > 0 else { return 0 }
        guard overflowHeight > 0 else { return ceil(contentHeight) }
        return ceil(max(1, contentHeight - overflowHeight - rowSpacing))
    }

    static func listPreferredHeight(
        chromeHeight: CGFloat,
        deviceContentHeight: CGFloat,
        overflowHeight: CGFloat,
        rowSpacing: CGFloat = controlRowSpacing
    ) -> CGFloat {
        guard chromeHeight > 0 else { return 0 }
        let deviceHeight = preferredHeight(
            contentHeight: deviceContentHeight,
            overflowHeight: overflowHeight,
            rowSpacing: rowSpacing
        )
        return ceil(chromeHeight + deviceHeight)
    }

    static func deviceViewportHeight(panelHeight: CGFloat, chromeHeight: CGFloat) -> CGFloat {
        max(0, panelHeight - chromeHeight)
    }

    static func panelHeight(preferredHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(preferredHeight, max(1, availableHeight))
    }

    static func needsScroll(contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        viewportHeight > 0 && contentHeight > viewportHeight + 1
    }

    struct ScrollEdgeFade: Equatable {
        var top: Double = 0
        var bottom: Double = 0

        static let fadeLength: CGFloat = 26

        static func calculate(
            contentOffsetY: CGFloat,
            contentHeight: CGFloat,
            viewportHeight: CGFloat,
            topInset: CGFloat = 0,
            bottomInset: CGFloat = 0,
            fadeLength: CGFloat = Self.fadeLength
        ) -> Self {
            let totalContentHeight = contentHeight + topInset + bottomInset
            guard viewportHeight > 0, totalContentHeight > viewportHeight + 1, fadeLength > 0 else {
                return .init()
            }
            let maxScrollOffset = totalContentHeight - viewportHeight
            let scrolledFromTop = max(0, contentOffsetY + topInset)
            let remainingBottom = max(0, maxScrollOffset - scrolledFromTop)
            return .init(
                top: min(1, Double(scrolledFromTop / fadeLength)),
                bottom: min(1, Double(remainingBottom / fadeLength))
            )
        }
    }
}

@Observable
final class MenuBarPanelState {
    var animatedHeight: CGFloat
    var targetHeight: CGFloat
    var isAnimatingHeight = false

    init(height: CGFloat = 240) {
        self.animatedHeight = height
        self.targetHeight = height
    }
}

final class MenuBarController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let showSettings: (SettingsPage) -> Void
    private let item: NSStatusItem
    private let panelState = MenuBarPanelState(height: 240)
    private var panel: MenuBarPanel?
    private var preferredHeight: CGFloat = 240
    private var containerCardHeight: CGFloat = 240
    private var targetCardFrame: NSRect?
    private var animationDoneTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
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

    func prepareWindow() {
        guard let window = controller.window, !window.isVisible else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        positionWindow(animated: false)
    }

    func closeWindow() {
        openTask?.cancel()
        openTask = nil
        animationDoneTask?.cancel()
        animationDoneTask = nil
        panelState.isAnimatingHeight = false
        panel?.orderOut(nil)
        item.button?.highlight(false)
    }

    @objc private func toggleWindow() {
        if openTask != nil {
            closeWindow()
            return
        }
        if panel?.isVisible == true {
            closeWindow()
            return
        }
        if !model.homePhoto.hasLoaded || panel == nil {
            item.button?.highlight(true)
            openTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.model.homePhoto.loadIfNeeded()
                guard !Task.isCancelled else { return }
                self.prepareWindow()
                await Task.yield()
                guard !Task.isCancelled else { return }
                self.openTask = nil
                self.presentWindow()
            }
            return
        }
        presentWindow()
    }

    private func presentWindow() {
        guard let window = controller.window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        positionWindow(animated: false)
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
            panelState: panelState,
            usesExternalShadowPadding: true,
            showSettings: { [weak self] page in
                guard let self else { return }
                self.closeWindow()
                self.showSettings(page)
            },
            contentHeightChanged: { [weak self] height in
                guard let self, height > 0 else { return }
                self.preferredHeight = ceil(height)
                self.positionWindow(animated: self.panel?.isVisible == true)
            },
            closePanel: { [weak self] in self?.closeWindow() }
        ))
        host.sceneBridgingOptions = .all
        host.sizingOptions = []
        let initialCardRect = NSRect(x: 0, y: 0, width: MenuBarLayout.width, height: preferredHeight)
        let panel = MenuBarPanel(
            contentRect: panelFrame(forCardRect: initialCardRect),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        self.panel = panel
        panel.contentViewController = host
        panel.title = "HALink"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
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
        panel.visibleCardRect = { [weak self, weak panel] in
            guard let self, let panel else { return .zero }
            let cardHeight = self.panelState.targetHeight
            return NSRect(
                x: MenuBarLayout.PanelShadowInsets.leading,
                y: panel.frame.height - MenuBarLayout.PanelShadowInsets.top - cardHeight,
                width: MenuBarLayout.width,
                height: cardHeight
            )
        }
        return NSWindowController(window: panel)
    }

    private func panelFrame(forCardRect cardRect: NSRect) -> NSRect {
        NSRect(
            x: cardRect.minX - MenuBarLayout.PanelShadowInsets.leading,
            y: cardRect.minY - MenuBarLayout.PanelShadowInsets.bottom,
            width: cardRect.width + MenuBarLayout.PanelShadowInsets.horizontal,
            height: cardRect.height + MenuBarLayout.PanelShadowInsets.vertical
        )
    }

    private func setWindowFrameWithoutAnimation(_ window: NSWindow, frame: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(frame, display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    private func positionWindow(animated: Bool = false) {
        guard let button = item.button, let anchorWindow = button.window,
              let visible = (anchorWindow.screen ?? NSScreen.main)?.visibleFrame,
              let window = panel else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let margin: CGFloat = 8
        let width = MenuBarLayout.width
        let x = min(max(anchor.midX - width / 2, visible.minX + margin), max(visible.minX + margin, visible.maxX - width - margin))
        let top = min(anchor.minY - 6, visible.maxY - margin)
        let height = MenuBarLayout.panelHeight(preferredHeight: preferredHeight, availableHeight: top - visible.minY - margin)
        let cardFrame = NSRect(x: x, y: top - height, width: width, height: height)
        let targetPanelFrame = panelFrame(forCardRect: cardFrame)

        guard targetCardFrame != cardFrame || (!animated && (window.frame != targetPanelFrame || panelState.animatedHeight != height)) else {
            return
        }
        let previousCardFrame = targetCardFrame
        targetCardFrame = cardFrame
        let sameAnchor = previousCardFrame.map { $0.origin.x == cardFrame.origin.x && $0.maxY == cardFrame.maxY } ?? false

        animationDoneTask?.cancel()
        animationDoneTask = nil

        if animated, window.isVisible, sameAnchor {
            // Keep the NSPanel frame stationary during the GPU-accelerated height transition.
            // If growing, expand the transparent backing window once before animating;
            // if shrinking, trim the transparent backing window once after the animation finishes.
            let neededContainerHeight = max(containerCardHeight, height)
            let expandedPanelFrame = panelFrame(forCardRect: NSRect(
                x: x,
                y: top - neededContainerHeight,
                width: width,
                height: neededContainerHeight
            ))
            if neededContainerHeight != containerCardHeight || window.frame != expandedPanelFrame {
                containerCardHeight = neededContainerHeight
                setWindowFrameWithoutAnimation(window, frame: expandedPanelFrame)
            }
            panelState.targetHeight = height
            panelState.isAnimatingHeight = true
            withAnimation(.easeInOut(duration: 0.25)) {
                panelState.animatedHeight = height
            }
            let finalCardHeight = height
            let finalPanelFrame = targetPanelFrame
            animationDoneTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(270))
                guard let self, !Task.isCancelled else { return }
                self.panelState.isAnimatingHeight = false
                if self.containerCardHeight != finalCardHeight, let window = self.panel {
                    self.containerCardHeight = finalCardHeight
                    self.setWindowFrameWithoutAnimation(window, frame: finalPanelFrame)
                }
            }
        } else {
            containerCardHeight = height
            panelState.targetHeight = height
            panelState.isAnimatingHeight = false
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                panelState.animatedHeight = height
            }
            setWindowFrameWithoutAnimation(window, frame: targetPanelFrame)
        }
    }
}

private final class MenuBarPanel: NSPanel {
    var onCancel: (() -> Void)?
    var visibleCardRect: () -> NSRect = { .zero }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !visibleCardRect().contains(event.locationInWindow) {
                onCancel?()
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}
