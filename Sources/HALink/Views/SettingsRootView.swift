import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case devices, settings
    var id: Self { self }
    var title: String {
        switch self { case .devices: "我的设备"; case .settings: "设置" }
    }
    var icon: String {
        switch self { case .devices: "house"; case .settings: "gearshape" }
    }
}

@Observable
final class SettingsNavigation {
    var selection: SettingsPage?
    init(selection: SettingsPage) { self.selection = selection }
}

struct SettingsRootView: View {
    @Bindable var model: AppModel
    @Bindable var navigation: SettingsNavigation
    private var selectedPage: SettingsPage { navigation.selection ?? .devices }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $navigation.selection) { page in
                Label(page.title, systemImage: page.icon).tag(page)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.currentServerName)
                        .font(.headline.weight(.medium)).foregroundStyle(.primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    ConnectionBadge(state: model.connectionState)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            Group {
                switch selectedPage {
                case .devices:
                    DevicesView(model: model, openConnection: { navigation.selection = .settings })
                case .settings:
                    SettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbarVisibility(.visible, for: .windowToolbar)
        .tint(.orange)
        .frame(minWidth: SettingsWindowController.fixedContentSize.width,
               minHeight: SettingsWindowController.fixedContentSize.height)
        .alert("未能保存", isPresented: Binding(get: { model.generalError != nil }, set: { if !$0 { model.generalError = nil } })) {
            Button("好", role: .cancel) { model.generalError = nil }
        } message: { Text(model.generalError ?? "") }
    }
}

struct ConnectionBadge: View {
    let state: AppModel.ConnectionState
    var textColor: Color = .secondary
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(state.title).foregroundStyle(textColor)
        }
    }
    private var color: Color {
        switch state { case .connected: .green; case .connecting: .orange; case .offline: .orange; case .notConfigured: .secondary }
    }
}
