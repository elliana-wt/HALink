import AppKit
import HALinkCore
import Observation
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    var panelState: MenuBarPanelState = MenuBarPanelState()
    var usesExternalShadowPadding = false
    let showSettings: (SettingsPage) -> Void
    let contentHeightChanged: (CGFloat) -> Void
    var closePanel: () -> Void = {}
    @State private var detailID: UUID?
    @State private var room: MenuBarRoom = .all
    @State private var listPosition = ScrollPosition()
    @State private var topChromeHeight: CGFloat = 0
    @State private var bottomChromeHeight: CGFloat = 0
    @State private var deviceContentHeight: CGFloat = 0
    @State private var deviceViewportHeight: CGFloat = 0
    @State private var overflowHeight: CGFloat = 0
    @State private var scrollFadeState = ScrollFadeState()
    @State private var detailHeight: CGFloat = 0
    @State private var frozenListHeight: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    private let sceneCardHeight: CGFloat = 76

    var body: some View {
        let activeHomePhoto = model.homePhoto.activeAsset(isDark: colorScheme == .dark)
        let detail = detailID.flatMap { id in model.devices.first { $0.id == id } }
        let snapshot = MenuBarViewSnapshot(
            devices: model.devices,
            entities: model.entities,
            metadata: model.homeMetadata,
            actionErrors: model.actionErrors,
            room: room,
            usesHomePhoto: activeHomePhoto?.backdrop != nil
        )
        let activeOverflowHeight = snapshot.overflowControlRows.isEmpty ? 0 : overflowHeight
        let preferredDeviceHeight = snapshot.hasDeviceSection
            ? MenuBarLayout.preferredHeight(contentHeight: deviceContentHeight, overflowHeight: activeOverflowHeight)
            : 0
        let needsDeviceScroll = snapshot.hasDeviceSection
            && MenuBarLayout.needsScroll(contentHeight: deviceContentHeight, viewportHeight: deviceViewportHeight)

        let card = Color.clear
            .frame(width: MenuBarLayout.width, height: usesExternalShadowPadding ? panelState.animatedHeight : nil)
            .frame(maxHeight: usesExternalShadowPadding ? nil : .infinity)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    topChrome(snapshot: snapshot, activeHomePhoto: activeHomePhoto)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            guard detail == nil, height > 0 else { return }
                            if topChromeHeight != height {
                                topChromeHeight = height
                                reportPreferredHeight(snapshot: snapshot, hasDetail: false)
                            }
                        }
                    if snapshot.hasDeviceSection {
                        deviceScrollSection(
                            snapshot: snapshot,
                            activeHomePhoto: activeHomePhoto,
                            preferredDeviceHeight: preferredDeviceHeight,
                            needsDeviceScroll: needsDeviceScroll,
                            hasDetail: detail != nil
                        )
                        .modifier(HomePhotoForeground(theme: activeHomePhoto?.theme))
                    }
                    bottomChrome(snapshot: snapshot, activeHomePhoto: activeHomePhoto)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            guard detail == nil, height > 0 else { return }
                            if bottomChromeHeight != height {
                                bottomChromeHeight = height
                                reportPreferredHeight(snapshot: snapshot, hasDetail: false)
                            }
                        }
                }
                .frame(
                    width: MenuBarLayout.width,
                    height: listContainerHeight(hasDetail: detail != nil),
                    alignment: .topLeading
                )
                .opacity(detail == nil ? 1 : 0)
                .allowsHitTesting(detail == nil)
                .accessibilityHidden(detail != nil)
                .animation(.easeInOut(duration: 0.25), value: detailID)
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    if let detail {
                        VStack(alignment: .leading, spacing: 18) {
                            DeviceDetailView(model: model, binding: detail) { setDetail(nil, snapshot: snapshot) }
                            footer
                        }
                        .padding(16)
                        .frame(width: MenuBarLayout.width, alignment: .topLeading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            guard self.detailID != nil, height > 0 else { return }
                            if detailHeight != height {
                                detailHeight = height
                                reportPreferredHeight(snapshot: snapshot, hasDetail: true)
                            }
                        }
                        .modifier(HomePhotoForeground(theme: activeHomePhoto?.theme))
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: detailID)
            }
            .background {
                (activeHomePhoto?.theme.surfaceColor ?? Color.clear)
                    .animation(.easeInOut(duration: 0.45), value: activeHomePhoto?.id)
                    .overlay(alignment: .top) {
                        if let photo = activeHomePhoto {
                            let detailBackdrop = photo.detailBackdrop
                            let backdropHeight = max(760, MenuBarLayout.width * detailBackdrop.size.height / max(1, detailBackdrop.size.width))
                            ZStack {
                                Image(nsImage: detailBackdrop)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: MenuBarLayout.width, height: backdropHeight, alignment: .top)
                                    .clipped()
                                    .id(photo.id)
                                    .transition(.opacity)
                            }
                            .animation(.easeInOut(duration: 0.45), value: photo.id)
                            .overlay(Color.black.opacity(0.2))
                            .frame(width: MenuBarLayout.width, height: backdropHeight, alignment: .top)
                            .opacity(detail != nil ? 1 : 0)
                            .animation(.easeInOut(duration: 0.25), value: detailID != nil)
                        }
                    }
                    .clipShape(.rect(cornerRadius: MenuBarLayout.cornerRadius, style: .continuous))
            }
            .environment(\.usesHomePhoto, activeHomePhoto?.theme != nil)
            .environment(\.homePhotoTheme, activeHomePhoto?.theme)
            .tint(activeHomePhoto?.theme.accentColor ?? .orange)
            .modifier(PanelGlassBackground(enabled: activeHomePhoto?.theme == nil))
            .environment(\.colorScheme, activeHomePhoto?.theme != nil ? .dark : colorScheme)
            .contentShape(.rect(cornerRadius: MenuBarLayout.cornerRadius, style: .continuous))

        Group {
            if usesExternalShadowPadding {
                card
                    .background {
                        if let theme = activeHomePhoto?.theme {
                            RoundedRectangle(cornerRadius: MenuBarLayout.cornerRadius, style: .continuous)
                                .fill(theme.surfaceColor)
                                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
                                .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
                                .animation(.easeInOut(duration: 0.45), value: activeHomePhoto?.id)
                        }
                    }
                    .padding(.leading, MenuBarLayout.PanelShadowInsets.leading)
                    .padding(.trailing, MenuBarLayout.PanelShadowInsets.trailing)
                    .padding(.top, MenuBarLayout.PanelShadowInsets.top)
                    .padding(.bottom, MenuBarLayout.PanelShadowInsets.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                card
            }
        }
        .onExitCommand { if detailID != nil { setDetail(nil, snapshot: snapshot) } else { closePanel() } }
        .task { await model.homePhoto.loadIfNeeded() }
        .onChange(of: model.address) { _, _ in setDetail(nil, snapshot: snapshot); room = .all }
        .onChange(of: model.devices.map(\.id)) { _, ids in if let detailID, !ids.contains(detailID) { setDetail(nil, snapshot: snapshot) } }
        .onChange(of: snapshot.areaIDs) { _, ids in if case .area(let id) = room, !ids.contains(id) { room = .all } }
        .onChange(of: snapshot.hasUnassignedControls) { _, hasUnassigned in if room == .unassigned, !hasUnassigned { room = .all } }
        .onChange(of: snapshot.hasDeviceSection) { _, visible in
            if !visible {
                deviceContentHeight = 0
                deviceViewportHeight = 0
                overflowHeight = 0
                scrollFadeState.fade = .init()
                reportPreferredHeight(snapshot: snapshot, hasDetail: detail != nil)
            }
        }
        .onChange(of: snapshot.overflowControlRows.isEmpty) { _, empty in
            if empty {
                overflowHeight = 0
                reportPreferredHeight(snapshot: snapshot, hasDetail: detail != nil)
            }
        }
        .onChange(of: needsDeviceScroll) { _, scrollable in
            if detail == nil, !scrollable { listPosition.scrollTo(edge: .top) }
        }
        .onChange(of: room) { _, _ in
            listPosition.scrollTo(edge: .top)
        }
    }

    private func listContainerHeight(hasDetail: Bool) -> CGFloat? {
        guard usesExternalShadowPadding else { return nil }
        if hasDetail {
            return frozenListHeight ?? panelState.targetHeight
        }
        return panelState.targetHeight
    }

    private func setDetail(_ id: UUID?, snapshot: MenuBarViewSnapshot) {
        if let id {
            guard let binding = model.devices.first(where: { $0.id == id }),
                  model.supportsDetails(binding) else { return }
            if detailID == nil, panelState.targetHeight > 0 {
                frozenListHeight = panelState.targetHeight
            }
            detailHeight = 0
            detailID = id
        } else {
            guard detailID != nil else { return }
            reportPreferredHeight(snapshot: snapshot, hasDetail: false)
            detailID = nil
        }
    }

    private func reportPreferredHeight(snapshot: MenuBarViewSnapshot, hasDetail: Bool) {
        if hasDetail {
            guard detailHeight > 0 else { return }
            contentHeightChanged(ceil(detailHeight))
            return
        }
        guard topChromeHeight > 0, bottomChromeHeight > 0 else { return }
        if snapshot.hasDeviceSection && deviceContentHeight <= 0 { return }
        let activeOverflow = snapshot.overflowControlRows.isEmpty ? 0 : overflowHeight
        let height = MenuBarLayout.listPreferredHeight(
            chromeHeight: topChromeHeight + bottomChromeHeight,
            deviceContentHeight: snapshot.hasDeviceSection ? deviceContentHeight : 0,
            overflowHeight: activeOverflow
        )
        if height > 0 { contentHeightChanged(height) }
    }

    private func topChrome(snapshot: MenuBarViewSnapshot, activeHomePhoto: HomePhotoStore.Asset?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let photo = activeHomePhoto {
                photoHeader(photo, scenes: snapshot.scenes, activeHomePhoto: activeHomePhoto)
            } else {
                header(activeHomePhoto: activeHomePhoto)
                if !snapshot.scenes.isEmpty { sceneStrip(scenes: snapshot.scenes, usesHomePhoto: false) }
            }
            Group {
                if model.devices.isEmpty {
                    emptyState
                } else {
                    if !snapshot.areas.isEmpty {
                        roomStrip(areas: snapshot.areas, hasUnassignedControls: snapshot.hasUnassignedControls)
                    }
                    overviewHeader(activeDeviceCount: snapshot.activeDeviceCount)
                }
            }
            .modifier(HomePhotoForeground(theme: activeHomePhoto?.theme))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, snapshot.hasDeviceSection ? MenuBarLayout.controlRowSpacing : 18)
    }

    private func bottomChrome(snapshot: MenuBarViewSnapshot, activeHomePhoto: HomePhotoStore.Asset?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = model.connectionError, model.connectionState == .offline {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6)
            }
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, snapshot.hasDeviceSection ? 18 : 0)
        .padding(.bottom, 16)
        .modifier(HomePhotoForeground(theme: activeHomePhoto?.theme))
    }

    private func photoHeader(_ photo: HomePhotoStore.Asset, scenes: [DeviceBinding], activeHomePhoto: HomePhotoStore.Asset?) -> some View {
        let image = photo.backdrop
        let transitionCenter = MenuBarLayout.width * HomePhotoProcessor.bottomTransitionRatio / 2
        return VStack(alignment: .leading, spacing: -(sceneCardHeight / 2 + transitionCenter)) {
            VStack(alignment: .leading) {
                header(activeHomePhoto: activeHomePhoto)
                    .shadow(color: .black.opacity(0.32), radius: 6, y: 1)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: MenuBarLayout.width, height: MenuBarLayout.width * image.size.height / max(1, image.size.width), alignment: .topLeading)
            .background {
                ZStack {
                    HomePhotoBackdrop(image: image)
                        .id(photo.id)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.45), value: photo.id)
            }
            if !scenes.isEmpty { sceneStrip(scenes: scenes, usesHomePhoto: true).padding(.horizontal, 16) }
        }
        .coordinateSpace(name: HomePhotoCoordinateSpace.backdrop)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, -16)
        .padding(.top, -16)
    }

    private func header(activeHomePhoto: HomePhotoStore.Asset?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.currentServerName).font(.title2.weight(.medium)).lineLimit(2)
                HStack(spacing: 7) {
                    ConnectionBadge(state: model.connectionState,
                                    textColor: activeHomePhoto?.backdrop == nil ? .secondary : .white.opacity(0.86)).font(.caption)
                    if model.isConnected {
                        Text(model.realtimeStatus == .live ? "实时同步" : "定时刷新 · 实时连接恢复中")
                            .font(.caption2).foregroundStyle(activeHomePhoto?.backdrop == nil ? Color.secondary.opacity(0.6) : Color.white.opacity(0.86))
                    }
                }
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
            }.buttonStyle(.plain).disabled(!model.canSend).help("刷新设备状态").accessibilityLabel("刷新设备状态")
        }.padding(.horizontal, 6).padding(.top, 4)
    }

    private func sceneStrip(scenes: [DeviceBinding], usesHomePhoto: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MenuBarLayout.sceneCardSpacing) {
                ForEach(scenes) { binding in
                    Button { model.run(binding.id) } label: {
                        VStack(spacing: 3) {
                            if model.busyIDs.contains(binding.id) { ProgressView().controlSize(.small).frame(height: 32) }
                            else { DeviceIconView(icon: binding.icon, fallback: "sparkles", color: binding.iconColor, size: 26).frame(height: 32) }
                            Text(binding.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                        }
                        .frame(width: MenuBarLayout.sceneCardWidth, height: sceneCardHeight)
                        .modifier(SceneCardSurface(usesHomePhoto: usesHomePhoto))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.isConnected || model.entities[binding.entityID]?.isAvailable != true || model.busyIDs.contains(binding.id))
                    .help(model.actionErrors[binding.id] ?? "执行\(binding.name)")
                    .accessibilityLabel("执行\(binding.name)")
                }
            }
            .padding(10)
        }
        .scrollDisabled(scenes.count <= MenuBarLayout.maxVisibleSceneCards)
        .padding(-10)
    }

    private func roomStrip(areas: [HAHomeMetadata.Area], hasUnassignedControls: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                roomButton("全部", selection: .all)
                ForEach(areas) { area in roomButton(area.name, selection: .area(area.id)) }
                if hasUnassignedControls {
                    roomButton("未分组", selection: .unassigned)
                }
            }
        }
    }
    private func roomButton(_ title: String, selection: MenuBarRoom) -> some View {
        Button { room = selection } label: {
            Text(title).font(.callout.weight(room == selection ? .medium : .regular)).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.primary.opacity(room == selection ? 0.12 : 0), in: .capsule)
                .contentShape(.capsule)
        }.buttonStyle(.plain).accessibilityAddTraits(room == selection ? .isSelected : [])
    }

    private func overviewHeader(activeDeviceCount: Int) -> some View {
        HStack {
            Text(roomTitle).font(.headline.weight(.medium))
            Text("\(activeDeviceCount) 个开启")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func deviceScrollSection(
        snapshot: MenuBarViewSnapshot,
        activeHomePhoto: HomePhotoStore.Asset?,
        preferredDeviceHeight: CGFloat,
        needsDeviceScroll: Bool,
        hasDetail: Bool
    ) -> some View {
        let fadeHeight = min(MenuBarLayout.ScrollEdgeFade.fadeLength, max(0, deviceViewportHeight / 3))
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: MenuBarLayout.controlRowSpacing) {
                if !snapshot.visibleControlRows.isEmpty {
                    VStack(alignment: .leading, spacing: MenuBarLayout.controlRowSpacing) {
                        ForEach(snapshot.visibleControlRows) { row in
                            controlRowView(row, snapshot: snapshot)
                        }
                    }
                }
                if !snapshot.overflowControlRows.isEmpty {
                    VStack(alignment: .leading, spacing: MenuBarLayout.controlRowSpacing) {
                        ForEach(snapshot.overflowControlRows) { row in
                            controlRowView(row, snapshot: snapshot)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard !hasDetail, height > 0 else { return }
                        if overflowHeight != height {
                            overflowHeight = height
                            reportPreferredHeight(snapshot: snapshot, hasDetail: false)
                        }
                    }
                }
                if snapshot.showsEmptyRoomHint {
                    Text("这个房间还没有添加设备。")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                }
                ForEach(snapshot.sceneErrors) { binding in
                    Label("\(binding.name)：\(model.actionErrors[binding.id] ?? "")", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .frame(width: MenuBarLayout.width, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard !hasDetail, height > 0 else { return }
                if deviceContentHeight != height {
                    deviceContentHeight = height
                    reportPreferredHeight(snapshot: snapshot, hasDetail: false)
                }
            }
        }
        .scrollPosition($listPosition)
        .defaultScrollAnchor(.top)
        .scrollIndicators(needsDeviceScroll ? .automatic : .hidden)
        .scrollDisabled(!needsDeviceScroll)
        .frame(
            idealHeight: preferredDeviceHeight > 0 ? preferredDeviceHeight : nil,
            maxHeight: preferredDeviceHeight > 0 ? preferredDeviceHeight : nil
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            guard !hasDetail else { return }
            if deviceViewportHeight != height {
                deviceViewportHeight = height
            }
        }
        .onScrollGeometryChange(for: MenuBarLayout.ScrollEdgeFade.self) { geometry in
            MenuBarLayout.ScrollEdgeFade.calculate(
                contentOffsetY: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                viewportHeight: geometry.containerSize.height,
                topInset: geometry.contentInsets.top,
                bottomInset: geometry.contentInsets.bottom
            )
        } action: { _, newValue in
            guard !hasDetail else { return }
            if scrollFadeState.fade != newValue {
                scrollFadeState.fade = newValue
            }
        }
        .modifier(ScrollEdgeFadeModifier(
            state: scrollFadeState,
            enabled: needsDeviceScroll,
            surfaceColor: activeHomePhoto?.theme.surfaceColor,
            fadeHeight: fadeHeight
        ))
    }

    @ViewBuilder
    private func controlRowView(_ row: MenuBarControlRow, snapshot: MenuBarViewSnapshot) -> some View {
        switch row {
        case .climate(let binding):
            ClimateDeviceCard(model: model, binding: binding) { setDetail(binding.id, snapshot: snapshot) }
        case .pair(let first, let second):
            HStack(alignment: .top, spacing: 10) {
                compactDeviceCard(first, snapshot: snapshot)
                    .frame(maxWidth: .infinity)
                if let second {
                    compactDeviceCard(second, snapshot: snapshot)
                        .frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(height: 1).frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func compactDeviceCard(_ binding: DeviceBinding, snapshot: MenuBarViewSnapshot) -> some View {
        if model.entities[binding.entityID]?.domain == "light" {
            LightDeviceCard(model: model, binding: binding) { setDetail(binding.id, snapshot: snapshot) }
        } else {
            OtherDeviceCard(model: model, binding: binding)
        }
    }
    private var roomTitle: String {
        switch room {
        case .all: "全部设备"
        case .unassigned: "未分组"
        case .area(let id): model.homeMetadata.areas.first(where: { $0.id == id })?.name ?? "设备"
        }
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("还没有添加设备").font(.headline.weight(.medium))
            Text(model.isConnected ? "添加常用设备，即可在这里快速控制。" : "先在设置中连接 Home Assistant。")
                .font(.callout).foregroundStyle(.secondary)
            Button(model.isConnected ? "添加设备" : "打开设置") { showSettings(model.isConnected ? .devices : .settings) }
                .buttonStyle(.bordered)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 22)
    }
    private var footer: some View {
        HStack(spacing: 14) {
            Button { showSettings(.settings) } label: { Label("设置", systemImage: "gearshape") }
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label("退出", systemImage: "power") }
                .help("退出 HALink").accessibilityLabel("退出 HALink")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .tint(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

enum MenuBarRoom: Hashable { case all, area(String), unassigned }

struct MenuBarRoomFilter {
    let allControls: [DeviceBinding]
    let metadata: HAHomeMetadata
    let areaIDs: Set<String>
    let areas: [HAHomeMetadata.Area]
    let hasUnassigned: Bool

    init(devices: [DeviceBinding], entities: [String: HAEntity], metadata: HAHomeMetadata) {
        var seen: Set<String> = []
        let controls = devices.filter { binding in
            let domain = entities[binding.entityID]?.domain ?? ""
            if ["scene", "script"].contains(domain) { return false }
            if ["light", "climate"].contains(domain), !seen.insert(binding.entityID).inserted { return false }
            return true
        }
        self.allControls = controls
        self.metadata = metadata
        let ids = Set(controls.compactMap { metadata.areaID(for: $0.entityID) })
        self.areaIDs = ids
        self.areas = metadata.areas
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.hasUnassigned = controls.contains { metadata.areaID(for: $0.entityID) == nil }
    }

    func controls(in room: MenuBarRoom) -> [DeviceBinding] {
        switch room {
        case .all: allControls
        case .area(let id): allControls.filter { metadata.areaID(for: $0.entityID) == id }
        case .unassigned: allControls.filter { metadata.areaID(for: $0.entityID) == nil }
        }
    }
}

enum MenuBarControlRow: Identifiable, Equatable {
    case climate(DeviceBinding)
    case pair(DeviceBinding, DeviceBinding?)

    var id: String {
        switch self {
        case .climate(let binding): "climate:\(binding.id.uuidString)"
        case .pair(let first, let second): "pair:\(first.id.uuidString):\(second?.id.uuidString ?? "")"
        }
    }

    static func makeRows(climates: [DeviceBinding], lights: [DeviceBinding], others: [DeviceBinding]) -> [Self] {
        var rows: [Self] = climates.map(Self.climate)
        let compact = lights + others
        for index in stride(from: 0, to: compact.count, by: 2) {
            let second = index + 1 < compact.count ? compact[index + 1] : nil
            rows.append(.pair(compact[index], second))
        }
        return rows
    }
}

private struct MenuBarViewSnapshot {
    let scenes: [DeviceBinding]
    let areaIDs: Set<String>
    let areas: [HAHomeMetadata.Area]
    let hasUnassignedControls: Bool
    let visibleControlRows: [MenuBarControlRow]
    let overflowControlRows: [MenuBarControlRow]
    let sceneErrors: [DeviceBinding]
    let showsEmptyRoomHint: Bool
    let hasDeviceSection: Bool
    let activeDeviceCount: Int

    init(
        devices: [DeviceBinding],
        entities: [String: HAEntity],
        metadata: HAHomeMetadata,
        actionErrors: [UUID: String],
        room: MenuBarRoom,
        usesHomePhoto: Bool
    ) {
        let scenes = devices.filter { ["scene", "script"].contains(entities[$0.entityID]?.domain ?? "") }
        let roomFilter = MenuBarRoomFilter(devices: devices, entities: entities, metadata: metadata)
        let controls = roomFilter.controls(in: room)
        var climates: [DeviceBinding] = []
        var lights: [DeviceBinding] = []
        var others: [DeviceBinding] = []
        var activeCount = 0
        for binding in controls {
            let entity = entities[binding.entityID]
            if entity?.powerState == true { activeCount += 1 }
            switch entity?.domain {
            case "climate": climates.append(binding)
            case "light": lights.append(binding)
            default: others.append(binding)
            }
        }
        let rows = MenuBarControlRow.makeRows(climates: climates, lights: lights, others: others)
        let maxVisible = MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: usesHomePhoto)
        let sceneErrors = scenes.filter { actionErrors[$0.id] != nil }
        let showsEmptyRoomHint = controls.isEmpty && !devices.isEmpty && scenes.isEmpty

        self.scenes = scenes
        self.areaIDs = roomFilter.areaIDs
        self.areas = roomFilter.areas
        self.hasUnassignedControls = roomFilter.hasUnassigned
        self.visibleControlRows = Array(rows.prefix(maxVisible))
        self.overflowControlRows = Array(rows.dropFirst(maxVisible))
        self.sceneErrors = sceneErrors
        self.showsEmptyRoomHint = showsEmptyRoomHint
        self.hasDeviceSection = !devices.isEmpty && (!rows.isEmpty || showsEmptyRoomHint || !sceneErrors.isEmpty)
        self.activeDeviceCount = activeCount
    }
}

@Observable
private final class ScrollFadeState {
    var fade = MenuBarLayout.ScrollEdgeFade()
}

private struct PanelGlassBackground: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .clipShape(.rect(cornerRadius: MenuBarLayout.cornerRadius, style: .continuous))
                .glassEffect(.regular, in: .rect(cornerRadius: MenuBarLayout.cornerRadius))
        } else {
            content.clipShape(.rect(cornerRadius: MenuBarLayout.cornerRadius, style: .continuous))
        }
    }
}

private struct SceneCardSurface: ViewModifier {
    let usesHomePhoto: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if usesHomePhoto {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                .contentShape(.rect(cornerRadius: 20))
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial.materialActiveAppearance(.active))
                        .opacity(0.4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.09), lineWidth: 1)
                }
                .contentShape(.rect(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct HomePhotoForeground: ViewModifier {
    let theme: HomePhotoProcessor.Theme?

    func body(content: Content) -> some View {
        if let theme {
            content
                .foregroundStyle(theme.primaryTextColor, theme.secondaryTextColor)
                .animation(.easeInOut(duration: 0.45), value: theme)
        } else {
            content
        }
    }
}

private struct ScrollEdgeFadeModifier: ViewModifier {
    let state: ScrollFadeState
    let enabled: Bool
    let surfaceColor: Color?
    let fadeHeight: CGFloat

    func body(content: Content) -> some View {
        if let surfaceColor {
            content.overlay {
                ScrollEdgeFadeOverlay(
                    state: state,
                    enabled: enabled,
                    color: surfaceColor,
                    fadeHeight: fadeHeight
                )
            }
        } else {
            content.mask {
                ScrollEdgeFadeMask(
                    state: state,
                    enabled: enabled,
                    fadeHeight: fadeHeight
                )
            }
        }
    }
}

private struct ScrollEdgeFadeOverlay: View {
    let state: ScrollFadeState
    let enabled: Bool
    let color: Color
    let fadeHeight: CGFloat

    var body: some View {
        let fade = enabled ? state.fade : .init()
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: color, location: 0),
                    .init(color: color.opacity(0.65), location: 0.35),
                    .init(color: color.opacity(0.22), location: 0.7),
                    .init(color: color.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            .opacity(fadeHeight > 0 ? fade.top : 0)
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: color.opacity(0), location: 0),
                    .init(color: color.opacity(0.22), location: 0.3),
                    .init(color: color.opacity(0.65), location: 0.65),
                    .init(color: color, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: fadeHeight)
            .opacity(fadeHeight > 0 ? fade.bottom : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScrollEdgeFadeMask: View {
    let state: ScrollFadeState
    let enabled: Bool
    let fadeHeight: CGFloat

    var body: some View {
        let fade = enabled ? state.fade : .init()
        VStack(spacing: 0) {
            if fade.top > 0, fadeHeight > 0 {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(1 - fade.top), location: 0),
                        .init(color: .black.opacity(1 - fade.top * 0.65), location: 0.35),
                        .init(color: .black.opacity(1 - fade.top * 0.22), location: 0.7),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
            Color.black
            if fade.bottom > 0, fadeHeight > 0 {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(1 - fade.bottom * 0.22), location: 0.3),
                        .init(color: .black.opacity(1 - fade.bottom * 0.65), location: 0.65),
                        .init(color: .black.opacity(1 - fade.bottom), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
        }
    }
}
