import AppKit
import HALinkCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var settings = SettingsWindowController(model: model)
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(model: model) { [weak self] page in self?.showSettings(page: page) }
        if ProcessInfo.processInfo.arguments.contains("--check-hotkeys") {
            checkHotkeys()
            return
        }
        showSettings()
        Task {
            await model.homePhoto.loadIfNeeded()
            menuBar?.prepareWindow()
        }
        Task { await model.start() }
    }
    func showSettings(page: SettingsPage? = nil) {
        menuBar?.closeWindow()
        settings.present(page: page)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }

    private func checkHotkeys() {
        let first = HotKeyManager(), second = HotKeyManager()
        let key = HotKey(keyCode: 64, modifiers: 0, label: "F17")
        do {
            try first.register(key, id: UUID())
            do {
                try second.register(key, id: UUID())
                FileHandle.standardError.write(Data("Duplicate F17 registration was incorrectly allowed.\n".utf8))
                exit(1)
            } catch {}
            first.stop()
            try second.register(key, id: UUID())
            second.stop()
            FileHandle.standardOutput.write(Data("F17 registration, conflict detection and release passed.\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("F17 check failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

@main
struct HALinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    init() {
        UserDefaults.standard.set(1, forKey: "AppleAccentColor")
    }
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("设置…") { delegate.showSettings() }.keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
