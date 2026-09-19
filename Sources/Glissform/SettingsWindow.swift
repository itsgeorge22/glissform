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
    var onOpenPermissions: (() -> Void)?

    func configure(animationEnabled: Bool, startAngle: Double, screenCaptureAllowed: Bool) {
        self.animationEnabled = animationEnabled
        self.startAngle = startAngle
        self.screenCaptureAllowed = screenCaptureAllowed
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
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 660),
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
        window.contentViewController = NSHostingController(rootView: SettingsRootView(model: model))
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

private struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Group {
            switch model.selectedPage {
            case .infiniteScreen: AnimationSettingsView(model: model)
            case .about: AboutSettingsView(model: model)
            }
        }
        .frame(width: 720, height: 660, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { model.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
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

private struct AnimationSettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var preview = MotionPreviewState()

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Infinite Screen")
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                            .tracking(-0.6)
                        Text("Your desktop stays in place as the lid closes.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Toggle("Infinite Screen", isOn: Binding(
                            get: { model.animationEnabled }, set: { model.setAnimationEnabled($0) }
                        ))
                        .labelsHidden().toggleStyle(AppleSwitchStyle())
                        .accessibilityLabel("Enable Infinite Screen")
                    }
                }

                previewPanel
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                ReadinessView(model: model)

            }

            HStack(spacing: 6) {
                Image(systemName: "lock").accessibilityHidden(true)
                Text("One screenshot. Only in memory.")
                Spacer()
                Button("Privacy & About") { model.selectedPage = .about }
                    .buttonStyle(FeedbackButtonStyle(kind: .link))
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 28)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(32)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Begin at").font(.system(size: 14, weight: .semibold))
                    Text("Higher angles start the effect sooner.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                AngleEntry(model: model)
            }
            AngleSlider(value: angleBinding)
                .frame(height: 22)
                .accessibilityLabel("Animation start angle")
                .accessibilityValue("\(Int(model.startAngle)) degrees")
            HStack {
                Text("20° · Later").foregroundStyle(.secondary)
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
                Text("Earlier · 130°").foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.top, -6)
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(model.currentAngle.map { "\(Int($0))°" } ?? "—")
                    .font(.system(size: 28, weight: .light, design: .rounded)).monospacedDigit()
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
                    Label(previewButtonTitle, systemImage: isIllustrating ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 3).padding(.vertical, 3)
                }
                .buttonStyle(FeedbackButtonStyle(kind: .filled)).controlSize(.small)
                .help("An illustration of the effect. No screenshot or screen permission needed.")
            }
            .padding(.horizontal, 20).padding(.top, 18)
            MotionIllustration(angle: displayedAngle, referenceAngle: isIllustrating ? preview.referenceAngle : max(model.startAngle, displayedAngle))
                .frame(height: 165)
                .animation(reduceMotion || preview.isPlaying ? nil : .easeOut(duration: 0.16), value: displayedAngle)
                .accessibilityHidden(true)
                .padding(.bottom, 16)

            Divider().overlay(Color.primary.opacity(0.025))
                .padding(.horizontal, 20)
            angleControls
                .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
        }
        .modifier(SettingsCardSurface())
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
        HStack(spacing: 4) {
            VStack(spacing: 0) {
                arrow("chevron.up", label: "Increase start angle", step: 1)
                    .disabled(model.startAngle >= 130)
                arrow("chevron.down", label: "Decrease start angle", step: -1)
                    .disabled(model.startAngle <= 20)
            }
            .padding(.leading, 4)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                TextField("Start angle", text: $draft.text)
                    .labelsHidden().multilineTextAlignment(.trailing)
                    .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                    .textFieldStyle(.plain).frame(width: 38)
                    .focused($isFocused)
                    .accessibilityLabel("Start angle in degrees")
                    .help("Enter an angle from 20° to 130°, then press Return.")
                    .onSubmit { commit() }
                Text("°")
                    .font(.system(size: 20)).foregroundStyle(.secondary)
                    .offset(y: -2)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, 8).padding(.vertical, 7)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .modifier(ControlHoverFeedback(isActive: isFocused, inset: 0, showsHover: false))
        .onAppear { draft.text = String(Int(model.startAngle)) }
        .onChange(of: model.startAngle) { _, angle in draft.text = String(Int(angle)) }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func arrow(_ symbol: String, label: String, step: Double) -> some View {
        Button {
            commit()
            model.setStartAngle(model.startAngle + step)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 17)
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
            context.fill(desktop, with: .color(Color(nsColor: .textBackgroundColor)))
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
                context.fill(lid, with: .color(Color(nsColor: .textBackgroundColor).opacity(0.68)))
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

private struct SettingsCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.04)))
    }
}

private struct ReadinessView: View {
    @ObservedObject var model: SettingsModel

    private var message: (symbol: String, title: String, detail: String, needsPermission: Bool) {
        if !model.animationEnabled {
            return ("pause.circle", "Take a pause", "Turn on Infinite Screen whenever you want it back.", false)
        }
        if !model.screenCaptureAllowed {
            return ("rectangle.badge.checkmark", "One step to your first gesture", "Allow Screen Recording in macOS settings. No audio is captured.", true)
        }
        if model.currentAngle == nil {
            return ("laptopcomputer", "Waiting for your MacBook", "A compatible built-in lid sensor is needed. The preview is still available.", false)
        }
        if model.runtimeStatus.contains("unavailable") || model.runtimeStatus.contains("Waiting") || model.runtimeStatus == "Starting…" {
            return ("exclamationmark.circle", "Not ready yet", model.runtimeStatus, model.runtimeStatus.contains("permission"))
        }
        if model.runtimeStatus.contains("Animating") || model.runtimeStatus.contains("Taking screenshot") {
            return ("arrow.uturn.backward.circle", "Following your gesture", "Reopen the lid to return to your live desktop.", false)
        }
        if let angle = model.currentAngle, angle <= model.startAngle {
            return ("arrow.up.forward.circle", "Open a little farther to begin", "Open past \(Int(model.startAngle))°, then close slowly to see the effect.", false)
        }
        return ("checkmark.circle", "Ready when you close", "Close past \(Int(model.startAngle))°. Reopen before sleep to reverse the effect.", false)
    }

    var body: some View {
        let state = message
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: state.symbol).font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(state.title).font(.system(size: 12, weight: .medium))
                Text(state.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if state.needsPermission {
                Button("Open Settings…") { model.onOpenPermissions?() }
                    .buttonStyle(FeedbackButtonStyle(kind: .filled)).controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsCardSurface())
        .accessibilityElement(children: .contain)
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Button {
                    model.selectedPage = .infiniteScreen
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(FeedbackButtonStyle(kind: .quiet))
                .keyboardShortcut("[", modifiers: .command)
                .help("Back to Infinite Screen")

                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 68, height: 68).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A little depth.\nA different perspective.")
                            .font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.5)
                        Text("Glissform \(Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Your desktop appears to stay in place as your MacBook closes. One familiar gesture, with a little more dimension.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your screen stays yours.")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    privacyDetail("One gesture. One screenshot.", text: "Captured only when the effect begins. No continuous recording.", symbol: "rectangle.on.rectangle")
                    privacyDetail("Here for a moment.", text: "Kept in memory, then released. Never saved or uploaded.", symbol: "memorychip")
                    privacyDetail("Quiet by design.", text: "No audio capture, analytics, or network requests.", symbol: "hand.raised")
                    Divider()
                    HStack {
                        Label(model.screenCaptureAllowed ? "Screen access allowed" : "Screen access needed", systemImage: model.screenCaptureAllowed ? "checkmark.circle" : "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Manage…") { model.onOpenPermissions?() }
                            .buttonStyle(FeedbackButtonStyle(kind: .filled)).controlSize(.small)
                    }
                    Text("macOS calls this Screen Recording, even for a single screenshot. Glissform captures only the built-in display for the effect.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 7) {
                    Text("A small app. Still taking shape.").font(.system(size: 12, weight: .semibold))
                    Text("This alpha has been tested on the MacBook Air M5 15-inch. Other models are still unverified. Normal sleep stays enabled; an opening effect after sleep is not yet available.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("Available in your menu bar. Close this window to keep Glissform running.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(32)
        }
    }

    private func privacyDetail(_ title: String, text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .light))
                .foregroundStyle(.secondary).frame(width: 22).padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(text).font(.caption).foregroundStyle(.secondary)
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
            .foregroundStyle(isEnabled ? tint : Color.secondary)
            .padding(.horizontal, kind == .filled ? 10 : 6)
            .padding(.vertical, kind == .filled ? 6 : 4)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(tint.opacity(isPressed ? 0.18 : (isHovered ? 0.10 : (kind == .filled ? 0.06 : 0))))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(tint.opacity(isPressed ? 0.3 : (isHovered ? 0.18 : 0)), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
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
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(highlighted ? 0.07 : 0))
                    .padding(-inset)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(active ? Color.accentColor.opacity(0.65) : Color.primary.opacity(highlighted ? 0.18 : 0), lineWidth: 1)
                    .padding(-inset)
                    .allowsHitTesting(false)
            }
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: active)
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
            .background(Color.primary.opacity(pressed ? 0.16 : (highlighted ? 0.09 : 0)),
                        in: RoundedRectangle(cornerRadius: 4))
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
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
            .fill(isOn ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            .opacity(isEnabled ? 1 : 0.45)
            .overlay {
                Capsule().fill(isEnabled && isPressed ? Color.black.opacity(0.14) : Color.white.opacity(isEnabled && hover.isHovered ? 0.1 : 0))
            }
            .overlay(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 26, height: 18)
                    .padding(2)
            }
            .frame(width: 44, height: 22)
            .contentShape(Capsule())
            .onHover { hover.isHovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isOn)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hover.isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
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
