import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    enum Page: Hashable {
        case infiniteScreen, general, about, foundBug, license

        var title: String {
            switch self {
            case .infiniteScreen: return "Seamless Close"
            case .general: return "General"
            case .about: return "Privacy & about"
            case .foundBug: return "Send feedback"
            case .license: return "License"
            }
        }
    }
    @Published var selectedPage: Page = .infiniteScreen
    let licensing = LicenseController()
    @Published var licenseAllowsUse = true
    @Published private(set) var animationEnabled = true
    @Published private(set) var startAngle = 90.0
    @Published private(set) var automaticStartAngle = false
    @Published private(set) var automaticDetectionThreshold = 20.0
    var onAutomaticDetectionThresholdChange: ((Double) -> Void)?
    @Published private(set) var automaticAngleDuration = 1.0
    var onAutomaticAngleDurationChange: ((Double) -> Void)?
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
    @Published private(set) var resumeAfterPause = true
    @Published private(set) var pauseDuration = 1.0
    var onResumeAfterPauseChange: ((Bool) -> Void)?
    var onPauseDurationChange: ((Double) -> Void)?
    @Published private(set) var connectionEffectEnabled = true
    var onConnectionEffectEnabledChange: ((Bool) -> Void)?
    @Published private(set) var externalDisplaySupportEnabled = true
    @Published private(set) var externalDisplayStatus: String?
    var onExternalDisplaySupportChange: ((Bool) -> Void)?
    @Published private(set) var blurEnabled = true
    var onBlurEnabledChange: ((Bool) -> Void)?
    @Published private(set) var blurStrength: BlurStrength = .defaultStrength
    var onBlurStrengthChange: ((BlurStrength) -> Void)?
    @Published private(set) var runInBackground = true
    var onRunInBackgroundChange: ((Bool) -> Void)?
    @Published private(set) var showMenuBarIcon = true
    var onShowMenuBarIconChange: ((Bool) -> Void)?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginMessage: String?
    struct AvailableUpdate {
        let version: String
        let install: () -> Void
    }
    @Published private(set) var automaticUpdatesEnabled = false
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var canCheckForUpdates = false
    var onCheckForUpdates: (() -> Void)?
    var isDevelopmentBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "GlissformDeveloperTools") as? Bool == true
    }
    var manualUpdateAvailable: Bool { !automaticUpdatesEnabled && availableUpdate != nil }
    var onAutomaticUpdatesEnabledChange: ((Bool) -> Void)?

    @Published private(set) var analyticsConsent: UsageAnalyticsState.Consent = .undecided
    var onAnalyticsChoice: ((Bool) -> Void)?
    func syncAnalyticsConsent(_ consent: UsageAnalyticsState.Consent) { analyticsConsent = consent }
    func chooseAnalytics(_ allowed: Bool) { onAnalyticsChoice?(allowed) }

    var onOpenPermissions: (() -> Void)?

    func configure(animationEnabled: Bool, startAngle: Double, screenCaptureAllowed: Bool,
                   resumeAfterPause: Bool = true, automaticStartAngle: Bool = false,
                   pauseDuration: Double = 1, automaticAngleDuration: Double = 1,
                   automaticDetectionThreshold: Double = 20,
                   connectionEffectEnabled: Bool = true, blurEnabled: Bool = true, blurStrength: BlurStrength = .defaultStrength,
                   externalDisplaySupportEnabled: Bool = true,
                   runInBackground: Bool = true, showMenuBarIcon: Bool = true) {
        self.animationEnabled = animationEnabled
        self.startAngle = startAngle
        self.screenCaptureAllowed = screenCaptureAllowed
        self.resumeAfterPause = resumeAfterPause
        self.automaticStartAngle = automaticStartAngle
        self.automaticDetectionThreshold = ClosingMotion.validDetectionThreshold(automaticDetectionThreshold)
        self.pauseDuration = ClosingMotion.validStillDuration(pauseDuration)
        self.automaticAngleDuration = ClosingMotion.validStillDuration(automaticAngleDuration)
        self.connectionEffectEnabled = connectionEffectEnabled
        self.externalDisplaySupportEnabled = externalDisplaySupportEnabled
        self.blurEnabled = blurEnabled
        self.blurStrength = blurStrength
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

    func setAutomaticUpdatesEnabled(_ enabled: Bool) {
        guard automaticUpdatesEnabled != enabled else { return }
        automaticUpdatesEnabled = enabled
        onAutomaticUpdatesEnabledChange?(enabled)
    }

    func syncAutomaticUpdatesEnabled(_ enabled: Bool) {
        automaticUpdatesEnabled = enabled
    }

    func setAvailableUpdate(_ update: AvailableUpdate?) {
        availableUpdate = update
    }

    func syncCanCheckForUpdates(_ available: Bool) {
        canCheckForUpdates = available
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        onCheckForUpdates?()
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

    func setPauseDuration(_ duration: Double) {
        let value = ClosingMotion.validStillDuration(duration)
        guard pauseDuration != value else { return }
        pauseDuration = value
        onPauseDurationChange?(value)
    }

    func setAutomaticAngleDuration(_ duration: Double) {
        let value = ClosingMotion.validStillDuration(duration)
        guard automaticAngleDuration != value else { return }
        automaticAngleDuration = value
        onAutomaticAngleDurationChange?(value)
    }

    func setAutomaticDetectionThreshold(_ angle: Double) {
        let value = ClosingMotion.validDetectionThreshold(angle)
        guard automaticDetectionThreshold != value else { return }
        automaticDetectionThreshold = value
        learnedStartAngle = nil
        onAutomaticDetectionThresholdChange?(value)
    }

    func setConnectionEffectEnabled(_ enabled: Bool) {
        guard connectionEffectEnabled != enabled else { return }
        connectionEffectEnabled = enabled
        onConnectionEffectEnabledChange?(enabled)
    }

    func setExternalDisplaySupportEnabled(_ enabled: Bool) {
        guard externalDisplaySupportEnabled != enabled else { return }
        externalDisplaySupportEnabled = enabled
        onExternalDisplaySupportChange?(enabled)
    }

    func updateExternalDisplayStatus(_ status: String?) {
        if externalDisplayStatus != status { externalDisplayStatus = status }
    }

    func setBlurEnabled(_ enabled: Bool) {
        guard blurEnabled != enabled else { return }
        blurEnabled = enabled
        onBlurEnabledChange?(enabled)
    }

    func setBlurStrength(_ strength: BlurStrength) {
        guard blurStrength != strength else { return }
        blurStrength = strength
        onBlurStrengthChange?(strength)
    }

    var seamlessCloseHasCustomSettings: Bool {
        !animationEnabled || startAngle != 90 || automaticStartAngle
            || automaticDetectionThreshold != 20 || automaticAngleDuration != 1
            || !resumeAfterPause || pauseDuration != 1 || !connectionEffectEnabled || !blurEnabled
            || blurStrength != .defaultStrength || !externalDisplaySupportEnabled
    }

    func resetSeamlessCloseToDefaults() {
        setAutomaticStartAngle(false)
        setStartAngle(90)
        setAutomaticDetectionThreshold(20)
        setAutomaticAngleDuration(1)
        setResumeAfterPause(true)
        setPauseDuration(1)
        setConnectionEffectEnabled(true)
        setExternalDisplaySupportEnabled(true)
        setBlurEnabled(true)
        setBlurStrength(.defaultStrength)
        setAnimationEnabled(true)
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
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Glissform"
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
                sidebarSectionTitle("More")
                    .padding(.top, 12)
                navigationRow(.about)
                navigationRow(.foundBug)
                if model.licensing.isPreview { navigationRow(.license) }
                Spacer(minLength: 0)
                if model.analyticsConsent == .undecided {
                    AnalyticsSidebarCard(model: model)
                        .padding(.bottom, SettingsDesign.Spacing.detail)
                }
                if let update = model.availableUpdate, model.manualUpdateAvailable || model.licensing.isPreview {
                    sidebarUpdateCard(for: update)
                } else {
                    SidebarTrialCard(licensing: model.licensing) { model.selectedPage = .license }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 58).padding(.bottom, 16)
            .frame(width: SettingsDesign.Metrics.sidebarWidth)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings pages")
            .onMoveCommand { direction in
                let pages: [SettingsModel.Page] = [.general, .infiniteScreen, .about, .foundBug]
                    + (model.licensing.isPreview ? [.license] : [])
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
                    case .infiniteScreen:
                        if model.licenseAllowsUse { AnimationSettingsView(model: model) }
                        else { licensePage }
                    case .general: GeneralSettingsView(model: model)
                    case .about: AboutSettingsView(model: model)
                    case .foundBug: SendFeedbackView()
                    case .license: licensePage
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
        .tint(SettingsDesign.Palette.primaryBlue)
        .accentColor(SettingsDesign.Palette.primaryBlue)
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

    @ViewBuilder private var licensePage: some View {
        if model.licensing.isPreview {
            LicenseSettingsView(licensing: model.licensing)
        } else {
            GeneralSettingsView(model: model)
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

    private func sidebarUpdateCard(for update: SettingsModel.AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                FeatureIcon(.automaticUpdates, size: 16)
                    .foregroundStyle(SettingsDesign.Palette.primaryBlue)
                    .frame(width: 28, height: 28)
                    .background(SettingsDesign.Palette.primaryBlue.opacity(SettingsDesign.Palette.iconTileOpacity),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Update available")
                        .font(.system(size: 11, weight: .semibold))
                    Text(update.version)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Update", action: update.install)
                .buttonStyle(SidebarUpdateButtonStyle())
                .modifier(SettingsActionCursor())
                .accessibilityLabel("Update to \(update.version)")
        }
        .modifier(SidebarStatusCardSurface())
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
                    case .general: FeatureIcon(.general, size: 17)
                    case .about: IconlyIcon(.shieldDone, size: 17)
                    case .foundBug: FeatureIcon(.sendFeedback, size: 17)
                    case .license: FeatureIcon(.license, size: 17)
                    }
                }
                .foregroundStyle(SettingsDesign.Palette.onAccent)
                .frame(width: 28, height: 28)
                .background {
                    let tint = page == .infiniteScreen ? SettingsDesign.Palette.feature
                        : page == .general ? SettingsDesign.Palette.generalSidebar
                        : page == .about ? SettingsDesign.Palette.aboutSidebar
                        : page == .license ? SettingsDesign.Palette.licenseSidebar
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
        .modifier(SettingsActionCursor())
        .focused($focusedPage, equals: page)
        .focusEffectDisabled()
        .accessibilityAddTraits(model.selectedPage == page ? .isSelected : [])
        .accessibilityLabel(page.title)
    }

}

private struct SidebarStatusCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.065)))
            .padding(.horizontal, SettingsDesign.Metrics.sidebarRowInset)
    }
}

private struct SidebarTrialCard: View {
    @ObservedObject var licensing: LicenseController
    let openLicense: () -> Void

    var body: some View {
        if licensing.isPreview && licensing.access.licenseKey == nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Int(ceil(licensing.access.remainingTrial(at: context.date)))
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        FeatureIcon(.trial, size: 16)
                            .foregroundStyle(SettingsDesign.Palette.licenseSidebar)
                            .frame(width: 28, height: 28)
                            .background(SettingsDesign.Palette.licenseSidebar.opacity(SettingsDesign.Palette.iconTileOpacity),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(remaining > 0 ? "Free trial" : "Trial ended")
                                .font(.system(size: 11, weight: .semibold))
                            Text(licensing.access.trialTimeLeft(at: context.date))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("View license", action: openLicense)
                        .buttonStyle(SidebarUpdateButtonStyle())
                        .modifier(SettingsActionCursor())
                }
                .modifier(SidebarStatusCardSurface())
            }
        }
    }
}

private struct SidebarUpdateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarUpdateButtonBody(configuration: configuration)
    }
}

private struct SidebarUpdateButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SettingsDesign.Palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(configuration.isPressed ? SettingsDesign.Palette.primaryPressed
                        : hovered ? SettingsDesign.Palette.primaryHover : SettingsDesign.Palette.primaryBlue,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.hoverDuration), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.pressedDuration), value: configuration.isPressed)
    }
}

private struct LicenseSettingsView: View {
    @ObservedObject var licensing: LicenseController
    @State private var key = ""
    @State private var confirmingDeactivation = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.cards) {
            SettingsFeatureHeader(title: "Make Glissform yours",
                subtitle: "Subtle animations for everyday Mac interactions.")
                .padding(.bottom, SettingsDesign.Spacing.detail)
            HStack(spacing: SettingsDesign.Spacing.controls) {
                CardIconTile(color: .success) { FeatureIcon(.license) }
                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
                    Text(licensing.status).font(SettingsDesign.Typography.controlTitle)
                    Text(licensing.access.licenseKey == nil
                        ? "Pay $2.99 once for lifetime access on this Mac."
                        : "Lifetime access for this Mac.")
                        .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: SettingsDesign.Spacing.controls)
                if licensing.access.licenseKey == nil {
                    Button("Buy for $2.99") { Task { await licensing.buy() } }
                        .buttonStyle(FeedbackButtonStyle(kind: .filled))
                        .fixedSize()
                        .modifier(SettingsActionCursor(isActionEnabled: !licensing.busy))
                }
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SettingsCardSurface())

            VStack(alignment: .leading, spacing: 12) {
                if let savedKey = licensing.access.licenseKey {
                    Text("License key").font(SettingsDesign.Typography.controlTitle)
                    Text(savedKey).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button("Deactivate this Mac") { confirmingDeactivation = true }
                        .buttonStyle(FeedbackButtonStyle(kind: .quiet))
                    Text("Free a device slot before moving Glissform to another Mac.")
                        .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                } else {
                    Text("Already have a license?").font(SettingsDesign.Typography.controlTitle)
                    TextField("Paste your license key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("License key")
                        .onSubmit { Task { await licensing.activate(key) } }
                    Button("Activate this Mac") { Task { await licensing.activate(key) } }
                        .buttonStyle(FeedbackButtonStyle(kind: .quiet))
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SettingsCardSurface())
            if licensing.busy { ProgressView().controlSize(.small).accessibilityLabel("Contacting license service") }
            if let message = licensing.message {
                Text(message).font(SettingsDesign.Typography.body)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }

        }
        .disabled(licensing.busy)
        .padding(SettingsDesign.Spacing.page)
        .confirmationDialog("Deactivate Glissform on this Mac?", isPresented: $confirmingDeactivation) {
            Button("Deactivate this Mac", role: .destructive) { Task { await licensing.deactivate() } }
        } message: {
            Text("The license slot becomes available for another Mac. An active trial can still be used.")
        }
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
            Toggle(title, isOn: $isEnabled)
                .labelsHidden().toggleStyle(AppleSwitchStyle())
                .accessibilityLabel("Enable \(title)")
        }
    }
}

@MainActor
private final class PermissionPresentationState: ObservableObject {
    @Published var showConfirmation = false
}

private enum BlurPreviewAssets {
    static let images: [BlurStrength: NSImage] = Dictionary(uniqueKeysWithValues:
        BlurStrength.allCases.map { strength in
            guard let url = AppResource.url("blur-\(strength.rawValue)",
                                            extension: "png", subdirectory: "BlurPreviews"),
                  let image = NSImage(contentsOf: url), image.isValid else {
                preconditionFailure("Missing \(strength.title) blur preview")
            }
            return (strength, image)
        })
}

private struct AnimationSettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var permission = PermissionPresentationState()
    @State private var hoveredBlurStrength: BlurStrength?

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

            if showsAccessCard {
                ScreenAccessCard(model: model).transition(.opacity)
            }
            infiniteScreenCard
            automaticAngleControls
                .modifier(SettingsCardSurface())
            pauseControls
                .modifier(SettingsCardSurface())
            connectionEffectControls
                .padding(SettingsDesign.Spacing.mainCardInsets)
                .modifier(SettingsCardSurface())
            blurControls
                .modifier(SettingsCardSurface())
            externalDisplayControls
                .modifier(SettingsCardSurface())
            Button("Reset to defaults") { model.resetSeamlessCloseToDefaults() }
                .buttonStyle(FeedbackButtonStyle(kind: .quiet))
                .disabled(!model.seamlessCloseHasCustomSettings)
                .modifier(SettingsActionCursor(isActionEnabled: model.seamlessCloseHasCustomSettings))
                .help("Restore all Seamless Close settings to their defaults.")
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                             isEnabled: Binding(get: { model.animationEnabled }, set: { model.setAnimationEnabled($0) })) {
                FeatureIcon(.infiniteScreen)
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)

            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)

            angleControls
                .padding(SettingsDesign.Spacing.supportCardInsets)
            escapeShortcutHint
        }
        .modifier(SettingsCardSurface())
    }

    private var escapeShortcutHint: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)
            HStack(spacing: 12) {
                Text("Esc")
                    .font(SettingsDesign.Typography.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SettingsDesign.Palette.cardBorder, in: RoundedRectangle(cornerRadius: 6))
                Text("Press Esc during the animation to return to your desktop.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SettingsDesign.Spacing.supportCardInsets)
        }
    }

    private var angleControls: some View {
        let automaticAngleIsActive = model.automaticStartAngle && model.learnedStartAngle != nil
        return VStack(alignment: .leading, spacing: SettingsDesign.Spacing.controls) {
            HStack {
                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                    Text("Begin at").font(SettingsDesign.Typography.controlTitle)
                    Text(automaticAngleIsActive
                         ? "Turn off automatic selection to edit this saved angle."
                         : "Higher angles start the effect sooner.")
                        .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                AngleEntry(title: "Start angle", angle: model.startAngle,
                           isDisabled: automaticAngleIsActive, setAngle: model.setStartAngle)
            }
            VStack(spacing: SettingsDesign.Spacing.detail) {
                AngleSlider(value: angleBinding, isFallback: automaticAngleIsActive)
                    .frame(height: 22)
                    .disabled(automaticAngleIsActive)
                    .accessibilityLabel("Animation start angle")
                    .accessibilityValue("\(Int(model.startAngle)) degrees")
                HStack {
                    Text("20°").foregroundStyle(.secondary)
                    Spacer()
                    Button(model.displayedLidAngle.map { "Use current angle (\(Int($0))°)" }
                           ?? "Use current angle") {
                        if let angle = model.currentAngle { model.setStartAngle(angle) }
                    }
                    .buttonStyle(FeedbackButtonStyle(kind: .link))
                    .disabled(!canUseCurrentAngle || automaticAngleIsActive)
                    .modifier(SettingsActionCursor(isActionEnabled: canUseCurrentAngle && !automaticAngleIsActive))
                    .help("Use the current lid angle. Open a little farther, then close to begin.")
                    Text("·").foregroundStyle(.tertiary)
                    Button("Reset") { model.setStartAngle(90) }
                        .buttonStyle(FeedbackButtonStyle(kind: .link))
                        .disabled(model.startAngle == 90 || automaticAngleIsActive)
                        .modifier(SettingsActionCursor(isActionEnabled: model.startAngle != 90 && !automaticAngleIsActive))
                        .help("Restore the default start angle of 90°")
                        .accessibilityLabel("Reset start angle to 90 degrees")
                    Spacer()
                    Text("130°").foregroundStyle(.secondary)
                }
                .font(SettingsDesign.Typography.caption)
            }
        }
        .opacity(automaticAngleIsActive ? 0.72 : 1)
    }

    private var pauseControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: SettingsDesign.Spacing.cards) {
                PauseFeatureIcon().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resume desktop after pause").font(SettingsDesign.Typography.controlTitle)
                    Text("Restores the desktop when the lid stays still.")
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
            .padding(SettingsDesign.Spacing.mainCardInsets)

            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)

            waitTimeControl(title: "Resume wait time",
                            detail: "How long the lid stays still before restoring the desktop.",
                            duration: model.pauseDuration,
                            setDuration: model.setPauseDuration)
                .padding(SettingsDesign.Spacing.supportCardInsets)
        }
    }

    private var connectionEffectControls: some View {
        FeatureToggleRow(title: "Connection effect",
                         detail: "Adds a soft edge glow and click when the desktop returns.",
                         color: .connectionEffect,
                         isEnabled: Binding(get: { model.connectionEffectEnabled },
                                            set: { model.setConnectionEffectEnabled($0) })) {
            FeatureIcon(.connectionEffect)
        }
    }

    private var externalDisplayControls: some View {
        VStack(spacing: 0) {
            FeatureToggleRow(title: "External display support",
                             detail: "Adapt Seamless Close when other displays are connected.",
                             color: .externalDisplay,
                             isEnabled: Binding(get: { model.externalDisplaySupportEnabled },
                                                set: { model.setExternalDisplaySupportEnabled($0) })) {
                FeatureIcon(.externalDisplay)
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)
            .help("When on, animate only the MacBook display and pause while it is mirrored. When off, pause whenever an external display is connected.")
            if let status = model.externalDisplayStatus {
                Rectangle().fill(SettingsDesign.Palette.cardBorder).frame(height: 1)
                Text(status)
                    .font(SettingsDesign.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SettingsDesign.Spacing.supportCardInsets)
            }
        }
    }

    private var blurControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: SettingsDesign.Spacing.cards) {
                CardIconTile(color: .blur) {
                    FeatureIcon(.blur)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blur").font(SettingsDesign.Typography.controlTitle)
                    Text("Softens the desktop as the lid closes.")
                        .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Blur", isOn: Binding(
                    get: { model.blurEnabled }, set: { model.setBlurEnabled($0) }
                ))
                .labelsHidden().toggleStyle(AppleSwitchStyle())
                .accessibilityLabel("Blur")
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)

            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)

            HStack(spacing: SettingsDesign.Spacing.cards) {
                ForEach(BlurStrength.allCases, id: \.self) { strength in
                    Button {
                        model.setBlurStrength(strength)
                    } label: {
                        VStack(spacing: SettingsDesign.Spacing.label) {
                            Image(nsImage: BlurPreviewAssets.images[strength]!)
                                .resizable()
                                .aspectRatio(1.6, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.Radius.control))
                                .overlay {
                                    RoundedRectangle(cornerRadius: SettingsDesign.Radius.control)
                                        .fill(Color.black.opacity(hoveredBlurStrength == strength ? 0.12 : 0))
                                }
                                .padding(4)
                                .overlay {
                                    if model.blurStrength == strength {
                                        RoundedRectangle(cornerRadius: SettingsDesign.Radius.icon)
                                            .strokeBorder(SettingsDesign.Palette.primaryBlue, lineWidth: 2)
                                    }
                                }
                                .accessibilityHidden(true)
                            Text(strength.title)
                                .font(SettingsDesign.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredBlurStrength = $0 ? strength : nil }
                    .modifier(SettingsActionCursor())
                    .animation(reduceMotion ? nil : .easeOut(duration: SettingsDesign.Feedback.hoverDuration),
                               value: hoveredBlurStrength == strength)
                    .accessibilityLabel("\(strength.title) blur strength")
                    .accessibilityValue(model.blurStrength == strength ? "Selected" : "Not selected")
                    .help("Use \(strength.title.lowercased()) blur for Seamless Close.")
                }
            }
            .padding(SettingsDesign.Spacing.supportCardInsets)
        }
    }

    private var automaticAngleControls: some View {
        VStack(spacing: 0) {
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
            .padding(SettingsDesign.Spacing.mainCardInsets)

            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)

            waitTimeControl(title: "Detection wait time",
                            detail: "How long the lid stays still before choosing the angle.",
                            duration: model.automaticAngleDuration,
                            setDuration: model.setAutomaticAngleDuration)
                .padding(SettingsDesign.Spacing.supportCardInsets)

            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)

            HStack(spacing: SettingsDesign.Spacing.cards) {
                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
                    Text("Detect above").font(SettingsDesign.Typography.controlTitle)
                    Text("Learn an angle when the lid is above this value. Set to 0 to disable.")
                        .font(SettingsDesign.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AngleEntry(title: "Detection threshold", angle: model.automaticDetectionThreshold,
                           allowsZero: true,
                           setAngle: model.setAutomaticDetectionThreshold)
            }
            .padding(SettingsDesign.Spacing.supportCardInsets)
        }
    }

    private var automaticAngleDescription: String {
        if model.automaticStartAngle, let angle = model.learnedStartAngle {
            return "Using \(Int(angle))°. Updates after a still lid pause."
        }
        if model.automaticStartAngle {
            if model.automaticDetectionThreshold == 0 {
                return "Waiting for a still lid. Begin at applies until then."
            }
            return "Waiting above \(Int(model.automaticDetectionThreshold))°. Begin at applies until then."
        }
        if model.automaticDetectionThreshold == 0 {
            return "Detects an angle after a still pause."
        }
        return "Detects an angle after a still pause above \(Int(model.automaticDetectionThreshold))°."
    }

    private func waitTimeControl(title: String, detail: String, duration: Double,
                                 setDuration: @escaping (Double) -> Void) -> some View {
        HStack(spacing: SettingsDesign.Spacing.cards) {
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
                Text("Wait time").font(SettingsDesign.Typography.controlTitle)
                Text(detail)
                    .font(SettingsDesign.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            WaitTimeEntry(title: title, duration: duration, setDuration: setDuration)
        }
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
                                                set: { model.setRunInBackground($0) })) {
                FeatureIcon(.backgroundRunning)
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)
            .modifier(SettingsCardSurface())

            FeatureToggleRow(title: "Menu bar icon",
                             detail: "Open Settings and controls from the menu bar.",
                             color: .neutral,
                             isEnabled: Binding(get: { model.showMenuBarIcon },
                                                set: { model.setShowMenuBarIcon($0) })) {
                FeatureIcon(.menuBarIcon)
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)
            .modifier(SettingsCardSurface())

            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                FeatureToggleRow(title: "Launch at login",
                                 detail: "Open Glissform when you sign in.",
                                 color: .neutral,
                                 isEnabled: Binding(get: { model.launchAtLoginEnabled },
                                                    set: { model.setLaunchAtLogin($0) })) {
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
            .padding(SettingsDesign.Spacing.mainCardInsets)
            .modifier(SettingsCardSurface())

            if model.isDevelopmentBuild {
                HStack(spacing: SettingsDesign.Spacing.controls) {
                    CardIconTile(color: .neutral) {
                        FeatureIcon(.automaticUpdates)
                    }
                    VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                        Text("Updates disabled in Dev")
                            .font(SettingsDesign.Typography.sectionTitle)
                        Text("Release updates are available only in Glissform.")
                            .font(SettingsDesign.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(SettingsDesign.Spacing.mainCardInsets)
                .modifier(SettingsCardSurface())
            } else {
                FeatureToggleRow(title: "Automatic updates",
                                 detail: "Download updates and install when Glissform quits.",
                                 color: .neutral,
                                 isEnabled: Binding(get: { model.automaticUpdatesEnabled },
                                                    set: { model.setAutomaticUpdatesEnabled($0) })) {
                    FeatureIcon(.automaticUpdates)
                }
                .padding(SettingsDesign.Spacing.mainCardInsets)
                .modifier(SettingsCardSurface())
            }
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
    let title: String
    let angle: Double
    var allowsZero = false
    var isDisabled = false
    let setAngle: (Double) -> Void
    @StateObject private var draft = AngleDraft()
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: SettingsDesign.Spacing.detail) {
            VStack(spacing: 0) {
                FieldStepArrow(rotation: 0, label: "Increase \(title.lowercased())",
                               help: "Increase \(title.lowercased()) by 1°", step: 1,
                               isDisabled: isDisabled || angle >= 130) {
                    stepAngle(1)
                }
                FieldStepArrow(rotation: 180, label: "Decrease \(title.lowercased())",
                               help: "Decrease \(title.lowercased()) by 1°", step: -1,
                               isDisabled: isDisabled || angle <= (allowsZero ? 0 : 20)) {
                    stepAngle(-1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                TextField(title, text: $draft.text)
                    .labelsHidden().multilineTextAlignment(.trailing)
                    .font(SettingsDesign.Typography.editableValue)
                    .textFieldStyle(.plain).frame(width: SettingsDesign.Metrics.angleNumberWidth)
                    .focused($isFocused)
                    .disabled(isDisabled)
                    .accessibilityLabel("\(title) in degrees")
                    .help(allowsZero
                          ? "Enter 0° to disable the threshold, or an angle from 20° to 130°, then press Return."
                          : "Enter an angle from 20° to 130°, then press Return.")
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
        .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.Radius.angleField))
        .modifier(ControlHoverFeedback(isActive: isFocused, inset: 0, isDisabled: isDisabled))
        .onAppear { draft.text = String(Int(angle)) }
        .onChange(of: angle) { _, newAngle in draft.text = String(Int(newAngle)) }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func commit() {
        let value = normalizedDraftAngle()
        setAngle(value)
        draft.text = String(Int(value))
    }

    private func stepAngle(_ step: Double) {
        let current = normalizedDraftAngle()
        let value: Double
        if allowsZero && step < 0 && current == 20 {
            value = 0
        } else if allowsZero && step > 0 && current == 0 {
            value = 20
        } else {
            value = min(130, max(20, current + step))
        }
        setAngle(value)
        draft.text = String(Int(value))
    }

    private func normalizedDraftAngle() -> Double {
        guard let typed = Double(draft.text.trimmingCharacters(in: .whitespacesAndNewlines)),
              typed.isFinite else { return angle }
        if allowsZero && typed <= 0 { return 0 }
        return min(130, max(20, typed)).rounded()
    }
}

private struct WaitTimeEntry: View {
    let title: String
    let duration: Double
    let setDuration: (Double) -> Void

    private var numberText: String {
        duration.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(duration)) : String(format: "%.1f", duration)
    }

    var body: some View {
        HStack(spacing: SettingsDesign.Spacing.detail) {
            VStack(spacing: 0) {
                FieldStepArrow(rotation: 0, label: "Increase \(title.lowercased())",
                               help: "Increase \(title.lowercased()) by 0.5 seconds", step: 1,
                               isDisabled: duration >= 10) {
                    setDuration(duration + 0.5)
                }
                FieldStepArrow(rotation: 180, label: "Decrease \(title.lowercased())",
                               help: "Decrease \(title.lowercased()) by 0.5 seconds", step: -1,
                               isDisabled: duration <= 0.5) {
                    setDuration(duration - 0.5)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(numberText)
                    .font(SettingsDesign.Typography.editableValue)
                    .frame(width: SettingsDesign.Metrics.angleNumberWidth, alignment: .trailing)
                Text("s")
                    .font(SettingsDesign.Typography.angleUnit)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, SettingsDesign.Spacing.angleFieldTrailingInset)
            .padding(.vertical, SettingsDesign.Spacing.angleFieldInset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(numberText) seconds")
        }
        .background(SettingsDesign.Palette.field,
                    in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.angleField))
        .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.Radius.angleField))
        .modifier(ControlHoverFeedback(inset: 0))
    }
}

private struct FieldStepArrow: View {
    let rotation: Double
    let label: String
    let help: String
    let step: Double
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconlyIcon(.chevronUp, size: SettingsDesign.Metrics.angleChevronSize, rotation: rotation)
                .offset(y: step > 0 ? 1.5 : -1.5)
                .frame(width: SettingsDesign.Metrics.arrowWidth, height: SettingsDesign.Metrics.arrowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(AngleArrowStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(isDisabled)
        .modifier(SettingsActionCursor(isActionEnabled: !isDisabled))
        .accessibilityLabel(label)
        .help(help)
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
                .fill(color.tile.opacity(SettingsDesign.Palette.iconTileOpacity))
            content.foregroundStyle(color.symbol(in: colorScheme))
        }
        .frame(width: SettingsDesign.Metrics.iconSize, height: SettingsDesign.Metrics.iconSize)
    }
}

private struct PauseFeatureIcon: View {
    var body: some View {
        CardIconTile(color: .pause) {
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
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
                Text(model.screenCaptureAllowed ? "Screen access allowed" : "Screen access required")
                    .font(SettingsDesign.Typography.controlTitle)
                Text(model.screenCaptureAllowed
                     ? "Screen images stay in memory."
                     : "Allow screen access for desktop effects.")
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(model.screenCaptureAllowed ? "Manage access…" : "Open Settings…") {
                model.onOpenPermissions?()
            }
            .buttonStyle(FeedbackButtonStyle(kind: .filled)).controlSize(.small)
            .modifier(SettingsActionCursor())
            .fixedSize()
            .help("Open Screen & System Audio Recording in System Settings to enable or revoke access for Glissform.")
        }
        .padding(SettingsDesign.Spacing.mainCardInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
        .accessibilityElement(children: .contain)
    }
}

enum FeedbackEmail {
    static let address = "support@glissform.app"

    static var draftURL: URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "body", value: "Glissform version: \(version)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        ]
        return components.url
    }
}

private struct SendFeedbackView: View {
    @State private var addressCopied = false
    @State private var copyFeedbackToken = 0
    @State private var emailAppUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.cards) {
            SettingsFeatureHeader(title: "Send feedback",
                subtitle: "We'd love to hear what you think about Glissform.")
                .padding(.bottom, SettingsDesign.Spacing.detail)
            contactCard
            guidanceCard
            HStack(alignment: .top, spacing: SettingsDesign.Spacing.label) {
                IconlyIcon(.shieldDone, size: 17)
                    .accessibilityHidden(true)
                Text("Nothing is sent until you send the email. Glissform does not attach screenshots or diagnostic files.")
                    .font(SettingsDesign.Typography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
        }
        .padding(SettingsDesign.Spacing.page)
        .alert("No email app available", isPresented: $emailAppUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy \(FeedbackEmail.address) and use it in your preferred email service.")
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: SettingsDesign.Spacing.controls) {
                CardIconTile(color: .feedback) { FeatureIcon(.sendFeedback) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
                    Text("Tell us what's on your mind")
                        .font(SettingsDesign.Typography.controlTitle)
                    Text("Send us a problem report, an idea, or a question.")
                        .font(SettingsDesign.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SettingsDesign.Spacing.mainCardInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(SettingsDesign.Palette.cardBorder)
                .frame(height: 1)
            HStack(spacing: SettingsDesign.Spacing.detail) {
                Text(FeedbackEmail.address)
                    .font(SettingsDesign.Typography.body)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    addressCopied = NSPasteboard.general.setString(FeedbackEmail.address, forType: .string)
                    if addressCopied { copyFeedbackToken += 1 }
                } label: {
                    if addressCopied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SettingsDesign.Palette.success)
                            .frame(width: 16, height: 16)
                    } else {
                        IconlyIcon(.copy, size: 16)
                    }
                }
                .buttonStyle(FeedbackButtonStyle(kind: .link))
                .modifier(SettingsActionCursor())
                .accessibilityLabel(addressCopied ? "Email address copied" : "Copy support email address")
                .help(addressCopied ? "Copied" : "Copy email address")
                .task(id: copyFeedbackToken) {
                    guard addressCopied else { return }
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                    addressCopied = false
                }
                Spacer(minLength: 0)
                Button("Send an email") { compose() }
                    .buttonStyle(FeedbackButtonStyle(kind: .filled))
                    .modifier(SettingsActionCursor())
            }
            .padding(SettingsDesign.Spacing.supportCardInsets)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
            Text("What helps in feedback")
                .font(SettingsDesign.Typography.controlTitle)
            Text("For a problem, tell us what happened, what you expected, and how to repeat it if you know. For an idea, tell us what you would like Glissform to do. The draft includes your Glissform and macOS versions; you can edit or remove them.")
                .font(SettingsDesign.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsDesign.Spacing.supportCardInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
    }

    private func compose() {
        guard let url = FeedbackEmail.draftURL, NSWorkspace.shared.open(url) else {
            emailAppUnavailable = true
            return
        }
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.groups) {
                Text("Privacy & about")
                    .font(SettingsDesign.Typography.pageTitle)
                    .tracking(SettingsDesign.Typography.headlineTracking)

                HStack(spacing: SettingsDesign.Spacing.label) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 68, height: 68).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Glissform")
                            .font(SettingsDesign.Typography.aboutTitle)
                            .tracking(SettingsDesign.Typography.headlineTracking)
                        Text("\(Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development")")
                            .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: SettingsDesign.Spacing.controls)
                    Button("Check for updates…") { model.checkForUpdates() }
                        .buttonStyle(FeedbackButtonStyle(kind: .filled))
                        .fixedSize()
                        .disabled(!model.canCheckForUpdates)
                        .modifier(SettingsActionCursor(isActionEnabled: model.canCheckForUpdates))
                        .help(model.isDevelopmentBuild
                              ? "Release updates are available only in Glissform."
                              : "Check for a newer version of Glissform.")
                }
                VStack(spacing: SettingsDesign.Spacing.cards) {
                    privacyCard
                    AnalyticsSettingsCard(model: model)
                    ScreenAccessCard(model: model)
                }

            }
            .padding(SettingsDesign.Spacing.page)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.cardInset) {
            Text("Private by design").font(SettingsDesign.Typography.sectionTitle)
            privacyDetail("Only what’s needed", text: "Uses lid angle and temporary screen images.", symbol: .copy)
            privacyDetail("Kept in memory", text: "Screen images are released after use, never saved or sent.", symbol: .memory)
            privacyDetail("Your choice", text: "Usage sharing is optional. Updates connect separately.", symbol: .lock)
        }
        .padding(SettingsDesign.Spacing.supportCardInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
    }

    private func privacyDetail(_ title: String, text: String, symbol: IconlySymbol) -> some View {
        HStack(alignment: .center, spacing: SettingsDesign.Spacing.controls) {
            CardIconTile(color: .neutral) {
                IconlyIcon(symbol, size: 24, isCardIcon: true)
            }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    private var isPressed: Bool { isEnabled && configuration.isPressed }
    private var isHovered: Bool { isEnabled && hover.isHovered }
    private var tint: Color { kind == .link ? SettingsDesign.Palette.link(in: colorScheme) : .primary }

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

/// Feedback stays within the text field; the outline indicates active editing.
private struct ControlHoverFeedback: ViewModifier {
    var isActive = false
    var inset: CGFloat = 4
    var isDisabled = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        let highlighted = isEnabled && !isDisabled && hover.isHovered
        let active = isEnabled && !isDisabled && isActive
        content
            .background {
                RoundedRectangle(cornerRadius: SettingsDesign.Radius.angleField)
                    .fill(Color.primary.opacity(highlighted ? SettingsDesign.Feedback.fieldHoverFill : 0))
                    .padding(-inset)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsDesign.Radius.angleField)
                    .strokeBorder(active ? SettingsDesign.Palette.focus : Color.primary.opacity(highlighted ? SettingsDesign.Feedback.fieldHoverBorder : 0), lineWidth: 1)
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
            .background {
                Rectangle()
                    .fill(Color.primary.opacity(pressed ? SettingsDesign.Feedback.pressedFill
                                                  : highlighted ? SettingsDesign.Feedback.hoverFill : 0))
                    .allowsHitTesting(false)
            }
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
        .modifier(SettingsActionCursor())
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
            .fill(isOn ? SettingsDesign.Palette.primaryBlue : SettingsDesign.Palette.switchOff)
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
        slider.trackFillColor = NSColor(SettingsDesign.Palette.primaryBlue)
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

private enum AnalyticsConsentContent {
    static let title = "Help improve Glissform"
    static let detail: LocalizedStringKey = "Optional usage statistics. [Privacy details](https://glissform.app/privacy/)"
    static let sidebarDetail: LocalizedStringKey = "Usage statistics. [Details](https://glissform.app/privacy/)"
}

private struct AnalyticsSidebarCard: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
                Text(AnalyticsConsentContent.title)
                    .font(.system(size: 11, weight: .semibold))
                Text(AnalyticsConsentContent.sidebarDetail)
                    .tint(SettingsDesign.Palette.link(in: colorScheme))
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: SettingsDesign.Spacing.detail) {
                Button("No thanks") { model.chooseAnalytics(false) }
                    .buttonStyle(FeedbackButtonStyle(kind: .quiet))
                    .fixedSize()
                Button("Allow") { model.chooseAnalytics(true) }
                    .buttonStyle(SidebarUpdateButtonStyle())
            }
            .modifier(SettingsActionCursor())
        }
        .modifier(SidebarStatusCardSurface())
    }
}

private struct AnalyticsSettingsCard: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: SettingsDesign.Spacing.controls) {
            CardIconTile(color: .feature) {
                FeatureIcon(.analytics, size: 24)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.detail) {
                Text(AnalyticsConsentContent.title).font(SettingsDesign.Typography.controlTitle)
                Text(AnalyticsConsentContent.detail)
                    .tint(SettingsDesign.Palette.link(in: colorScheme))
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.analyticsConsent == .undecided {
                HStack(spacing: SettingsDesign.Spacing.detail) {
                    Button("No thanks") { model.chooseAnalytics(false) }
                        .buttonStyle(FeedbackButtonStyle(kind: .quiet))
                    Button("Allow") { model.chooseAnalytics(true) }
                        .buttonStyle(SidebarUpdateButtonStyle())
                        .frame(width: 64)
                }
                .fixedSize()
                .modifier(SettingsActionCursor())
            } else {
                Toggle("Share usage statistics", isOn: Binding(
                    get: { model.analyticsConsent == .allowed },
                    set: { model.chooseAnalytics($0) }))
                    .labelsHidden().toggleStyle(AppleSwitchStyle())
            }
        }
        .padding(SettingsDesign.Spacing.mainCardInsets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
    }
}
