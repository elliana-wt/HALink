import SwiftUI

struct HomePhotoBackdrop: View {
    let image: NSImage

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct HomePhotoHeaderShade: View {
    let opacity: Double
    var color: Color = .black

    var body: some View {
        GeometryReader { geometry in
            let protectedHeight = geometry.size.height + 12
            let arcHeight: CGFloat = 12
            Canvas { context, size in
                for column in 0..<Int(ceil(size.width)) {
                    let x = (CGFloat(column) + 0.5) / size.width * 2 - 1
                    let fadeEnd = protectedHeight + 52 + arcHeight * x * x
                    let gradient = Gradient(stops: [
                        .init(color: color.opacity(opacity), location: 0),
                        .init(color: color.opacity(opacity), location: protectedHeight / fadeEnd),
                        .init(color: color.opacity(opacity * 0.42), location: (protectedHeight + (fadeEnd - protectedHeight) * 0.45) / fadeEnd),
                        .init(color: .clear, location: 1)
                    ])
                    let rect = CGRect(x: CGFloat(column), y: 0, width: 1, height: size.height)
                    context.fill(Path(rect), with: .linearGradient(gradient,
                        startPoint: CGPoint(x: CGFloat(column), y: 0),
                        endPoint: CGPoint(x: CGFloat(column), y: fadeEnd)), style: FillStyle(antialiased: false))
                }
            }
            .frame(width: geometry.size.width + 32, height: protectedHeight + 52 + arcHeight)
            .offset(x: -16, y: -16)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension HomePhotoProcessor.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

extension HomePhotoProcessor.Theme {
    var color: Color { primary.color }
    var surfaceColor: Color { surface.color }
    var primaryTextColor: Color { primaryText.color }
    var secondaryTextColor: Color { secondaryText.color }
    var accentColor: Color { accent.color }
}

extension EnvironmentValues {
    @Entry var usesHomePhoto = false
    @Entry var homePhotoTheme: HomePhotoProcessor.Theme? = nil
}
