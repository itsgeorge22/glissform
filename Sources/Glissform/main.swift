import AppKit
import MetalKit

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let enableMenuItem = NSMenuItem(title: "Enable Infinite Screen", action: nil, keyEquivalent: "")
    private let sensor = LidSensor()
    private let capture: DesktopScreenshotSource
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

    init(capture: DesktopScreenshotSource = DesktopCapture()) {
        self.capture = capture
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = BrandIcon.menuBar
        statusItem.button?.toolTip = "Glissform"
        UserDefaults.standard.register(defaults: ["animationStartAngle": 100.0, "animationEnabled": true,
                                                  "resumeAfterPause": false])
        let storedAngle = UserDefaults.standard.double(forKey: "animationStartAngle")
        let startAngle = storedAngle.isFinite ? min(130, max(20, storedAngle)).rounded() : 100
        let animationEnabled = UserDefaults.standard.bool(forKey: "animationEnabled")
        motion.startAngle = startAngle
        motion.resumeAfterPause = UserDefaults.standard.bool(forKey: "resumeAfterPause")
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
            screenCaptureAllowed: CGPreflightScreenCaptureAccess(),
            resumeAfterPause: motion.resumeAfterPause
        )
        settingsModel.onAnimationEnabledChange = { [weak self] enabled in
            self?.applyAnimationEnabled(enabled)
        }
        settingsModel.onStartAngleChange = { [weak self] angle in
            self?.applyStartAngle(angle)
        }
        settingsModel.onResumeAfterPauseChange = { [weak self] enabled in
            guard let self else { return }
            self.motion.resumeAfterPause = enabled
            UserDefaults.standard.set(enabled, forKey: "resumeAfterPause")
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setStatus(_ text: String) {
        statusLine.title = text
        settingsModel.updateRuntimeStatus(text)
    }

    private func startSensor() {
        motion.reset()
        sensor.start(onReading: { [weak self] angle in
            self?.handleLidReading(angle)
        }, onStatus: { [weak self] status in
            guard let self else { return }
            self.settingsModel.updateSensorStatus(status)
            if !status.lowercased().contains("connected") { self.setStatus(status) }
        })
    }

    private func handleLidReading(_ angle: Double, time: Double = ProcessInfo.processInfo.systemUptime) {
        guard !sleeping, !quitting else { return }
        lastReading = Date()
        settingsModel.updateAngle(angle)
        guard settingsModel.animationEnabled else {
            finishGesture()
            motion.reset()
            setStatus("Paused")
            return
        }
        guard ready else { return }
        let progress = motion.update(angle: angle, time: time)
        currentProgress = progress
        renderer?.setLidAngle(angle, referenceAngle: motion.activationAngle)
        guard motion.active else {
            finishGesture()
            setStatus(motion.desktopResumed ? "Desktop restored" : "Ready")
            return
        }
        if finishingGesture {
            finishingGesture = false
            entrancePending = false
            renderer?.beginAnimation()
            revealOverlay()
        }
        if !snapshotRequested { takeSnapshot() }
        showProgress()
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
        guard let effect = EffectRenderer(view: view, framesPerSecond: screen.maximumFramesPerSecond) else {
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
                // Reveal the prepared identity frame, then blend geometry and
                // opacity together so two handoffs do not accumulate latency.
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
                if !hiding, self.entrancePending, !self.finishingGesture {
                    self.entrancePending = false
                    self.renderer?.beginAnimation()
                    self.showProgress()
                }
                if amount == 1 {
                    timer.invalidate()
                    self.revealTimer = nil
                    if hiding, self.finishingGesture { self.endGesture() }
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
        if Bundle.main.object(forInfoDictionaryKey: "GlissformDeveloperTools") as? Bool == true {
            let developerItem = NSMenuItem()
            let developerMenu = NSMenu(title: "Developer")
            let heading = developerMenu.addItem(withTitle: "Icon Style", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            for (index, style) in [IconlyStyle.bulk, .bold, .outline, .custom].enumerated() {
                let item = developerMenu.addItem(withTitle: style.rawValue, action: #selector(changeIconStyle(_:)), keyEquivalent: String(index + 1))
                item.keyEquivalentModifierMask = [.command, .option]
                item.representedObject = style.rawValue
                item.target = self
                item.state = style == .current ? .on : .off
            }
            developerItem.submenu = developerMenu
            mainMenu.addItem(developerItem)
        }
        NSApp.mainMenu = mainMenu
    }

    @objc private func changeIconStyle(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let style = IconlyStyle(rawValue: value) else { return }
        IconlyAppearance.shared.style = style
        for item in sender.menu?.items ?? [] {
            guard let value = item.representedObject as? String else { continue }
            item.state = value == style.rawValue ? .on : .off
        }
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
        shutdown()
        NSApp.terminate(nil)
    }

    private func shutdown() {
        quitting = true
        heartbeat?.invalidate()
        sensor.stop()
        endGesture()
    }
}

extension AppDelegate {
    /// Real gesture/cancellation paths with synthetic pixels and no capture permission.
    static func lifecycleSelfTest() async throws {
        final class SyntheticCapture: DesktopScreenshotSource {
            var pending: CheckedContinuation<CVPixelBuffer, Error>?
            var count = 0
            func screenshot(displayID: CGDirectDisplayID) async throws -> CVPixelBuffer {
                count += 1
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
        }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition {
                throw NSError(domain: "Glissform.LifecycleTest", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        var storage: CVPixelBuffer?
        let attributes = [kCVPixelBufferMetalCompatibilityKey as String: true,
                          kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as [String: Any]
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &storage)
        guard let buffer = storage else { throw NSError(domain: "Glissform.LifecycleTest", code: 2) }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        func makeGesture() throws -> (AppDelegate, SyntheticCapture) {
            let source = SyntheticCapture()
            let app = AppDelegate(capture: source)
            let window = OverlayWindow(contentRect: NSRect(x: 16, y: 16, width: 64, height: 64),
                                       styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            let view = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
            guard let renderer = EffectRenderer(view: view) else {
                throw NSError(domain: "Glissform.LifecycleTest", code: 3)
            }
            window.contentView = view
            window.orderFrontRegardless()
            view.drawableSize = CGSize(width: 64, height: 64)
            app.window = window
            app.renderer = renderer
            app.displayID = CGMainDisplayID()
            app.ready = true
            app.settingsModel.configure(animationEnabled: true, startAngle: 100, screenCaptureAllowed: true)
            app.motion.startAngle = 100
            app.handleLidReading(110)
            app.handleLidReading(80)
            return (app, source)
        }
        func checkCleared(_ app: AppDelegate) throws {
            try check(!app.hasSnapshot && !app.snapshotRequested && app.snapshotTask == nil,
                      "Snapshot state must be cleared (alpha \(app.window?.alphaValue ?? -1), finishing \(app.finishingGesture), entrance \(app.entrancePending), paused \((app.window?.contentView as? MTKView)?.isPaused ?? true))")
            try check(app.window?.alphaValue == 0 && app.window?.ignoresMouseEvents == true,
                      "Interrupted gesture must restore desktop access")
            try check(!app.entrancePending && !app.finishingGesture && app.revealTimer == nil,
                      "Interrupted transitions must not remain pending")
        }
        func waitForCapture(_ source: SyntheticCapture) async throws {
            for _ in 0..<100 {
                if source.pending != nil { return }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            try check(false, "Gesture must request its screenshot")
        }
        func waitForCleanup(_ app: AppDelegate) async throws {
            // Display callbacks can be deprioritized for a tiny diagnostic
            // window. Verify eventual cleanup, without asserting frame pacing.
            for _ in 0..<100 {
                if !app.hasSnapshot { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        // Closing settings must preserve both an in-flight capture and a visible
        // gesture. Reopening must reuse the window and restore foreground access.
        for visible in [false, true] {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            let captureTask = app.snapshotTask
            if visible {
                try await Task.sleep(nanoseconds: 50_000_000)
                source.pending?.resume(returning: buffer)
                source.pending = nil
                await captureTask?.value
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            app.showSettings()
            let settings = app.settingsWindowController!.window!
            try check(settings.isVisible && NSApp.activationPolicy() == .regular,
                      "Opening settings must show the window and Dock icon")
            settings.performClose(nil)
            try check(!settings.isVisible && NSApp.activationPolicy() == .accessory,
                      "Closing settings must hide the window and Dock icon")
            try check(!app.applicationShouldTerminateAfterLastWindowClosed(NSApp) && !app.quitting && app.ready,
                      "Closing settings must leave the background coordinator running")
            try check(app.snapshotRequested && app.hasSnapshot == visible && source.count == 1,
                      "Closing settings must preserve the current gesture and its single capture")
            if visible {
                try check(app.window!.isVisible && app.window!.alphaValue > 0 && !app.window!.ignoresMouseEvents,
                          "Closing settings must preserve the active overlay")
            }
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await captureTask?.value
            try check(app.hasSnapshot, "Pending capture must complete while settings are closed")
            _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
            try check(app.settingsWindowController?.window === settings && settings.isVisible && NSApp.activationPolicy() == .regular,
                      "Reopening with an overlay present must restore the same settings window and Dock icon")
            settings.performClose(nil)
            app.handleLidReading(100)
            try await waitForCleanup(app)
            try checkCleared(app)
            print("PASS: settings close/reopen during \(visible ? "visible" : "pending") capture, background continuation and reversal cleanup")
        }
        // Resolve a capture *after* each interruption to prove stale work cannot reappear.
        // Also interrupt a revealed snapshot to verify overlay and GPU cleanup.
        for visible in [false, true] {
            for interruption in ["reversal", "sleep", "display change", "quit"] {
                let (app, source) = try makeGesture()
                defer { app.shutdown(); app.window?.close() }
                let task = app.snapshotTask
                try await waitForCapture(source)
                if visible {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    source.pending?.resume(returning: buffer)
                    source.pending = nil
                    await task?.value
                    try await Task.sleep(nanoseconds: 45_000_000)
                    try check(app.hasSnapshot && app.window!.alphaValue > 0, "Test snapshot must be visible")
                }
                switch interruption {
                case "reversal": app.handleLidReading(100)
                case "sleep": app.suspend()
                case "display change": app.restart(); app.sensor.stop()
                default: app.shutdown()
                }
                source.pending?.resume(returning: buffer)
                source.pending = nil
                await task?.value
                if visible && interruption == "reversal" { try await waitForCleanup(app) }
                try checkCleared(app)
                print("PASS: \(visible ? "visible snapshot cleanup" : "delayed snapshot cancellation") on \(interruption)")
            }
        }
        // Expire the still-lid timer through the real coordinator with fresh
        // synthetic timestamps, including captures that have not completed yet.
        for visible in [false, true] {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            let pendingTask = app.snapshotTask
            if visible {
                try await Task.sleep(nanoseconds: 50_000_000)
                source.pending?.resume(returning: buffer)
                source.pending = nil
                await pendingTask?.value
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            app.motion.resumeAfterPause = true
            app.motion.pauseDuration = 0.5
            for frame in 0...10 { app.handleLidReading(80, time: 100 + Double(frame) * 0.05) }
            try check(app.motion.desktopResumed && !app.motion.active, "Still lid must latch desktop restoration")
            if visible { try check(app.finishingGesture, "Visible restoration must return to flat before release") }
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await pendingTask?.value
            if visible { try await waitForCleanup(app) }
            try checkCleared(app)
            app.handleLidReading(70, time: 101)
            app.handleLidReading(100, time: 101.1)
            app.handleLidReading(80, time: 101.2)
            try check(source.count == 1 && !app.snapshotRequested,
                      "At or below the starting angle, resumed desktop must not recapture")
            app.handleLidReading(101, time: 101.3)
            app.handleLidReading(80, time: 101.4)
            try await waitForCapture(source)
            try check(source.count == 2, "Opening above threshold must allow one fresh capture")
            let rearmedTask = app.snapshotTask
            app.suspend()
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await rearmedTask?.value
            try checkCleared(app)
            print("PASS: pause restoration with \(visible ? "visible" : "pending") snapshot, below-threshold suppression, fresh rearm and sleep cleanup")
        }
        for interruption in ["sleep", "display change", "quit"] {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            try await Task.sleep(nanoseconds: 50_000_000)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            app.motion.resumeAfterPause = true
            app.motion.pauseDuration = 0.5
            for frame in 0...10 { app.handleLidReading(80, time: 100 + Double(frame) * 0.05) }
            switch interruption {
            case "sleep": app.suspend()
            case "display change": app.restart(); app.sensor.stop()
            default: app.shutdown()
            }
            try await Task.sleep(nanoseconds: 180_000_000)
            try checkCleared(app)
            print("PASS: pause return interrupted by \(interruption)")
        }
        let (app, source) = try makeGesture()
        defer { app.shutdown(); app.window?.close() }
        try await waitForCapture(source)
        // Let AppKit attach the test window's Metal layer before preparing it.
        try await Task.sleep(nanoseconds: 50_000_000)
        source.pending?.resume(returning: buffer)
        source.pending = nil
        await app.snapshotTask?.value
        try check(app.hasSnapshot, "Synthetic screenshot must reach the real renderer")
        try await Task.sleep(nanoseconds: 45_000_000)
        try check(!app.entrancePending && app.window!.alphaValue > 0,
                  "Geometry must begin during the visibility fade")
        app.handleLidReading(100)
        try await Task.sleep(nanoseconds: 40_000_000)
        app.handleLidReading(80)
        try await Task.sleep(nanoseconds: 250_000_000)
        try check(app.hasSnapshot && !app.finishingGesture && source.count == 1 && app.window!.alphaValue == 1,
                  "Reclosing must retain one snapshot and reject the old return completion")
        app.handleLidReading(100)
        try await waitForCleanup(app)
        try checkCleared(app)
        print("PASS: overlapping entrance, interrupted return, one-snapshot reclose, flat-frame cleanup")
    }
}

if CommandLine.arguments.contains("--version") {
    print("Glissform \(Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development")")
} else if CommandLine.arguments.contains("--probe") {
    print(LidSensor.probe())
} else if CommandLine.arguments.contains("--lifecycle-test") {
    _ = NSApplication.shared
    Task { @MainActor in
        do {
            try await AppDelegate.lifecycleSelfTest()
            print("Synthetic lifecycle checks passed")
            exit(0)
        } catch {
            fputs("Lifecycle test failed: \(error)\n", stderr)
            exit(1)
        }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--material-preview") {
    _ = NSApplication.shared
    do {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/material-preview")
        try EffectRenderer.materialPreview(outputDirectory: directory)
        print("Synthetic desktop material previews: \(directory.path)")
    } catch {
        fputs("Material preview failed: \(error)\n", stderr)
        exit(1)
    }
} else if CommandLine.arguments.contains("--render-test") || CommandLine.arguments.contains("--render-benchmark") {
    _ = NSApplication.shared
    do {
        let benchmark = CommandLine.arguments.contains("--render-benchmark")
        let directory = benchmark ? "render-benchmark" : "render-test"
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/\(directory)/hinge.png")
        try EffectRenderer.selfTest(outputURL: output, benchmark: benchmark)
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
