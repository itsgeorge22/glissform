import AppKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    enum Page: Hashable { case infiniteScreen, about }
    @Published var selectedPage: Page = .infiniteScreen
    @Published private(set) var animationEnabled = true
    @Published private(set) var startAngle = 100.0
    @Published private(set) var currentAngle: Double?
    @Published private(set) var sensorStatus = "Connecting…"
    @Published private(set) var screenCaptureAllowed = false
    @Published private(set) var runtimeStatus = "Starting…"

    var onAnimationEnabledChange: ((Bool) -> Void)?
    var onStartAngleChange: ((Double) -> Void)?
    @Published private(set) var resumeAfterPause = false
    var onResumeAfterPauseChange: ((Bool) -> Void)?

    var onOpenPermissions: (() -> Void)?

    func configure(animationEnabled: Bool, startAngle: Double, screenCaptureAllowed: Bool, resumeAfterPause: Bool = false) {
        self.animationEnabled = animationEnabled
        self.startAngle = startAngle
        self.screenCaptureAllowed = screenCaptureAllowed
        self.resumeAfterPause = resumeAfterPause
    }

    func setResumeAfterPause(_ enabled: Bool) {
        guard resumeAfterPause != enabled else { return }
        resumeAfterPause = enabled
        onResumeAfterPauseChange?(enabled)
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

    func updateAngle(_ angle: Double) {
        guard angle.isFinite, (0...180).contains(angle) else { return }
        if sensorStatus != "Connected" { sensorStatus = "Connected" }
        if currentAngle != angle { currentAngle = angle }
    }

    func updateSensorStatus(_ status: String) {
        if status == "Lid sensor ready" || status == "Connected" {
            sensorStatus = "Connected"
        } else {
            sensorStatus = "Sensor unavailable"
            currentAngle = nil
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
final class SettingsWindowController: NSWindowController {
    init(model: SettingsModel) {
        let contentHeight = min(SettingsDesign.Metrics.preferredHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 48)
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsDesign.Metrics.windowWidth, height: contentHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Glissform"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .textBackgroundColor
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: SettingsRootView(model: model) { [weak window] naturalHeight in
            guard let window else { return naturalHeight }
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            let maximumHeight = min(SettingsDesign.Metrics.preferredHeight, (visible?.height ?? 900) - 48)
            let height = min(ceil(naturalHeight), maximumHeight)
            var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0,
                width: SettingsDesign.Metrics.windowWidth, height: height))
            frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            if let visible { frame.origin.y = max(visible.minY, frame.origin.y) }
            if abs(window.frame.height - frame.height) > 0.5 {
                window.setFrame(frame, display: true)
            }
            return height
        })
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
private final class SettingsLayoutState: ObservableObject {
    @Published var height = SettingsDesign.Metrics.preferredHeight
    var naturalHeight: CGFloat = 0
}

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var layout = SettingsLayoutState()
    let resizeWindow: (CGFloat) -> CGFloat

    var body: some View {
        ScrollView {
            Group {
                switch model.selectedPage {
                case .infiniteScreen: AnimationSettingsView(model: model)
                case .about: AboutSettingsView(model: model)
                }
            }
            .frame(width: SettingsDesign.Metrics.windowWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: SettingsContentHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .frame(width: SettingsDesign.Metrics.windowWidth, height: layout.height, alignment: .topLeading)
        .background(SettingsDesign.Palette.background)
        .onPreferenceChange(SettingsContentHeightKey.self) { height in
            guard height > 0 else { return }
            layout.naturalHeight = height
            layout.height = resizeWindow(height)
        }
        .onAppear { model.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            if layout.naturalHeight > 0 { layout.height = resizeWindow(layout.naturalHeight) }
        }
    }
}

@MainActor
private final class MotionPreviewState: ObservableObject {
    @Published var isPlaying = false
    @Published var angle = 110.0
    var startingAngle = 110.0
    var referenceAngle = 110.0
    @Published var isStill = false
}

@MainActor
private final class PermissionPresentationState: ObservableObject {
    @Published var showConfirmation = false
}

private struct AnimationSettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var preview = MotionPreviewState()
    @StateObject private var permission = PermissionPresentationState()

    private var showsAccessCard: Bool { !model.screenCaptureAllowed || permission.showConfirmation }

    private var angleBinding: Binding<Double> {
        Binding(get: { model.startAngle }, set: { model.setStartAngle($0) })
    }
    private var displayedAngle: Double {
        if preview.isStill { return 42 }
        return preview.isPlaying ? preview.angle : (model.currentAngle ?? 110)
    }
    private var isIllustrating: Bool { preview.isPlaying || preview.isStill }
    private var canUseCurrentAngle: Bool {
        guard let angle = model.currentAngle else { return false }
        return (20...130).contains(angle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                        Text("Infinite Screen")
                            .font(SettingsDesign.Typography.pageTitle)
                            .tracking(-0.6)
                        Text("Your desktop stays in place as the lid closes.")
                            .font(SettingsDesign.Typography.body).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SettingsDesign.Spacing.label) {
                        Toggle("Infinite Screen", isOn: Binding(
                            get: { model.animationEnabled }, set: { model.setAnimationEnabled($0) }
                        ))
                        .labelsHidden().toggleStyle(AppleSwitchStyle())
                        .accessibilityLabel("Enable Infinite Screen")
                    }
                }

                if showsAccessCard {
                    ScreenAccessCard(model: model)
                        .padding(.top, SettingsDesign.Spacing.sections)
                        .transition(.opacity)
                }

                previewPanel
                    .padding(.top, showsAccessCard ? SettingsDesign.Spacing.cards : SettingsDesign.Spacing.sections)
                    .padding(.bottom, SettingsDesign.Spacing.cards)

                pauseControls
                    .padding(.vertical, SettingsDesign.Spacing.cardInset)
                    .modifier(SettingsCardSurface())

            }

            HStack(spacing: SettingsDesign.Spacing.label) {
                IconlyIcon(.lock, size: 12)
                Text("One screenshot. Only in memory.")
                Spacer()
                Button("Privacy & About") { model.selectedPage = .about }
                    .buttonStyle(FeedbackButtonStyle(kind: .link))
            }
            .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
            .padding(.top, SettingsDesign.Spacing.sections)
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
        .task(id: preview.isPlaying) {
            guard preview.isPlaying else { return }
            let start = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                guard elapsed < 4.928 else { break }
                // Remove the former 672 ms opening hold; retain the closing,
                // closed pause, reopening and final settling durations.
                let t = (elapsed + 0.672) / 5.6
                let amount: Double
                if t < 0.46 { amount = smooth((t - 0.12) / 0.34) }
                else if t < 0.56 { amount = 1 }
                else if t < 0.94 { amount = 1 - smooth((t - 0.56) / 0.38) }
                else { amount = 0 }
                preview.angle = preview.startingAngle
                    - max(0, preview.startingAngle - 22) * amount
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
            }
            if !Task.isCancelled { preview.isPlaying = false }
        }
        .onChange(of: reduceMotion) { _, _ in
            preview.isPlaying = false
            preview.isStill = false
        }
        .onDisappear { preview.isPlaying = false }
    }

    private var angleControls: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.Spacing.controls) {
            HStack {
                VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                    Text("Begin at").font(SettingsDesign.Typography.controlTitle)
                    Text("Higher angles start the effect sooner.")
                        .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                AngleEntry(model: model)
            }
            VStack(spacing: SettingsDesign.Spacing.detail) {
                AngleSlider(value: angleBinding)
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
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(model.currentAngle.map { "\(Int($0))°" } ?? "—")
                    .font(SettingsDesign.Typography.liveValue)
                    .accessibilityLabel("Current lid angle")
                    .accessibilityValue(model.currentAngle.map { "\(Int($0)) degrees" } ?? "Unavailable")
                Spacer()
                Button {
                    if !isIllustrating {
                        preview.startingAngle = displayedAngle
                        preview.referenceAngle = max(model.startAngle, displayedAngle)
                        preview.angle = displayedAngle
                    }
                    if reduceMotion {
                        preview.isStill.toggle()
                    } else {
                        preview.isPlaying.toggle()
                    }
                } label: {
                    IconlyLabel(previewButtonTitle, icon: isIllustrating ? .stop : .play)
                        .font(SettingsDesign.Typography.action)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .filled)).controlSize(.small)
                .help("An illustration of the effect. No screenshot or screen permission needed.")
            }
            .padding(.horizontal, SettingsDesign.Spacing.cardInset).padding(.top, SettingsDesign.Spacing.cardInset)
            MotionIllustration(angle: displayedAngle, referenceAngle: isIllustrating ? preview.referenceAngle : max(model.startAngle, displayedAngle))
                .frame(height: 165)
                .animation(reduceMotion || preview.isPlaying ? nil : .easeOut(duration: 0.16), value: displayedAngle)
                .accessibilityHidden(true)
                .padding(.bottom, SettingsDesign.Spacing.cards)

            SettingsDivider()
            angleControls
                .padding(.horizontal, SettingsDesign.Spacing.cardInset).padding(.top, SettingsDesign.Spacing.sections).padding(.bottom, SettingsDesign.Spacing.cardInset)
        }
        .modifier(SettingsCardSurface())
    }

    private var pauseControls: some View {
        HStack(spacing: SettingsDesign.Spacing.cards) {
            PauseFeatureIcon().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                Text("Resume desktop after a pause").font(SettingsDesign.Typography.controlTitle)
                Text("Restore your desktop after a 2-second pause below the starting angle.")
                    .font(SettingsDesign.Typography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("Resume desktop after a pause", isOn: Binding(
                get: { model.resumeAfterPause }, set: { model.setResumeAfterPause($0) }
            ))
            .labelsHidden().toggleStyle(AppleSwitchStyle())
            .accessibilityLabel("Resume desktop after a pause")
        }
        .padding(.horizontal, SettingsDesign.Spacing.cardInset)
    }

    private var previewButtonTitle: String {
        if reduceMotion { return preview.isStill ? "End preview" : "Still preview" }
        return preview.isPlaying ? "Stop preview" : "Preview motion"
    }

    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
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
                    .textFieldStyle(.plain).frame(width: 38)
                    .focused($isFocused)
                    .accessibilityLabel("Start angle in degrees")
                    .help("Enter an angle from 20° to 130°, then press Return.")
                    .onSubmit { commit() }
                Text("°")
                    .font(SettingsDesign.Typography.angleUnit).foregroundStyle(.secondary)
                    .offset(y: -2)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, SettingsDesign.Spacing.label).padding(.vertical, SettingsDesign.Spacing.label)
        }
        .background(SettingsDesign.Palette.field, in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.control))
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
            IconlyIcon(.chevronUp, size: 16, rotation: rotation)
                .offset(y: step > 0 ? 2 : -2)
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

/// An original vector study of the fixed desktop plane and moving lid.
/// It only draws synthetic geometry; it never talks to DesktopCapture or the overlay.
private struct MotionIllustration: View, Animatable {
    var angle: Double
    var referenceAngle: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, referenceAngle) }
        set { angle = newValue.first; referenceAngle = newValue.second }
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 480, size.height / 230)
            let origin = CGPoint(x: size.width * 0.52, y: size.height * 0.72)
            func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                CGPoint(x: origin.x + (x + y * 0.52) * scale,
                        y: origin.y + (x * 0.14 - y * 0.32 - z) * scale)
            }
            func panelPoint(_ u: Double, _ v: Double, _ degrees: Double) -> CGPoint {
                let r = degrees * .pi / 180
                return project((u - 0.5) * 224, -cos(r) * v * 139, sin(r) * v * 139)
            }
            func polygon(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points)
                path.closeSubpath()
                return path
            }
            func panel(_ degrees: Double, inset: Double = 0) -> Path {
                polygon([panelPoint(inset, inset, degrees), panelPoint(1-inset, inset, degrees),
                         panelPoint(1-inset, 1-inset, degrees), panelPoint(inset, 1-inset, degrees)])
            }
            let separation = min(1, max(0, (referenceAngle - angle) / 70))
            let base = polygon([project(-112, 0, 0), project(112, 0, 0),
                                project(112, -115, 0), project(-112, -115, 0)])
            context.fill(base, with: .color(.primary.opacity(0.045)))
            context.stroke(base, with: .color(.primary.opacity(0.36)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            let trackpad = polygon([project(-34, -72, 0), project(34, -72, 0),
                                    project(34, -100, 0), project(-34, -100, 0)])
            context.stroke(trackpad, with: .color(.primary.opacity(0.22)), lineWidth: 0.8)
            for row in 0..<4 {
                var line = Path()
                line.move(to: project(-89, -Double(15 + row * 12), 0))
                line.addLine(to: project(89, -Double(15 + row * 12), 0))
                context.stroke(line, with: .color(.primary.opacity(0.16)), lineWidth: 3)
            }

            let desktop = panel(referenceAngle)
            context.fill(desktop, with: .color(SettingsDesign.Palette.background))
            context.fill(desktop, with: .color(.primary.opacity(0.035)))
            context.stroke(desktop, with: .color(.primary.opacity(0.32)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            var artwork = context
            artwork.clip(to: panel(referenceAngle, inset: 0.035))
            // Contour ribbons give the app its own quiet visual signature.
            for index in 0..<13 {
                var ribbon = Path()
                for sample in 0...90 {
                    let u = Double(sample) / 90
                    let wave = sin(u * .pi * 1.6 + Double(index) * 0.055) * 0.22
                    let v = Double(index) * 0.064 + wave - 0.07
                    let point = panelPoint(u, v, referenceAngle)
                    if sample == 0 { ribbon.move(to: point) } else { ribbon.addLine(to: point) }
                }
                artwork.stroke(ribbon, with: .color(.primary.opacity(0.12 + Double(index) * 0.019)), lineWidth: 1.3)
            }
            if separation > 0.02 {
                for u in [0.0, 1.0] {
                    var guide = Path()
                    guide.move(to: panelPoint(u, 1, referenceAngle))
                    guide.addLine(to: panelPoint(u, 1, angle))
                    context.stroke(guide, with: .color(.primary.opacity(0.2 * separation)),
                                   style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                }
                let lid = panel(angle)
                context.fill(lid, with: .color(SettingsDesign.Palette.background.opacity(0.68)))
                context.fill(lid, with: .color(.primary.opacity(0.055)))
                context.stroke(lid, with: .color(.primary.opacity(0.6)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            } else {
                context.stroke(desktop, with: .color(.primary.opacity(0.55)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            }
            let camera = panelPoint(0.5, 0.976, angle)
            context.fill(Path(ellipseIn: CGRect(x: camera.x - 1.1, y: camera.y - 1.1, width: 2.2, height: 2.2)),
                         with: .color(.primary.opacity(0.5)))
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(SettingsDesign.Palette.dividerOverlay)
    }
}

private struct SettingsCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SettingsDesign.Palette.card, in: RoundedRectangle(cornerRadius: SettingsDesign.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: SettingsDesign.Radius.card).strokeBorder(SettingsDesign.Palette.cardBorder))
    }
}

private struct CardIconTile<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearance = IconlyAppearance.shared
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
            content.foregroundStyle(appearance.style == .custom || appearance.style == .bold
                ? SettingsDesign.Palette.cardIcon(color, scheme: colorScheme) : color.tile)
        }
        .frame(width: SettingsDesign.Metrics.iconSize, height: SettingsDesign.Metrics.iconSize)
    }
}

private struct PauseFeatureIcon: View {
    var body: some View {
        CardIconTile(color: .feature) {
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
                     ? "One screenshot per gesture, kept in memory. No audio captured."
                     : "Allow Screen & System Audio Recording to use the lid effect.")
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
        .padding(SettingsDesign.Spacing.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
        .accessibilityElement(children: .contain)
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
            VStack(alignment: .leading, spacing: SettingsDesign.Spacing.groups) {
                Button {
                    model.selectedPage = .infiniteScreen
                } label: {
                    HStack(spacing: SettingsDesign.Spacing.optical) {
                        IconlyIcon(.chevronUp, rotation: -90)
                        Text("Back")
                    }
                }
                .buttonStyle(FeedbackButtonStyle(kind: .filled)).controlSize(.small)
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to Infinite Screen")

                HStack(spacing: SettingsDesign.Spacing.label) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 68, height: 68).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SettingsDesign.Spacing.label) {
                        Text("Glissform")
                            .font(SettingsDesign.Typography.aboutTitle).tracking(-0.5)
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
            Text("Your screen stays yours.").font(SettingsDesign.Typography.sectionTitle)
            privacyDetail("One gesture. One screenshot.", text: "Captured only when the effect begins. No continuous recording.", symbol: .copy)
            privacyDetail("Here for a moment.", text: "Kept in memory, then released. Never saved or uploaded.", symbol: .memory)
            privacyDetail("Quiet by design.", text: "No audio capture, analytics, or network requests.", symbol: .lock)
        }
        .padding(SettingsDesign.Spacing.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
    }

    private func privacyDetail(_ title: String, text: String, symbol: IconlySymbol) -> some View {
        HStack(alignment: .top, spacing: SettingsDesign.Spacing.controls) {
            IconlyIcon(symbol, size: 20)
                .foregroundStyle(.secondary).frame(width: 22).padding(.top, SettingsDesign.Spacing.optical)
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
        slider.toolTip = "Choose the lid angle at which the effect starts."
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
