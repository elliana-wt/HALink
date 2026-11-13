import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            ConnectionSection(model: model)
            Section("通用") {
                Toggle("登录时启动 HALink", isOn: Binding(get: { model.launchAtLogin }, set: model.setLogin))
            }
            Section("关于") {
                UpdateRow(model: model)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}
