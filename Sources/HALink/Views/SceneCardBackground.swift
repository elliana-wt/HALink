import SwiftUI

enum HomePhotoCoordinateSpace: Hashable {
    case backdrop
}

struct SceneCardBackground: View {
    let image: NSImage

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named(HomePhotoCoordinateSpace.backdrop))
            let photoHeight = MenuBarLayout.width * image.size.height / max(1, image.size.width)
            Image(nsImage: image)
                .resizable()
                .frame(width: MenuBarLayout.width, height: photoHeight)
                .blur(radius: 20, opaque: true)
                .offset(x: -frame.minX, y: -frame.minY)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipShape(.rect(cornerRadius: 18))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
