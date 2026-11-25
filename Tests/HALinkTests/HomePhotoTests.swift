import AppKit
import CoreImage
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HALink

@Suite("家庭照片")
struct HomePhotoTests {
    @Test(arguments: [0.05, 0.5, 1.0])
    func adaptsHeaderContrastAndSoftensBrightPhotoFade(brightness: Double) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = try #require(CIContext().createCGImage(CIImage(color: CIColor(red: brightness, green: brightness, blue: brightness)),
            from: CGRect(x: 0, y: 0, width: 320, height: 320)))
        let url = directory.appending(path: "brightness.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let photo = try await HomePhotoProcessor.prepare(url)
        let headerBackdrop = try #require(CIContext().createCGImage(
            CIImage(cgImage: photo.backdrop),
            from: CGRect(x: 160, y: photo.backdrop.height - 20, width: 1, height: 1)))
        let headerPixel = try #require(NSBitmapImageRep(cgImage: headerBackdrop).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        func luminance(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let shade = photo.theme.headerShade
        let background = headerPixel.redComponent * (1 - photo.headerShadeOpacity) + shade.red * photo.headerShadeOpacity
        let secondaryText = background * 0.14 + 0.86
        #expect((luminance(secondaryText) + 0.05) / (luminance(background) + 0.05) >= 4.5)
        let linearBackground = luminance(headerPixel.redComponent) * (1 - photo.headerShadeOpacity)
            + luminance(shade.red) * photo.headerShadeOpacity
        #expect((0.86 + linearBackground * 0.14 + 0.05) / (linearBackground + 0.05) >= 4.5)
        let surface = photo.theme.surface
        #expect(min(surface.red, surface.green, surface.blue) > 0.05)
        #expect(max(surface.red, surface.green, surface.blue) < 0.4)
        if brightness < 0.1 { #expect(photo.headerShadeOpacity < 0.35) }
        if brightness > 0.9 {
            let middleFade = try #require(CIContext().createCGImage(CIImage(cgImage: photo.backdrop),
                from: CGRect(x: 160, y: 64, width: 1, height: 1)))
            let color = try #require(NSBitmapImageRep(cgImage: middleFade).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
            #expect(color.redComponent > 0.4)
            #expect(color.redComponent < 0.75)
            let edgeFade = try #require(CIContext().createCGImage(CIImage(cgImage: photo.backdrop),
                from: CGRect(x: 32, y: 64, width: 1, height: 1)))
            let edge = try #require(NSBitmapImageRep(cgImage: edgeFade).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
            #expect(edge.redComponent < color.redComponent - 0.025)
        }
    }

    @Test func ignoresBlackAndWhiteAreasWhenChoosingWarmTheme() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: 320, height: 320, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.02, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(x: 160, y: 0, width: 128, height: 320))
        context.setFillColor(CGColor(red: 0.9, green: 0.45, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 288, y: 0, width: 32, height: 320))
        let url = directory.appending(path: "warm-light.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let photo = try await HomePhotoProcessor.prepare(url)
        #expect(photo.theme.red > photo.theme.green * 1.3)
        #expect(photo.theme.red > photo.theme.blue * 3)
        #expect(photo.theme.surface.red > 0.28)
        #expect(photo.theme.surface.blue > 0.05)
    }

    @Test func extractsRankedPaletteAndClampsNeonAndVerifiesWCAGContrast() async throws {
        // Multi-tone image: 50% blue, 30% warm amber, 20% sage green.
        let context = try #require(CGContext(data: nil, width: 360, height: 360, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.12, green: 0.32, blue: 0.78, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 180, height: 360))
        context.setFillColor(CGColor(red: 0.88, green: 0.48, blue: 0.14, alpha: 1))
        context.fill(CGRect(x: 180, y: 0, width: 108, height: 360))
        context.setFillColor(CGColor(red: 0.22, green: 0.66, blue: 0.36, alpha: 1))
        context.fill(CGRect(x: 288, y: 0, width: 72, height: 360))
        let multi = try HomePhotoProcessor.extractTheme(from: try #require(context.makeImage()))
        #expect(multi.palette.count == 3)
        #expect(multi.palette[0].blue > multi.palette[0].red * 2)
        #expect(multi.palette[1].red > multi.palette[1].blue * 2)
        #expect(multi.palette[2].green > multi.palette[2].red * 1.4)
        #expect(HomePhotoProcessor.contrastRatio(multi.primaryText, multi.surface) >= 7.0)
        #expect(HomePhotoProcessor.contrastRatio(multi.secondaryText, multi.surface) >= 4.5)
        #expect(HomePhotoProcessor.contrastRatio(multi.accent, multi.surface) >= 4.5)

        // Pure fluorescent green should have saturation & brightness clamped.
        let neonImage = try #require(CIContext().createCGImage(
            CIImage(color: CIColor(red: 0, green: 1, blue: 0)),
            from: CGRect(x: 0, y: 0, width: 200, height: 200)))
        let neon = try HomePhotoProcessor.extractTheme(from: neonImage)
        let maxC = max(neon.primary.red, neon.primary.green, neon.primary.blue)
        let minC = min(neon.primary.red, neon.primary.green, neon.primary.blue)
        #expect(maxC <= 0.85)
        #expect((maxC - minC) / maxC <= 0.83)
        #expect(HomePhotoProcessor.contrastRatio(neon.primaryText, neon.surface) >= 7.0)
        #expect(HomePhotoProcessor.contrastRatio(neon.secondaryText, neon.surface) >= 4.5)

        // Direct WCAG fallback check: low-contrast candidate adjusts or falls back cleanly.
        let darkBg = HomePhotoProcessor.RGB(red: 0.14, green: 0.18, blue: 0.24)
        let lowContrast = HomePhotoProcessor.RGB(red: 0.18, green: 0.22, blue: 0.28)
        let adjusted = HomePhotoProcessor.ensureContrast(lowContrast, against: darkBg, minimumRatio: 4.5)
        #expect(HomePhotoProcessor.contrastRatio(adjusted, darkBg) >= 4.5)

        let lightBg = HomePhotoProcessor.RGB(red: 0.92, green: 0.92, blue: 0.90)
        let paleText = HomePhotoProcessor.RGB(red: 0.85, green: 0.85, blue: 0.80)
        let darkened = HomePhotoProcessor.ensureContrast(paleText, against: lightBg, minimumRatio: 7.0)
        #expect(HomePhotoProcessor.contrastRatio(darkened, lightBg) >= 7.0)
    }

    @Test(arguments: [CGSize(width: 640, height: 320), CGSize(width: 320, height: 640), CGSize(width: 2_400, height: 2_000)])
    func importsSquareAndBlursOnlyEdges(size: CGSize) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try checkerboard(in: directory, size: size)
        let photo = try await HomePhotoProcessor.prepare(url)
        #expect(photo.image.width == photo.image.height)
        #expect(photo.image.width <= 1_600)
        #expect(photo.backdrop.width == photo.image.width)
        let extensionHeight = max(1, Int(Double(photo.image.height) * HomePhotoProcessor.topExtensionRatio))
        let bottomHeight = max(1, Int(Double(photo.image.height) * HomePhotoProcessor.bottomExtensionRatio))
        #expect(photo.backdrop.height == photo.image.height + extensionHeight + bottomHeight)
        let context = CIContext()
        let body = try #require(context.createCGImage(CIImage(cgImage: photo.backdrop),
            from: CGRect(x: 0, y: bottomHeight, width: photo.image.width, height: photo.image.height)))
        let reflection = try #require(context.createCGImage(CIImage(cgImage: photo.backdrop),
            from: CGRect(x: 0, y: photo.image.height + bottomHeight, width: photo.image.width, height: extensionHeight)))
        let center = try contrast(body, fraction: 0.5)
        #expect(center > 30)
        for fraction in [0.35, 0.45, 0.6, 0.75] {
            #expect(try contrast(body, fraction: fraction) > center * 0.9)
        }
        let seam = try #require(context.createCGImage(CIImage(cgImage: photo.backdrop),
            from: CGRect(x: 0, y: bottomHeight + Int(Double(photo.image.height) * 0.97),
                         width: photo.image.width, height: max(3, Int(Double(photo.image.height) * 0.06)))))
        for fraction in [0.2, 0.5, 0.8] {
            #expect(try contrast(seam, fraction: fraction) < center * 0.5)
        }
        #expect(try contrast(reflection, fraction: 0.5) < center * 0.5)
        #expect(photo.detailBackdrop.width == 230)
        #expect(photo.detailBackdrop.height == 380)
        #expect(try contrast(photo.detailBackdrop, fraction: 0.5) < center * 0.25)
    }

    @Test func reflectsUpperEdgeAndIgnoresObsoleteFlipPreference() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: 320, height: 320, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
        context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 240, width: 320, height: 80))
        let original = directory.appending(path: "colors.png")
        let destination = try #require(CGImageDestinationCreateWithURL(original as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let normal = try await HomePhotoProcessor.prepare(original)
        #expect(normal.theme.blue > normal.theme.red * 3)
        #expect(normal.theme.blue > normal.theme.green * 2)
        let normalPixels = NSBitmapImageRep(cgImage: normal.image)
        let extensionHeight = max(1, Int(320 * HomePhotoProcessor.topExtensionRatio))
        let bottomHeight = max(1, Int(320 * HomePhotoProcessor.bottomExtensionRatio))
        let topExtension = try #require(CIContext().createCGImage(CIImage(cgImage: normal.backdrop),
            from: CGRect(x: 0, y: 320 + bottomHeight, width: 320, height: extensionHeight)))
        let topColor = try #require(NSBitmapImageRep(cgImage: topExtension).colorAt(x: 160, y: extensionHeight / 2)?.usingColorSpace(.deviceRGB))
        let upperOriginal = try #require(normalPixels.colorAt(x: 160, y: 10)?.usingColorSpace(.deviceRGB))
        // Top extension blurs the upper edge and tints it with 30% theme surface color.
        #expect(topColor.blueComponent > upperOriginal.blueComponent + 0.03)
        #expect(topColor.redComponent < upperOriginal.redComponent - 0.15)
        #expect(topColor.redComponent > topColor.blueComponent)
        #expect(try contrast(topExtension, fraction: 0.5) < 2)

        let savedDirectory = directory.appending(path: "saved")
        let store = HomePhotoStore(directory: savedDirectory)
        try await store.importPhoto(from: original)
        let savedFile = savedDirectory.appending(path: "home-photo.jpg")
        let savedBytes = try Data(contentsOf: savedFile)
        try JSONEncoder().encode(true).write(to: savedDirectory.appending(path: "home-photo-direction.json"))
        let reloaded = HomePhotoStore(directory: savedDirectory)
        await reloaded.loadIfNeeded()
        #expect(reloaded.theme != nil)
        let restoredImage = try #require(reloaded.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let restoredPixels = NSBitmapImageRep(cgImage: restoredImage)
        for y in [20, 280] {
            let expected = try #require(normalPixels.colorAt(x: 20, y: y)?.usingColorSpace(.deviceRGB))
            let actual = try #require(restoredPixels.colorAt(x: 20, y: y)?.usingColorSpace(.deviceRGB))
            #expect(abs(expected.redComponent - actual.redComponent) < 0.03)
            #expect(abs(expected.blueComponent - actual.blueComponent) < 0.03)
        }
        #expect(try Data(contentsOf: savedFile) == savedBytes)
        try reloaded.removePhoto()
        #expect(reloaded.theme == nil)
    }

    @Test func survivesOriginalDeletionAndFailedReplacementThenRemoves() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try checkerboard(in: directory, size: CGSize(width: 640, height: 320))
        let store = HomePhotoStore(directory: directory.appending(path: "saved"))
        try await store.importPhoto(from: original)
        #expect(store.image != nil)
        try FileManager.default.removeItem(at: original)

        let reloaded = HomePhotoStore(directory: directory.appending(path: "saved"))
        await reloaded.loadIfNeeded()
        #expect(reloaded.image != nil)
        #expect(reloaded.backdrop != nil)
        let invalid = directory.appending(path: "invalid.png")
        try Data("invalid image".utf8).write(to: invalid)
        await #expect(throws: HomePhotoProcessor.PhotoError.self) { try await reloaded.importPhoto(from: invalid) }
        #expect(reloaded.image != nil)
        #expect(!reloaded.isImporting)
        let afterFailure = HomePhotoStore(directory: directory.appending(path: "saved"))
        await afterFailure.loadIfNeeded()
        #expect(afterFailure.image != nil)

        try reloaded.removePhoto()
        #expect(reloaded.image == nil)
        #expect(reloaded.backdrop == nil)
        let removed = HomePhotoStore(directory: directory.appending(path: "saved"))
        await removed.loadIfNeeded()
        #expect(removed.image == nil)
    }

    @Test func supportsLightAndDarkWallpapersWithAutoSwitchAndManualMode() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func makeSolidPhoto(name: String, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> URL {
            let context = try #require(CGContext(data: nil, width: 320, height: 320, bitsPerComponent: 8,
                                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            let url = directory.appending(path: name)
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
            #expect(CGImageDestinationFinalize(destination))
            return url
        }

        let lightSource = try makeSolidPhoto(name: "light.png", red: 0.9, green: 0.55, blue: 0.2)
        let darkSource = try makeSolidPhoto(name: "dark.png", red: 0.15, green: 0.35, blue: 0.85)
        let savedDirectory = directory.appending(path: "saved")
        let store = HomePhotoStore(directory: savedDirectory)

        // Importing only light falls back to light in dark mode when auto-switch is enabled.
        try await store.importPhoto(from: lightSource, for: .light)
        #expect(store.autoSwitchWithSystem)
        #expect(store.activeAsset(isDark: false)?.theme == store.light?.theme)
        #expect(store.activeAsset(isDark: true)?.theme == store.light?.theme)

        // Importing dark switches automatically based on system appearance.
        try await store.importPhoto(from: darkSource, for: .dark)
        #expect(store.activeAsset(isDark: false)?.theme == store.light?.theme)
        #expect(store.activeAsset(isDark: true)?.theme == store.dark?.theme)
        #expect(store.light?.theme != store.dark?.theme)

        // Disabling auto-switch pins the chosen appearance regardless of system appearance.
        store.setAutoSwitchWithSystem(false)
        store.setManualAppearance(.dark)
        #expect(store.activeAsset(isDark: false)?.theme == store.dark?.theme)
        #expect(store.activeAsset(isDark: true)?.theme == store.dark?.theme)

        // Preferences and both wallpapers persist across reloads.
        let reloaded = HomePhotoStore(directory: savedDirectory)
        await reloaded.loadIfNeeded()
        #expect(!reloaded.autoSwitchWithSystem)
        #expect(reloaded.manualAppearance == .dark)
        #expect(reloaded.light != nil)
        #expect(reloaded.dark != nil)
        #expect(reloaded.activeAsset(isDark: false)?.theme == reloaded.dark?.theme)

        // Removing dark clears only the dark slot and falls back to the remaining light wallpaper.
        try reloaded.removePhoto(for: .dark)
        #expect(reloaded.dark == nil)
        #expect(reloaded.light != nil)
        #expect(reloaded.activeAsset(isDark: false)?.theme == reloaded.light?.theme)
        #expect(reloaded.activeAsset(isDark: true)?.theme == reloaded.light?.theme)
        reloaded.setAutoSwitchWithSystem(true)
        #expect(reloaded.activeAsset(isDark: true)?.theme == reloaded.light?.theme)
    }

    @Test func concurrentLoadIfNeededWaitsUntilWallpaperIsReady() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try checkerboard(in: directory, size: CGSize(width: 640, height: 640))
        let savedDirectory = directory.appending(path: "saved")
        let importer = HomePhotoStore(directory: savedDirectory)
        try await importer.importPhoto(from: original, for: .light)

        let reloaded = HomePhotoStore(directory: savedDirectory)
        #expect(!reloaded.hasLoaded)
        let first = Task {
            await reloaded.loadIfNeeded()
            return reloaded.light != nil
        }
        let second = Task {
            await reloaded.loadIfNeeded()
            return reloaded.light != nil
        }
        let (firstSawPhoto, secondSawPhoto) = await (first.value, second.value)
        #expect(firstSawPhoto)
        #expect(secondSawPhoto)
        #expect(reloaded.hasLoaded)
        #expect(reloaded.activeAsset(isDark: false)?.backdrop != nil)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "HALink-photo-\(UUID().uuidString)")
    }

    private func checkerboard(in directory: URL, size: CGSize) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        for x in stride(from: 0, to: Int(size.width), by: 8) {
            context.fill(CGRect(x: x, y: 0, width: 4, height: Int(size.height)))
        }
        let url = directory.appending(path: "source.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func contrast(_ image: CGImage, fraction: Double, horizontalRange: Range<Double> = 0.25..<0.75) throws -> Double {
        let width = image.width
        let context = try #require(CGContext(data: nil, width: width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let row = Int(Double(image.height) * fraction) * width * 4
        let differences = (Int(Double(width) * horizontalRange.lowerBound) ..< Int(Double(width) * horizontalRange.upperBound)).map { x in
            abs(Double(bytes[row + x * 4]) - Double(bytes[row + (x + 1) * 4]))
        }
        return differences.reduce(0, +) / Double(differences.count)
    }
}
