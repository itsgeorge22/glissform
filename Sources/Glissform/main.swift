import AppKit
import MetalKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private func makeGlissformAppIcon() -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()

    let background = NSBezierPath(
        roundedRect: NSRect(x: 42, y: 42, width: 428, height: 428),
        xRadius: 112,
        yRadius: 112
    )
    background.addClip()
    NSGradient(colors: [
        NSColor(red: 0.24, green: 0.26, blue: 0.29, alpha: 1),
        NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1),
    ])?.draw(in: background, angle: -45)

    NSColor.white.setStroke()
    let rearScreen = NSBezierPath(
        roundedRect: NSRect(x: 142, y: 188, width: 224, height: 150),
        xRadius: 20,
        yRadius: 20
    )
    rearScreen.lineWidth = 22
    rearScreen.stroke()

    let frontScreen = NSBezierPath(
        roundedRect: NSRect(x: 188, y: 146, width: 224, height: 150),
        xRadius: 20,
        yRadius: 20
    )
    frontScreen.lineWidth = 22
    frontScreen.stroke()

    image.unlockFocus()
    image.isTemplate = false
    return image
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let enableMenuItem = NSMenuItem(title: "Enable Infinite Screen", action: nil, keyEquivalent: "")
    private let sensor = LidSensor()
    private let capture = DesktopCapture()
    private let settingsModel = SettingsModel()
    private var settingsWindowController: SettingsWindowController?
    private var window: OverlayWindow?
    private var renderer: EffectRenderer?
    private var motion = ClosingMotion()
    private var observers: [NSObjectProtocol] = []
    private var heartbeat: Timer?
    private var revealTimer: Timer?
    private var lastReading = Date.distantPast
    private var hasSnapshot = false
    private var finishingGesture = false
    private var entrancePending = false
    private var snapshotTask: Task<Void, Never>?
    private var snapshotRequested = false
    private var snapshotToken = 0
    private var displayID: CGDirectDisplayID?
    private var sleeping = false
    private var quitting = false
    private var ready = false
    private var currentProgress: Float = 0
    private var retryAfter = Date.distantPast
    private var starting = false
    private var permissionRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = makeGlissformAppIcon()
        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "Glissform")
        statusItem.button?.toolTip = "Glissform — lid animation"
        UserDefaults.standard.register(defaults: ["animationStartAngle": 100.0, "animationEnabled": true])
        let storedAngle = UserDefaults.standard.double(forKey: "animationStartAngle")
        let startAngle = storedAngle.isFinite ? min(130, max(20, storedAngle)).rounded() : 100
        let animationEnabled = UserDefaults.standard.bool(forKey: "animationEnabled")
        motion.startAngle = startAngle
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        enableMenuItem.target = self
        enableMenuItem.action = #selector(toggleAnimation)
        enableMenuItem.state = animationEnabled ? .on : .off
        menu.addItem(enableMenuItem)
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Glissform", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
        installApplicationMenu()

        settingsModel.configure(
            animationEnabled: animationEnabled,
            startAngle: startAngle,
            screenCaptureAllowed: CGPreflightScreenCaptureAccess()
        )
        settingsModel.onAnimationEnabledChange = { [weak self] enabled in
            self?.applyAnimationEnabled(enabled)
        }
        settingsModel.onStartAngleChange = { [weak self] angle in
            self?.applyStartAngle(angle)
        }
        settingsModel.onOpenPermissions = { [weak self] in self?.openPermissions() }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
            guard let self, !self.sleeping else { return }
            self.restart()
            }
        })
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
            guard let self, !self.sleeping, !self.quitting else { return }
            self.settingsModel.refreshPermission()
            if Date().timeIntervalSince(self.lastReading) > 1 {
                self.endGesture()
                self.motion.reset()
                self.settingsModel.updateSensorStatus("Sensor unavailable")
            }
            if !self.ready, !self.starting, Date() >= self.retryAfter { self.connect() }
            }
        }
        startSensor()
        connect()
        DispatchQueue.main.async { [weak self] in
            self?.showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func setStatus(_ text: String) {
        statusLine.title = text
        settingsModel.updateRuntimeStatus(text)
    }

    private func startSensor() {
        motion.reset()
        sensor.start(onReading: { [weak self] angle in
            guard let self, !self.sleeping, !self.quitting else { return }
            self.lastReading = Date()
            self.settingsModel.updateAngle(angle)
            guard self.settingsModel.animationEnabled else {
                self.finishGesture()
                self.motion.reset()
                self.setStatus("Paused")
                return
            }
            guard self.ready else { return }
            let progress = self.motion.update(angle: angle)
            self.currentProgress = progress
            self.renderer?.setLidAngle(angle, referenceAngle: self.motion.activationAngle)
            guard self.motion.active else {
                self.finishGesture()
                self.setStatus("Ready")
                return
            }
            if self.finishingGesture {
                self.finishingGesture = false
                self.entrancePending = false
                self.renderer?.beginAnimation()
                self.revealOverlay()
            }
            if !self.snapshotRequested { self.takeSnapshot() }
            self.showProgress()
        }, onStatus: { [weak self] status in
            guard let self else { return }
            self.settingsModel.updateSensorStatus(status)
            if !status.lowercased().contains("connected") { self.setStatus(status) }
        })
    }

    private func connect() {
        guard !starting, !sleeping, !quitting else { return }
        guard CGPreflightScreenCaptureAccess() else {
            setStatus("Screen Recording permission required")
            if !permissionRequested {
                permissionRequested = true
                CGRequestScreenCaptureAccess()
            }
            retryAfter = Date().addingTimeInterval(2)
            return
        }
        guard let screen = NSScreen.screens.first(where: {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }), let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            setStatus("Waiting for built-in display")
            retryAfter = Date().addingTimeInterval(3)
            return
        }
        starting = true
        window?.close()
        let overlay = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        overlay.animationBehavior = .none
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        guard let effect = EffectRenderer(view: view) else {
            setStatus("Metal rendering unavailable")
            starting = false
            retryAfter = Date().addingTimeInterval(10)
            return
        }
        overlay.contentView = view
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()
        window = overlay
        renderer = effect
        self.displayID = displayID
        ready = true
        starting = false
        motion.reset()
        setStatus("Ready · Close the lid to animate")
    }

    private func takeSnapshot() {
        guard let displayID else { return }
        snapshotRequested = true
        snapshotToken += 1
        let token = snapshotToken
        setStatus("Taking screenshot…")
        snapshotTask = Task { [weak self] in
            guard let self else { return }
            do {
                let buffer = try await capture.screenshot(displayID: displayID)
                guard !Task.isCancelled, token == snapshotToken, motion.active,
                      ready, !sleeping, !quitting else { return }
                guard let renderer else { return }
                try await renderer.prepareSnapshot(pixelBuffer: buffer)
                guard !Task.isCancelled, token == snapshotToken, motion.active,
                      ready, !sleeping, !quitting else { return }
                hasSnapshot = true
                // Raise only after capture: the snapshot retains the normal Dock
                // and menu bar, while their live counterparts stay underneath.
                window?.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
                window?.ignoresMouseEvents = false
                window?.orderFrontRegardless()
                setStatus("Animating · Reopen to reverse")
                // First reveal the identity screenshot. Start geometry only
                // after the live-to-snapshot handoff has finished.
                entrancePending = true
                showProgress()
                revealOverlay()
            } catch {
                guard token == snapshotToken, !Task.isCancelled else { return }
                setStatus("Screenshot unavailable · check permission")
                NSLog("Screenshot: %@", error.localizedDescription)
            }
        }
    }

    private func revealOverlay(hiding: Bool = false) {
        revealTimer?.invalidate()
        let initialAlpha = window?.alphaValue ?? 0
        let targetAlpha: Double = hiding ? 0 : 1
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.hasSnapshot, !self.sleeping, !self.quitting else {
                    timer.invalidate()
                    return
                }
                let amount = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.08)
                let blend = amount * amount * (3 - 2 * amount)
                self.window?.alphaValue = initialAlpha + (targetAlpha - initialAlpha) * blend
                if amount == 1 {
                    timer.invalidate()
                    self.revealTimer = nil
                    if hiding, self.finishingGesture { self.endGesture() }
                    else if !hiding, self.entrancePending, !self.finishingGesture {
                        self.entrancePending = false
                        self.renderer?.beginAnimation()
                        self.showProgress()
                    }
                }
            }
        }
        revealTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func showProgress() {
        renderer?.progress = hasSnapshot && !entrancePending ? currentProgress : 0
        // Once revealed, sensor updates must not overwrite the entrance fade.
        if !hasSnapshot { window?.alphaValue = 0 }
    }

    private func finishGesture() {
        guard hasSnapshot else { endGesture(); return }
        guard !finishingGesture else { return }
        finishingGesture = true
        if entrancePending {
            entrancePending = false
            revealOverlay(hiding: true)
            return
        }
        // Keep the snapshot and controls covered until geometry reaches flat.
        renderer?.finishAnimation { [weak self] in
            guard let self, self.finishingGesture else { return }
            self.revealOverlay(hiding: true)
        }
    }

    private func endGesture() {
        finishingGesture = false
        entrancePending = false
        revealTimer?.invalidate()
        revealTimer = nil
        currentProgress = 0
        window?.alphaValue = 0
        window?.ignoresMouseEvents = true
        window?.level = .floating
        renderer?.progress = 0
        guard snapshotRequested else { return }
        snapshotToken += 1
        snapshotTask?.cancel()
        snapshotTask = nil
        snapshotRequested = false
        hasSnapshot = false
        renderer?.clear()
    }

    private func suspend() {
        sleeping = true
        ready = false
        starting = false
        endGesture()
        sensor.stop()
        motion.reset()
        renderer?.clear()
        displayID = nil
    }

    private func resume() {
        guard sleeping else { return }
        sleeping = false
        startSensor()
        retryAfter = Date().addingTimeInterval(1)
    }

    private func restart() {
        suspend()
        resume()
    }

    private func applyStartAngle(_ angle: Double) {
        guard motion.startAngle != angle else { return }
        endGesture()
        motion.reset()
        motion.startAngle = angle
        UserDefaults.standard.set(angle, forKey: "animationStartAngle")
        setStatus("Ready · Close past \(Int(angle))° to animate")
    }

    private func applyAnimationEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "animationEnabled")
        enableMenuItem.state = enabled ? .on : .off
        endGesture()
        motion.reset()
        if enabled {
            setStatus("Ready · Close past \(Int(settingsModel.startAngle))° to animate")
        } else {
            setStatus("Infinite Screen is off")
        }
    }

    @objc private func toggleAnimation() {
        settingsModel.setAnimationEnabled(!settingsModel.animationEnabled)
    }

    @objc private func showAbout() {
        settingsModel.selectedPage = .about
        showSettings()
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Glissform")
        for (title, action, key) in [("About Glissform", #selector(showAbout), ""),
                                     ("Settings…", #selector(showSettings), ",")] {
            let item = appMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide Glissform", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit Glissform", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsModel.refreshPermission()
        settingsWindowController?.present()
    }

    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func quitApp() {
        quitting = true
        heartbeat?.invalidate()
        sensor.stop()
        endGesture()
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--version") {
    print("Glissform \(Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development")")
} else if CommandLine.arguments.contains("--probe") {
    print(LidSensor.probe())
} else if CommandLine.arguments.contains("--render-test") {
    _ = NSApplication.shared
    do {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/render-test/hinge.png")
        try EffectRenderer.selfTest(outputURL: output)
        print("Metal rendering checks passed: \(output.path)")
    } catch {
        fputs("Render test failed: \(error)\n", stderr)
        exit(1)
    }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
