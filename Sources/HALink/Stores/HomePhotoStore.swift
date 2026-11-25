import AppKit
import Observation

@Observable
final class HomePhotoStore {
    enum Appearance: String, Codable, CaseIterable, Identifiable, Sendable {
        case light
        case dark

        var id: String { rawValue }
        var title: String {
            switch self {
            case .light: "浅色壁纸"
            case .dark: "深色壁纸"
            }
        }
        var shortTitle: String {
            switch self {
            case .light: "浅色"
            case .dark: "深色"
            }
        }
        var symbolName: String {
            switch self {
            case .light: "sun.max"
            case .dark: "moon.stars"
            }
        }
    }

    struct Preferences: Codable, Equatable, Sendable {
        var autoSwitchWithSystem = true
        var manualAppearance: Appearance = .light
    }

    struct Asset {
        let id = UUID()
        let image: NSImage
        let backdrop: NSImage
        let detailBackdrop: NSImage
        let theme: HomePhotoProcessor.Theme
        let headerShadeOpacity: Double
    }

    private(set) var light: Asset?
    private(set) var dark: Asset?
    private(set) var preferences = Preferences()
    private(set) var importingAppearances: Set<Appearance> = []

    var image: NSImage? { light?.image ?? dark?.image }
    var backdrop: NSImage? { light?.backdrop ?? dark?.backdrop }
    var theme: HomePhotoProcessor.Theme? { light?.theme ?? dark?.theme }
    var headerShadeOpacity: Double { light?.headerShadeOpacity ?? dark?.headerShadeOpacity ?? 0.55 }
    var isImporting: Bool { !importingAppearances.isEmpty }
    var autoSwitchWithSystem: Bool { preferences.autoSwitchWithSystem }
    var manualAppearance: Appearance { preferences.manualAppearance }

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let preferencesFile: URL
    @ObservationIgnored private(set) var hasLoaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var revisions: [Appearance: Int] = [.light: 0, .dark: 0]

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Hestia")
        self.directory = directory
        self.preferencesFile = directory.appending(path: "home-photo-preferences.json")
        loadPreferences()
    }

    func asset(for appearance: Appearance) -> Asset? {
        switch appearance {
        case .light: light
        case .dark: dark
        }
    }

    func isImporting(_ appearance: Appearance) -> Bool {
        importingAppearances.contains(appearance)
    }

    func activeAsset(isDark: Bool) -> Asset? {
        if preferences.autoSwitchWithSystem {
            return isDark ? (dark ?? light) : (light ?? dark)
        }
        return asset(for: preferences.manualAppearance) ?? light ?? dark
    }

    func loadIfNeeded() async {
        if hasLoaded { return }
        if let loadTask {
            await loadTask.value
            return
        }
        loadPreferences()

        let lightVersion = revisions[.light, default: 0]
        let darkVersion = revisions[.dark, default: 0]
        let lightURL = file(for: .light)
        let darkURL = file(for: .dark)

        let task = Task { @MainActor in
            async let lightPhoto: HomePhotoProcessor.Photo? = {
                guard FileManager.default.fileExists(atPath: lightURL.path) else { return nil }
                return try? await HomePhotoProcessor.prepare(lightURL, includeJPEG: false)
            }()
            async let darkPhoto: HomePhotoProcessor.Photo? = {
                guard FileManager.default.fileExists(atPath: darkURL.path) else { return nil }
                return try? await HomePhotoProcessor.prepare(darkURL, includeJPEG: false)
            }()

            let (loadedLight, loadedDark) = await (lightPhoto, darkPhoto)
            if let loadedLight, self.revisions[.light, default: 0] == lightVersion {
                self.display(loadedLight, for: .light)
            }
            if let loadedDark, self.revisions[.dark, default: 0] == darkVersion {
                self.display(loadedDark, for: .dark)
            }
            self.hasLoaded = true
            self.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    func importPhoto(from url: URL, for appearance: Appearance = .light) async throws {
        guard !importingAppearances.contains(appearance) else { return }
        importingAppearances.insert(appearance)
        defer { importingAppearances.remove(appearance) }
        let photo = try await HomePhotoProcessor.prepare(url)
        let targetFile = file(for: appearance)
        try FileManager.default.createDirectory(at: targetFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try photo.jpeg.write(to: targetFile, options: .atomic)
        hasLoaded = true
        revisions[appearance, default: 0] += 1
        display(photo, for: appearance)
    }

    func removePhoto(for appearance: Appearance = .light) throws {
        let targetFile = file(for: appearance)
        if FileManager.default.fileExists(atPath: targetFile.path) {
            try FileManager.default.removeItem(at: targetFile)
        }
        revisions[appearance, default: 0] += 1
        hasLoaded = true
        setAsset(nil, for: appearance)
    }

    func setAutoSwitchWithSystem(_ enabled: Bool) {
        guard preferences.autoSwitchWithSystem != enabled else { return }
        preferences.autoSwitchWithSystem = enabled
        savePreferences()
    }

    func setManualAppearance(_ appearance: Appearance) {
        guard preferences.manualAppearance != appearance else { return }
        preferences.manualAppearance = appearance
        savePreferences()
    }

    private func file(for appearance: Appearance) -> URL {
        switch appearance {
        case .light: directory.appending(path: "home-photo.jpg")
        case .dark: directory.appending(path: "home-photo-dark.jpg")
        }
    }

    private func display(_ photo: HomePhotoProcessor.Photo, for appearance: Appearance) {
        let asset = Asset(
            image: NSImage(cgImage: photo.image, size: .zero),
            backdrop: NSImage(cgImage: photo.backdrop, size: .zero),
            detailBackdrop: NSImage(cgImage: photo.detailBackdrop, size: NSSize(width: 460, height: 760)),
            theme: photo.theme,
            headerShadeOpacity: photo.headerShadeOpacity
        )
        setAsset(asset, for: appearance)
    }

    private func setAsset(_ asset: Asset?, for appearance: Appearance) {
        switch appearance {
        case .light: light = asset
        case .dark: dark = asset
        }
    }

    private func loadPreferences() {
        guard FileManager.default.fileExists(atPath: preferencesFile.path),
              let data = try? Data(contentsOf: preferencesFile),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else { return }
        preferences = decoded
    }

    private func savePreferences() {
        try? FileManager.default.createDirectory(at: preferencesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(preferences) {
            try? data.write(to: preferencesFile, options: .atomic)
        }
    }
}
