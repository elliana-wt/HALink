import AppKit
import CoreGraphics
import HALinkCore
import SwiftUI
import Testing
@testable import HALink

@Suite("菜单栏面板布局与滚动")
struct MenuBarLayoutTests {
    @Test func groupsControlsIntoExpectedRowCount() {
        let climate = DeviceBinding(entityID: "climate.living", name: "起居室空调", action: .toggle)
        let lights = (1...7).map { DeviceBinding(entityID: "light.lamp_\($0)", name: "灯 \($0)", action: .toggle) }
        let curtain = DeviceBinding(entityID: "cover.curtain", name: "窗帘", action: .open)
        let coffee = DeviceBinding(entityID: "switch.coffee", name: "咖啡机", action: .toggle)

        // 1 climate + 2 lights = 2 rows
        let twoRows = MenuBarControlRow.makeRows(climates: [climate], lights: Array(lights.prefix(2)), others: [])
        #expect(twoRows.count == 2)
        #expect(twoRows.dropFirst(MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: true)).isEmpty)

        // 1 climate + 1 light + 1 other = 2 rows (non-climate devices share 2-column grid)
        let mixedTwoRows = MenuBarControlRow.makeRows(climates: [climate], lights: [lights[0]], others: [curtain])
        #expect(mixedTwoRows == [.climate(climate), .pair(lights[0], curtain)])

        // 1 climate + 2 lights + 2 others = 3 rows
        let threeRows = MenuBarControlRow.makeRows(climates: [climate], lights: Array(lights.prefix(2)), others: [curtain, coffee])
        #expect(threeRows == [.climate(climate), .pair(lights[0], lights[1]), .pair(curtain, coffee)])

        // 1 climate + 5 lights + 1 other = 4 rows (1 + 3 full pairs)
        let fourRows = MenuBarControlRow.makeRows(climates: [climate], lights: Array(lights.prefix(5)), others: [curtain])
        #expect(fourRows.count == 4)
        #expect(fourRows.dropFirst(MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: true)).isEmpty)

        // 1 climate + 6 lights + 1 other = 5 rows (1 overflow row with home photo, 0 without)
        let fiveRows = MenuBarControlRow.makeRows(climates: [climate], lights: Array(lights.prefix(6)), others: [curtain])
        #expect(fiveRows.count == 5)
        #expect(fiveRows.dropFirst(MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: true)).count == 1)
        #expect(fiveRows.dropFirst(MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: false)).isEmpty)

        // 1 climate + 7 lights = 5 rows (1 + 4, 1 overflow row with home photo)
        let fiveWithOddLight = MenuBarControlRow.makeRows(climates: [climate], lights: lights, others: [])
        #expect(fiveWithOddLight.count == 5)
        #expect(fiveWithOddLight.dropFirst(MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: true)).count == 1)

        // Without home photo, up to 8 rows fit without scrolling; 9 rows has 1 overflow row
        let moreLights = (1...16).map { DeviceBinding(entityID: "light.lamp_\($0)", name: "灯 \($0)", action: .toggle) }
        let eightRows = MenuBarControlRow.makeRows(climates: [], lights: moreLights, others: [])
        #expect(eightRows.count == 8)
        #expect(eightRows.dropFirst(MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: false)).isEmpty)

        let nineRows = MenuBarControlRow.makeRows(climates: [climate], lights: moreLights, others: [])
        #expect(nineRows.count == 9)
        #expect(nineRows.dropFirst(MenuBarLayout.maxUnscrolledControlRows(usesHomePhoto: false)).count == 1)
    }

    @Test func expandsWithoutScrollWhenUpToFourRowsFitOnScreen() {
        // With home photo + 2 rows (~840pt) or 4 rows (~1004pt), should not be capped at 780pt.
        for contentHeight: CGFloat in [620, 839.4, 1004.2] {
            let preferred = MenuBarLayout.preferredHeight(contentHeight: contentHeight, overflowHeight: 0)
            let panel = MenuBarLayout.panelHeight(preferredHeight: preferred, availableHeight: 1252)
            #expect(panel == ceil(contentHeight))
            #expect(!MenuBarLayout.needsScroll(contentHeight: contentHeight, viewportHeight: panel))
        }
    }

    @Test func capsAtFourRowHeightAndEnablesScrollBeyondFourRows() {
        // 5 rows = 4 rows (1004pt) + 12pt spacing + 70pt 5th row = 1086pt
        let contentHeight: CGFloat = 1086
        let overflowHeight: CGFloat = 70
        let preferred = MenuBarLayout.preferredHeight(contentHeight: contentHeight, overflowHeight: overflowHeight)
        let panel = MenuBarLayout.panelHeight(preferredHeight: preferred, availableHeight: 1252)
        #expect(panel == 1004)
        #expect(MenuBarLayout.needsScroll(contentHeight: contentHeight, viewportHeight: panel))
    }

    @Test func clampsToScreenHeightAndEnablesScrollWhenScreenIsShort() {
        let contentHeight: CGFloat = 1004
        let preferred = MenuBarLayout.preferredHeight(contentHeight: contentHeight, overflowHeight: 0)
        let panel = MenuBarLayout.panelHeight(preferredHeight: preferred, availableHeight: 830)
        #expect(panel == 830)
        #expect(MenuBarLayout.needsScroll(contentHeight: contentHeight, viewportHeight: panel))
    }

    @Test func scrollsOnlyDeviceSectionWhenChromeIsFixed() {
        let chromeHeight: CGFloat = 580
        // 4 rows fit without scrolling in the device section
        let fourRowsHeight: CGFloat = 316
        let preferredFour = MenuBarLayout.listPreferredHeight(
            chromeHeight: chromeHeight,
            deviceContentHeight: fourRowsHeight,
            overflowHeight: 0
        )
        #expect(preferredFour == 896)
        let panelFour = MenuBarLayout.panelHeight(preferredHeight: preferredFour, availableHeight: 1200)
        let viewportFour = MenuBarLayout.deviceViewportHeight(panelHeight: panelFour, chromeHeight: chromeHeight)
        #expect(viewportFour == 316)
        #expect(!MenuBarLayout.needsScroll(contentHeight: fourRowsHeight, viewportHeight: viewportFour))

        // 5 rows keep panel at 4-row height and scroll only inside the device section
        let fiveRowsHeight: CGFloat = 398
        let overflowHeight: CGFloat = 70
        let preferredFive = MenuBarLayout.listPreferredHeight(
            chromeHeight: chromeHeight,
            deviceContentHeight: fiveRowsHeight,
            overflowHeight: overflowHeight
        )
        #expect(preferredFive == 896)
        let panelFive = MenuBarLayout.panelHeight(preferredHeight: preferredFive, availableHeight: 1200)
        let viewportFive = MenuBarLayout.deviceViewportHeight(panelHeight: panelFive, chromeHeight: chromeHeight)
        #expect(viewportFive == 316)
        #expect(MenuBarLayout.needsScroll(contentHeight: fiveRowsHeight, viewportHeight: viewportFive))

        // On a shorter screen, chrome stays fixed and the device viewport shrinks to scroll
        let shortPanel = MenuBarLayout.panelHeight(preferredHeight: preferredFour, availableHeight: 780)
        let shortViewport = MenuBarLayout.deviceViewportHeight(panelHeight: shortPanel, chromeHeight: chromeHeight)
        #expect(shortViewport == 200)
        #expect(MenuBarLayout.needsScroll(contentHeight: fourRowsHeight, viewportHeight: shortViewport))
    }

    @Test func computesScrollEdgeFadeForTopMiddleBottomAndNonScrollingLists() {
        let nonScrolling = MenuBarLayout.ScrollEdgeFade.calculate(
            contentOffsetY: 0,
            contentHeight: 300,
            viewportHeight: 300,
            fadeLength: 26
        )
        #expect(nonScrolling == .init(top: 0, bottom: 0))

        let atTop = MenuBarLayout.ScrollEdgeFade.calculate(
            contentOffsetY: 0,
            contentHeight: 500,
            viewportHeight: 300,
            fadeLength: 26
        )
        #expect(atTop == .init(top: 0, bottom: 1))

        let partiallyScrolled = MenuBarLayout.ScrollEdgeFade.calculate(
            contentOffsetY: 13,
            contentHeight: 500,
            viewportHeight: 300,
            fadeLength: 26
        )
        #expect(partiallyScrolled == .init(top: 0.5, bottom: 1))

        let inMiddle = MenuBarLayout.ScrollEdgeFade.calculate(
            contentOffsetY: 100,
            contentHeight: 500,
            viewportHeight: 300,
            fadeLength: 26
        )
        #expect(inMiddle == .init(top: 1, bottom: 1))

        let nearBottom = MenuBarLayout.ScrollEdgeFade.calculate(
            contentOffsetY: 187,
            contentHeight: 500,
            viewportHeight: 300,
            fadeLength: 26
        )
        #expect(nearBottom == .init(top: 1, bottom: 0.5))

        let atBottom = MenuBarLayout.ScrollEdgeFade.calculate(
            contentOffsetY: 200,
            contentHeight: 500,
            viewportHeight: 300,
            fadeLength: 26
        )
        #expect(atBottom == .init(top: 1, bottom: 0))

        let overscrolledTop = MenuBarLayout.ScrollEdgeFade.calculate(
            contentOffsetY: -20,
            contentHeight: 500,
            viewportHeight: 300,
            fadeLength: 26
        )
        #expect(overscrolledTop == .init(top: 0, bottom: 1))
    }

    @Test @MainActor func returningFromDetailRestoresPanelAndDeviceViewportHeight() async throws {
        struct LayoutHarness: View {
            var nav: DetailNavigationState
            let contentHeightChanged: (CGFloat) -> Void
            let viewportChanged: (CGFloat) -> Void
            let detailMinYChanged: (CGFloat) -> Void
            @State private var detailID: UUID?
            @State private var listPosition = ScrollPosition()
            @State private var topChromeHeight: CGFloat = 0
            @State private var bottomChromeHeight: CGFloat = 0
            @State private var deviceContentHeight: CGFloat = 0
            @State private var deviceViewportHeight: CGFloat = 0
            @State private var detailHeight: CGFloat = 0

            private var preferredDeviceHeight: CGFloat {
                MenuBarLayout.preferredHeight(contentHeight: deviceContentHeight, overflowHeight: 0)
            }
            private var needsDeviceScroll: Bool {
                MenuBarLayout.needsScroll(contentHeight: deviceContentHeight, viewportHeight: deviceViewportHeight)
            }

            var body: some View {
                Color.clear
                    .frame(width: MenuBarLayout.width)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.red.frame(height: 630)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    guard detailID == nil, height > 0 else { return }
                                    topChromeHeight = height
                                    reportPreferredHeight()
                                }
                            ScrollView(.vertical) {
                                VStack(alignment: .leading, spacing: MenuBarLayout.controlRowSpacing) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Color.green.frame(height: 70)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(width: MenuBarLayout.width, alignment: .topLeading)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    guard detailID == nil, height > 0 else { return }
                                    deviceContentHeight = height
                                    reportPreferredHeight()
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
                                guard detailID == nil else { return }
                                deviceViewportHeight = height
                                viewportChanged(height)
                            }
                            Color.purple.frame(height: 57)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    guard detailID == nil, height > 0 else { return }
                                    bottomChromeHeight = height
                                    reportPreferredHeight()
                                }
                        }
                        .frame(width: MenuBarLayout.width, alignment: .topLeading)
                        .opacity(detailID == nil ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: detailID)
                    }
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            if detailID != nil {
                                VStack(alignment: .leading, spacing: 18) {
                                    Color.blue.frame(height: 500)
                                    Color.gray.frame(height: 30)
                                }
                                .padding(16)
                                .frame(width: MenuBarLayout.width, alignment: .topLeading)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("panel")) } action: { rect in
                                    guard detailID != nil, rect.height > 0 else { return }
                                    detailHeight = rect.height
                                    detailMinYChanged(rect.minY)
                                    reportPreferredHeight()
                                }
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: detailID)
                    }
                    .coordinateSpace(name: "panel")
                    .onChange(of: needsDeviceScroll) { _, scrollable in
                        if detailID == nil, !scrollable { listPosition.scrollTo(edge: .top) }
                    }
                    .onChange(of: detailID) { _, newID in
                        if newID == nil {
                            reportPreferredHeight()
                        } else {
                            detailHeight = 0
                        }
                    }
                    .onChange(of: nav.detailID) { _, newValue in
                        detailID = newValue
                    }
            }

            private func reportPreferredHeight() {
                if detailID != nil {
                    guard detailHeight > 0 else { return }
                    contentHeightChanged(ceil(detailHeight))
                    return
                }
                guard topChromeHeight > 0, bottomChromeHeight > 0, deviceContentHeight > 0 else { return }
                let height = MenuBarLayout.listPreferredHeight(
                    chromeHeight: topChromeHeight + bottomChromeHeight,
                    deviceContentHeight: deviceContentHeight,
                    overflowHeight: 0
                )
                if height > 0 { contentHeightChanged(height) }
            }
        }

        let nav = DetailNavigationState()
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: MenuBarLayout.width, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        var targetFrame: NSRect?
        var latestViewport: CGFloat = 0
        var latestDetailMinY: CGFloat = -1
        let host = NSHostingController(rootView: LayoutHarness(
            nav: nav,
            contentHeightChanged: { height in
                let clamped = MenuBarLayout.panelHeight(preferredHeight: height, availableHeight: 1100)
                let frame = NSRect(x: 100, y: 1150 - clamped, width: MenuBarLayout.width, height: clamped)
                guard targetFrame != frame else { return }
                targetFrame = frame
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.allowsImplicitAnimation = true
                    panel.animator().setFrame(frame, display: true)
                }
            },
            viewportChanged: { latestViewport = $0 },
            detailMinYChanged: { latestDetailMinY = $0 }
        ))
        host.sceneBridgingOptions = .all
        host.sizingOptions = []
        panel.contentViewController = host
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }

        try await Task.sleep(for: .milliseconds(400))
        let initialHeight = panel.frame.height
        #expect(initialHeight == 921)
        #expect(latestViewport == 234)

        nav.detailID = UUID()
        try await Task.sleep(for: .milliseconds(450))
        #expect(panel.frame.height == 580)
        #expect(latestDetailMinY == 0)

        nav.detailID = nil
        try await Task.sleep(for: .milliseconds(450))
        #expect(panel.frame.height == initialHeight)
        #expect(latestViewport == 234)
    }

    @Test func switchOnlyDevicesDoNotOpenDetailPage() throws {
        let onOffLight = try decodeEntity(#"{"entity_id":"light.hall","state":"on","attributes":{"supported_color_modes":["onoff"]}}"#)
        let dimmableLight = try decodeEntity(#"{"entity_id":"light.desk","state":"on","attributes":{"supported_color_modes":["brightness"],"brightness":128}}"#)
        let colorTempLight = try decodeEntity(#"{"entity_id":"light.ceiling","state":"on","attributes":{"supported_color_modes":["color_temp"],"min_color_temp_kelvin":2700,"max_color_temp_kelvin":6500}}"#)
        let rgbLight = try decodeEntity(#"{"entity_id":"light.strip","state":"on","attributes":{"supported_color_modes":["hs"]}}"#)
        let plainSwitch = try decodeEntity(#"{"entity_id":"switch.coffee","state":"off","attributes":{}}"#)
        let onOffClimate = try decodeEntity(#"{"entity_id":"climate.simple","state":"off","attributes":{"supported_features":384}}"#)
        let fullClimate = try decodeEntity(#"{"entity_id":"climate.living","state":"heat","attributes":{"supported_features":1,"min_temp":16,"max_temp":30,"temperature":24,"hvac_modes":["off","heat","cool"]}}"#)

        let services: Set<String> = ["light.turn_on", "light.turn_off", "switch.turn_on", "switch.turn_off", "climate.turn_on", "climate.turn_off", "climate.set_temperature", "climate.set_hvac_mode"]

        #expect(!AppModel.supportsDetails(for: onOffLight, services: services))
        #expect(AppModel.supportsDetails(for: dimmableLight, services: services))
        #expect(AppModel.supportsDetails(for: colorTempLight, services: services))
        #expect(AppModel.supportsDetails(for: rgbLight, services: services))
        #expect(!AppModel.supportsDetails(for: dimmableLight, services: ["light.turn_off"]))
        #expect(!AppModel.supportsDetails(for: plainSwitch, services: services))
        #expect(!AppModel.supportsDetails(for: onOffClimate, services: services))
        #expect(AppModel.supportsDetails(for: fullClimate, services: services))
    }

    @Test func roomFilterExcludesScenesAndScriptsFromAreasAndUnassigned() throws {
        let light = DeviceBinding(entityID: "light.living", name: "客厅灯", action: .toggle)
        let unassignedLight = DeviceBinding(entityID: "light.desk", name: "台灯", action: .toggle)
        let script = DeviceBinding(entityID: "script.cozy_night", name: "氛围夜晚", action: .turnOn)
        let scene = DeviceBinding(entityID: "scene.bedroom_sleep", name: "睡眠场景", action: .turnOn)

        let entities: [String: HAEntity] = [
            light.entityID: try decodeEntity(#"{"entity_id":"light.living","state":"on","attributes":{}}"#),
            unassignedLight.entityID: try decodeEntity(#"{"entity_id":"light.desk","state":"off","attributes":{}}"#),
            script.entityID: try decodeEntity(#"{"entity_id":"script.cozy_night","state":"off","attributes":{}}"#),
            scene.entityID: try decodeEntity(#"{"entity_id":"scene.bedroom_sleep","state":"scening","attributes":{}}"#)
        ]

        var metadata = HAHomeMetadata()
        metadata.areas = try JSONDecoder().decode([HAHomeMetadata.Area].self, from: Data(#"""
            [{"area_id":"living","name":"客厅"},{"area_id":"bedroom","name":"卧室"}]
            """#.utf8))
        metadata.entities = try JSONDecoder().decode([HAHomeMetadata.Entity].self, from: Data(#"""
            [
                {"entity_id":"light.living","area_id":"living","device_id":null},
                {"entity_id":"light.desk","area_id":null,"device_id":null},
                {"entity_id":"script.cozy_night","area_id":null,"device_id":null},
                {"entity_id":"scene.bedroom_sleep","area_id":"bedroom","device_id":null}
            ]
            """#.utf8))

        // Only assigned control + unassigned script + bedroom scene:
        // neither "未分组" nor empty "卧室" tab should appear.
        let withoutUnassignedControl = MenuBarRoomFilter(
            devices: [light, script, scene],
            entities: entities,
            metadata: metadata
        )
        #expect(withoutUnassignedControl.areas.map(\.id) == ["living"])
        #expect(!withoutUnassignedControl.hasUnassigned)
        #expect(withoutUnassignedControl.controls(in: .unassigned).isEmpty)

        // Adding an unassigned control should show "未分组" and return it under .unassigned.
        let withUnassignedControl = MenuBarRoomFilter(
            devices: [light, unassignedLight, script, scene],
            entities: entities,
            metadata: metadata
        )
        #expect(withUnassignedControl.areas.map(\.id) == ["living"])
        #expect(withUnassignedControl.hasUnassigned)
        #expect(withUnassignedControl.controls(in: .unassigned) == [unassignedLight])
    }

    private func decodeEntity(_ json: String) throws -> HAEntity {
        try JSONDecoder().decode(HAEntity.self, from: Data(json.utf8))
    }
}

@Observable private final class DetailNavigationState { var detailID: UUID? = nil }
