import SwiftUI
import UniformTypeIdentifiers

struct HomePhotoSettings: View {
    let photo: HomePhotoStore
    @State private var choosingPhoto = false
    @State private var importTarget: HomePhotoStore.Appearance = .light
    @State private var dropTarget: HomePhotoStore.Appearance?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 20) {
                ForEach(HomePhotoStore.Appearance.allCases) { appearance in
                    wallpaperItem(for: appearance)
                }
            }

            Toggle("随系统外观自动切换", isOn: Binding(
                get: { photo.autoSwitchWithSystem },
                set: { photo.setAutoSwitchWithSystem($0) }
            ))

            if !photo.autoSwitchWithSystem {
                Picker("当前使用壁纸", selection: Binding(
                    get: { photo.manualAppearance },
                    set: { photo.setManualAppearance($0) }
                )) {
                    ForEach(HomePhotoStore.Appearance.allCases) { appearance in
                        Text(appearance.shortTitle).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("控制窗口外观")
        } footer: {
            Text("仅设置一张壁纸时，浅色与深色外观将共用此壁纸。")
        }
        .fileImporter(isPresented: $choosingPhoto, allowedContentTypes: [.image]) { result in
            let target = importTarget
            switch result {
            case .success(let url):
                importWallpaper(from: url, for: target)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("控制窗口壁纸", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { await photo.loadIfNeeded() }
    }

    private func importWallpaper(from url: URL, for target: HomePhotoStore.Appearance) {
        Task {
            do { try await photo.importPhoto(from: url, for: target) }
            catch { errorMessage = "无法设置\(target.title)：\(error.localizedDescription)" }
        }
    }

    private func wallpaperItem(for appearance: HomePhotoStore.Appearance) -> some View {
        let asset = photo.asset(for: appearance)
        let busy = photo.isImporting(appearance)
        let isTargeted = dropTarget == appearance

        return HStack(alignment: .center, spacing: 14) {
            Group {
                if let image = asset?.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: appearance.symbolName)
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 2.5)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))
                }
            }
            .contentShape(.rect(cornerRadius: 12))
            .dropDestination(for: URL.self) { urls, _ in
                guard !busy, let url = urls.first else { return false }
                importWallpaper(from: url, for: appearance)
                return true
            } isTargeted: { targeted in
                if targeted {
                    dropTarget = appearance
                } else if dropTarget == appearance {
                    dropTarget = nil
                }
            }
            .accessibilityLabel(asset == nil ? "尚未设置\(appearance.title)，可拖入图片" : "\(appearance.title)预览，可拖入图片更换")

            VStack(alignment: .leading, spacing: 10) {
                Text(appearance.title)
                    .font(.headline.weight(.medium))
                HStack(spacing: 8) {
                    Button(asset == nil ? "选择…" : "更换…") {
                        importTarget = appearance
                        choosingPhoto = true
                    }
                    if asset != nil {
                        Button("移除", role: .destructive) {
                            do { try photo.removePhoto(for: appearance) }
                            catch { errorMessage = "无法移除\(appearance.title)：\(error.localizedDescription)" }
                        }
                    }
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在处理\(appearance.title)")
                    }
                }
                .disabled(busy)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
