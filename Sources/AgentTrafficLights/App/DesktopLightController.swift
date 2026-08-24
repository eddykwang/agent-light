import AgentTrafficLightsCore
import AppKit
import Combine
import QuartzCore
import SwiftUI

enum DesktopLightResizeCorner {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

enum DesktopLightLayout {
    static let verticalContentSize = NSSize(width: 50, height: 126)
    static let horizontalContentSize = NSSize(width: 126, height: 50)
    static let windowPadding: CGFloat = 8
    static let screenMargin: CGFloat = 14

    static func contentSize(for orientation: TrafficLightOrientation) -> NSSize {
        orientation == .vertical ? verticalContentSize : horizontalContentSize
    }

    static func windowSize(
        for orientation: TrafficLightOrientation,
        scale: CGFloat = CGFloat(DesktopLightScaleLimits.defaultValue)
    ) -> NSSize {
        let contentSize = contentSize(for: orientation)
        let scale = clampedScale(scale)
        return NSSize(
            width: (contentSize.width + windowPadding * 2) * scale,
            height: (contentSize.height + windowPadding * 2) * scale
        )
    }

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        CGFloat(DesktopLightScaleLimits.clamped(Double(scale)))
    }

    static func scale(for size: NSSize, orientation: TrafficLightOrientation) -> CGFloat {
        let baseSize = windowSize(for: orientation)
        return clampedScale(min(size.width / baseSize.width, size.height / baseSize.height))
    }

    static func contentSafetyScale(for scale: CGFloat) -> CGFloat {
        let minimumCompensation = min(max((0.85 - clampedScale(scale)) / 0.10, 0), 1)
        return 1 - minimumCompensation * 0.02
    }

    static func resizedFrame(
        from initialFrame: NSRect,
        corner: DesktopLightResizeCorner,
        dragDelta: NSPoint,
        orientation: TrafficLightOrientation
    ) -> NSRect {
        let baseSize = windowSize(for: orientation)
        let horizontalDelta = corner == .bottomLeft || corner == .topLeft
            ? -dragDelta.x
            : dragDelta.x
        let verticalDelta = corner == .bottomLeft || corner == .bottomRight
            ? -dragDelta.y
            : dragDelta.y
        let proposedWidth = initialFrame.width + horizontalDelta
        let proposedHeight = initialFrame.height + verticalDelta
        let denominator = baseSize.width * baseSize.width + baseSize.height * baseSize.height
        let projectedScale = (
            proposedWidth * baseSize.width + proposedHeight * baseSize.height
        ) / denominator
        let newSize = windowSize(for: orientation, scale: projectedScale)

        let origin: NSPoint
        switch corner {
        case .bottomLeft:
            origin = NSPoint(x: initialFrame.maxX - newSize.width, y: initialFrame.maxY - newSize.height)
        case .bottomRight:
            origin = NSPoint(x: initialFrame.minX, y: initialFrame.maxY - newSize.height)
        case .topLeft:
            origin = NSPoint(x: initialFrame.maxX - newSize.width, y: initialFrame.minY)
        case .topRight:
            origin = initialFrame.origin
        }
        return NSRect(origin: origin, size: newSize)
    }

    static func defaultOrigin(for size: NSSize, in visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.maxX - size.width - 22,
            y: visibleFrame.maxY - size.height - 22
        )
    }

    static func clampedOrigin(
        _ origin: NSPoint,
        size: NSSize,
        visibleFrames: [NSRect],
        margin: CGFloat = screenMargin
    ) -> NSPoint {
        guard let fallbackFrame = visibleFrames.first else { return origin }

        let candidate = NSRect(origin: origin, size: size)
        let targetFrame = visibleFrames
            .map { ($0, intersectionArea(candidate, $0)) }
            .max { $0.1 < $1.1 }
            .flatMap { $0.1 > 0 ? $0.0 : nil }
            ?? fallbackFrame

        let minX = targetFrame.minX + margin
        let maxX = max(minX, targetFrame.maxX - size.width - margin)
        let minY = targetFrame.minY + margin
        let maxY = max(minY, targetFrame.maxY - size.height - margin)

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    static func adjacentPanelOrigin(
        panelSize: NSSize,
        anchorFrame: NSRect,
        visibleFrames: [NSRect],
        gap: CGFloat = 10,
        margin: CGFloat = 8
    ) -> NSPoint {
        guard let fallbackFrame = visibleFrames.first else { return anchorFrame.origin }
        let targetFrame = visibleFrames
            .map { ($0, intersectionArea(anchorFrame, $0)) }
            .max { $0.1 < $1.1 }
            .flatMap { $0.1 > 0 ? $0.0 : nil }
            ?? fallbackFrame

        let rightX = anchorFrame.maxX + gap
        let leftX = anchorFrame.minX - panelSize.width - gap
        let x: CGFloat
        if rightX + panelSize.width <= targetFrame.maxX - margin {
            x = rightX
        } else if leftX >= targetFrame.minX + margin {
            x = leftX
        } else {
            let minX = targetFrame.minX + margin
            let maxX = max(minX, targetFrame.maxX - panelSize.width - margin)
            x = min(max(anchorFrame.midX - panelSize.width / 2, minX), maxX)
        }

        let centeredY = anchorFrame.midY - panelSize.height / 2
        let minY = targetFrame.minY + margin
        let maxY = max(minY, targetFrame.maxY - panelSize.height - margin)
        let y = min(max(centeredY, minY), maxY)
        return NSPoint(x: x, y: y)
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

@MainActor
final class DesktopLightController {
    var onOpenStatusPanel: ((NSRect) -> Void)?

    private let store: StatusStore
    private let settings: AppSettings
    private let interaction = DesktopLightInteractionModel()
    private var panel: DesktopLightPanel?
    private var hideTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(store: StatusStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        settings.$desktopLightVisible
            .removeDuplicates()
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        settings.$orientation
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] orientation in
                self?.updateOrientation(orientation)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.keepWindowOnScreen()
            }
            .store(in: &cancellables)
    }

    func closeImmediately() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }

    private var rootView: DesktopLightView {
        DesktopLightView(
            store: store,
            settings: settings,
            interaction: interaction,
            openStatus: { [weak self] in
                guard let self, let panel = self.panel else { return }
                self.onOpenStatusPanel?(panel.frame.insetBy(
                    dx: DesktopLightLayout.windowPadding,
                    dy: DesktopLightLayout.windowPadding
                ))
            },
            hide: { [weak settings] in
                settings?.desktopLightVisible = false
            },
            saveGeometry: { [weak self] in
                self?.saveGeometry()
            }
        )
    }

    private func show() {
        hideTask?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel

        let size = DesktopLightLayout.windowSize(
            for: settings.orientation,
            scale: settings.desktopLightScale
        )
        if !panel.isVisible {
            let desiredOrigin: NSPoint
            if let saved = settings.desktopLightPosition {
                desiredOrigin = NSPoint(x: saved.x, y: saved.y)
            } else {
                let visibleFrame = orderedVisibleFrames().first ?? .zero
                desiredOrigin = DesktopLightLayout.defaultOrigin(for: size, in: visibleFrame)
            }

            let origin = DesktopLightLayout.clampedOrigin(
                desiredOrigin,
                size: size,
                visibleFrames: orderedVisibleFrames()
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        panel.orderFrontRegardless()
        interaction.isPresented = false
        Task { @MainActor [weak interaction] in
            interaction?.isPresented = true
        }
    }

    private func hide() {
        guard panel?.isVisible == true else { return }
        hideTask?.cancel()
        interaction.isPresented = false

        let delay: UInt64 = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 90_000_000
            : 180_000_000
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, self?.settings.desktopLightVisible == false else { return }
            self?.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> DesktopLightPanel {
        let size = DesktopLightLayout.windowSize(
            for: settings.orientation,
            scale: settings.desktopLightScale
        )
        let panel = DesktopLightPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.isExcludedFromWindowsMenu = true
        return panel
    }

    private func updateOrientation(_ orientation: TrafficLightOrientation) {
        guard let panel else { return }

        let oldCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let newSize = DesktopLightLayout.windowSize(
            for: orientation,
            scale: settings.desktopLightScale
        )
        let desiredOrigin = NSPoint(
            x: oldCenter.x - newSize.width / 2,
            y: oldCenter.y - newSize.height / 2
        )
        let origin = DesktopLightLayout.clampedOrigin(
            desiredOrigin,
            size: newSize,
            visibleFrames: orderedVisibleFrames()
        )
        let newFrame = NSRect(origin: origin, size: newSize)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.10 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.savePosition() }
        }
    }

    private func keepWindowOnScreen() {
        guard let panel else { return }
        let origin = DesktopLightLayout.clampedOrigin(
            panel.frame.origin,
            size: panel.frame.size,
            visibleFrames: orderedVisibleFrames()
        )
        guard origin != panel.frame.origin else { return }
        panel.setFrameOrigin(origin)
        savePosition()
    }

    private func savePosition() {
        guard let panel else { return }
        let origin = DesktopLightLayout.clampedOrigin(
            panel.frame.origin,
            size: panel.frame.size,
            visibleFrames: orderedVisibleFrames()
        )
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
        settings.desktopLightPosition = DesktopLightPosition(x: origin.x, y: origin.y)
    }

    private func saveGeometry() {
        guard let panel else { return }
        settings.desktopLightScale = Double(DesktopLightLayout.scale(
            for: panel.frame.size,
            orientation: settings.orientation
        ))
        savePosition()
    }

    private func orderedVisibleFrames() -> [NSRect] {
        var frames = NSScreen.screens.map(\.visibleFrame)
        guard let mainFrame = NSScreen.main?.visibleFrame,
              let index = frames.firstIndex(of: mainFrame) else { return frames }
        frames.remove(at: index)
        frames.insert(mainFrame, at: 0)
        return frames
    }
}

private final class DesktopLightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class DesktopLightInteractionModel: ObservableObject {
    @Published var isPresented = false
    @Published var isHovering = false
    @Published var isPressed = false
    @Published var isDragging = false
    @Published var isResizing = false
}

private struct DesktopLightView: View {
    @ObservedObject var store: StatusStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var interaction: DesktopLightInteractionModel
    let openStatus: () -> Void
    let hide: () -> Void
    let saveGeometry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        GeometryReader { proxy in
            let layoutScale = DesktopLightLayout.scale(
                for: NSSize(width: proxy.size.width, height: proxy.size.height),
                orientation: settings.orientation
            )
            let contentSafetyScale = DesktopLightLayout.contentSafetyScale(for: layoutScale)

            ZStack {
                Color.clear

                lightBody
                    .scaleEffect(contentSafetyScale)
                    .frame(
                        width: DesktopLightLayout.contentSize(for: settings.orientation).width,
                        height: DesktopLightLayout.contentSize(for: settings.orientation).height
                    )
                    .overlay {
                        DesktopLightInteractionSurface(
                            accessibilityValue: store.aggregateStatus.displayName,
                            openStatus: openStatus,
                            hide: hide,
                            hoverChanged: { interaction.isHovering = $0 },
                            pressedChanged: { interaction.isPressed = $0 },
                            draggingChanged: { interaction.isDragging = $0 },
                            geometryChanged: saveGeometry
                        )
                    }
                    .overlay {
                        DesktopLightResizeHandles(
                            orientation: settings.orientation,
                            resizingChanged: { interaction.isResizing = $0 },
                            geometryChanged: saveGeometry
                        )
                    }
                    .scaleEffect(layoutScale * presentationScale)
                    .offset(y: presentationOffset)
                    .opacity(interaction.isPresented ? 1 : 0)
            }
        }
        .animation(presentationAnimation, value: interaction.isPresented)
        .animation(interactionAnimation, value: interaction.isHovering)
        .animation(interactionAnimation, value: interaction.isPressed)
        .animation(interactionAnimation, value: interaction.isDragging)
        .animation(interactionAnimation, value: interaction.isResizing)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: settings.orientation)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Desktop traffic light")
        .accessibilityValue(store.aggregateStatus.displayName)
        .accessibilityHint("Opens Agent Light status")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) {
            openStatus()
        }
    }

    private var lightBody: some View {
        ZStack {
            housing

            lampLayout
                .padding(6)
        }
        .contentShape(chamberShape)
    }

    @ViewBuilder
    private var housing: some View {
        if settings.orientation == .horizontal,
           let image = DesktopLightAssetLoader.image(.housingHorizontal) {
            assetHousing(image, rotated: false)
        } else if settings.orientation == .vertical,
                  let image = DesktopLightAssetLoader.image(.housingVertical) {
            assetHousing(image, rotated: false)
        } else if settings.orientation == .vertical,
                  let image = DesktopLightAssetLoader.image(.housingHorizontal) {
            assetHousing(image, rotated: true)
        } else {
            fallbackHousing
        }
    }

    @ViewBuilder
    private func assetHousing(_ image: NSImage, rotated: Bool) -> some View {
        if settings.orientation == .horizontal {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 126, height: 50)
        } else if rotated {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 126, height: 50)
                .rotationEffect(.degrees(90))
                .frame(width: 50, height: 126)
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 50, height: 126)
        }
    }

    private var fallbackHousing: some View {
        ZStack {
            if reduceTransparency {
                chamberShape
                    .fill(Color(nsColor: .black).opacity(0.92))
            } else {
                DesktopGlassMaterialView()
                    .clipShape(chamberShape)
            }

            chamberShape
                .fill(Color.black.opacity(reduceTransparency ? 0.20 : 0.66))

            chamberShape
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(interaction.isHovering ? 0.10 : 0.075),
                            .clear,
                            .black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(chamberShape)
        .overlay {
            chamberShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorSchemeContrast == .increased ? 0.34 : 0.22),
                            Color(nsColor: .darkGray).opacity(0.50),
                            .black.opacity(0.88),
                            .white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: colorSchemeContrast == .increased ? 1.8 : 1.4
                )
        }
        .overlay {
            chamberShape
                .inset(by: 2)
                .stroke(Color.black.opacity(0.58), lineWidth: 0.8)
        }
    }

    private var chamberShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
    }

    private var lampLayout: some View {
        let layout = settings.orientation == .vertical
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))

        return layout {
            PremiumTrafficLamp(lampStatus: .failed, aggregateStatus: store.aggregateStatus)
            PremiumTrafficLamp(lampStatus: .needsInput, aggregateStatus: store.aggregateStatus)
            PremiumTrafficLamp(lampStatus: .working, aggregateStatus: store.aggregateStatus)
        }
    }

    private var presentationScale: CGFloat {
        if reduceMotion { return 1 }
        if !interaction.isPresented { return 0.97 }
        if interaction.isDragging || interaction.isResizing { return 1.006 }
        if interaction.isPressed { return 0.985 }
        if interaction.isHovering { return 1.008 }
        return 1
    }

    private var presentationOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        if !interaction.isPresented { return -5 }
        return interaction.isDragging ? -2 : 0
    }

    private var presentationAnimation: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.10)
            : .spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.08)
    }

    private var interactionAnimation: Animation? {
        reduceMotion
            ? .easeOut(duration: 0.08)
            : .spring(response: 0.30, dampingFraction: 0.88, blendDuration: 0.05)
    }
}

private struct PremiumTrafficLamp: View {
    let lampStatus: AgentStatus
    let aggregateStatus: AgentStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var isActive: Bool {
        TrafficLightIconRenderer.isActiveLamp(lampStatus, for: aggregateStatus)
    }

    private var color: Color {
        Color(nsColor: TrafficLightIconRenderer.lampColor(
            lampStatus: lampStatus,
            aggregateStatus: aggregateStatus,
            active: isActive
        ))
    }

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.40), color.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 20
                        )
                    )
                    .frame(width: 38, height: 38)
                    .blur(radius: 2.8)
            }

            if let lampImage = DesktopLightAssetLoader.image(.lampNeutral) {
                assetLamp(lampImage)
            } else {
                fallbackLamp
            }
        }
        .frame(width: 32, height: 32)
        .animation(lampAnimation, value: isActive)
    }

    private func assetLamp(_ image: NSImage) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 30.5, height: 30.5)

            Circle()
                .fill(
                    RadialGradient(
                        colors: isActive
                            ? [color.opacity(0.98), color, color.opacity(0.88)]
                            : [color.opacity(0.78), color.opacity(0.68), color.opacity(0.56)],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 1,
                        endRadius: 13
                    )
                )
                .frame(width: 25, height: 25)
                .blendMode(.color)

            if isActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.20),
                                color.opacity(0.42),
                                color.opacity(0.18),
                                .clear
                            ],
                            center: UnitPoint(x: 0.40, y: 0.34),
                            startRadius: 0,
                            endRadius: 15
                        )
                    )
                    .frame(width: 25.5, height: 25.5)
                    .blendMode(.screen)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.44))
                    .frame(width: 25, height: 25)
                    .blendMode(.multiply)
            }
        }
        .compositingGroup()
    }

    private var fallbackLamp: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.30), Color(nsColor: .darkGray), .black.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)

            Circle()
                .fill(Color.black.opacity(0.90))
                .frame(width: 31, height: 31)

            Circle()
                .fill(
                    RadialGradient(
                        colors: isActive
                            ? [.white.opacity(0.30), color, color.opacity(0.82)]
                            : [color.opacity(0.84), color.opacity(0.65), .black.opacity(0.70)],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 1,
                        endRadius: 19
                    )
                )
                .frame(width: 27.5, height: 27.5)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(isActive ? 0.48 : 0.18), .clear, .black.opacity(0.62)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: colorSchemeContrast == .increased ? 1.4 : 0.9
                        )
                }

            Ellipse()
                .fill(.white.opacity(isActive ? 0.36 : 0.10))
                .frame(width: 10, height: 4.5)
                .blur(radius: isActive ? 1 : 0.7)
                .offset(x: -5, y: -6)
        }
    }

    private var lampAnimation: Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.10)
        }
        return isActive
            ? .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.06)
            : .easeOut(duration: 0.12)
    }
}

private struct DesktopGlassMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct DesktopLightInteractionSurface: NSViewRepresentable {
    let accessibilityValue: String
    let openStatus: () -> Void
    let hide: () -> Void
    let hoverChanged: (Bool) -> Void
    let pressedChanged: (Bool) -> Void
    let draggingChanged: (Bool) -> Void
    let geometryChanged: () -> Void

    func makeNSView(context: Context) -> DesktopLightTrackingView {
        let view = DesktopLightTrackingView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: DesktopLightTrackingView, context: Context) {
        update(nsView)
    }

    private func update(_ view: DesktopLightTrackingView) {
        view.accessibilityValueText = accessibilityValue
        view.openStatus = openStatus
        view.hide = hide
        view.hoverChanged = hoverChanged
        view.pressedChanged = pressedChanged
        view.draggingChanged = draggingChanged
        view.geometryChanged = geometryChanged
    }
}

private final class DesktopLightTrackingView: NSView {
    var accessibilityValueText = "Unknown"
    var openStatus: (() -> Void)?
    var hide: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    var pressedChanged: ((Bool) -> Void)?
    var draggingChanged: ((Bool) -> Void)?
    var geometryChanged: (() -> Void)?

    private var trackingAreaReference: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var hasDragged = false

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        hasDragged = false
        pressedChanged?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let mouseDownLocation,
              let windowOriginAtMouseDown else { return }

        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - mouseDownLocation.x
        let deltaY = currentLocation.y - mouseDownLocation.y
        if !hasDragged, hypot(deltaX, deltaY) >= 3 {
            hasDragged = true
            draggingChanged?(true)
        }
        guard hasDragged else { return }
        window.setFrameOrigin(NSPoint(
            x: windowOriginAtMouseDown.x + deltaX,
            y: windowOriginAtMouseDown.y + deltaY
        ))
    }

    override func mouseUp(with event: NSEvent) {
        pressedChanged?(false)
        if hasDragged {
            draggingChanged?(false)
            geometryChanged?()
        } else {
            openStatus?()
        }
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
        hasDragged = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Hide Desktop Light",
            action: #selector(hideDesktopLight),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func hideDesktopLight() {
        hide?()
    }
}

private struct DesktopLightResizeHandles: View {
    let orientation: TrafficLightOrientation
    let resizingChanged: (Bool) -> Void
    let geometryChanged: () -> Void

    var body: some View {
        ZStack {
            handle(.topLeft, alignment: .topLeading)
            handle(.topRight, alignment: .topTrailing)
            handle(.bottomLeft, alignment: .bottomLeading)
            handle(.bottomRight, alignment: .bottomTrailing)
        }
    }

    private func handle(_ corner: DesktopLightResizeCorner, alignment: Alignment) -> some View {
        DesktopLightResizeHandle(
            corner: corner,
            orientation: orientation,
            resizingChanged: resizingChanged,
            geometryChanged: geometryChanged
        )
        .frame(width: 18, height: 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

private struct DesktopLightResizeHandle: NSViewRepresentable {
    let corner: DesktopLightResizeCorner
    let orientation: TrafficLightOrientation
    let resizingChanged: (Bool) -> Void
    let geometryChanged: () -> Void

    func makeNSView(context: Context) -> DesktopLightResizeHandleView {
        let view = DesktopLightResizeHandleView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: DesktopLightResizeHandleView, context: Context) {
        update(nsView)
    }

    private func update(_ view: DesktopLightResizeHandleView) {
        view.corner = corner
        view.orientation = orientation
        view.resizingChanged = resizingChanged
        view.geometryChanged = geometryChanged
    }
}

private final class DesktopLightResizeHandleView: NSView {
    var corner: DesktopLightResizeCorner = .bottomRight
    var orientation: TrafficLightOrientation = .horizontal
    var resizingChanged: ((Bool) -> Void)?
    var geometryChanged: (() -> Void)?

    private var mouseDownLocation: NSPoint?
    private var initialWindowFrame: NSRect?
    private var isResizing = false

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        initialWindowFrame = window?.frame
        isResizing = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let mouseDownLocation, let initialWindowFrame else { return }
        let currentLocation = NSEvent.mouseLocation
        let delta = NSPoint(
            x: currentLocation.x - mouseDownLocation.x,
            y: currentLocation.y - mouseDownLocation.y
        )
        if !isResizing, hypot(delta.x, delta.y) >= 2 {
            isResizing = true
            resizingChanged?(true)
        }
        guard isResizing else { return }

        let frame = DesktopLightLayout.resizedFrame(
            from: initialWindowFrame,
            corner: corner,
            dragDelta: delta,
            orientation: orientation
        )
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if isResizing {
            resizingChanged?(false)
            geometryChanged?()
        }
        mouseDownLocation = nil
        initialWindowFrame = nil
        isResizing = false
    }
}
