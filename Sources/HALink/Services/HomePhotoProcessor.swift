import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum HomePhotoProcessor {
    static let topExtensionRatio = 0.10
    static let topTransitionRatio = 0.34
    static let topTintOpacity = 0.30
    static let bottomExtensionRatio = 0.18
    static let bottomTransitionRatio = 0.40

    struct Photo: Sendable {
        let image: CGImage
        let backdrop: CGImage
        let detailBackdrop: CGImage
        let jpeg: Data
        let theme: Theme
        let headerShadeOpacity: Double
    }

    static let sampleSide = 36

    struct RGB: Equatable, Sendable {
        static let white = Self(red: 1, green: 1, blue: 1)
        static let black = Self(red: 0, green: 0, blue: 0)

        let red: Double
        let green: Double
        let blue: Double
    }

    struct Theme: Equatable, Sendable {
        let primary: RGB
        let palette: [RGB]
        let surface: RGB
        let headerShade: RGB
        let primaryText: RGB
        let secondaryText: RGB
        let accent: RGB

        var red: Double { primary.red }
        var green: Double { primary.green }
        var blue: Double { primary.blue }
    }

    enum PhotoError: LocalizedError {
        case unreadable, tooLarge, processingFailed

        var errorDescription: String? {
            switch self {
            case .unreadable: "无法读取这张图片，请选择其他照片。"
            case .tooLarge: "图片超过 100 MB，请选择较小的照片。"
            case .processingFailed: "无法处理这张照片，请选择其他图片。"
            }
        }
    }

    @concurrent
    static func prepare(_ url: URL, includeJPEG: Bool = true) async throws -> Photo {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100 * 1_024 * 1_024 else { throw PhotoError.tooLarge }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PhotoError.unreadable }
        let side = min(thumbnail.width, thumbnail.height)
        let crop = CGRect(x: (thumbnail.width - side) / 2, y: (thumbnail.height - side) / 2, width: side, height: side)
        guard let square = thumbnail.cropping(to: crop) else { throw PhotoError.processingFailed }

        // Flatten transparency onto a neutral background before writing the local JPEG.
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let original = CIImage(cgImage: square)
            .composited(over: CIImage(color: CIColor(red: 0.12, green: 0.12, blue: 0.12)).cropped(to: bounds))
        let context = CIContext()
        guard let image = context.createCGImage(original, from: bounds) else { throw PhotoError.processingFailed }
        let theme = try extractTheme(from: image)
        let surface = theme.surface
        let surfaceImage = CIImage(color: CIColor(red: surface.red, green: surface.green, blue: surface.blue))
        let extensionHeight = max(1, Int(Double(side) * topExtensionRatio))
        let bottomHeight = max(1, Int(Double(side) * bottomExtensionRatio))
        let extendedBounds = CGRect(x: 0, y: -bottomHeight, width: side, height: side + extensionHeight + bottomHeight)
        // Extend the top smoothly by clamping edge pixels (no mirrored reflection),
        // blur progressively, and apply the extracted theme color at 30% opacity.
        let topClamped = original.clampedToExtent()
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side + extensionHeight))
        let bottomReflection = original
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .cropped(to: CGRect(x: 0, y: -bottomHeight, width: side, height: bottomHeight))
        let extended = topClamped.composited(over: bottomReflection)
        let bottomFade = try curvedFade(in: extendedBounds)
        let topFade = try curvedFade(in: extendedBounds, top: true)
        let topBlurMask = topFade.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.85, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.85, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.85, w: 0)
        ])
        let bottomBlurMask = bottomFade.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.55, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0.55, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0.55, w: 0)
        ])
        let blurMask = topBlurMask.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: bottomBlurMask])
            .cropped(to: extendedBounds)
        let blurred = extended.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: [
            "inputMask": blurMask, kCIInputRadiusKey: CGFloat(side) * 0.055
        ])
        // Blend the top theme tint in perceptual sRGB space at 30% opacity so the
        // blurred sky/photo stays airy and translucent while transitioning silkily.
        let topTintMask = topFade.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: topTintOpacity, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: topTintOpacity, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: topTintOpacity, w: 0)
        ])
        let topBlended = surfaceImage.applyingFilter("CILinearToSRGBToneCurve")
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: blurred.applyingFilter("CILinearToSRGBToneCurve"),
                kCIInputMaskImageKey: topTintMask
            ])
            .applyingFilter("CISRGBToneCurveToLinear")
        // Compensate for linear-light blending so a pale photo does not stay bright
        // until the very end of the fade into the dark bottom surface.
        let bottomColorFade = bottomFade.applyingFilter("CIColorPolynomial", parameters: [
            "inputRedCoefficients": CIVector(x: 0, y: 2, z: -1, w: 0),
            "inputGreenCoefficients": CIVector(x: 0, y: 2, z: -1, w: 0),
            "inputBlueCoefficients": CIVector(x: 0, y: 2, z: -1, w: 0)
        ])
        // Use the same curved field for blur and color so their boundaries stay aligned.
        let blended = surfaceImage
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: topBlended, kCIInputMaskImageKey: bottomColorFade
            ])
        guard let backdrop = context.createCGImage(blended, from: extendedBounds) else { throw PhotoError.processingFailed }
        let detailBounds = CGRect(x: 0, y: 0, width: 230, height: 380)
        let detailScale = max(detailBounds.width / extendedBounds.width, detailBounds.height / extendedBounds.height)
        let scaledDetail = blended
            .transformed(by: CGAffineTransform(translationX: -extendedBounds.midX, y: -extendedBounds.midY))
            .transformed(by: CGAffineTransform(scaleX: detailScale, y: detailScale))
            .transformed(by: CGAffineTransform(translationX: detailBounds.midX, y: detailBounds.midY))
            .cropped(to: detailBounds)
        let blurredDetail = scaledDetail
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18.0])
            .cropped(to: detailBounds)
        let detailTintMask = CIImage(color: CIColor(red: 0.42, green: 0.42, blue: 0.42))
            .cropped(to: detailBounds)
        let detailTinted = surfaceImage.applyingFilter("CILinearToSRGBToneCurve")
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: blurredDetail.applyingFilter("CILinearToSRGBToneCurve"),
                kCIInputMaskImageKey: detailTintMask
            ])
            .applyingFilter("CISRGBToneCurveToLinear")
        guard let detailBackdrop = context.createCGImage(detailTinted, from: detailBounds) else {
            throw PhotoError.processingFailed
        }
        let jpegData: Data
        if includeJPEG {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw PhotoError.processingFailed
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PhotoError.processingFailed }
            jpegData = data as Data
        } else {
            jpegData = Data()
        }
        let headerRegion = CGRect(x: 0, y: extendedBounds.maxY - CGFloat(side) * 0.15,
                                  width: CGFloat(side), height: CGFloat(side) * 0.15)
        guard let header = context.createCGImage(blended, from: headerRegion) else { throw PhotoError.processingFailed }
        return Photo(image: image, backdrop: backdrop, detailBackdrop: detailBackdrop, jpeg: jpegData, theme: theme,
                     headerShadeOpacity: try headerShadeOpacity(in: header, shade: theme.headerShade))
    }

    private static func curvedFade(in bounds: CGRect, top: Bool = false) throws -> CIImage {
        let width = 256
        let height = max(1, Int(Double(width) * bounds.height / bounds.width))
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            for row in 0..<height {
                let y = ((Double(height - row) - 0.5) / Double(height) * bounds.height + bounds.minY) / bounds.width
                for column in 0..<width {
                    let x = (Double(column) + 0.5) / Double(width) * 2 - 1
                    let progress: Double
                    if top {
                        let dip = 0.015 * x * x
                        let distanceFromTop = bounds.maxY / bounds.width - y
                        progress = min(1, max(0, 1 - (distanceFromTop - dip) / topTransitionRatio))
                    } else {
                        // Continue into the lower reflection to lengthen the fade
                        // without covering more of the original square photo.
                        let rise = 0.035 * x * x
                        let distanceFromBottom = y - bounds.minY / bounds.width
                        progress = min(1, max(0, 1 - (distanceFromBottom - rise) / bottomTransitionRatio))
                    }
                    let smooth = progress * progress * progress * (progress * (progress * 6 - 15) + 10)
                    let value = UInt8((smooth * 255).rounded())
                    let offset = (row * width + column) * 4
                    bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
                    bytes[offset + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw PhotoError.processingFailed
        }
        return CIImage(cgImage: image, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: bounds.width / CGFloat(width), y: bounds.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }

    private static func headerShadeOpacity(in image: CGImage, shade: RGB) throws -> Double {
        let width = 64, height = 16
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PhotoError.processingFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { throw PhotoError.processingFailed }
        var brightness: [Double] = []
        brightness.reserveCapacity(width * height)
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let pixel = RGB(red: Double(bytes[offset]) / 255,
                            green: Double(bytes[offset + 1]) / 255,
                            blue: Double(bytes[offset + 2]) / 255)
            brightness.append(relativeLuminance(pixel))
        }
        brightness.sort()
        let bright = brightness[Int(Double(brightness.count - 1) * 0.95)]
        let shadeLuminance = relativeLuminance(shade)
        // Use only the shade needed for readable text, retaining the photo's color.
        return min(0.90, max(0.06, (bright - 0.14) / max(0.01, bright - shadeLuminance)))
    }

    // MARK: - Apple Music-inspired 4-stage color extraction

    private struct LabColor {
        var l: Double
        var a: Double
        var b: Double

        var chroma: Double { hypot(a, b) }

        func squaredDistance(to other: Self) -> Double {
            let dl = l - other.l
            let da = a - other.a
            let db = b - other.b
            return dl * dl + da * da + db * db
        }
    }

    private struct LabSample {
        let lab: LabColor
        let saturation: Double
    }

    private struct HSBColor {
        var hue: Double
        var saturation: Double
        var brightness: Double
    }

    private struct Cluster {
        var centroid: LabColor
        var count: Int
    }

    static func extractTheme(from image: CGImage) throws -> Theme {
        // 1. Extreme downsampling (36x36) to suppress noise and reduce work.
        let pixels = try downsample(image, side: sampleSide)
        let samples = pixels.map { rgb in
            LabSample(lab: rgbToLab(rgb), saturation: rgbToHSB(rgb).saturation)
        }

        // 2 & 3. Filter meaningless black/white/gray pixels, then cluster in CIE Lab
        // (Median Cut + K-Means refinement) and clamp saturation & brightness.
        let filtered = filterMeaningfulSamples(samples)
        let rawPalette: [RGB]
        if filtered.isEmpty {
            rawPalette = [RGB(red: 0.45, green: 0.45, blue: 0.45)]
        } else {
            rawPalette = clusterDominantColors(filtered, maxBuckets: 8, maxDominant: 3)
        }
        let palette = rawPalette.map(clampDominant)
        let primary = palette[0]
        let secondarySeed = palette.count > 1 ? palette[1] : primary

        let surface = makeSurface(from: primary)
        let headerShade = RGB(red: surface.red * 0.35, green: surface.green * 0.35, blue: surface.blue * 0.35)

        // 4. WCAG 2.1 contrast verification for text & accent roles against surface.
        let primaryHSB = rgbToHSB(primary)
        let primaryTextSeed = hsbToRGB(HSBColor(hue: primaryHSB.hue,
                                                saturation: min(0.10, primaryHSB.saturation * 0.25),
                                                brightness: 0.96))
        let secondaryHSB = rgbToHSB(secondarySeed)
        let secondaryTextSeed = hsbToRGB(HSBColor(hue: secondaryHSB.hue,
                                                  saturation: min(0.28, secondaryHSB.saturation * 0.45),
                                                  brightness: 0.78))
        let accentSeed = hsbToRGB(HSBColor(hue: secondaryHSB.hue,
                                           saturation: secondaryHSB.saturation < 0.08
                                               ? 0 : min(0.68, max(0.32, secondaryHSB.saturation)),
                                           brightness: 0.84))

        let primaryText = ensureContrast(primaryTextSeed, against: surface, minimumRatio: 7.0)
        let secondaryText = ensureContrast(secondaryTextSeed, against: surface, minimumRatio: 4.5)
        let accent = ensureContrast(accentSeed, against: surface, minimumRatio: 4.5)

        return Theme(primary: primary, palette: palette, surface: surface, headerShade: headerShade,
                     primaryText: primaryText, secondaryText: secondaryText, accent: accent)
    }

    static func relativeLuminance(_ rgb: RGB) -> Double {
        func linear(_ value: Double) -> Double {
            let clamped = min(1, max(0, value))
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    static func contrastRatio(_ first: RGB, _ second: RGB) -> Double {
        let l1 = relativeLuminance(first)
        let l2 = relativeLuminance(second)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    static func ensureContrast(_ candidate: RGB, against background: RGB, minimumRatio: Double) -> RGB {
        if contrastRatio(candidate, background) >= minimumRatio { return candidate }
        let useLighter = contrastRatio(.white, background) >= contrastRatio(.black, background)
        let fallback = useLighter ? RGB.white : RGB.black
        let origin = rgbToLab(candidate)
        let targetL = useLighter ? 100.0 : 0.0

        var low = 0.0
        var high = 1.0
        var best: RGB?
        for _ in 0..<18 {
            let mid = (low + high) * 0.5
            let chromaScale = 1.0 - mid * mid
            let adjusted = labToRGB(LabColor(
                l: origin.l + (targetL - origin.l) * mid,
                a: origin.a * chromaScale,
                b: origin.b * chromaScale
            ))
            if contrastRatio(adjusted, background) >= minimumRatio {
                best = adjusted
                high = mid
            } else {
                low = mid
            }
        }
        if let best, contrastRatio(best, background) >= minimumRatio { return best }
        return fallback
    }

    private static func downsample(_ image: CGImage, side: Int) throws -> [RGB] {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PhotoError.processingFailed
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { throw PhotoError.processingFailed }
        var pixels: [RGB] = []
        pixels.reserveCapacity(side * side)
        for offset in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha > 0.01 else { continue }
            let scale = alpha < 0.999 ? 1.0 / (255 * alpha) : 1.0 / 255
            pixels.append(RGB(
                red: min(1, Double(bytes[offset]) * scale),
                green: min(1, Double(bytes[offset + 1]) * scale),
                blue: min(1, Double(bytes[offset + 2]) * scale)
            ))
        }
        return pixels
    }

    private static func filterMeaningfulSamples(_ samples: [LabSample]) -> [LabSample] {
        let minimumCount = max(1, Int((Double(samples.count) * 0.02).rounded(.up)))
        // Tier 1: chromatic midtones, excluding pure black, pure white, and gray.
        let chromatic = samples.filter {
            $0.lab.l >= 12 && $0.lab.l <= 93 && $0.lab.chroma >= 10 && $0.saturation >= 0.12
        }
        if chromatic.count >= minimumCount { return chromatic }
        // Tier 2: subtle low-saturation tones for misty or muted photos.
        let subtle = samples.filter {
            $0.lab.l >= 12 && $0.lab.l <= 93 && $0.lab.chroma >= 4
        }
        if subtle.count >= minimumCount { return subtle }
        // Tier 3: monochrome photos with non-extreme grays.
        return samples.filter { $0.lab.l >= 8 && $0.lab.l <= 95 }
    }

    private static func clusterDominantColors(_ samples: [LabSample], maxBuckets: Int, maxDominant: Int) -> [RGB] {
        // Stage A: deterministic Median Cut in CIE Lab for initial centroids.
        var buckets: [[LabColor]] = [samples.map(\.lab)]
        while buckets.count < maxBuckets {
            var chosenIndex: Int?
            var chosenScore = 0.0
            var chosenAxis = 0
            for (index, bucket) in buckets.enumerated() where bucket.count >= 2 {
                var minL = Double.infinity, maxL = -Double.infinity
                var minA = Double.infinity, maxA = -Double.infinity
                var minB = Double.infinity, maxB = -Double.infinity
                for p in bucket {
                    if p.l < minL { minL = p.l }; if p.l > maxL { maxL = p.l }
                    if p.a < minA { minA = p.a }; if p.a > maxA { maxA = p.a }
                    if p.b < minB { minB = p.b }; if p.b > maxB { maxB = p.b }
                }
                let ranges = [maxL - minL, maxA - minA, maxB - minB]
                guard let axis = ranges.indices.max(by: { ranges[$0] < ranges[$1] }), ranges[axis] > 1.0 else { continue }
                let score = Double(bucket.count) * ranges[axis]
                if score > chosenScore {
                    chosenScore = score
                    chosenIndex = index
                    chosenAxis = axis
                }
            }
            guard let splitIndex = chosenIndex else { break }
            var bucket = buckets.remove(at: splitIndex)
            bucket.sort { lhs, rhs in
                switch chosenAxis {
                case 0: return lhs.l != rhs.l ? lhs.l < rhs.l : (lhs.a != rhs.a ? lhs.a < rhs.a : lhs.b < rhs.b)
                case 1: return lhs.a != rhs.a ? lhs.a < rhs.a : (lhs.l != rhs.l ? lhs.l < rhs.l : lhs.b < rhs.b)
                default: return lhs.b != rhs.b ? lhs.b < rhs.b : (lhs.l != rhs.l ? lhs.l < rhs.l : lhs.a < rhs.a)
                }
            }
            let mid = bucket.count / 2
            buckets.append(Array(bucket[..<mid]))
            buckets.append(Array(bucket[mid...]))
        }

        var centroids = buckets.map(meanLab)
        let points = samples.map(\.lab)
        var assignments = [Int](repeating: -1, count: points.count)

        // Stage B: K-Means refinement in CIE Lab.
        for _ in 0..<10 {
            var changed = false
            var sumL = [Double](repeating: 0, count: centroids.count)
            var sumA = [Double](repeating: 0, count: centroids.count)
            var sumB = [Double](repeating: 0, count: centroids.count)
            var counts = [Int](repeating: 0, count: centroids.count)

            for (index, point) in points.enumerated() {
                var nearest = 0
                var bestDistance = point.squaredDistance(to: centroids[0])
                for c in 1..<centroids.count {
                    let distance = point.squaredDistance(to: centroids[c])
                    if distance < bestDistance { bestDistance = distance; nearest = c }
                }
                if assignments[index] != nearest { assignments[index] = nearest; changed = true }
                sumL[nearest] += point.l
                sumA[nearest] += point.a
                sumB[nearest] += point.b
                counts[nearest] += 1
            }

            var nextCentroids: [LabColor] = []
            nextCentroids.reserveCapacity(centroids.count)
            for c in 0..<centroids.count where counts[c] > 0 {
                let n = Double(counts[c])
                nextCentroids.append(LabColor(l: sumL[c] / n, a: sumA[c] / n, b: sumB[c] / n))
            }
            if nextCentroids.count != centroids.count {
                centroids = nextCentroids
                assignments = [Int](repeating: -1, count: points.count)
                continue
            }
            centroids = nextCentroids
            if !changed { break }
        }

        // Count final cluster sizes and sort by pixel share descending.
        var finalCounts = [Int](repeating: 0, count: centroids.count)
        for point in points {
            var nearest = 0
            var bestDistance = point.squaredDistance(to: centroids[0])
            for c in 1..<centroids.count {
                let distance = point.squaredDistance(to: centroids[c])
                if distance < bestDistance { bestDistance = distance; nearest = c }
            }
            finalCounts[nearest] += 1
        }

        let sorted = zip(centroids, finalCounts)
            .filter { $0.1 > 0 }
            .map { Cluster(centroid: $0.0, count: $0.1) }
            .sorted { $0.count > $1.count }

        // Merge perceptually close clusters (Delta-E < 14) so top tones stay distinct.
        let mergeThresholdSquared = 14.0 * 14.0
        var merged: [Cluster] = []
        for cluster in sorted {
            if let existing = merged.firstIndex(where: { $0.centroid.squaredDistance(to: cluster.centroid) < mergeThresholdSquared }) {
                let total = merged[existing].count + cluster.count
                let w1 = Double(merged[existing].count) / Double(total)
                let w2 = Double(cluster.count) / Double(total)
                merged[existing] = Cluster(
                    centroid: LabColor(
                        l: merged[existing].centroid.l * w1 + cluster.centroid.l * w2,
                        a: merged[existing].centroid.a * w1 + cluster.centroid.a * w2,
                        b: merged[existing].centroid.b * w1 + cluster.centroid.b * w2
                    ),
                    count: total
                )
            } else {
                merged.append(cluster)
            }
        }
        merged.sort { $0.count > $1.count }

        let totalPixels = Double(points.count)
        var dominant: [RGB] = []
        for (index, cluster) in merged.prefix(maxDominant).enumerated() {
            if index == 0 || Double(cluster.count) / totalPixels >= 0.05 {
                dominant.append(labToRGB(cluster.centroid))
            }
        }
        return dominant
    }

    private static func meanLab(_ colors: [LabColor]) -> LabColor {
        let count = Double(max(1, colors.count))
        var l = 0.0, a = 0.0, b = 0.0
        for color in colors { l += color.l; a += color.a; b += color.b }
        return LabColor(l: l / count, a: a / count, b: b / count)
    }

    private static func clampDominant(_ rgb: RGB) -> RGB {
        var hsb = rgbToHSB(rgb)
        if hsb.saturation >= 0.08 {
            hsb.saturation = min(0.82, max(0.18, hsb.saturation))
            hsb.brightness = min(0.84, max(0.28, hsb.brightness))
        } else {
            hsb.saturation = min(0.08, hsb.saturation)
            hsb.brightness = min(0.72, max(0.28, hsb.brightness))
        }
        return hsbToRGB(hsb)
    }

    private static func makeSurface(from primary: RGB) -> RGB {
        let hsb = rgbToHSB(primary)
        let luminance = relativeLuminance(primary)
        let targetBrightness = min(0.35, max(0.24, 0.28 + 0.06 * luminance))
        let targetSaturation = hsb.saturation < 0.05 ? 0 : min(0.65, max(0.20, hsb.saturation * 0.85))
        var surface = hsbToRGB(HSBColor(hue: hsb.hue, saturation: targetSaturation, brightness: targetBrightness))
        // Keep dark panel surface within a luminance ceiling so white/tinted text has >= 7:1 headroom.
        var brightness = targetBrightness
        while relativeLuminance(surface) > 0.095 && brightness > 0.16 {
            brightness -= 0.015
            surface = hsbToRGB(HSBColor(hue: hsb.hue, saturation: targetSaturation, brightness: brightness))
        }
        return surface
    }

    private static func rgbToLab(_ rgb: RGB) -> LabColor {
        func linear(_ value: Double) -> Double {
            let clamped = min(1, max(0, value))
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        func pivot(_ value: Double) -> Double {
            let epsilon = 216.0 / 24389.0
            let kappa = 24389.0 / 27.0
            return value > epsilon ? cbrt(value) : (kappa * value + 16.0) / 116.0
        }
        let r = linear(rgb.red), g = linear(rgb.green), b = linear(rgb.blue)
        let fx = pivot((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047)
        let fy = pivot(0.2126729 * r + 0.7151522 * g + 0.0722000 * b)
        let fz = pivot((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883)
        return LabColor(l: 116.0 * fy - 16.0, a: 500.0 * (fx - fy), b: 200.0 * (fy - fz))
    }

    private static func labToRGB(_ lab: LabColor) -> RGB {
        let fy = (lab.l + 16.0) / 116.0
        let fx = lab.a / 500.0 + fy
        let fz = fy - lab.b / 200.0
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        let fx3 = fx * fx * fx
        let fz3 = fz * fz * fz
        let xr = fx3 > epsilon ? fx3 : (116.0 * fx - 16.0) / kappa
        let yr = lab.l > kappa * epsilon ? pow((lab.l + 16.0) / 116.0, 3) : lab.l / kappa
        let zr = fz3 > epsilon ? fz3 : (116.0 * fz - 16.0) / kappa
        let x = xr * 0.95047, y = yr, z = zr * 1.08883
        func gamma(_ value: Double) -> Double {
            let clamped = min(1, max(0, value))
            return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
        }
        return RGB(
            red: gamma(3.2404542 * x - 1.5371385 * y - 0.4985314 * z),
            green: gamma(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z),
            blue: gamma(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)
        )
    }

    private static func rgbToHSB(_ rgb: RGB) -> HSBColor {
        let r = min(1, max(0, rgb.red))
        let g = min(1, max(0, rgb.green))
        let b = min(1, max(0, rgb.blue))
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        let saturation = maximum > 0 ? delta / maximum : 0
        var hue = 0.0
        if delta > 1e-6 {
            if maximum == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return HSBColor(hue: hue, saturation: saturation, brightness: maximum)
    }

    private static func hsbToRGB(_ hsb: HSBColor) -> RGB {
        let s = min(1, max(0, hsb.saturation))
        let v = min(1, max(0, hsb.brightness))
        guard s > 1e-6 else { return RGB(red: v, green: v, blue: v) }
        let sector = (hsb.hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let index = Int(floor(sector))
        let fraction = sector - Double(index)
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))
        switch index % 6 {
        case 0: return RGB(red: v, green: t, blue: p)
        case 1: return RGB(red: q, green: v, blue: p)
        case 2: return RGB(red: p, green: v, blue: t)
        case 3: return RGB(red: p, green: q, blue: v)
        case 4: return RGB(red: t, green: p, blue: v)
        default: return RGB(red: v, green: p, blue: q)
        }
    }
}
