import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    enum Page: Hashable {
        case infiniteScreen, batteryRipple, general, about, foundBug

        var title: String {
            switch self {
            case .infiniteScreen: return "Seamless Close"
            case .batteryRipple: return "Battery Ripple"
            case .general: return "General"
            case .about: return "Privacy & About"
            case .foundBug: return "Send feedback"
            }
        }
    }
    @Published var selectedPage: Page = .infiniteScreen
    @Published private(set) var animationEnabled = true
    @Published private(set) var startAngle = 100.0
    @Published private(set) var automaticStartAngle = false
    @Published private(set) var learnedStartAngle: Double?
    var effectiveStartAngle: Double { automaticStartAngle ? (learnedStartAngle ?? startAngle) : startAngle }
    private(set) var currentAngle: Double?
    @Published private(set) var displayedLidAngle: Double?
    private var lidAnglePresentation = LidAnglePresentation()
    @Published private(set) var sensorStatus = "Connecting…"
    @Published private(set) var screenCaptureAllowed = false
    @Published private(set) var runtimeStatus = "Starting…"

    var onAnimationEnabledChange: ((Bool) -> Void)?
    var onStartAngleChange: ((Double) -> Void)?
    var onAutomaticStartAngleChange: ((Bool) -> Void)?
    @Published private(set) var resumeAfterPause = false
    var onResumeAfterPauseChange: ((Bool) -> Void)?
    @Published private(set) var chargingFeedbackEnabled = true
    var onChargingFeedbackEnabledChange: ((Bool) -> Void)?
    @Published private(set) var lowBatteryRippleEnabled = true
    var onLowBatteryRippleEnabledChange: ((Bool) -> Void)?
    @Published private(set) var runInBackground = true
    var onRunInBackgroundChange: ((Bool) -> Void)?
    @Published private(set) var showMenuBarIcon = true
    var onShowMenuBarIconChange: ((Bool) -> Void)?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginMessage: String?
    var onPreviewBatteryRipple: ((BatteryRippleStyle) -> Void)?

    var onOpenPermissions: (() -> Void)?

    func configure(animationEnabled: Bool, startAngle: Double, screenCaptureAllowed: Bool,
                   resumeAfterPause: Bool = false, automaticStartAngle: Bool = false,
                   chargingFeedbackEnabled: Bool = true, lowBatteryRippleEnabled: Bool = true,
                   runInBackground: Bool = true, showMenuBarIcon: Bool = true) {
        self.animationEnabled = animationEnabled
        self.startAngle = startAngle
        self.screenCaptureAllowed = screenCaptureAllowed
        self.resumeAfterPause = resumeAfterPause
        self.automaticStartAngle = automaticStartAngle
        self.chargingFeedbackEnabled = chargingFeedbackEnabled
        self.lowBatteryRippleEnabled = lowBatteryRippleEnabled
        self.runInBackground = runInBackground
        self.showMenuBarIcon = showMenuBarIcon
    }

    func setRunInBackground(_ enabled: Bool) {
        guard runInBackground != enabled else { return }
        runInBackground = enabled
        onRunInBackgroundChange?(enabled)
    }

    func setShowMenuBarIcon(_ enabled: Bool) {
        guard showMenuBarIcon != enabled else { return }
        showMenuBarIcon = enabled
        onShowMenuBarIconChange?(enabled)
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginMessage = status == .requiresApproval
            ? "Allow Glissform in System Settings → General → Login Items & Extensions."
            : nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard launchAtLoginEnabled != enabled else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLaunchAtLogin()
        } catch {
            refreshLaunchAtLogin()
            if launchAtLoginMessage == nil {
                launchAtLoginMessage = "Couldn’t change Launch at login: \(error.localizedDescription)"
            }
        }
    }

    func setAutomaticStartAngle(_ enabled: Bool) {
        guard automaticStartAngle != enabled else { return }
        automaticStartAngle = enabled
        learnedStartAngle = nil
        onAutomaticStartAngleChange?(enabled)
    }

    func updateLearnedStartAngle(_ angle: Double?) {
        if learnedStartAngle != angle { learnedStartAngle = angle }
    }

    func setResumeAfterPause(_ enabled: Bool) {
        guard resumeAfterPause != enabled else { return }
        resumeAfterPause = enabled
        onResumeAfterPauseChange?(enabled)
    }

    func setChargingFeedbackEnabled(_ enabled: Bool) {
        guard chargingFeedbackEnabled != enabled else { return }
        chargingFeedbackEnabled = enabled
        onChargingFeedbackEnabledChange?(enabled)
    }

    func setLowBatteryRippleEnabled(_ enabled: Bool) {
        guard lowBatteryRippleEnabled != enabled else { return }
        lowBatteryRippleEnabled = enabled
        onLowBatteryRippleEnabledChange?(enabled)
    }

    func setAnimationEnabled(_ enabled: Bool) {
        guard animationEnabled != enabled else { return }
        animationEnabled = enabled
        onAnimationEnabledChange?(enabled)
    }

    func setStartAngle(_ angle: Double) {
        guard angle.isFinite else { return }
        let normalized = min(130, max(20, angle)).rounded()
        guard startAngle != normalized else { return }
        startAngle = normalized
        onStartAngleChange?(normalized)
    }

    func updateAngle(_ angle: Double, time: Double = ProcessInfo.processInfo.systemUptime) {
        guard angle.isFinite, (0...180).contains(angle) else { return }
        if sensorStatus != "Connected" { sensorStatus = "Connected" }
        if currentAngle != angle { currentAngle = angle }
        let shown = lidAnglePresentation.ingest(angle, at: time)
        if displayedLidAngle != shown { displayedLidAngle = shown }
    }

    func updateSensorStatus(_ status: String) {
        if status == "Lid sensor ready" || status == "Connected" {
            sensorStatus = "Connected"
        } else {
            sensorStatus = "Sensor unavailable"
            currentAngle = nil
            lidAnglePresentation.reset()
            displayedLidAngle = nil
        }
    }

    func refreshPermission() {
        let allowed = CGPreflightScreenCaptureAccess()
        if screenCaptureAllowed != allowed { screenCaptureAllowed = allowed }
    }

    func updateRuntimeStatus(_ status: String) {
        if runtimeStatus != status { runtimeStatus = status }
    }
}

@MainActor
private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let editor = firstResponder as? NSTextView, editor.isFieldEditor {
            // End editing before delivering the same click to its intended control.
            // Clicks inside the field still position the caret or select text normally.
            let field = (editor.delegate as? NSView) ?? editor
            let point = field.convert(event.locationInWindow, from: nil)
            if !field.bounds.contains(point) {
                makeFirstResponder(nil)
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
private final class SettingsShadowWindow: NSWindow {
    static let margin: CGFloat = 80

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Keep the shadow aligned when its transparent margin extends beyond a screen edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    init(around window: SettingsWindow) {
        let frame = window.frame
        super.init(contentRect: frame.insetBy(dx: -Self.margin, dy: -Self.margin),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = SettingsShadowView(frame: NSRect(origin: .zero, size: self.frame.size))
    }

    func follow(_ window: SettingsWindow) {
        let frame = window.frame
        setFrame(frame.insetBy(dx: -Self.margin, dy: -Self.margin), display: true)
        (contentView as? SettingsShadowView)?.updateShadow()
    }
}

@MainActor
private final class SettingsShadowView: NSView {
    private let shadowLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(shadowLayer)
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.0544
        shadowLayer.shadowRadius = 24
        shadowLayer.shadowOffset = .zero
        updateShadow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        updateShadow()
    }

    func updateShadow() {
        let inset = SettingsShadowWindow.margin
        shadowLayer.frame = bounds.insetBy(dx: inset, dy: inset)
        shadowLayer.shadowPath = CGPath(roundedRect: shadowLayer.bounds, cornerWidth: 20,
                                        cornerHeight: 20, transform: nil)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let shadowWindow: SettingsShadowWindow
    private let model: SettingsModel
    var onClose: (() -> Void)?
    init(model: SettingsModel) {
        self.model = model
        let contentHeight = min(SettingsDesign.Metrics.preferredHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 48)
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsDesign.Metrics.windowWidth, height: contentHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Glissform"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "GlissformSettingsToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.showsToolbarButton = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // With a full-size content view, the rounded surface includes the titlebar.
        // Keep the actual window frame equal to that surface, rather than asking
        // AppKit to add the toolbar height to it as extra transparent space.
        window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - contentHeight,
                               width: SettingsDesign.Metrics.windowWidth, height: contentHeight),
                        display: false)
        window.center()
        let hostingController = NSHostingController(rootView: SettingsRootView(model: model) { [weak window] naturalHeight in
            guard let window else { return naturalHeight }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            let maximumHeight = min(SettingsDesign.Metrics.preferredHeight, (visible?.height ?? 900) - 48)
            let height = min(ceil(naturalHeight), maximumHeight)
            var frame = NSRect(x: 0, y: 0,
                               width: SettingsDesign.Metrics.windowWidth, height: height)
            frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            if let visible { frame.origin.y = max(visible.minY, frame.origin.y) }
            if abs(window.frame.height - frame.height) > 0.5 {
                window.setFrame(frame, display: true)
            }
            return height
        })
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        shadowWindow = SettingsShadowWindow(around: window)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.setActivationPolicy(.regular)
        // Restore the bundled icon each time the app returns to the Dock.
        // nil preserves macOS's native icon appearance selection.
        NSApp.applicationIconImage = nil
        showWindow(nil)
        if let window = window as? SettingsWindow {
            shadowWindow.follow(window)
            if shadowWindow.parent == nil {
                window.addChildWindow(shadowWindow, ordered: .below)
            }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.removeChildWindow(shadowWindow)
        shadowWindow.orderOut(nil)
        if model.runInBackground {
            NSApp.setActivationPolicy(.accessory)
        }
        onClose?()
    }

    func windowDidResize(_ notification: Notification) {
        if let window = window as? SettingsWindow { shadowWindow.follow(window) }
    }

    func windowWillMiniaturize(_ notification: Notification) {
        shadowWindow.orderOut(nil)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if let window = window as? SettingsWindow {
            shadowWindow.follow(window)
            shadowWindow.order(.below, relativeTo: window.windowNumber)
        }
    }

}

@MainActor
private final class SettingsLayoutState: ObservableObject {
    @Published var height = SettingsDesign.Metrics.preferredHeight
}

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var layout = SettingsLayoutState()
    @FocusState private var focusedPage: SettingsModel.Page?
    let resizeWindow: (CGFloat) -> CGFloat

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                sidebarSectionTitle("Features")
                navigationRow(.general)
                navigationRow(.infiniteScreen)
                navigationRow(.batteryRipple)
                sidebarSectionTitle("More")
                    .padding(.top, 12)
                navigationRow(.about)
                navigationRow(.foundBug)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 58).padding(.bottom, 16)
            .frame(width: SettingsDesign.Metrics.sidebarWidth)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings pages")
            .onMoveCommand { direction in
                let pages: [SettingsModel.Page] = [.general, .infiniteScreen, .batteryRipple, .about, .foundBug]
                let index = pages.firstIndex(of: focusedPage ?? model.selectedPage) ?? 0
                let next: Int
                if direction == .down { next = min(index + 1, pages.count - 1) }
                else if direction == .up { next = max(index - 1, 0) }
                else { return }
                focusedPage = pages[next]
                model.selectedPage = pages[next]
            }

            ScrollView {
                Group {
                    switch model.selectedPage {
                    case .infiniteScreen: AnimationSettingsView(model: model)
                    case .batteryRipple: BatterySettingsView(model: model)
                    case .general: GeneralSettingsView(model: model)
                    case .about: AboutSettingsView(model: model)
                    case .foundBug: FoundBugPlaceholderView()
                    }
                }
                .frame(width: SettingsDesign.Metrics.contentWidth)
                .fixedSize(horizontal: false, vertical: true)
            }
            // Each page starts at the top when selected.
            .id(model.selectedPage)
            .frame(width: SettingsDesign.Metrics.contentWidth)
            .background(SettingsDetailSurface())
        }
        .frame(width: SettingsDesign.Metrics.windowWidth, height: layout.height, alignment: .topLeading)
        .background(SettingsWindowMaterial().ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5))
        .ignoresSafeArea(edges: .top)
        .onAppear {
            layout.height = resizeWindow(SettingsDesign.Metrics.preferredHeight)
            model.refreshPermission()
            model.refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
            model.refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            layout.height = resizeWindow(SettingsDesign.Metrics.preferredHeight)
        }
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsDesign.Metrics.sidebarRowInset)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }

    private func navigationRow(_ page: SettingsModel.Page) -> some View {
        Button {
            focusedPage = page
            model.selectedPage = page
        } label: {
            HStack(spacing: 9) {
                Group {
                    switch page {
                    case .infiniteScreen: FeatureIcon(.infiniteScreen, size: 17)
                    case .batteryRipple: FeatureIcon(.batteryRipple, size: 17)
                    case .general: FeatureIcon(.general, size: 17)
                    case .about: IconlyIcon(.shieldDone, size: 17)
                    case .foundBug: FeatureIcon(.sendFeedback, size: 17)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background {
                    let tint = page == .infiniteScreen ? SettingsDesign.Palette.feature
                        : page == .batteryRipple ? SettingsDesign.Palette.batterySidebar
                        : page == .general || page == .about ? SettingsDesign.Palette.neutralSidebar
                        : SettingsDesign.Palette.feedbackSidebar
                    RoundedRectangle(cornerRadius: SettingsDesign.Metrics.sidebarIconRadius, style: .continuous)
                        .fill(tint.gradient)
                        .overlay(RoundedRectangle(cornerRadius: SettingsDesign.Metrics.sidebarIconRadius)
                            .strokeBorder(.white.opacity(0.25)))
                }
                .accessibilityHidden(true)
                Text(page.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(SettingsDesign.Metrics.sidebarRowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.Metrics.sidebarRowRadius))
        }
        .buttonStyle(SettingsNavigationButtonStyle(selected: model.selectedPage == page))
        .focused($focusedPage, equals: page)
        .focusEffectDisabled()
        .accessibilityAddTraits(model.selectedPage == page ? .isSelected : [])
        .accessibilityLabel(page.title)
    }

}

private struct SettingsFeatureHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
            Text(title).font(SettingsDesign.Typography.pageTitle)
                .tracking(SettingsDesign.Typography.headlineTracking)
            Text(subtitle).font(SettingsDesign.Typography.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FeatureToggleRow<Icon: View>: View {
    let title: String
    let detail: String
    let color: SettingsDesign.Palette.CardIconColor
    @Binding var isEnabled: Bool
    let preview: (() -> Void)?
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: SettingsDesign.Spacing.controls) {
            CardIconTile(color: color, content: icon).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SettingsDesign.Typography.controlTitle)
                Text(detail).font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let preview {
                Button(action: preview) {
                    IconlyIcon(.play, size: 16)
                }
                .buttonStyle(BatteryPreviewButtonStyle())
                .accessibilityLabel("Preview \(title) ripple")
                .help("Preview \(title) ripple")
            }
            Toggle(title, isOn: $isEnabled)
                .labelsHidden().toggleStyle(AppleSwitchStyle())
                .accessibilityLabel("Enable \(title)")
        }
    }
}

private struct FeatureToggleCard<Icon: View>: View {
    let title: String
    let detail: String
    let color: SettingsDesign.Palette.CardIconColor
    @Binding var isEnabled: Bool
    let preview: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        FeatureToggleRow(title: title, detail: detail, color: color, isEnabled: $isEnabled,
                         preview: preview, icon: icon)
            .padding(SettingsDesign.Spacing.switchCardInsets)
            .modifier(SettingsCardSurface())
    }
}

@MainActor
private final class PermissionPresentationState: ObservableObject {
    @Published var showConfirmation = false
}

private struct AnimationSettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var permission = PermissionPresentationState()

    private var showsAccessCard: Bool { !model.screenCaptureAllowed || permission.showConfirmation }

    private var angleBinding: Binding<Double> {
        Binding(get: { model.startAngle }, set: { model.setStartAngle($0) })
    }
    private var canUseCurrentAngle: Bool {
        guard let angle = model.currentAngle else { return false }
        return (20...130).contains(angle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.cards) {
            SettingsFeatureHeader(title: "Seamless Close",
                subtitle: "Your desktop appears to stay in place as the lid closes.")
                .padding(.bottom, SettingsDesign.Spacing.detail)

            infiniteScreenCard
            if showsAccessCard {
                ScreenAccessCard(model: model).transition(.opacity)
            }
            automaticAngleControls
                .padding(SettingsDesign.Spacing.switchCardInsets)
                .modifier(SettingsCardSurface())
            pauseControls
                .padding(SettingsDesign.Spacing.switchCardInsets)
                .modifier(SettingsCardSurface())
            lockScreenSupport
                .padding(SettingsDesign.Spacing.switchCardInsets)
                .modifier(SettingsCardSurface())
        }
        .padding(SettingsDesign.Spacing.page)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showsAccessCard)
        .onChange(of: model.screenCaptureAllowed) { previous, allowed in
            permission.showConfirmation = !previous && allowed
        }
        .task(id: permission.showConfirmation) {
            guard permission.showConfirmation else { return }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            permission.showConfirmation = false
        }
    }

    private var infiniteScreenCard: some View {
        VStack(spacing: 0) {
            FeatureToggleRow(title: "Seamless Close", detail: "Animates the desktop as the lid closes.",
                             color: .feature,
                             isEnabled: Binding(get: { model.animationEnabled }, set: { model.setAnimationEnabled($0) }),
                             preview: nil) {
                FeatureIcon(.infiniteScreen)
            }
            .padding(SettingsDesign.Spacing.switchCardInsets)

            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)

            angleControls
                .padding(SettingsDesign.Spacing.angleSectionInset)
        }
        .modifier(SettingsCardSurface())
    }

    private var angleControls: some View {
        let automaticAngleIsActive = model.automaticStartAngle && model.learnedStartAngle != nil
        return VStack(alignment: .leading, spacing: SettingsDesign.Spacing.controls) {
            HStack(spacing: 6) {
                Circle().fill(model.displayedLidAngle == nil ? Color.gray : SettingsDesign.Palette.feature)
                    .frame(width: 5, height: 5)
                Text("Current lid angle").foregroundStyle(.secondary)
                Text(model.displayedLidAngle.map { "\(Int($0))°" } ?? "—")
                    .font(SettingsDesign.Typography.liveValue)
                Spacer()
            }
            .font(SettingsDesign.Typography.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current lid angle")
            .accessibilityValue(model.displayedLidAngle.map { "\(Int($0)) degrees" } ?? "Unavailable")
            HStack {
                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                    Text("Begin at").font(SettingsDesign.Typography.controlTitle)
                    Text(automaticAngleIsActive
                         ? "Turn off automatic selection to edit this saved angle."
                         : "Higher angles start the effect sooner.")
                        .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                AngleEntry(model: model)
            }
            VStack(spacing: SettingsDesign.Spacing.detail) {
                AngleSlider(value: angleBinding, isFallback: automaticAngleIsActive)
                    .frame(height: 22)
                    .accessibilityLabel("Animation start angle")
                    .accessibilityValue("\(Int(model.startAngle)) degrees")
                HStack {
                    Text("20°").foregroundStyle(.secondary)
                    Spacer()
                    Button("Use current angle") {
                        if let angle = model.currentAngle { model.setStartAngle(angle) }
                    }
                    .buttonStyle(FeedbackButtonStyle(kind: .link)).disabled(!canUseCurrentAngle)
                    .help("Use the current lid angle. Open a little farther, then close to begin.")
                    Text("·").foregroundStyle(.tertiary)
                    Button("Reset") { model.setStartAngle(100) }
                        .buttonStyle(FeedbackButtonStyle(kind: .link)).disabled(model.startAngle == 100)
                        .help("Restore the default start angle of 100°")
                        .accessibilityLabel("Reset start angle to 100 degrees")
                    Spacer()
                    Text("130°").foregroundStyle(.secondary)
                }
                .font(SettingsDesign.Typography.caption)
            }
        }
        .disabled(automaticAngleIsActive)
        .opacity(automaticAngleIsActive ? 0.72 : 1)
    }

    private var pauseControls: some View {
        HStack(spacing: SettingsDesign.Spacing.cards) {
            PauseFeatureIcon().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Resume desktop after pause").font(SettingsDesign.Typography.controlTitle)
                Text("Restores the desktop after a 1-second lid pause.")
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("Resume desktop after pause", isOn: Binding(
                get: { model.resumeAfterPause }, set: { model.setResumeAfterPause($0) }
            ))
            .labelsHidden().toggleStyle(AppleSwitchStyle())
            .accessibilityLabel("Resume desktop after pause")
        }
    }

    private var lockScreenSupport: some View {
        HStack(spacing: SettingsDesign.Spacing.cards) {
            CardIconTile(color: .feature) {
                IconlyIcon(.lock, size: 24)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Lock Screen support").font(SettingsDesign.Typography.controlTitle)
                Text("Play the animation while your Mac is locked.")
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("Soon")
                .font(SettingsDesign.Typography.action)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.45)))
                .accessibilityLabel("Coming soon")
        }
    }

    private var automaticAngleControls: some View {
        HStack(spacing: SettingsDesign.Spacing.cards) {
            CardIconTile(color: .automaticAngle) {
                FeatureIcon(.automaticAngle)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Detect starting angle").font(SettingsDesign.Typography.controlTitle)
                Text(automaticAngleDescription)
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("Detect starting angle", isOn: Binding(
                get: { model.automaticStartAngle }, set: { model.setAutomaticStartAngle($0) }
            ))
                .labelsHidden().toggleStyle(AppleSwitchStyle())
                .accessibilityLabel("Detect starting angle")
                .accessibilityHint(automaticAngleDescription)
        }
    }

    private var automaticAngleDescription: String {
        if model.automaticStartAngle, let angle = model.learnedStartAngle {
            return "Using \(Int(angle))°. Updates after a 1-second lid pause."
        }
        if model.automaticStartAngle {
            return "Waiting for a 1-second lid pause. Begin at applies."
        }
        return "Detects the angle after a 1-second lid pause."
    }

}

private struct BatterySettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.cards) {
            SettingsFeatureHeader(title: "Battery Ripple",
                subtitle: "A soft ripple for charging and low battery.")
                .padding(.bottom, SettingsDesign.Spacing.detail)

            FeatureToggleCard(title: "Power connection", detail: "Shows a green ripple when power connects.",
                              color: .success,
                              isEnabled: Binding(get: { model.chargingFeedbackEnabled },
                                                 set: { model.setChargingFeedbackEnabled($0) }),
                              preview: { model.onPreviewBatteryRipple?(.connected) }) {
                FeatureIcon(.powerConnection)
            }

            FeatureToggleCard(title: "Battery at 20%", detail: "Shows a red ripple when battery reaches 20%.",
                              color: .danger,
                              isEnabled: Binding(get: { model.lowBatteryRippleEnabled },
                                                 set: { model.setLowBatteryRippleEnabled($0) }),
                              preview: { model.onPreviewBatteryRipple?(.lowBattery) }) {
                FeatureIcon(.batteryAt20Percent)
            }
        }
        .padding(SettingsDesign.Spacing.page)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.cards) {
            SettingsFeatureHeader(title: "General", subtitle: "Choose how Glissform stays available.")
                .padding(.bottom, SettingsDesign.Spacing.detail)

            FeatureToggleRow(title: "Run in background",
                             detail: "Keep effects active after closing Settings.",
                             color: .neutral,
                             isEnabled: Binding(get: { model.runInBackground },
                                                set: { model.setRunInBackground($0) }),
                             preview: nil) {
                FeatureIcon(.backgroundRunning)
            }
            .padding(SettingsDesign.Spacing.switchCardInsets)
            .modifier(SettingsCardSurface())

            FeatureToggleRow(title: "Menu bar icon",
                             detail: "Open Settings and controls from the menu bar.",
                             color: .neutral,
                             isEnabled: Binding(get: { model.showMenuBarIcon },
                                                set: { model.setShowMenuBarIcon($0) }),
                             preview: nil) {
                FeatureIcon(.menuBarIcon)
            }
            .padding(SettingsDesign.Spacing.switchCardInsets)
            .modifier(SettingsCardSurface())

            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                FeatureToggleRow(title: "Launch at login",
                                 detail: "Open Glissform when you sign in.",
                                 color: .neutral,
                                 isEnabled: Binding(get: { model.launchAtLoginEnabled },
                                                    set: { model.setLaunchAtLogin($0) }),
                                 preview: nil) {
                    FeatureIcon(.launchAtLogin)
                }
                if let message = model.launchAtLoginMessage {
                    Text(message)
                        .font(SettingsDesign.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, SettingsDesign.Metrics.iconSize + SettingsDesign.Spacing.controls)
                }
            }
            .padding(SettingsDesign.Spacing.switchCardInsets)
            .modifier(SettingsCardSurface())
        }
        .padding(SettingsDesign.Spacing.page)
    }
}

@MainActor
private final class AngleDraft: ObservableObject {
    @Published var text = ""
}

/// Keep incomplete typing separate from the clamped, persisted setting.
private struct AngleEntry: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var draft = AngleDraft()
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: SettingsDesign.Spacing.detail) {
            VStack(spacing: 0) {
                arrow(rotation: 0, label: "Increase start angle", step: 1)
                    .disabled(model.startAngle >= 130)
                arrow(rotation: 180, label: "Decrease start angle", step: -1)
                    .disabled(model.startAngle <= 20)
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                TextField("Start angle", text: $draft.text)
                    .labelsHidden().multilineTextAlignment(.trailing)
                    .font(SettingsDesign.Typography.editableValue)
                    .textFieldStyle(.plain).frame(width: SettingsDesign.Metrics.angleNumberWidth)
                    .focused($isFocused)
                    .accessibilityLabel("Start angle in degrees")
                    .help("Enter an angle from 20° to 130°, then press Return.")
                    .onSubmit { commit() }
                Text("°")
                    .font(SettingsDesign.Typography.angleUnit).foregroundStyle(.secondary)
                    .offset(y: -1.5)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, SettingsDesign.Spacing.angleFieldTrailingInset)
            .padding(.vertical, SettingsDesign.Spacing.angleFieldInset)
        }
        .background(SettingsDesign.Palette.field, in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.angleField))
        .modifier(ControlHoverFeedback(isActive: isFocused, inset: 0, showsHover: false))
        .onAppear { draft.text = String(Int(model.startAngle)) }
        .onChange(of: model.startAngle) { _, angle in draft.text = String(Int(angle)) }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func arrow(rotation: Double, label: String, step: Double) -> some View {
        Button {
            commit()
            model.setStartAngle(model.startAngle + step)
        } label: {
            IconlyIcon(.chevronUp, size: SettingsDesign.Metrics.angleChevronSize, rotation: rotation)
                .offset(y: step > 0 ? 1.5 : -1.5)
                .frame(width: SettingsDesign.Metrics.arrowWidth, height: SettingsDesign.Metrics.arrowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(AngleArrowStyle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
        .help(label + " by 1°")
    }

    private func commit() {
        if let value = Double(draft.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            model.setStartAngle(value)
        }
        draft.text = String(Int(model.startAngle))
    }
}

private struct SettingsCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SettingsDesign.Palette.card, in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: SettingsDesign.Radius.card)
                .strokeBorder(SettingsDesign.Palette.cardBorder))
    }
}

private struct CardIconTile<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let color: SettingsDesign.Palette.CardIconColor
    let content: Content

    init(color: SettingsDesign.Palette.CardIconColor, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SettingsDesign.Radius.icon, style: .continuous)
                .fill(color.tile.opacity(0.12))
            content.foregroundStyle(color.symbol(in: colorScheme))
        }
        .frame(width: SettingsDesign.Metrics.iconSize, height: SettingsDesign.Metrics.iconSize)
    }
}

private struct PauseFeatureIcon: View {
    var body: some View {
        CardIconTile(color: .success) {
            IconlyIcon(.pause, size: 24, isCardIcon: true)
        }
    }
}

private struct ScreenAccessIcon: View {
    let allowed: Bool

    var body: some View {
        CardIconTile(color: allowed ? .success : .attention) {
            IconlyIcon(allowed ? .shieldDone : .shieldInfo, size: 24, isCardIcon: true)
        }
    }
}

private struct ScreenAccessCard: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(alignment: .center, spacing: SettingsDesign.Spacing.cards) {
            ScreenAccessIcon(allowed: model.screenCaptureAllowed)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                Text(model.screenCaptureAllowed ? "Screen access allowed" : "Screen access required")
                    .font(SettingsDesign.Typography.controlTitle)
                Text(model.screenCaptureAllowed
                     ? "Screen images stay in memory."
                     : "Allow screen access for desktop effects.")
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(model.screenCaptureAllowed ? "Manage Access…" : "Open Settings…") {
                model.onOpenPermissions?()
            }
            .buttonStyle(FeedbackButtonStyle(kind: .filled)).controlSize(.small)
            .fixedSize()
            .help("Open Screen & System Audio Recording in System Settings to enable or revoke access for Glissform.")
        }
        .padding(SettingsDesign.Spacing.featureInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
        .accessibilityElement(children: .contain)
    }
}

private struct FoundBugPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Send feedback")
                .font(SettingsDesign.Typography.pageTitle)
                .tracking(SettingsDesign.Typography.headlineTracking)
            Text("Nothing here yet.")
                .font(SettingsDesign.Typography.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 360)
        }
        .padding(SettingsDesign.Spacing.page)
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.groups) {
                Text("Privacy & About")
                    .font(SettingsDesign.Typography.pageTitle)
                    .tracking(SettingsDesign.Typography.headlineTracking)

                HStack(spacing: SettingsDesign.Spacing.label) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 68, height: 68).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                        Text("Glissform")
                            .font(SettingsDesign.Typography.aboutTitle)
                            .tracking(SettingsDesign.Typography.headlineTracking)
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development")")
                            .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: SettingsDesign.Spacing.cards) {
                    privacyCard
                    ScreenAccessCard(model: model)
                }

            }
            .padding(SettingsDesign.Spacing.page)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.cardInset) {
            Text("Private by design.").font(SettingsDesign.Typography.sectionTitle)
            privacyDetail("Only what’s needed.", text: "Uses lid angle, power status, and temporary screen images.", symbol: .copy)
            privacyDetail("Kept in memory.", text: "Screen images are released after use, never saved or sent.", symbol: .memory)
            privacyDetail("No tracking.", text: "No audio capture, analytics, or network requests.", symbol: .lock)
        }
        .padding(SettingsDesign.Spacing.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
    }

    private func privacyDetail(_ title: String, text: String, symbol: IconlySymbol) -> some View {
        HStack(alignment: .top, spacing: SettingsDesign.Spacing.controls) {
            CardIconTile(color: .neutral) {
                IconlyIcon(symbol, size: 24, isCardIcon: true)
            }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                Text(title).font(SettingsDesign.Typography.controlTitle)
                Text(text).font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


@MainActor
private final class HoverState: ObservableObject {
    @Published var isHovered = false
}

/// Shared button feedback; Button still owns activation, cancellation and keyboard input.
private struct FeedbackButtonStyle: ButtonStyle {
    enum Kind { case link, quiet, filled }
    var kind: Kind = .quiet

    func makeBody(configuration: Configuration) -> some View {
        FeedbackButtonBody(configuration: configuration, kind: kind)
    }
}

private struct FeedbackButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: FeedbackButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    private var isPressed: Bool { isEnabled && configuration.isPressed }
    private var isHovered: Bool { isEnabled && hover.isHovered }
    private var tint: Color { kind == .link ? .accentColor : .primary }

    var body: some View {
        configuration.label
            .font(SettingsDesign.Typography.action)
            .foregroundStyle(tint)
            .padding(.horizontal, kind == .filled ? SettingsDesign.Spacing.controls : SettingsDesign.Spacing.label)
            .padding(.vertical, kind == .filled ? SettingsDesign.Spacing.label : SettingsDesign.Spacing.detail)
            .background {
                RoundedRectangle(cornerRadius: SettingsDesign.Radius.control)
                    .fill(tint.opacity(isPressed ? SettingsDesign.Feedback.pressedFill : (isHovered ? SettingsDesign.Feedback.hoverFill : (kind == .filled ? SettingsDesign.Feedback.idleFill : 0))))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.Radius.control)
                    .strokeBorder(tint.opacity(isPressed ? SettingsDesign.Feedback.pressedBorder : (isHovered ? SettingsDesign.Feedback.hoverBorder : 0)), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : SettingsDesign.Feedback.disabledOpacity)
            .contentShape(RoundedRectangle(cornerRadius: SettingsDesign.Radius.control))
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.hoverDuration), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.pressedDuration), value: isPressed)
    }
}

private struct BatteryPreviewButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BatteryPreviewButtonBody(configuration: configuration)
    }
}

private struct BatteryPreviewButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    var body: some View {
        let highlighted = configuration.isPressed || hover.isHovered
        configuration.label
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? SettingsDesign.Feedback.pressedFill
                                                 : (hover.isHovered ? SettingsDesign.Feedback.hoverFill
                                                    : SettingsDesign.Feedback.idleFill)))
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(highlighted ? SettingsDesign.Feedback.hoverBorder : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Circle())
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.hoverDuration), value: hover.isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.pressedDuration), value: configuration.isPressed)
    }
}

/// Feedback stays within the text field; the outline indicates active editing.
private struct ControlHoverFeedback: ViewModifier {
    var isActive = false
    var inset: CGFloat = 4
    var showsHover = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        let highlighted = showsHover && isEnabled && hover.isHovered
        let active = isEnabled && isActive
        content
            .background {
                RoundedRectangle(cornerRadius: SettingsDesign.Radius.control)
                    .fill(Color.primary.opacity(highlighted ? SettingsDesign.Feedback.hoverFill : 0))
                    .padding(-inset)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.Radius.control)
                    .strokeBorder(active ? SettingsDesign.Palette.focus : Color.primary.opacity(highlighted ? SettingsDesign.Feedback.hoverBorder : 0), lineWidth: 1)
                    .padding(-inset)
                    .allowsHitTesting(false)
            }
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.hoverDuration), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.pressedDuration), value: active)
    }
}


/// Each arrow reacts independently; neither has a background at rest.
private struct AngleArrowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AngleArrowFeedback(configuration: configuration)
    }
}

private struct AngleArrowFeedback: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    private var highlighted: Bool { isEnabled && hover.isHovered }
    private var pressed: Bool { isEnabled && configuration.isPressed }

    var body: some View {
        configuration.label
            .foregroundStyle(highlighted || pressed ? Color.primary : Color.secondary)
            .background(Color.primary.opacity(pressed ? SettingsDesign.Feedback.pressedFill : (highlighted ? SettingsDesign.Feedback.hoverFill : 0)),
                        in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.small))
            .opacity(isEnabled ? 1 : SettingsDesign.Feedback.disabledOpacity)
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.hoverDuration), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.pressedDuration), value: pressed)
    }
}

/// Use the system switch so current macOS supplies its material and accessibility.
/// System Settings proportions: a capsule thumb inside a compact capsule track.
private struct AppleSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
        }
        .buttonStyle(SwitchFeedbackStyle(isOn: configuration.isOn))
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

private struct SwitchFeedbackStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        SwitchFeedbackBody(isOn: isOn, isPressed: configuration.isPressed)
    }
}

private struct SwitchFeedbackBody: View {
    let isOn: Bool
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : SettingsDesign.Palette.switchOff)
            .overlay {
                Capsule().fill(isEnabled && isPressed ? Color.black.opacity(0.14) : Color.white.opacity(isEnabled && hover.isHovered ? 0.1 : 0))
            }
            .overlay(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 26, height: 18)
                    .padding(SettingsDesign.Spacing.optical)
            }
            .opacity(isEnabled ? 1 : SettingsDesign.Feedback.disabledOpacity)
            .frame(width: 44, height: 22)
            .contentShape(Capsule())
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: SettingsDesign.Feedback.switchDuration), value: isOn)
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.hoverDuration), value: hover.isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.pressedDuration), value: isPressed)
    }
}

/// Keep AppKit slider tracking, keyboard input and accessibility with a solid white thumb.
private struct AngleSlider: NSViewRepresentable {
    @Binding var value: Double
    let isFallback: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> ThumbFeedbackSlider {
        let slider = ThumbFeedbackSlider()
        slider.cell = ThumbFeedbackSliderCell()
        slider.minValue = 20
        slider.maxValue = 130
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel("Animation start angle")
        return slider
    }

    func updateNSView(_ slider: ThumbFeedbackSlider, context: Context) {
        context.coordinator.value = $value
        slider.doubleValue = value
        slider.isEnabled = isEnabled
        slider.toolTip = isFallback ? "Choose the manual fallback angle."
                                    : "Choose the lid angle at which the effect starts."
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ slider: NSSlider) {
            value.wrappedValue = slider.doubleValue
            slider.doubleValue = value.wrappedValue
        }
    }
}

private final class ThumbFeedbackSlider: NSSlider {
    var isHovered = false
    private var hoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
}

private final class ThumbFeedbackSliderCell: NSSliderCell {
    override func drawKnob(_ knobRect: NSRect) {
        let slider = controlView as? ThumbFeedbackSlider
        let enabled = slider?.isEnabled == true
        let inset: CGFloat = enabled && isHighlighted ? 3 : (enabled && slider?.isHovered == true ? 1 : 2)
        let diameter = min(knobRect.width, knobRect.height) - inset * 2
        let centerY = barRect(flipped: controlView?.isFlipped ?? false).midY
        let circle = NSRect(x: knobRect.midX - diameter / 2, y: centerY - diameter / 2,
                            width: diameter, height: diameter)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: circle).fill()
    }
}
