import SwiftUI

enum DeviceEditorLayout {
    static let rowHeight: CGFloat = 28
    static let shortcutWidth: CGFloat = 140
}

struct DeviceEditorRow<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title).fixedSize()
            Spacer(minLength: 0)
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: DeviceEditorLayout.rowHeight, alignment: .center)
    }
}
