import AppKit
import Carbon
import MetalKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let enableMenuItem = NSMenuItem(title: "Enable Seamless Close", action: nil, keyEquivalent: "")
    private let sensor = LidSensor()
    private let capture: DesktopScreenshotSource
    private let desktopAvailable: (CGDirectDisplayID) -> Bool
    private let screenAccessAllowed: () -> Bool
    private let connectionSound: ConnectionSoundPlayback
    private let settingsModel = SettingsModel()
    private var appUpdates: AppUpdates?
    private var usageAnalytics: UsageAnalytics?
    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Glissform"
    }
    private var settingsWindowController: SettingsWindowController?
    private var window: OverlayWindow?
    private var renderer: EffectRenderer?
    private var motion = ClosingMotion()
    private var openingAssist = OpeningAssist()
    private var assistedOpeningPeakAngle: Double?
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var heartbeat: Timer?
    private var cleanupTimer: Timer?
    private var captureWarmupTask: Task<Void, Never>?
    private var captureWarmupGeneration = 0
    private var lastReading = Date.distantPast
    private var sensorRestartedAt = Date.distantPast
    private var lastLidAngle: Double?
    private var lastLidTime = -Double.infinity
    private var wakeOpening = WakeOpening()
    private var wakeTimer: Timer?
    private var wakeReceivedSample = false
    private var openingGesture = false
    private var retainedClosingSnapshot = false
    private var sleepPreparationTimer: Timer?
    private var screenLocked = false
    private var sessionInactive = false
    private var displayScale: CGFloat?
    private struct DisplayGeometry: Equatable {
        let id: CGDirectDisplayID
        let frame: CGRect
        let scale: CGFloat
    }
    private var displayLayout: [DisplayGeometry] = []
    private let wakeLog = Logger(subsystem: "com.george.glissform.mvp", category: "WakeOpening")
    private let animationLog = Logger(subsystem: "com.george.glissform.mvp", category: "AnimationTiming")
    private let timingEnabled = ProcessInfo.processInfo.environment["GLISSFORM_MOTION_DIAGNOSTICS"] == "1"
    private var hasSnapshot = false
    private var snapshotPresented = false
    private var finishingGesture = false
    private var snapshotTask: Task<Void, Never>?
    private var snapshotRequested = false
    private var earlyCaptureRequested = false
    private var earlyCaptureBlocked = false
    private var earlyCaptureAngle = 0.0
    private var earlyCaptureTime = 0.0
    private var snapshotToken = 0
    private var displayID: CGDirectDisplayID?
    private var sleeping = false
    private var quitting = false
    private var ready = false
    private var currentProgress: Float = 0
    private var retryAfter = Date.distantPast
    private var starting = false
    private var permissionRequested = false
    private var escapeHotKey: EventHotKeyRef?
    private var escapeHandler: EventHandlerRef?
    private var escapeReturning = false

    init(capture: DesktopScreenshotSource? = nil,
         desktopAvailable: @escaping (CGDirectDisplayID) -> Bool = DesktopAvailability.allowsCapture,
         screenAccessAllowed: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
         connectionSound: ConnectionSoundPlayback? = nil) {
        self.capture = capture ?? DesktopCapture()
        self.desktopAvailable = desktopAvailable
        self.screenAccessAllowed = screenAccessAllowed
        self.connectionSound = connectionSound ?? OpeningConnectionSound.shared
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        usageAnalytics = UsageAnalytics()
        settingsModel.syncAnalyticsConsent(usageAnalytics!.state.consent)
        settingsModel.onAnalyticsChoice = { [weak self] allowed in
            guard let self else { return }
            self.usageAnalytics?.choose(allowed)
            self.settingsModel.syncAnalyticsConsent(self.usageAnalytics!.state.consent)
        }
        usageAnalytics?.start()
        UserDefaults.standard.register(defaults: ["animationStartAngle": 90.0, "animationEnabled": true,
                                                  "resumeAfterPause": true,
                                                  "seamlessClosePauseDuration": 1.0,
                                                  "seamlessCloseAutomaticAngleDuration": 1.0,
                                                  "seamlessCloseDetectionThreshold": 20.0,
                                                  "seamlessCloseConnectionEffectEnabled": true,
                                                  "seamlessCloseBlurEnabled": true,
                                                  "seamlessCloseBlurStrength": BlurStrength.defaultStrength.rawValue,
                                                  "automaticStartAngleEnabled": false,
                                                  "runInBackground": true,
                                                  "showMenuBarIcon": true])
        // Retire saved preferences from the removed battery feature.
        UserDefaults.standard.removeObject(forKey: "chargingFeedbackEnabled")
        UserDefaults.standard.removeObject(forKey: "lowBatteryRippleEnabled")
        let storedAngle = UserDefaults.standard.double(forKey: "animationStartAngle")
        let startAngle = storedAngle.isFinite ? min(130, max(20, storedAngle)).rounded() : 90
        let animationEnabled = UserDefaults.standard.bool(forKey: "animationEnabled")
        motion.startAngle = startAngle
        motion.resumeAfterPause = UserDefaults.standard.bool(forKey: "resumeAfterPause")
        motion.pauseDuration = ClosingMotion.validStillDuration(UserDefaults.standard.double(forKey: "seamlessClosePauseDuration"))
        motion.automaticAngleDuration = ClosingMotion.validStillDuration(UserDefaults.standard.double(forKey: "seamlessCloseAutomaticAngleDuration"))
        motion.automaticDetectionThreshold = ClosingMotion.validDetectionThreshold(UserDefaults.standard.double(forKey: "seamlessCloseDetectionThreshold"))
        motion.automaticStartAngle = UserDefaults.standard.bool(forKey: "automaticStartAngleEnabled")
        statusLine.isEnabled = false
        statusMenu.addItem(statusLine)
        statusMenu.addItem(.separator())
        enableMenuItem.target = self
        enableMenuItem.action = #selector(toggleAnimation)
        enableMenuItem.state = animationEnabled ? .on : .off
        statusMenu.addItem(enableMenuItem)
        let settings = statusMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        if !settingsModel.isDevelopmentBuild {
            let checkUpdates = statusMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            checkUpdates.target = self
        }
        statusMenu.addItem(.separator())
        let quit = statusMenu.addItem(withTitle: "Quit \(appDisplayName)", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        updateMenuBarIcon(visible: UserDefaults.standard.bool(forKey: "showMenuBarIcon"))
        installApplicationMenu()

        settingsModel.configure(
            animationEnabled: animationEnabled,
            startAngle: startAngle,
            screenCaptureAllowed: CGPreflightScreenCaptureAccess(),
            resumeAfterPause: motion.resumeAfterPause,
            automaticStartAngle: motion.automaticStartAngle,
            pauseDuration: motion.pauseDuration,
            automaticAngleDuration: motion.automaticAngleDuration,
            automaticDetectionThreshold: motion.automaticDetectionThreshold,
            connectionEffectEnabled: UserDefaults.standard.bool(forKey: "seamlessCloseConnectionEffectEnabled"),
            blurEnabled: UserDefaults.standard.bool(forKey: "seamlessCloseBlurEnabled"),
            blurStrength: BlurStrength(rawValue: UserDefaults.standard.string(forKey: "seamlessCloseBlurStrength") ?? "") ?? .defaultStrength,
            runInBackground: UserDefaults.standard.bool(forKey: "runInBackground"),
            showMenuBarIcon: UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        )
        settingsModel.onAnimationEnabledChange = { [weak self] enabled in
            self?.applyAnimationEnabled(enabled)
        }
        settingsModel.licensing.onAccessChange = { [weak self] allowed in
            self?.applyLicenseAccess(allowed)
        }
        applyLicenseAccess(settingsModel.licensing.allowsUse)
        settingsModel.onStartAngleChange = { [weak self] angle in
            self?.applyStartAngle(angle)
        }
        settingsModel.onAutomaticStartAngleChange = { [weak self] enabled in
            self?.applyAutomaticStartAngle(enabled)
        }
        settingsModel.onResumeAfterPauseChange = { [weak self] enabled in
            guard let self else { return }
            self.motion.resumeAfterPause = enabled
            UserDefaults.standard.set(enabled, forKey: "resumeAfterPause")
            self.updateEscapeHotKey()
        }
        settingsModel.onPauseDurationChange = { [weak self] duration in
            self?.motion.pauseDuration = duration
            UserDefaults.standard.set(duration, forKey: "seamlessClosePauseDuration")
        }
        settingsModel.onAutomaticAngleDurationChange = { [weak self] duration in
            self?.motion.automaticAngleDuration = duration
            UserDefaults.standard.set(duration, forKey: "seamlessCloseAutomaticAngleDuration")
        }
        settingsModel.onAutomaticDetectionThresholdChange = { [weak self] angle in
            self?.applyAutomaticDetectionThreshold(angle)
        }
        settingsModel.onConnectionEffectEnabledChange = { [weak self] enabled in
            self?.applyConnectionEffectEnabled(enabled)
        }
        settingsModel.onBlurEnabledChange = { [weak self] enabled in
            self?.applyBlurEnabled(enabled)
        }
        settingsModel.onBlurStrengthChange = { [weak self] strength in
            self?.applyBlurStrength(strength)
        }
        settingsModel.onOpenPermissions = { [weak self] in self?.openPermissions() }
        settingsModel.onRunInBackgroundChange = { enabled in
            UserDefaults.standard.set(enabled, forKey: "runInBackground")
        }
        settingsModel.onShowMenuBarIconChange = { [weak self] visible in
            UserDefaults.standard.set(visible, forKey: "showMenuBarIcon")
            self?.updateMenuBarIcon(visible: visible)
        }
        if !settingsModel.isDevelopmentBuild {
            appUpdates = AppUpdates(model: settingsModel)
        }

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
        for (name, inactive) in [(NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handleSessionActivity(inactive: inactive)
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleActiveSpaceChange() }
        })
        // These system notifications are undocumented. Never use them to draw
        // over loginwindow; the overlay explicitly retains normal login visibility.
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handleScreenLock(locked)
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
            self?.handleDisplayChange()
            }
        })
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
            guard let self, !self.quitting else { return }
            self.settingsModel.licensing.refresh()
            guard self.settingsModel.licenseAllowsUse else { return }
            guard self.checkScreenAccess(), !self.sleeping else { return }
            self.settingsModel.refreshPermission()
            self.checkSensorHealth()
            if !self.ready, !self.starting, Date() >= self.retryAfter { self.connect() }
            else { self.warmCaptureMetadata() }
            }
        }
        for name in [NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let changed = event.object as? NSWindow,
                          changed === self.settingsWindowController?.window else { return }
                    self.invalidateCaptureMetadata()
                }
            })
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
        !settingsModel.runInBackground
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !quitting { shutdown() }
    }

    private func updateMenuBarIcon(visible: Bool) {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = BrandIcon.menuBar
            item.button?.toolTip = appDisplayName
            item.menu = statusMenu
            statusItem = item
        }
        statusItem?.isVisible = visible || !settingsModel.licenseAllowsUse
    }

    private func setStatus(_ text: String) {
        let status = settingsModel.licenseAllowsUse ? text : "Trial or license required"
        statusLine.title = status
        settingsModel.updateRuntimeStatus(status)
    }

    private func applyLicenseAccess(_ allowed: Bool) {
        settingsModel.licenseAllowsUse = allowed
        if !allowed {
            cancelWake("license access ended")
            invalidateCaptureMetadata()
            endGesture()
            motion.reset()
            settingsModel.selectedPage = .license
            setStatus("Trial or license required")
        } else {
            retryAfter = .distantPast
            setStatus(settingsModel.animationEnabled ? "Ready" : "Paused")
        }
        updateMenuBarIcon(visible: settingsModel.showMenuBarIcon)
    }

    private func startSensor() {
        sensorRestartedAt = Date()
        motion.reset()
        sensor.start(onReading: { [weak self] angle, acquiredAt in
            self?.handleLidReading(angle, time: acquiredAt)
        }, onStatus: { [weak self] status in
            guard let self else { return }
            self.settingsModel.updateSensorStatus(status)
            if !status.lowercased().contains("connected") { self.setStatus(status) }
        })
    }

    private func checkSensorHealth(at now: Date = Date()) {
        guard !sleeping, !quitting,
              now.timeIntervalSince(lastReading) > 1,
              now.timeIntervalSince(sensorRestartedAt) > 1 else { return }
        // A heartbeat queued during sleep may run before the restarted sensor
        // delivers its first reading. Allow its normal one-second startup window
        // without pretending the old pre-sleep reading is fresh.
        cancelWake("sensor unavailable")
        endGesture()
        motion.reset()
        settingsModel.updateSensorStatus("Sensor unavailable")
    }

    private func handleLidReading(_ angle: Double, time: Double = ProcessInfo.processInfo.systemUptime) {
        guard !sleeping, !quitting else { return }
        settingsModel.licensing.refresh()
        guard settingsModel.licenseAllowsUse else { return }
        guard angle.isFinite, (0...180).contains(angle) else {
            cancelWake("invalid sensor reading")
            endGesture()
            motion.reset()
            return
        }
        let previousAngle = lastLidAngle
        let previousTime = lastLidTime
        lastReading = Date()
        lastLidAngle = angle
        lastLidTime = time
        settingsModel.updateAngle(angle, time: time)
        if escapeReturning { return }
        guard settingsModel.animationEnabled else {
            if assistedOpeningPeakAngle != nil {
                assistedOpeningPeakAngle = nil
                finishingGesture = false
                cleanupTimer?.invalidate()
                cleanupTimer = nil
            }
            finishGesture()
            motion.reset()
            setStatus("Paused")
            return
        }
        var beganOpening = false
        if wakeOpening.pending {
            let firstSample = !wakeReceivedSample
            wakeReceivedSample = true
            if firstSample {
                logWake("first sensor sample: angle=\(angle), locked=\(screenLocked), sessionInactive=\(sessionInactive)")
            }
            switch wakeOpening.observe(angle: angle, time: time,
                                       referenceAngle: motion.effectiveStartAngle ?? settingsModel.startAngle,
                                       desktopAvailable: ready && canUseDesktop()) {
            case .prepare:
                guard retainedClosingSnapshot, renderer?.hasPreparedSnapshot == true else {
                    cancelWake("closing screenshot unavailable")
                    return
                }
                beganOpening = true
                openingGesture = true
                currentProgress = motion.beginOpening(angle: angle, time: time)
                logWake("cached frame requested")
            case .skip(let reason): cancelWake(reason)
            case .waiting: break
            }
            // A pending wake must not accidentally enter the closing path.
            if wakeOpening.pending && !wakeOpening.preparing { return }
        }
        guard !screenLocked, !sessionInactive else { return }
        guard ready else { return }
        if let peak = assistedOpeningPeakAngle {
            let highest = max(peak, angle)
            assistedOpeningPeakAngle = highest
            if angle < motion.activationAngle && highest - angle >= 1.5 {
                // Reverse through the same captured image while it is still
                // visible. The next sensor sample becomes the new lid target.
                assistedOpeningPeakAngle = nil
                openingAssist.reset()
                finishingGesture = false
                cleanupTimer?.invalidate()
                cleanupTimer = nil
                connectionSound.stop()
                prepareConnectionSound()
                window?.ignoresMouseEvents = false
                renderer?.beginAnimation(opening: openingGesture)
                setStatus(openingGesture ? "Animating · Opening" : "Animating · Reopen to reverse")
            } else {
                return
            }
        }
        let progress = beganOpening ? currentProgress : motion.update(angle: angle, time: time)
        currentProgress = progress
        let openingSpeed = openingAssist.observe(angle: angle, time: time,
            referenceAngle: motion.activationAngle, active: motion.active)
        updateEscapeHotKey()
        settingsModel.updateLearnedStartAngle(motion.learnedStartAngle)
        sensor.setActivePolling(motion.active || earlyCaptureRequested || wakeOpening.pending
                                || (hasSnapshot && !motion.desktopResumed))
        if motion.active || !finishingGesture || renderer?.isFinishingWithLid == true {
            renderer?.setLidAngle(angle, referenceAngle: motion.activationAngle, sampleTime: time)
        }
        if let openingSpeed, hasSnapshot, snapshotPresented, !finishingGesture {
            assistedOpeningPeakAngle = angle
            finishGesture(mode: .assisted, openingSpeed: openingSpeed)
            setStatus("Finishing opening")
            return
        }
        if !motion.active && !openingGesture && !wakeOpening.pending,
           let startAngle = motion.effectiveStartAngle, !motion.desktopResumed {
            if angle >= startAngle + 3 { earlyCaptureBlocked = false }
            if earlyCaptureRequested {
                if angle > earlyCaptureAngle + 0.25 || time - earlyCaptureTime > 0.35 {
                    endGesture()
                    earlyCaptureBlocked = true
                    return
                } else {
                    // The screenshot is kept hidden until the actual threshold.
                    return
                }
            } else if !earlyCaptureBlocked && !snapshotRequested && !finishingGesture && canUseDesktop(),
                      let previousAngle, previousTime.isFinite {
                let elapsed = time - previousTime
                let drop = previousAngle - angle
                if angle >= startAngle && angle < startAngle + 3,
                   elapsed > 0 && elapsed <= 0.12,
                   drop >= 0.15 && drop / elapsed >= 12 {
                    earlyCaptureRequested = true
                    earlyCaptureAngle = angle
                    earlyCaptureTime = time
                    sensor.setActivePolling(true)
                    prepareGestureSnapshot()
                    return
                }
            }
        } else if motion.active {
            earlyCaptureRequested = false
        }
        guard motion.active else {
            finishGesture(mode: motion.desktopResumed ? .pause : .lid)
            setStatus(motion.desktopResumed ? "Desktop restored" : "Ready")
            return
        }
        if finishingGesture {
            connectionSound.stop()
            prepareConnectionSound()
            finishingGesture = false
            cleanupTimer?.invalidate()
            cleanupTimer = nil
            revealOverlay()
        }
        if !snapshotRequested { prepareGestureSnapshot() }
        showProgress()
        if hasSnapshot { presentPreparedSnapshot() }
    }

    private func connect() {
        guard !starting, !sleeping, !quitting else { return }
        guard settingsModel.licenseAllowsUse else { return }
        guard checkScreenAccess() else {
            setStatus("Screen Recording permission required")
            if !permissionRequested {
                permissionRequested = true
                CGRequestScreenCaptureAccess()
            }
            retryAfter = Date().addingTimeInterval(2)
            return
        }
        guard let screen = builtInScreen(),
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            setStatus("Waiting for built-in display")
            retryAfter = Date().addingTimeInterval(wakeOpening.pending ? 0.1 : 3)
            return
        }
        guard CGDisplayIsAsleep(displayID) == 0 else {
            retryAfter = Date().addingTimeInterval(0.1)
            return
        }
        if matchesConnection(screen) {
            // Reuse the hidden overlay, pipeline and any retained closing image.
            ready = true
            warmCaptureMetadata()
            return
        }
        cancelWake("display configuration changed")
        endGesture()
        starting = true
        window?.close()
        let overlay = OverlayWindow(contentRect: screen.frame)
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        guard let effect = EffectRenderer(view: view, framesPerSecond: screen.maximumFramesPerSecond) else {
            setStatus("Metal rendering unavailable")
            starting = false
            retryAfter = Date().addingTimeInterval(10)
            return
        }
        effect.connectionEffectEnabled = settingsModel.connectionEffectEnabled
        effect.blurEnabled = settingsModel.blurEnabled
        effect.blurStrength = settingsModel.blurStrength
        overlay.contentView = view
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()
        window = overlay
        renderer = effect
        self.displayID = displayID
        displayScale = screen.backingScaleFactor
        displayLayout = currentDisplayLayout()
        ready = true
        starting = false
        motion.reset()
        warmCaptureMetadata()
        setStatus("Ready · Close the lid to animate")
    }

    private func builtInScreen() -> NSScreen? {
        NSScreen.screens.first {
            guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    private func matchesConnection(_ screen: NSScreen) -> Bool {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return displayID == id && window?.frame == screen.frame
            && displayScale == screen.backingScaleFactor && renderer != nil
            && displayLayout == currentDisplayLayout()
    }

    private func currentDisplayLayout() -> [DisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return DisplayGeometry(id: id, frame: screen.frame, scale: screen.backingScaleFactor)
        }.sorted { $0.id < $1.id }
    }

    private func handleDisplayChange() {
        guard !quitting else { return }
        invalidateCaptureMetadata()
        if let screen = builtInScreen(), matchesConnection(screen) {
            if !sleeping, wakeOpening.pending { connect() }
            return
        }
        if sleeping {
            cancelWake("display changed during sleep")
            endGesture()
            displayID = nil
        } else { restart() }
    }

    @discardableResult private func checkScreenAccess() -> Bool {
        guard screenAccessAllowed() else {
            invalidateCaptureMetadata()
            cancelWake("screen access revoked")
            endGesture()
            ready = false
            return false
        }
        return true
    }

    private func prepareConnectionSound() {
        if settingsModel.connectionEffectEnabled { connectionSound.prepare() }
    }

    private func applyConnectionEffectEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "seamlessCloseConnectionEffectEnabled")
        renderer?.connectionEffectEnabled = enabled
        if !enabled { connectionSound.stop() }
    }

    private func prepareGestureSnapshot() {
        guard let displayID, canUseDesktop() else {
            cancelWake("desktop unavailable")
            motion.reset()
            return
        }
        snapshotRequested = true
        snapshotToken += 1
        let token = snapshotToken
        setStatus(openingGesture ? "Preparing opening…" : "Taking screenshot…")
        snapshotTask = Task { [weak self] in
            guard let self, let renderer = self.renderer else { return }
            let started = ProcessInfo.processInfo.systemUptime
            do {
                guard !Task.isCancelled, token == snapshotToken else { return }
                if openingGesture {
                    guard retainedClosingSnapshot, captureMayPresent() else { discardCapture(); return }
                    retainedClosingSnapshot = false
                    try await renderer.prepareRetainedSnapshot()
                } else {
                    guard let window, let view = window.contentView as? MTKView else { discardCapture(); return }
                    try await capture.prepare(displayID: displayID,
                                              excludingWindowID: CGWindowID(window.windowNumber),
                                              expectedPixelSize: view.drawableSize)
                    guard !Task.isCancelled, token == snapshotToken, captureMayPresent() else { return }
                    let captureStarted = ProcessInfo.processInfo.systemUptime
                    let buffer = try await capture.screenshot(displayID: displayID)
                    if timingEnabled {
                        animationLog.debug("capture: metadataWaitMs=\((captureStarted - started) * 1000), pixelsMs=\((ProcessInfo.processInfo.systemUptime - captureStarted) * 1000), width=\(CVPixelBufferGetWidth(buffer)), height=\(CVPixelBufferGetHeight(buffer))")
                    }
                    guard !Task.isCancelled, token == snapshotToken,
                          (motion.active || earlyCaptureRequested),
                          ready, !sleeping, !quitting else { return }
                    guard captureMayPresent() else { discardCapture(); return }
                    try await renderer.prepareSnapshot(pixelBuffer: buffer)
                }
                guard !Task.isCancelled, token == snapshotToken,
                      (motion.active || earlyCaptureRequested),
                      ready, !sleeping, !quitting else { return }
                guard captureMayPresent() else { discardCapture(); return }
                hasSnapshot = true
                // Starting audio alongside ScreenCaptureKit delayed repeated
                // captures on the development Mac. Prepare the image first;
                // audio can warm during motion without delaying its first frame.
                prepareConnectionSound()
                if timingEnabled {
                    animationLog.debug("prepared: opening=\(self.openingGesture), totalMs=\((ProcessInfo.processInfo.systemUptime - started) * 1000)")
                }
                if motion.active {
                    showProgress()
                    presentPreparedSnapshot()
                }
            } catch {
                guard token == snapshotToken, !Task.isCancelled else { return }
                let wasEarlyCapture = earlyCaptureRequested
                discardCapture()
                if wasEarlyCapture { earlyCaptureBlocked = true }
                setStatus("Screenshot unavailable · check permission")
                NSLog("Screenshot: %@", error.localizedDescription)
            }
        }
    }

    private func presentPreparedSnapshot() {
        guard hasSnapshot, motion.active, !snapshotPresented, captureMayPresent() else { return }
        snapshotPresented = true
        if !openingGesture { usageAnalytics?.recordClose() }
        // The prepared screenshot retains the Dock and menu bar underneath.
        window?.pinToCurrentSpace()
        window?.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        window?.ignoresMouseEvents = false
        window?.orderFrontRegardless()
        setStatus(openingGesture ? "Animating · Opening" : "Animating · Reopen to reverse")
        if openingGesture {
            logWake("cached frame prepared; reveal requested")
            clearWakeTracking()
        }
        revealOverlay()
    }

    private func invalidateCaptureMetadata() {
        captureWarmupGeneration += 1
        captureWarmupTask?.cancel()
        captureWarmupTask = nil
        capture.invalidate()
    }

    private func warmCaptureMetadata() {
        guard ready, settingsModel.animationEnabled, !sleeping, !quitting, canUseDesktop(), !snapshotRequested,
              captureWarmupTask == nil, let displayID, let window,
              let view = window.contentView as? MTKView else { return }
        let id = CGWindowID(window.windowNumber)
        let size = view.drawableSize
        let generation = captureWarmupGeneration
        captureWarmupTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.captureWarmupGeneration == generation { self.captureWarmupTask = nil } }
            try? await self.capture.prepare(displayID: displayID, excludingWindowID: id, expectedPixelSize: size)
        }
    }

    private func revealOverlay() {
        window?.alphaValue = 1
        window?.ignoresMouseEvents = false
        renderer?.beginAnimation(opening: openingGesture)
    }

    private func showProgress() {
        renderer?.progress = hasSnapshot ? currentProgress : 0
        // Once revealed, sensor updates must not overwrite the entrance fade.
        if !hasSnapshot { window?.alphaValue = 0 }
    }

    private func updateEscapeHotKey() {
        guard motion.active, settingsModel.animationEnabled,
              !sleeping, !quitting else {
            removeEscapeHotKey()
            return
        }
        guard escapeHotKey == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { app.exitSeamlessClose() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &escapeHandler)
        guard handlerStatus == noErr else { return }
        let hotKeyID = EventHotKeyID(signature: 0x474C4553, id: 1)
        if RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID,
                               GetApplicationEventTarget(), 0, &escapeHotKey) != noErr {
            removeEscapeHotKey()
        }
    }

    private func removeEscapeHotKey() {
        if let escapeHotKey { UnregisterEventHotKey(escapeHotKey); self.escapeHotKey = nil }
        if let escapeHandler { RemoveEventHandler(escapeHandler); self.escapeHandler = nil }
    }

    private func exitSeamlessClose() {
        guard motion.active else { return }
        let rearmAngle = motion.effectiveStartAngle ?? settingsModel.startAngle
        if snapshotPresented { clearWakeTracking() }
        else { cancelWake("Escape") }
        motion.cancelUntilOpened(above: rearmAngle)
        escapeReturning = true
        finishGesture(mode: .pause)
        setStatus("Desktop restored · Open above \(Int(rearmAngle))° to rearm")
    }

    private func finishGesture(mode: EffectRenderer.CompletionMode = .disabled,
                               openingSpeed: Double = 0) {
        removeEscapeHotKey()
        // Disabling is an explicit interruption even during an existing return.
        if mode == .disabled { connectionSound.stop() }
        guard hasSnapshot else { endGesture(); return }
        if mode.hasConnectionFeedback && !snapshotPresented { endGesture(); return }
        guard !finishingGesture else { return }
        // Inactive lid readings can request .lid during a Pause return (including
        // tiny upward jitter that rearms automatic angle detection). An ignored
        // request must not cancel the click belonging to the continuing return.
        finishingGesture = true
        let token = snapshotToken
        renderer?.finishAnimation(mode, openingSpeed: openingSpeed,
                                  onConnectionSchedule: mode.hasConnectionFeedback ? { [weak self] peak, completion in
                                      self?.connectionSound.schedule(peakAt: peak, completion: completion)
                                  } : nil,
                                  onLiveDesktop: mode.hasConnectionFeedback ? { [weak self] in
                                      self?.window?.ignoresMouseEvents = true
                                  } : nil) { [weak self] in
            self?.completeGesture(mode: mode, token: token, completedNaturally: true)
        }
        // Display callbacks can stop when occluded. Never leave a snapshot
        // blocking input indefinitely while waiting for a final frame.
        cleanupTimer?.invalidate()
        // Slow manual tracking can legitimately take more than 800 ms to settle.
        // Only extend its watchdog while rendered motion is actually advancing;
        // Connection feedback may continue over the live desktop for 400 ms;
        // keep its retreat alive while frames advance. Stopped callbacks still
        // release input on the next watchdog tick.
        let timer = Timer(timeInterval: 0.8, repeats: mode == .lid || mode.hasConnectionFeedback) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.finishingGesture, self.snapshotToken == token else { return }
                if mode == .lid && self.renderer?.manualCompletionIsAdvancing == true { return }
                if mode.hasConnectionFeedback && self.renderer?.connectionCompletionIsAdvancing == true { return }
                self.completeGesture(mode: mode, token: token)
            }
        }
        cleanupTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func completeGesture(mode: EffectRenderer.CompletionMode, token: Int, completedNaturally: Bool = false) {
        guard finishingGesture, snapshotToken == token else { return }
        if mode == .assisted {
            motion.completeAssistedOpening(at: lastLidAngle ?? motion.activationAngle)
            settingsModel.updateLearnedStartAngle(motion.learnedStartAngle)
            setStatus(motion.desktopResumed ? "Desktop restored" : "Ready")
        }
        endGesture(allowSoundToFinish: mode.hasConnectionFeedback && completedNaturally)
    }

    private func endGesture(retainingSnapshot: Bool = false, allowSoundToFinish: Bool = false) {
        if allowSoundToFinish { connectionSound.finish() }
        else { connectionSound.stop() }
        removeEscapeHotKey()
        escapeReturning = false
        assistedOpeningPeakAngle = nil
        openingAssist.reset()
        if openingGesture && wakeOpening.pending { clearWakeTracking() }
        openingGesture = false
        finishingGesture = false
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        currentProgress = 0
        sensor.setActivePolling(false)
        window?.alphaValue = 0
        window?.ignoresMouseEvents = true
        window?.level = .floating
        window?.parkAcrossSpaces()
        renderer?.progress = 0
        sleepPreparationTimer?.invalidate()
        sleepPreparationTimer = nil
        snapshotToken += 1
        snapshotTask?.cancel()
        snapshotTask = nil
        snapshotRequested = false
        hasSnapshot = false
        snapshotPresented = false
        earlyCaptureRequested = false
        earlyCaptureBlocked = false
        retainedClosingSnapshot = retainingSnapshot && renderer?.hasPreparedSnapshot == true
        if retainedClosingSnapshot { renderer?.pauseSnapshot() }
        else { renderer?.clear() }
    }

    private var recentClosedLid: Bool {
        guard let angle = lastLidAngle else { return false }
        let age = ProcessInfo.processInfo.systemUptime - lastLidTime
        return (0...20).contains(angle) && (0...1).contains(age)
    }

    private var canRetainClosingSnapshot: Bool {
        settingsModel.licenseAllowsUse && settingsModel.animationEnabled && !sessionInactive && !openingGesture && !finishingGesture
            && hasSnapshot && motion.active && recentClosedLid && renderer?.hasPreparedSnapshot == true
    }

    private func suspend() {
        guard !sleeping else { return }
        usageAnalytics?.checkpoint()
        invalidateCaptureMetadata()
        let retain = screenAccessAllowed() && (canRetainClosingSnapshot
            || (retainedClosingSnapshot && sleepPreparationTimer != nil && recentClosedLid))
        clearWakeTracking()
        let sampleAge = ProcessInfo.processInfo.systemUptime - lastLidTime
        if retain { wakeOpening.prepareForSleep(angle: lastLidAngle,
                                    sampleAge: sampleAge)
        }
        wakeLog.notice("sleep: last angle=\(self.lastLidAngle ?? -1), sample age=\(sampleAge)s, eligible=\(self.wakeOpening.awaitingWake), retainedFrame=\(retain)")
        sleeping = true
        ready = false
        starting = false
        endGesture(retainingSnapshot: retain)
        sensor.stop()
        motion.reset()
    }

    private func resume(startHardware: Bool = true) {
        guard sleeping else { return }
        settingsModel.licensing.refresh()
        sleeping = false
        usageAnalytics?.tick()
        sensorRestartedAt = Date()
        let hadClosedEvidence = wakeOpening.awaitingWake
        let eligible = settingsModel.licenseAllowsUse && settingsModel.animationEnabled && retainedClosingSnapshot
            && renderer?.hasPreparedSnapshot == true && checkScreenAccess()
            && wakeOpening.resume(time: ProcessInfo.processInfo.systemUptime)
        if !eligible { cancelWake("no eligible closing frame"); endGesture() }
        if startHardware {
            startSensor()
            retryAfter = .distantPast
            connect()
        }
        if eligible && wakeOpening.pending && retainedClosingSnapshot {
            wakeReceivedSample = false
            logWake("wake received")
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkWakeProgress() }
            }
            wakeTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            wakeLog.notice("wake skipped: enabled=\(self.settingsModel.animationEnabled), closedLidEvidence=\(hadClosedEvidence)")
        }
    }

    private func restart(startHardware: Bool = true) {
        suspend()
        cancelWake("display reconfiguration")
        endGesture()
        displayID = nil
        resume(startHardware: startHardware)
    }

    private func canUseDesktop() -> Bool {
        guard settingsModel.licenseAllowsUse, !screenLocked, !sessionInactive, screenAccessAllowed(), let displayID else { return false }
        return desktopAvailable(displayID)
    }

    private func captureMayPresent() -> Bool {
        guard canUseDesktop() else { return false }
        return !openingGesture || wakeOpening.canPresent(time: ProcessInfo.processInfo.systemUptime,
            referenceAngle: motion.effectiveStartAngle ?? settingsModel.startAngle, desktopAvailable: true)
    }

    private func checkWakeProgress() {
        guard wakeOpening.pending, !sleeping, !quitting else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if wakeOpening.expired(time: now) { cancelWake("wake window expired"); return }
        guard checkScreenAccess() else { return }
        if wakeOpening.preparing && !captureMayPresent() { cancelWake("frame became stale or unavailable"); return }
        if !ready, !starting, Date() >= retryAfter { connect() }
    }

    private func clearWakeTracking() {
        wakeTimer?.invalidate()
        wakeTimer = nil
        wakeOpening = WakeOpening()
    }

    private func logWake(_ event: String) {
        guard let start = wakeOpening.startedAt else { return }
        let milliseconds = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        wakeLog.notice("\(event, privacy: .public), elapsed=\(milliseconds)ms")
    }

    private func cancelWake(_ reason: String) {
        let wasOpening = openingGesture || retainedClosingSnapshot
        logWake("skip: \(reason); locked=\(screenLocked), sessionInactive=\(sessionInactive), sensorReceived=\(wakeReceivedSample), ready=\(ready), angle=\(lastLidAngle ?? -1)")
        clearWakeTracking()
        if wasOpening {
            endGesture()
            motion.reset()
        }
    }

    private func discardCapture() {
        cancelWake("capture no longer eligible")
        endGesture()
        motion.reset()
    }

    private func blockDesktop() {
        invalidateCaptureMetadata()
        // Lock may precede actual sleep. Keep a completed near-closed frame for
        // one second to bridge that ordering; an ordinary lock clears it.
        if !sleeping, !retainedClosingSnapshot, canRetainClosingSnapshot {
            endGesture(retainingSnapshot: true)
            motion.reset()
            let timer = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelWake("lock was not followed by sleep") }
            }
            sleepPreparationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            return
        }
        if sleeping || (wakeOpening.pending && !wakeOpening.preparing) || sleepPreparationTimer != nil {
            logWake("desktop blocked; retaining hidden closing frame")
            // Repeated lock hints must not extend a pre-sleep grace period.
            if sleepPreparationTimer != nil { return }
            endGesture(retainingSnapshot: retainedClosingSnapshot)
        } else {
            cancelWake("desktop locked or session inactive")
            endGesture()
        }
        motion.reset()
    }

    private func handleScreenLock(_ locked: Bool) {
        screenLocked = locked
        wakeLog.notice("screen lock changed: locked=\(locked), sleeping=\(self.sleeping), awaitingWake=\(self.wakeOpening.awaitingWake), pending=\(self.wakeOpening.pending)")
        if locked { blockDesktop() }
        else if sleepPreparationTimer != nil { cancelWake("unlocked without sleep") }
    }

    private func handleSessionActivity(inactive: Bool) {
        sessionInactive = inactive
        wakeLog.notice("session changed: inactive=\(inactive), sleeping=\(self.sleeping), awaitingWake=\(self.wakeOpening.awaitingWake), pending=\(self.wakeOpening.pending)")
        if inactive {
            invalidateCaptureMetadata()
            cancelWake("session inactive")
            endGesture()
            motion.reset()
        }
    }

    private func handleActiveSpaceChange() {
        guard !quitting else { return }
        invalidateCaptureMetadata()
        cancelWake("active Space changed")
        endGesture()
        motion.reset()
        if settingsModel.animationEnabled, ready, !sleeping {
            setStatus("Ready · Open above \(Int(motion.effectiveStartAngle ?? settingsModel.startAngle))° to rearm")
            // Let AppKit finish the Space transition before discovering capture
            // metadata for the newly active desktop.
            DispatchQueue.main.async { [weak self] in self?.warmCaptureMetadata() }
        }
    }

    private func applyStartAngle(_ angle: Double) {
        guard motion.startAngle != angle else { return }
        let previousReference = motion.effectiveStartAngle
        motion.startAngle = angle
        UserDefaults.standard.set(angle, forKey: "animationStartAngle")
        guard motion.effectiveStartAngle != previousReference else { return }
        cancelWake("starting angle changed")
        endGesture()
        motion.reset()
        setStatus("Ready · Close past \(Int(angle))° to animate")
    }

    private func applyBlurEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "seamlessCloseBlurEnabled")
        renderer?.blurEnabled = enabled
    }

    private func applyBlurStrength(_ strength: BlurStrength) {
        UserDefaults.standard.set(strength.rawValue, forKey: "seamlessCloseBlurStrength")
        renderer?.blurStrength = strength
    }

    private func applyAutomaticStartAngle(_ enabled: Bool) {
        cancelWake("automatic starting angle changed")
        endGesture()
        motion.automaticStartAngle = enabled
        settingsModel.updateLearnedStartAngle(nil)
        UserDefaults.standard.set(enabled, forKey: "automaticStartAngleEnabled")
        if settingsModel.animationEnabled {
            setStatus(enabled ? (motion.automaticDetectionThreshold == 0
                                 ? "Ready · Hold the lid still to set the starting angle"
                                 : "Ready · Hold above \(Int(motion.automaticDetectionThreshold))° to set the starting angle")
                              : "Ready · Close past \(Int(settingsModel.startAngle))° to animate")
        } else {
            setStatus("Seamless Close is off")
        }
    }

    private func applyAutomaticDetectionThreshold(_ angle: Double) {
        if motion.automaticStartAngle {
            cancelWake("automatic detection threshold changed")
            endGesture()
        }
        motion.automaticDetectionThreshold = angle
        settingsModel.updateLearnedStartAngle(nil)
        UserDefaults.standard.set(angle, forKey: "seamlessCloseDetectionThreshold")
        guard motion.automaticStartAngle else { return }
        if settingsModel.animationEnabled {
            setStatus(angle == 0
                      ? "Ready · Hold the lid still to detect a starting angle"
                      : "Ready · Hold the lid above \(Int(angle))° to detect a starting angle")
        } else {
            setStatus("Seamless Close is off")
        }
    }

    private func applyAnimationEnabled(_ enabled: Bool) {
        cancelWake("animation setting changed")
        UserDefaults.standard.set(enabled, forKey: "animationEnabled")
        enableMenuItem.state = enabled ? .on : .off
        endGesture()
        motion.reset()
        if enabled {
            setStatus("Ready · Close past \(Int(motion.effectiveStartAngle ?? settingsModel.startAngle))° to animate")
        } else {
            setStatus("Seamless Close is off")
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
        let appMenu = NSMenu(title: appDisplayName)
        for (title, action, key) in [("About \(appDisplayName)", #selector(showAbout), ""),
                                     ("Settings…", #selector(showSettings), ",")] {
            let item = appMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide \(appDisplayName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit \(appDisplayName)", action: #selector(quitApp), keyEquivalent: "q")
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
        invalidateCaptureMetadata()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: settingsModel)
            settingsWindowController?.onClose = { [weak self] in
                guard let self, !self.settingsModel.runInBackground else { return }
                DispatchQueue.main.async { [weak self] in self?.quitApp() }
            }
        }
        settingsModel.refreshPermission()
        settingsWindowController?.present()
        warmCaptureMetadata()
    }

    @objc private func checkForUpdates() {
        appUpdates?.checkForUpdates()
    }

    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func quitApp() {
        guard !quitting else { return }
        shutdown()
        NSApp.terminate(nil)
    }

    private func shutdown() {
        quitting = true
        usageAnalytics?.stop()
        invalidateCaptureMetadata()
        cancelWake("quit")
        heartbeat?.invalidate()
        sensor.stop()
        endGesture()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        lockObservers.removeAll()
    }
}

extension AppDelegate {
    /// Uses existing permission to validate live metadata only, never pixels.
    static func captureMetadataSelfTest() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw NSError(domain: "Glissform.CaptureTest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Existing screen access is required; no permission prompt was requested"])
        }
        guard let screen = NSScreen.screens.first(where: {
            let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            return id.map { CGDisplayIsBuiltin($0) != 0 } ?? false
        }), let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            throw CapturePreparationError.displayUnavailable
        }
        let window = OverlayWindow(contentRect: screen.frame)
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = view
        window.orderFrontRegardless()
        let capture = DesktopCapture()
        defer { capture.invalidate(); window.close() }
        try await capture.prepare(displayID: id, excludingWindowID: CGWindowID(window.windowNumber),
                                  expectedPixelSize: view.drawableSize)
        print("PASS: live capture metadata matches \(Int(view.drawableSize.width))x\(Int(view.drawableSize.height)) backing pixels and safely excludes the hidden overlay; no screenshot taken")
    }

    /// Real gesture/cancellation paths with synthetic pixels and no capture permission.
    static func lifecycleSelfTest() async throws {
        let savedSettings = ["animationStartAngle", "animationEnabled", "automaticStartAngleEnabled",
                             "resumeAfterPause", "seamlessClosePauseDuration",
                             "seamlessCloseAutomaticAngleDuration", "seamlessCloseDetectionThreshold",
                             "seamlessCloseConnectionEffectEnabled", "seamlessCloseBlurEnabled", "seamlessCloseBlurStrength",
                             "runInBackground", "showMenuBarIcon"].map {
            ($0, UserDefaults.standard.object(forKey: $0))
        }
        defer {
            for (key, value) in savedSettings {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
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
        let feedbackDraft = FeedbackEmail.draftURL
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let version = Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development"
        let expectedBody = "Glissform version: \(version)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"
        try check(feedbackDraft?.scheme == "mailto" && feedbackDraft?.path == FeedbackEmail.address
                  && feedbackDraft?.queryItems?.count == 1
                  && feedbackDraft?.queryItems?.first?.name == "body"
                  && feedbackDraft?.queryItems?.first?.value == expectedBody,
                  "Feedback draft must address support and include the current app and macOS versions")
        print("PASS: feedback draft includes the support address and current versions")
        try check(AppResource.url("PauseRestored", extension: "wav") != nil,
                  "The original opening connection sound must be bundled")
        var storage: CVPixelBuffer?
        let attributes = [kCVPixelBufferMetalCompatibilityKey as String: true,
                          kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as [String: Any]
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &storage)
        guard let buffer = storage else { throw NSError(domain: "Glissform.LifecycleTest", code: 2) }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        final class SyntheticSound: ConnectionSoundPlayback {
            var onPeak: @MainActor () -> Void
            var task: Task<Void, Never>?
            var stopped = false
            var finished = false
            var scheduledPeaks: [Double] = []
            var readinessDelay = 0.0
            var outputLatency = 0.0
            var preparationCount = 0
            init(onPeak: @escaping @MainActor () -> Void = {}) { self.onPeak = onPeak }
            func prepare() { preparationCount += 1; stopped = false }
            func schedule(peakAt time: Double, completion: @escaping @MainActor (Double?) -> Void) {
                task?.cancel()
                scheduledPeaks.append(time)
                task = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: UInt64(readinessDelay * 1_000_000_000)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    let plan = ConnectionFeedbackTiming.playback(requestedPeak: time,
                        now: ProcessInfo.processInfo.systemUptime, latency: outputLatency, samplePeak: 116 / 44100.0)
                    completion(plan.audiblePeak)
                    let delay = max(0, plan.audiblePeak - ProcessInfo.processInfo.systemUptime)
                    do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    onPeak()
                }
            }
            func finish() { finished = true }
            func stop() { stopped = true; task?.cancel(); task = nil }
        }

        func makeGesture(screenAccessAllowed: @escaping () -> Bool = { true },
                         startGesture: Bool = true,
                         resumeAfterPause: Bool = false,
                         playConnectionSound: @escaping @MainActor () -> Void = {}) throws -> (AppDelegate, SyntheticCapture) {
            let source = SyntheticCapture()
            let app = AppDelegate(capture: source, desktopAvailable: { _ in true },
                                  screenAccessAllowed: screenAccessAllowed,
                                  connectionSound: SyntheticSound(onPeak: playConnectionSound))
            let window = OverlayWindow(contentRect: NSRect(x: 16, y: 16, width: 64, height: 64))
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
            app.settingsModel.configure(animationEnabled: true, startAngle: 100,
                                        screenCaptureAllowed: true, resumeAfterPause: resumeAfterPause)
            app.settingsModel.onConnectionEffectEnabledChange = { [weak app] enabled in
                app?.applyConnectionEffectEnabled(enabled)
            }
            app.motion.startAngle = 100
            app.motion.resumeAfterPause = resumeAfterPause
            if startGesture {
                app.handleLidReading(110)
                app.handleLidReading(80)
            }
            return (app, source)
        }
        func checkCleared(_ app: AppDelegate) throws {
            try check(!app.hasSnapshot && !app.snapshotRequested && app.snapshotTask == nil,
                      "Snapshot state must be cleared (alpha \(app.window?.alphaValue ?? -1), finishing \(app.finishingGesture), paused \((app.window?.contentView as? MTKView)?.isPaused ?? true), visible \(app.window?.isVisible ?? false), occlusion \(app.window?.occlusionState.rawValue ?? 0), progress \(app.renderer?.progress ?? -1))")
            try check(app.window?.alphaValue == 0 && app.window?.ignoresMouseEvents == true,
                      "Interrupted gesture must restore desktop access")
            try check(!app.finishingGesture && app.cleanupTimer == nil && app.renderer?.isRendering == false,
                      "Interrupted transitions must not remain pending")
            try check(!app.retainedClosingSnapshot && app.renderer?.hasPreparedSnapshot == false
                      && app.sleepPreparationTimer == nil, "Cleared gestures must release cached pixels and pre-sleep timers")
        }
        func waitForCapture(_ source: SyntheticCapture) async throws {
            for _ in 0..<100 {
                if source.pending != nil { return }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            try check(false, "Gesture must request its screenshot")
        }
        func waitForConnectionDesktop(_ app: AppDelegate) async throws {
            for _ in 0..<200 {
                if app.hasSnapshot, app.renderer?.opacity == 0,
                   app.window?.ignoresMouseEvents == true { return }
                if let view = app.window?.contentView as? MTKView, app.renderer?.isRendering == true {
                    app.renderer?.draw(in: view)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try check(false, "Connection feedback must release mouse access while the glow retreats")
        }

        func waitForCleanup(_ app: AppDelegate) async throws {
            // Pump synthetic rendering explicitly: MetalKit can suspend display
            // callbacks for a tiny/occluded window or a sleeping display. This
            // checks coordinator/GPU cleanup, not compositor frame delivery.
            // The synthetic assisted path can start with no displayed velocity,
            // so allow its slow fallback to reach flat before checking cleanup.
            for _ in 0..<450 {
                if !app.hasSnapshot { return }
                if let view = app.window?.contentView as? MTKView, app.renderer?.isRendering == true {
                    app.renderer?.draw(in: view)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        do {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            app.settingsModel.onBlurEnabledChange = { [weak app] enabled in
                app?.applyBlurEnabled(enabled)
            }
            app.settingsModel.onBlurStrengthChange = { [weak app] strength in
                app?.applyBlurStrength(strength)
            }
            try await waitForCapture(source)
            let captureTask = app.snapshotTask
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await captureTask?.value
            try check(app.hasSnapshot && source.count == 1, "Blur switch test needs one active screenshot")
            app.settingsModel.setBlurEnabled(false)
            try check(!app.settingsModel.blurEnabled && app.renderer?.blurEnabled == false
                      && !UserDefaults.standard.bool(forKey: "seamlessCloseBlurEnabled")
                      && app.hasSnapshot && source.count == 1,
                      "Turning Blur off must save the setting and keep the current gesture")
            app.settingsModel.setBlurEnabled(true)
            try check(app.settingsModel.blurEnabled && app.renderer?.blurEnabled == true
                      && UserDefaults.standard.bool(forKey: "seamlessCloseBlurEnabled")
                      && app.hasSnapshot && source.count == 1,
                      "Turning Blur on must reuse the current screenshot")
            for strength in [BlurStrength.high, .subtle, .regular] {
                app.settingsModel.setBlurStrength(strength)
                try check(app.settingsModel.blurStrength == strength
                          && app.renderer?.blurStrength == strength
                          && UserDefaults.standard.string(forKey: "seamlessCloseBlurStrength") == strength.rawValue
                          && app.hasSnapshot && source.count == 1,
                          "Changing Blur strength must save and reuse the current screenshot")
            }
            try check(BlurStrength(rawValue: "unknown") == nil
                      && BlurStrength.defaultStrength == .regular && BlurStrength.high.scale == 1,
                      "Regular must be the default while High retains the previous material")
            print("PASS: saved Blur switch and strengths change an active gesture without recapture")
        }
        do {
            let (app, _) = try makeGesture(startGesture: false)
            defer { app.shutdown(); app.window?.close() }
            let model = app.settingsModel
            model.onAnimationEnabledChange = { [weak app] enabled in app?.applyAnimationEnabled(enabled) }
            model.onStartAngleChange = { [weak app] angle in app?.applyStartAngle(angle) }
            model.onAutomaticStartAngleChange = { [weak app] enabled in app?.applyAutomaticStartAngle(enabled) }
            model.onAutomaticDetectionThresholdChange = { [weak app] angle in app?.applyAutomaticDetectionThreshold(angle) }
            model.onAutomaticAngleDurationChange = { [weak app] duration in
                app?.motion.automaticAngleDuration = duration
                UserDefaults.standard.set(duration, forKey: "seamlessCloseAutomaticAngleDuration")
            }
            model.onResumeAfterPauseChange = { [weak app] enabled in
                app?.motion.resumeAfterPause = enabled
                UserDefaults.standard.set(enabled, forKey: "resumeAfterPause")
            }
            model.onPauseDurationChange = { [weak app] duration in
                app?.motion.pauseDuration = duration
                UserDefaults.standard.set(duration, forKey: "seamlessClosePauseDuration")
            }
            model.onBlurEnabledChange = { [weak app] enabled in app?.applyBlurEnabled(enabled) }
            model.onBlurStrengthChange = { [weak app] strength in app?.applyBlurStrength(strength) }
            model.configure(animationEnabled: true, startAngle: 90, screenCaptureAllowed: true)
            app.motion.startAngle = 90
            app.motion.resumeAfterPause = true
            try check(model.resumeAfterPause && model.startAngle == 90 && !model.seamlessCloseHasCustomSettings && model.connectionEffectEnabled && model.blurStrength == .regular,
                      "Fresh Seamless Close settings must start at defaults")
            let backgroundBefore = model.runInBackground
            model.setAnimationEnabled(false)
            model.setStartAngle(120)
            model.setAutomaticDetectionThreshold(80)
            model.setAutomaticAngleDuration(2)
            model.setAutomaticStartAngle(true)
            model.setResumeAfterPause(false)
            model.setPauseDuration(3)
            model.setConnectionEffectEnabled(false)
            try check(!UserDefaults.standard.bool(forKey: "seamlessCloseConnectionEffectEnabled")
                      && app.renderer?.connectionEffectEnabled == false,
                      "Connection effect off must be persisted and applied to rendering")
            let restoredModel = SettingsModel()
            restoredModel.configure(animationEnabled: true, startAngle: 100, screenCaptureAllowed: true,
                connectionEffectEnabled: UserDefaults.standard.bool(forKey: "seamlessCloseConnectionEffectEnabled"))
            try check(!restoredModel.connectionEffectEnabled, "Saved connection switch must restore on configuration")
            model.setBlurEnabled(false)
            model.setBlurStrength(.subtle)
            try check(model.seamlessCloseHasCustomSettings, "Changed controls must enable page reset")
            model.resetSeamlessCloseToDefaults()
            try check(!model.seamlessCloseHasCustomSettings && model.animationEnabled
                      && model.startAngle == 90 && !model.automaticStartAngle
                      && model.automaticDetectionThreshold == 20 && model.automaticAngleDuration == 1
                      && model.resumeAfterPause && model.pauseDuration == 1
                      && model.connectionEffectEnabled && model.blurEnabled && model.blurStrength == .regular,
                      "Reset must restore every Seamless Close control")
            try check(app.motion.startAngle == 90 && !app.motion.automaticStartAngle
                      && app.motion.automaticDetectionThreshold == 20 && app.motion.automaticAngleDuration == 1
                      && app.motion.resumeAfterPause && app.motion.pauseDuration == 1
                      && app.renderer?.connectionEffectEnabled == true
                      && app.renderer?.blurEnabled == true && app.renderer?.blurStrength == .regular,
                      "Reset must update active motion and rendering")
            try check(UserDefaults.standard.bool(forKey: "animationEnabled"),
                      "Reset must save the Seamless Close switch default")
            try check(UserDefaults.standard.double(forKey: "animationStartAngle") == 90,
                      "Reset must save the start angle default")
            try check(!UserDefaults.standard.bool(forKey: "automaticStartAngleEnabled"),
                      "Reset must save the automatic detection switch default")
            try check(UserDefaults.standard.double(forKey: "seamlessCloseDetectionThreshold") == 20,
                      "Reset must save the detection threshold default")
            try check(UserDefaults.standard.double(forKey: "seamlessCloseAutomaticAngleDuration") == 1,
                      "Reset must save the detection wait default")
            try check(UserDefaults.standard.bool(forKey: "resumeAfterPause")
                      && UserDefaults.standard.double(forKey: "seamlessClosePauseDuration") == 1,
                      "Reset must save pause defaults")
            try check(UserDefaults.standard.bool(forKey: "seamlessCloseConnectionEffectEnabled"),
                      "Reset must persist the enabled connection effect default")
            try check(UserDefaults.standard.bool(forKey: "seamlessCloseBlurEnabled")
                      && UserDefaults.standard.string(forKey: "seamlessCloseBlurStrength") == BlurStrength.regular.rawValue,
                      "Reset must save Blur defaults")
            try check(model.runInBackground == backgroundBefore,
                      "Page reset must preserve General settings")
            print("PASS: Seamless Close reset restores saved defaults and leaves other pages untouched")
        }
        do {
            let (app, source) = try makeGesture(startGesture: false)
            defer { app.shutdown(); app.window?.close() }
            app.motion.automaticStartAngle = true
            app.settingsModel.configure(animationEnabled: true, startAngle: 100,
                                        screenCaptureAllowed: true, automaticStartAngle: true)
            app.settingsModel.onStartAngleChange = { [weak app] angle in app?.applyStartAngle(angle) }
            app.settingsModel.onAutomaticStartAngleChange = { [weak app] enabled in
                app?.applyAutomaticStartAngle(enabled)
            }
            app.settingsModel.onAutomaticDetectionThresholdChange = { [weak app] angle in
                app?.applyAutomaticDetectionThreshold(angle)
            }
            for frame in 0...40 { app.handleLidReading(110, time: Double(frame) / 20) }
            try check(app.motion.learnedStartAngle == 109 && app.settingsModel.learnedStartAngle == 109,
                      "The live settings model must show the automatically learned angle")
            app.handleLidReading(80, time: 2.05)
            try await waitForCapture(source)
            let captureTask = app.snapshotTask
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await captureTask?.value
            try check(app.hasSnapshot && app.motion.active, "The learned angle must start a real gesture")
            app.settingsModel.setStartAngle(120)
            try check(app.hasSnapshot && app.motion.active && app.motion.activationAngle == 109
                      && app.motion.effectiveStartAngle == 109,
                      "Editing the manual fallback must not cancel an automatically anchored capture")
            app.settingsModel.setAutomaticDetectionThreshold(120)
            try checkCleared(app)
            try check(app.motion.learnedStartAngle == nil && app.motion.effectiveStartAngle == 120
                      && app.settingsModel.learnedStartAngle == nil
                      && UserDefaults.standard.double(forKey: "seamlessCloseDetectionThreshold") == 120,
                      "Changing detection threshold must save it, restore Begin at, and clear the old gesture")
            app.settingsModel.setAutomaticStartAngle(false)
            try checkCleared(app)
            try check(app.motion.effectiveStartAngle == 120 && app.settingsModel.learnedStartAngle == nil,
                      "Turning automatic selection off must restore the manual trigger and clear capture")
            print("PASS: live automatic learning, manual fallback, threshold cleanup and toggle-off cleanup")
        }
        do {
            let (app, source) = try makeGesture(startGesture: false)
            defer { app.shutdown(); app.window?.close() }
            app.motion.automaticDetectionThreshold = 80
            app.motion.automaticStartAngle = true
            app.settingsModel.configure(animationEnabled: true, startAngle: 100,
                                        screenCaptureAllowed: true, automaticStartAngle: true,
                                        automaticDetectionThreshold: 80)
            for frame in 0...20 { app.handleLidReading(90, time: Double(frame) / 20) }
            try check(app.motion.learnedStartAngle == 89 && app.settingsModel.learnedStartAngle == 89,
                      "The live app must learn above Detect above even below Begin at")
            app.handleLidReading(88, time: 1.05)
            try await waitForCapture(source)
            let captureTask = app.snapshotTask
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await captureTask?.value
            try check(app.hasSnapshot && app.motion.active && app.motion.activationAngle == 89,
                      "The below-manual learned angle must start a real gesture")
            print("PASS: below-manual automatic threshold starts one real capture")
        }
        do {
            let (app, source) = try makeGesture(startGesture: false)
            defer { app.shutdown(); app.window?.close() }
            app.motion.automaticDetectionThreshold = 80
            app.motion.automaticStartAngle = true
            app.motion.resumeAfterPause = true
            app.motion.pauseDuration = 0.5
            app.settingsModel.configure(animationEnabled: true, startAngle: 100,
                                        screenCaptureAllowed: true, resumeAfterPause: true,
                                        automaticStartAngle: true, pauseDuration: 0.5,
                                        automaticDetectionThreshold: 80)
            for frame in 0...20 { app.handleLidReading(110, time: Double(frame) / 20) }
            try check(app.motion.learnedStartAngle == 109, "An eligible open lid must learn before closing")
            app.handleLidReading(70, time: 1.05)
            try await waitForCapture(source)
            let captureTask = app.snapshotTask
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await captureTask?.value
            for frame in 0...11 { app.handleLidReading(70, time: 2 + Double(frame) * 0.05) }
            try check(app.motion.desktopResumed && app.motion.learnedStartAngle == nil
                      && app.motion.effectiveStartAngle == 100 && app.settingsModel.learnedStartAngle == nil,
                      "A below-threshold pause must keep desktop restoration but return to Begin at")
            try await waitForCleanup(app)
            try checkCleared(app)
            print("PASS: below-threshold pause restores desktop and clears the automatic angle")
        }
        do {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            app.settingsModel.onAutomaticDetectionThresholdChange = { [weak app] angle in
                app?.applyAutomaticDetectionThreshold(angle)
            }
            try await waitForCapture(source)
            let captureTask = app.snapshotTask
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await captureTask?.value
            try check(app.hasSnapshot && app.motion.active, "The manual threshold test needs an active snapshot")
            app.settingsModel.setAutomaticDetectionThreshold(80)
            try check(app.hasSnapshot && app.motion.active && app.motion.effectiveStartAngle == 100
                      && source.count == 1,
                      "Editing Detect above while automatic detection is off must preserve the manual gesture")
            print("PASS: inactive detection threshold edit preserves the manual gesture")
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
        do {
            let (app, _) = try makeGesture()
            defer {
                if let item = app.statusItem { NSStatusBar.system.removeStatusItem(item) }
                app.shutdown()
                app.window?.close()
            }
            app.showSettings()
            let settings = app.settingsWindowController!.window!
            app.settingsModel.onShowMenuBarIconChange = { [weak app] visible in
                app?.updateMenuBarIcon(visible: visible)
            }
            app.settingsModel.setShowMenuBarIcon(false)
            let statusItem = app.statusItem
            try check(statusItem != nil && statusItem?.isVisible == false,
                      "Turning the menu bar icon off must hide its status item")
            app.settingsModel.setShowMenuBarIcon(true)
            try check(app.statusItem === statusItem && statusItem?.isVisible == true && statusItem?.button?.image != nil,
                      "Turning the menu bar icon back on must restore the same item and image")
            app.settingsModel.setShowMenuBarIcon(false)
            settings.performClose(nil)
            try check(NSApp.activationPolicy() == .accessory && !app.applicationShouldTerminateAfterLastWindowClosed(NSApp),
                      "Background running must hide the Dock icon even without a menu bar icon")
            app.showSettings()
            try check(settings.isVisible && NSApp.activationPolicy() == .regular,
                      "Opening the app again must restore Settings and its Dock icon")
            app.settingsModel.setRunInBackground(false)
            try check(app.applicationShouldTerminateAfterLastWindowClosed(NSApp),
                      "Disabling background running must make closing the last Settings window quit")
            app.settingsModel.setRunInBackground(true)
            app.settingsModel.setShowMenuBarIcon(true)
            settings.performClose(nil)
            try check(NSApp.activationPolicy() == .accessory,
                      "With menu bar access enabled, background operation must hide the Dock icon")
            print("PASS: General restores the same menu bar item and preserves access through menu bar or Dock")
        }
        // A Space change must discard both pending and visible snapshots and
        // require a fresh opening above the configured threshold before recapture.
        for visible in [false, true] {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            let oldTask = app.snapshotTask
            if visible {
                source.pending?.resume(returning: buffer)
                source.pending = nil
                await oldTask?.value
                try await Task.sleep(nanoseconds: 100_000_000)
                try check(app.hasSnapshot && app.window?.alphaValue == 1,
                          "Synthetic snapshot must be visible before the Space change")
                try check(app.window?.collectionBehavior.contains(.canJoinAllSpaces) == false,
                          "A visible snapshot must stay in its source Space")
            }
            app.handleActiveSpaceChange()
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await oldTask?.value
            try checkCleared(app)
            try check(app.window?.collectionBehavior.contains(.canJoinAllSpaces) == true,
                      "A hidden overlay must park across Spaces for the next gesture")
            app.handleLidReading(70)
            try check(source.count == 1 && !app.motion.active,
                      "Movement below Begin at must remain disarmed after a Space change")
            app.handleLidReading(101)
            app.handleLidReading(80)
            try await waitForCapture(source)
            try check(source.count == 2 && app.motion.active,
                      "Opening above Begin at must rearm a fresh capture after a Space change")
            let freshTask = app.snapshotTask
            app.handleActiveSpaceChange()
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await freshTask?.value
            try checkCleared(app)
            print("PASS: Space change cancels \(visible ? "visible" : "pending") animation and requires opening above Begin at")
        }
        for pauseEnabled in [false, true] {
            for visible in [false, true] {
                var connectionClicks = 0
                let (app, source) = try makeGesture(resumeAfterPause: pauseEnabled,
                                                  playConnectionSound: { connectionClicks += 1 })
                defer { app.shutdown(); app.window?.close() }
                try await waitForCapture(source)
                let task = app.snapshotTask
                if visible {
                    source.pending?.resume(returning: buffer)
                    source.pending = nil
                    await task?.value
                    try check(app.hasSnapshot, "Escape test needs a visible snapshot")
                }
                app.exitSeamlessClose()
                if visible {
                    try check(app.finishingGesture && app.escapeReturning && app.hasSnapshot,
                              "Escape must use the pause return before releasing a visible capture")
                    app.handleLidReading(70)
                    try check(source.count == 1 && app.finishingGesture,
                              "Lid movement during Escape return must not start a new capture")
                }
                source.pending?.resume(returning: buffer)
                source.pending = nil
                await task?.value
                if visible {
                    try await waitForConnectionDesktop(app)
                    try await waitForCleanup(app)
                }
                try checkCleared(app)
                try check(connectionClicks == (visible ? 1 : 0),
                          "Escape must click once at visible contact and stay silent for a pending capture")
                app.handleLidReading(70)
                try check(source.count == 1 && !app.motion.active,
                          "Escape must not restart below Begin at")
                app.handleLidReading(101)
                app.handleLidReading(80)
                try await waitForCapture(source)
                try check(source.count == 2 && app.motion.active,
                          "Opening above Begin at must rearm after Escape")
                app.exitSeamlessClose()
                source.pending?.resume(returning: buffer)
                source.pending = nil
                print("PASS: Escape \(visible ? "animates visible" : "releases pending") capture with pause \(pauseEnabled ? "on" : "off") and requires reopening")
            }
        }
        for interruption in ["sleep", "Space change", "display change", "lock", "quit"] {
            var connectionClicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { connectionClicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            app.exitSeamlessClose()
            try check(app.finishingGesture, "Escape must begin a visible pause return")
            switch interruption {
            case "sleep": app.suspend()
            case "Space change": app.handleActiveSpaceChange()
            case "display change": app.restart(startHardware: false)
            case "lock": app.handleScreenLock(true)
            default: app.shutdown()
            }
            try checkCleared(app)
            try await Task.sleep(nanoseconds: 50_000_000)
            try check(connectionClicks == 0, "An interrupted Escape return must stay silent")
            print("PASS: Escape return cleanup on \(interruption)")
        }
        for interruption in ["sleep", "Space change", "display change", "lock", "quit"] {
            var clicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { clicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            app.exitSeamlessClose()
            if let view = app.window?.contentView as? MTKView { app.renderer?.draw(in: view) }
            let sound = app.connectionSound as! SyntheticSound
            try check(sound.scheduledPeaks.count == 1, "Interruption must exercise an already scheduled click")
            switch interruption {
            case "sleep": app.suspend()
            case "Space change": app.handleActiveSpaceChange()
            case "display change": app.restart(startHardware: false)
            case "lock": app.handleScreenLock(true)
            default: app.shutdown()
            }
            try await Task.sleep(nanoseconds: 650_000_000)
            try check(clicks == 0 && sound.stopped, "A canceled scheduled click must not fire later")
            try checkCleared(app)
            print("PASS: scheduled connection audio canceled by \(interruption)")
        }
        do {
            var clicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { clicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            let sound = app.connectionSound as! SyntheticSound
            sound.readinessDelay = 0.520
            sound.outputLatency = 0.300
            app.exitSeamlessClose()
            try await waitForConnectionDesktop(app)
            try await waitForCleanup(app)
            try check(clicks == 1 && sound.finished && !sound.stopped,
                      "Fresh frames waiting for a slow output route must survive the 800 ms cleanup watchdog")
            try checkCleared(app)
            print("PASS: slow audio readiness keeps its paired pulse alive while desktop access returns")
        }
        // Resolve a capture *after* each interruption to prove stale work cannot reappear.
        // Also interrupt a revealed snapshot to verify overlay and GPU cleanup.
        for visible in [false, true] {
            for interruption in ["reversal", "sleep", "display change", "quit", "license expiry"] {
                let (app, source) = try makeGesture()
                defer { app.shutdown(); app.window?.close() }
                let task = app.snapshotTask
                try await waitForCapture(source)
                let sound = app.connectionSound as! SyntheticSound
                try check(sound.preparationCount == 0,
                          "Audio startup must not overlap pending screenshot acquisition")
                if visible {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    source.pending?.resume(returning: buffer)
                    source.pending = nil
                    await task?.value
                    try await Task.sleep(nanoseconds: 45_000_000)
                    try check(app.hasSnapshot && app.window!.alphaValue > 0, "Test snapshot must be visible")
                    try check(sound.preparationCount == 1,
                              "A prepared snapshot must warm audio once for connection feedback")
                }
                switch interruption {
                case "reversal": app.handleLidReading(100)
                case "sleep": app.suspend()
                case "display change": app.restart(startHardware: false)
                case "license expiry": app.applyLicenseAccess(false)
                default: app.shutdown()
                }
                source.pending?.resume(returning: buffer)
                source.pending = nil
                await task?.value
                if visible && interruption == "reversal" { try await waitForCleanup(app) }
                try checkCleared(app)
                if interruption == "license expiry" {
                    let captures = source.count
                    app.handleLidReading(110)
                    app.handleLidReading(80)
                    try check(source.count == captures && !app.motion.active && !app.snapshotRequested,
                              "Locked app must not start another gesture")
                }
                if !visible {
                    try check(sound.preparationCount == 0,
                              "A canceled capture must not start audio when its stale result arrives")
                }
                print("PASS: \(visible ? "visible snapshot cleanup" : "delayed snapshot cancellation") on \(interruption)")
            }
        }
        for (automatic, overshoot) in [(false, 0.0), (false, 8.0), (true, 0.0), (true, 8.0)] {
            for visible in [false, true] {
                var clicks = 0
                let (app, source) = try makeGesture(startGesture: false, playConnectionSound: { clicks += 1 })
                defer { app.shutdown(); app.window?.close() }
                let started = ProcessInfo.processInfo.systemUptime
                if automatic {
                    app.motion.automaticStartAngle = true
                    app.settingsModel.configure(animationEnabled: true, startAngle: 100,
                        screenCaptureAllowed: true, resumeAfterPause: false, automaticStartAngle: true)
                    for frame in 0...20 {
                        app.handleLidReading(110, time: started - 1 + Double(frame) / 20)
                    }
                    try check(app.motion.learnedStartAngle == 109,
                              "Fast automatic reopening must use a real learned reference")
                } else {
                    app.handleLidReading(110, time: started)
                }
                app.handleLidReading(80, time: started)
                let reference = app.motion.activationAngle
                let finalAngle = reference + overshoot
                try await waitForCapture(source)
                let task = app.snapshotTask
                if visible {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    source.pending?.resume(returning: buffer)
                    source.pending = nil
                    await task?.value
                    try await Task.sleep(nanoseconds: 45_000_000)
                    try check(app.hasSnapshot && app.window!.alphaValue > 0,
                              "Fast return test needs a visible snapshot")
                }
                let sampleTime = ProcessInfo.processInfo.systemUptime - 0.05
                for (index, angle) in [80.0, reference - 10, reference - 6, finalAngle].enumerated() {
                    app.handleLidReading(angle, time: sampleTime + Double(index) / 60)
                }
                if visible {
                    try check(app.finishingGesture && app.renderer?.isFinishingWithLid == true
                              && app.assistedOpeningPeakAngle == nil,
                              "Skipping the assisted region must keep the existing lid-driven return")
                    app.handleLidReading(finalAngle)
                }
                source.pending?.resume(returning: buffer)
                source.pending = nil
                await task?.value
                if visible {
                    try await waitForConnectionDesktop(app)
                    try await waitForCleanup(app)
                }
                try checkCleared(app)
                let sound = app.connectionSound as! SyntheticSound
                try check(clicks == (visible ? 1 : 0) && sound.scheduledPeaks.count == (visible ? 1 : 0)
                          && source.count == 1,
                          "Skipped-angle feedback must occur once for visible returns, without recapture; pending captures stay silent")
                print("PASS: \(visible ? "visible" : "pending") fast \(automatic ? "learned" : "manual") return to \(finalAngle) degrees")
            }
        }
        // The longer ordinary return must remain cancellable while its
        // snapshot is visible, including callbacks queued before cancellation.
        for interruption in ["reclose", "sleep", "Space change", "display change", "lock", "quit"] {
            var clicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { clicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            try await Task.sleep(nanoseconds: 50_000_000)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            app.handleLidReading(100)
            try check(app.finishingGesture, "Reopening must begin the ordinary return")
            switch interruption {
            case "reclose":
                app.handleLidReading(80)
                try check(!app.finishingGesture && app.hasSnapshot && app.motion.active && source.count == 1,
                          "Reclosing must rejoin the same smoothed gesture without recapturing")
                app.suspend()
            case "sleep": app.suspend()
            case "Space change": app.handleActiveSpaceChange()
            case "display change": app.restart(startHardware: false)
            case "lock": app.handleScreenLock(true)
            default: app.shutdown()
            }
            try await Task.sleep(nanoseconds: 180_000_000)
            try checkCleared(app)
            try check(clicks == 0, "An interrupted fast-opening approach must stay silent")
            print("PASS: continuous ordinary return interrupted by \(interruption)")
        }

        for mode in ["Pause", "Esc", "assisted", "lid"] {
            var clicks = 0
            let (app, source) = try makeGesture(startGesture: false,
                                              playConnectionSound: { clicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            app.settingsModel.setConnectionEffectEnabled(false)
            app.handleLidReading(110)
            app.handleLidReading(80)
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            if mode == "Esc" { app.exitSeamlessClose() }
            else if mode == "lid" { app.handleLidReading(100) }
            else { app.finishGesture(mode: mode == "Pause" ? .pause : .assisted, openingSpeed: 30) }
            try await waitForCleanup(app)
            let sound = app.connectionSound as! SyntheticSound
            try check(clicks == 0 && sound.preparationCount == 0 && sound.scheduledPeaks.isEmpty,
                      "Connection effect off must keep \(mode) returns silent without starting audio")
            try checkCleared(app)
            print("PASS: Connection effect off preserves \(mode) return without audio startup")
        }
        do {
            var clicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { clicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            app.exitSeamlessClose()
            if let view = app.window?.contentView as? MTKView { app.renderer?.draw(in: view) }
            let sound = app.connectionSound as! SyntheticSound
            try check(sound.scheduledPeaks.count == 1, "Live switch check must start with a scheduled click")
            app.settingsModel.setConnectionEffectEnabled(false)
            app.settingsModel.setConnectionEffectEnabled(true)
            try await waitForCleanup(app)
            try check(clicks == 0 && sound.stopped && sound.scheduledPeaks.count == 1,
                      "Disabling feedback must cancel its click; re-enabling must not replay the current return")
            try checkCleared(app)
            print("PASS: live connection switch cancels feedback without interrupting desktop return")
        }
        func beginAssistedReturn(_ app: AppDelegate, _ source: SyntheticCapture) async throws {
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            try check(app.hasSnapshot && app.snapshotPresented,
                      "Opening assist needs the visible closing screenshot")
            let sampleTime = ProcessInfo.processInfo.systemUptime - 0.31
            app.handleLidReading(70, time: sampleTime + 0.01)
            app.handleLidReading(80, time: sampleTime + 0.11)
            app.handleLidReading(90, time: sampleTime + 0.21)
            try check(!app.finishingGesture,
                      "The image must keep following the lid outside the last five degrees")
            app.handleLidReading(95, time: sampleTime + 0.31)
            try check(app.finishingGesture && app.assistedOpeningPeakAngle == 95
                      && app.hasSnapshot && source.count == 1,
                      "Opening into the final five degrees must start one assisted return")
        }
        do {
            var connectionClicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { connectionClicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            try await beginAssistedReturn(app, source)
            app.handleLidReading(95)
            try check(app.finishingGesture && source.count == 1,
                      "Holding the lid during assisted return must not recapture")
            app.handleLidReading(92)
            try check(!app.finishingGesture && app.assistedOpeningPeakAngle == nil
                      && app.hasSnapshot && app.motion.active && source.count == 1,
                      "Reversal must rejoin the same captured gesture")
            try check(connectionClicks == 0, "Reversal before contact must remain silent")
            app.handleLidReading(100)
            try await waitForCleanup(app)
            try checkCleared(app)
            print("PASS: assisted opening reverses through the same screenshot")
        }
        do {
            var connectionClicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { connectionClicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            try await beginAssistedReturn(app, source)
            var desktopUsableDuringGlow = false
            for _ in 0..<200 {
                if app.hasSnapshot, app.renderer?.opacity == 0,
                   app.window?.ignoresMouseEvents == true {
                    desktopUsableDuringGlow = true
                    break
                }
                if let view = app.window?.contentView as? MTKView, app.renderer?.isRendering == true {
                    app.renderer?.draw(in: view)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try check(desktopUsableDuringGlow,
                      "The live desktop must accept input while the connection rim retracts")
            try await waitForCleanup(app)
            try checkCleared(app)
            try check(connectionClicks == 1,
                      "Assisted opening must play its connection sound once at visible contact")
            try check(app.motion.desktopResumed, "Early completion must keep desktop access live")
            app.handleLidReading(95)
            app.handleLidReading(92)
            try check(!app.motion.active && source.count == 1,
                      "Stopping or closing below the manual start must not start another capture")
            app.handleLidReading(101)
            app.handleLidReading(80)
            try await waitForCapture(source)
            try check(source.count == 2,
                      "Opening above the manual start must arm one fresh closing screenshot")
            app.suspend()
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try checkCleared(app)
            print("PASS: assisted opening completes early and rearms safely")
        }
        do {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            // Seed a stationary five-degree frame. The watchdog test needs a
            // known visible speed; sensor replay and takeover momentum have
            // separate coverage and can legitimately finish this return sooner.
            app.renderer?.pauseSnapshot()
            app.renderer?.setLidAngle(95, referenceAngle: 100,
                                      sampleTime: ProcessInfo.processInfo.systemUptime)
            try await app.renderer?.prepareSnapshot(pixelBuffer: buffer)
            app.renderer?.progress = 0.05
            let slowStarted = ProcessInfo.processInfo.systemUptime
            app.assistedOpeningPeakAngle = 95
            app.finishGesture(mode: .assisted, openingSpeed: 5)
            try check(app.finishingGesture, "Slow opening must enter the assisted finish")
            // Keep presenting frames while testing the slow finish. If an
            // occluded synthetic window stops presenting, the watchdog is
            // supposed to release it instead of waiting for this trajectory.
            while ProcessInfo.processInfo.systemUptime - slowStarted < 0.85 {
                if let view = app.window?.contentView as? MTKView, app.renderer?.isRendering == true {
                    app.renderer?.draw(in: view)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try check(app.hasSnapshot && app.finishingGesture,
                      "The cleanup watchdog must allow a slow assisted finish to keep moving; elapsed=\(ProcessInfo.processInfo.systemUptime - slowStarted), peaks=\((app.connectionSound as! SyntheticSound).scheduledPeaks.map { $0 - slowStarted }), natural=\((app.connectionSound as! SyntheticSound).finished), stopped=\((app.connectionSound as! SyntheticSound).stopped)")
            try await waitForCleanup(app)
            try checkCleared(app)
            print("PASS: slow assisted opening retains its image until the speed-matched finish")
        }
        do {
            let (app, source) = try makeGesture(startGesture: false)
            defer { app.shutdown(); app.window?.close() }
            app.motion.automaticStartAngle = true
            app.settingsModel.configure(animationEnabled: true, startAngle: 100,
                                        screenCaptureAllowed: true, automaticStartAngle: true)
            app.handleLidReading(110)
            app.handleLidReading(80)
            try await beginAssistedReturn(app, source)
            try await waitForCleanup(app)
            try check(app.motion.learnedStartAngle == 94
                      && app.settingsModel.learnedStartAngle == 94,
                      "Automatic mode must display the newly learned angle after early completion")
            app.handleLidReading(93)
            try await waitForCapture(source)
            try check(source.count == 2,
                      "Automatic mode must rearm on a real close below the learned angle")
            app.suspend()
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try checkCleared(app)
            print("PASS: assisted opening updates automatic angle and rearms on closing")
        }
        for interruption in ["sleep", "display change", "quit", "lock"] {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await beginAssistedReturn(app, source)
            switch interruption {
            case "sleep": app.suspend()
            case "display change": app.restart(startHardware: false)
            case "lock": app.handleScreenLock(true)
            default: app.shutdown()
            }
            try checkCleared(app)
            print("PASS: assisted opening cleanup on \(interruption)")
        }

        // Expire the still-lid timer through the real coordinator with fresh
        // synthetic timestamps, including captures that have not completed yet.
        for visible in [false, true] {
            var connectionClicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { connectionClicks += 1 })
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
            if visible {
                try await waitForConnectionDesktop(app)
                try await waitForCleanup(app)
            }
            try checkCleared(app)
            try check(connectionClicks == (visible ? 1 : 0),
                      "Pause must click once at visible contact and stay silent for a pending capture")
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
        for outcome in ["complete", "disable", "reclose"] {
            var clicks = 0
            let (app, source) = try makeGesture(startGesture: false,
                                              playConnectionSound: { clicks += 1 })
            defer { app.shutdown(); app.window?.close() }
            app.motion.automaticStartAngle = true
            app.motion.resumeAfterPause = true
            app.motion.pauseDuration = 0.5
            app.settingsModel.configure(animationEnabled: true, startAngle: 100,
                                        screenCaptureAllowed: true, resumeAfterPause: true,
                                        automaticStartAngle: true, pauseDuration: 0.5)
            let started = ProcessInfo.processInfo.systemUptime
            for frame in 0...20 {
                app.handleLidReading(110, time: started - 1 + Double(frame) / 20)
            }
            app.handleLidReading(80, time: started + 0.01)
            try await waitForCapture(source)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            for frame in 0...11 {
                app.handleLidReading(80, time: started + 0.1 + Double(frame) * 0.05)
            }
            try check(app.finishingGesture && app.motion.desktopResumed
                      && app.motion.learnedStartAngle == 79,
                      "Automatic Pause must begin a visible return and learn the lower start angle")
            if let view = app.window?.contentView as? MTKView { app.renderer?.draw(in: view) }
            let sound = app.connectionSound as! SyntheticSound
            try check(sound.scheduledPeaks.count == 1 && !sound.stopped,
                      "Pause jitter check must exercise an already scheduled click")
            app.handleLidReading(80.01, time: started + 0.66)
            try check(!app.motion.desktopResumed && !app.motion.active && app.finishingGesture,
                      "Fractional upward jitter must exercise the ignored lid-finish request")
            try check(!sound.stopped && sound.scheduledPeaks.count == 1,
                      "An ignored lid-finish request must preserve the scheduled Pause click")
            if outcome == "complete" {
                // Keep sensor delivery going throughout the return, as on hardware.
                for frame in 0..<200 {
                    if !app.finishingGesture { break }
                    app.handleLidReading(frame.isMultiple(of: 2) ? 80.01 : 80.05,
                                         time: started + 0.67 + Double(frame) / 30)
                    if let view = app.window?.contentView as? MTKView { app.renderer?.draw(in: view) }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                try checkCleared(app)
                try check(clicks == 1 && sound.finished && !sound.stopped,
                          "Automatic Pause must click exactly once despite continuing sensor jitter")
            } else {
                if outcome == "disable" {
                    app.settingsModel.setAnimationEnabled(false)
                    app.handleLidReading(80.01, time: started + 0.67)
                } else {
                    app.handleLidReading(78, time: started + 0.67)
                    try check(app.motion.active && app.hasSnapshot && source.count == 1,
                              "A genuine reclose must reuse the captured image")
                    app.suspend()
                }
                try await Task.sleep(nanoseconds: 650_000_000)
                try check(clicks == 0 && sound.stopped,
                          "Explicit interruption must still cancel the click after harmless jitter")
            }
            print("PASS: automatic Pause audio survives fractional lid jitter; outcome=\(outcome)")
        }
        for interruption in ["sleep", "display change", "Space change", "lock", "reversal", "quit"] {
            var connectionClicks = 0
            let (app, source) = try makeGesture(playConnectionSound: { connectionClicks += 1 })
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
            case "display change": app.restart(startHardware: false)
            case "Space change": app.handleActiveSpaceChange()
            case "lock": app.handleScreenLock(true)
            case "reversal":
                app.handleLidReading(101, time: 101)
                app.handleLidReading(80, time: 101.1)
                try check(app.motion.active && app.hasSnapshot && source.count == 1,
                          "A reclose during Pause must rejoin the same image without replaying feedback")
                app.suspend()
            default: app.shutdown()
            }
            try await Task.sleep(nanoseconds: 180_000_000)
            try checkCleared(app)
            try check(connectionClicks == 0, "An interrupted pause return must stay silent")
            print("PASS: pause return interrupted by \(interruption)")
        }

        func checkParked(_ app: AppDelegate) throws {
            try check(app.retainedClosingSnapshot && app.renderer?.hasPreparedSnapshot == true,
                      "Sleep must keep the prepared closing image")
            try check(!app.hasSnapshot && !app.snapshotRequested && app.snapshotTask == nil,
                      "Retained pixels must not remain an active gesture")
            try check(app.window?.alphaValue == 0 && app.window?.ignoresMouseEvents == true
                      && app.renderer?.progress == 0 && app.renderer?.isRendering == false,
                      "Retained pixels must remain hidden, paused and nonblocking")
        }
        func makeSleepingWake(lockBeforeSleep: Bool = false,
                              screenAccessAllowed: @escaping () -> Bool = { true }) async throws -> (AppDelegate, SyntheticCapture) {
            let (app, source) = try makeGesture(screenAccessAllowed: screenAccessAllowed)
            try await waitForCapture(source)
            let pipeline = app.renderer
            try await Task.sleep(nanoseconds: 50_000_000)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            app.handleLidReading(8)
            if lockBeforeSleep {
                app.handleScreenLock(true)
                let grace = app.sleepPreparationTimer
                try checkParked(app)
                app.handleScreenLock(true)
                try check(app.sleepPreparationTimer === grace, "Repeated lock cannot extend the pre-sleep grace")
            }
            app.suspend()
            app.suspend()
            try checkParked(app)
            try check(app.renderer === pipeline && app.sleepPreparationTimer == nil,
                      "Sleep must reuse the renderer and end pre-sleep grace")
            try check(app.wakeOpening.awaitingWake && source.count == 1, "Only a completed closing frame may arm wake")
            return (app, source)
        }
        func makeWake(screenAccessAllowed: @escaping () -> Bool = { true }) async throws -> (AppDelegate, SyntheticCapture) {
            let (app, source) = try await makeSleepingWake(screenAccessAllowed: screenAccessAllowed)
            app.resume(startHardware: false)
            app.ready = true
            app.resume(startHardware: false)
            try check(app.wakeOpening.pending && app.wakeTimer != nil, "Near-closed sleep must arm one wake")
            app.handleLidReading(12)
            app.handleLidReading(16)
            // No await: callers can interrupt before the preparation task starts.
            try check(source.count == 1 && app.openingGesture && app.snapshotRequested,
                      "Wake must prepare the retained frame without capturing again")
            return (app, source)
        }
        do {
            let (app, source) = try await makeWake()
            defer { app.shutdown(); app.window?.close() }
            await app.snapshotTask?.value
            try check(app.snapshotPresented && app.openingGesture,
                      "Cached-opening Escape needs the visible retained image")
            let sound = app.connectionSound as! SyntheticSound
            var clicks = 0
            sound.onPeak = { clicks += 1 }
            app.exitSeamlessClose()
            try check(app.hasSnapshot && app.finishingGesture,
                      "Escape must preserve the visible wake image for its return")
            try await waitForConnectionDesktop(app)
            try await waitForCleanup(app)
            try check(clicks == 1 && sound.finished && !sound.stopped && source.count == 1,
                      "A completed cached Escape must finish its one scheduled click without stopping or recapturing")
            try checkCleared(app)
            print("PASS: cached-opening Escape keeps one image and lets its scheduled click finish naturally")
        }
        for failure in [false, true] {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            let lateTask = app.snapshotTask
            if failure {
                source.pending?.resume(throwing: NSError(domain: "SyntheticCapture", code: 1))
                source.pending = nil
                await lateTask?.value
            }
            app.handleLidReading(8)
            app.suspend()
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await lateTask?.value
            try checkCleared(app)
            app.resume(startHardware: false)
            app.ready = true
            app.handleLidReading(12)
            app.handleLidReading(16)
            try check(!app.wakeOpening.pending && !app.openingGesture && source.count == 1,
                      "Missing or failed closing captures must skip wake, with no fresh-capture fallback")
            print("PASS: wake skips \(failure ? "failed" : "late") closing capture")
        }
        for receivesSample in [false, true] {
            let (app, source) = try await makeSleepingWake()
            defer { app.shutdown(); app.window?.close() }
            app.lastReading = .distantPast
            app.resume(startHardware: false)
            app.ready = true
            let restarted = app.sensorRestartedAt
            app.resume(startHardware: false)
            try check(app.sensorRestartedAt == restarted, "Duplicate wake must not extend sensor recovery")
            app.checkSensorHealth(at: restarted)
            app.checkSensorHealth(at: restarted.addingTimeInterval(0.004))
            try check(app.wakeOpening.pending && !app.wakeReceivedSample && source.count == 1,
                      "A queued heartbeat cannot reject the sensor before its first sample")
            if receivesSample {
                app.handleLidReading(12)
                app.handleLidReading(16)
                await app.snapshotTask?.value
                try check(app.hasSnapshot && source.count == 1, "Fresh sensor delivery must reuse closing pixels")
            }
            app.checkSensorHealth(at: Date().addingTimeInterval(1.1))
            try check(!app.wakeOpening.pending, "Real sensor loss must still cancel")
            try checkCleared(app)
            print("PASS: cached wake heartbeat race with \(receivesSample ? "fresh then missing" : "missing") sensor readings")
        }
        for lockOrder in ["before sleep", "during sleep", "after wake"] {
            for completesWhileLocked in [false, true] {
                let (app, source) = try await makeSleepingWake(lockBeforeSleep: lockOrder == "before sleep")
                defer { app.shutdown(); app.window?.close() }
                if lockOrder == "during sleep" { app.handleScreenLock(true) }
                app.resume(startHardware: false)
                app.ready = true
                let wakeStarted = app.wakeOpening.startedAt
                if lockOrder == "after wake" { app.handleScreenLock(true) }
                app.handleLidReading(12)
                app.handleLidReading(16)
                try checkParked(app)
                try check(app.wakeReceivedSample && source.count == 1 && app.wakeOpening.startedAt == wakeStarted,
                          "Locked wake must keep one hidden frame without extending the deadline")
                if completesWhileLocked { app.handleLidReading(100) }
                app.handleScreenLock(false)
                if completesWhileLocked {
                    app.handleLidReading(110)
                    try check(!app.wakeOpening.pending && source.count == 1, "Unlock must not replay completed motion")
                    try checkCleared(app)
                } else {
                    app.handleLidReading(20)
                    await app.snapshotTask?.value
                    try check(app.hasSnapshot && source.count == 1 && !app.retainedClosingSnapshot,
                              "Remaining opening must reveal the same image, consuming the cache")
                    app.handleScreenLock(true)
                    try checkCleared(app)
                }
                print("PASS: lock \(lockOrder), \(completesWhileLocked ? "completed opening skipped" : "same frame after unlock")")
            }
        }
        for interruption in ["deadline", "session change", "permission", "disable", "threshold", "quit", "display", "license expiry"] {
            var access = true
            let (app, source) = try await makeSleepingWake(screenAccessAllowed: { access })
            defer { app.shutdown(); app.window?.close() }
            switch interruption {
            case "deadline":
                app.handleScreenLock(true)
                app.resume(startHardware: false)
                app.ready = true
                app.handleLidReading(16, time: (app.wakeOpening.startedAt ?? 0) + WakeOpening.deadline + 0.01)
            case "session change": app.handleSessionActivity(inactive: true)
            case "permission": access = false; app.checkScreenAccess()
            case "disable": app.settingsModel.setAnimationEnabled(false); app.applyAnimationEnabled(false)
            case "threshold": app.applyStartAngle(95)
            case "license expiry": app.applyLicenseAccess(false)
            case "quit": app.shutdown()
            default: app.restart(startHardware: false)
            }
            try checkCleared(app)
            try check(!app.wakeOpening.awaitingWake && !app.wakeOpening.pending && app.wakeTimer == nil && source.count == 1,
                      "Dormant-cache cancellation must release pixels and wake eligibility")
            print("PASS: retained frame released on \(interruption)")
        }
        for unlocked in [false, true] {
            let (app, source) = try makeGesture()
            defer { app.shutdown(); app.window?.close() }
            try await waitForCapture(source)
            try await Task.sleep(nanoseconds: 50_000_000)
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await app.snapshotTask?.value
            app.handleLidReading(8)
            app.handleScreenLock(true)
            try checkParked(app)
            if unlocked { app.handleScreenLock(false) }
            else { app.sleepPreparationTimer?.fire() }
            try checkCleared(app)
            print("PASS: near-closed lock without sleep clears on \(unlocked ? "unlock" : "grace expiry")")
        }
        do {
            let (app, _) = try await makeSleepingWake()
            defer { app.shutdown(); app.window?.close() }
            guard let screen = app.builtInScreen() else { throw NSError(domain: "LifecycleTest", code: 4) }
            app.window?.setFrame(screen.frame, display: false)
            app.displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            app.displayScale = screen.backingScaleFactor
            app.displayLayout = app.currentDisplayLayout()
            app.handleDisplayChange()
            try checkParked(app)
            app.displayLayout = [] // Simulate a changed display layout, even with the same built-in screen.
            app.handleDisplayChange()
            try checkCleared(app)
            print("PASS: redundant display notification retains pixels; changed layout during sleep releases them")
        }
        for visible in [false, true] {
            for interruption in ["reversal", "sleep", "display change", "quit", "lock", "disable", "threshold", "permission"] {
                var access = true
                let (app, source) = try await makeWake(screenAccessAllowed: { access })
                defer { app.shutdown(); app.window?.close() }
                let task = app.snapshotTask
                if visible {
                    await task?.value
                    try check(app.hasSnapshot && !app.wakeOpening.pending,
                              "Cached wake must prepare folded pixels without a closing entrance")
                    try await Task.sleep(nanoseconds: 100_000_000)
                    try check(app.window!.alphaValue == 1, "Cached wake must fully reveal")
                }
                switch interruption {
                case "reversal": app.handleLidReading(100)
                case "sleep": app.suspend()
                case "display change": app.restart(startHardware: false)
                case "quit": app.shutdown()
                case "lock": app.handleScreenLock(true)
                case "disable": app.settingsModel.setAnimationEnabled(false); app.applyAnimationEnabled(false)
                case "threshold": app.applyStartAngle(95)
                default: access = false; app.checkScreenAccess()
                }
                await task?.value
                if interruption == "reversal" { try await waitForCleanup(app) }
                try checkCleared(app)
                try check(!app.wakeOpening.pending && app.wakeTimer == nil && source.count == 1,
                          "Interrupted cached wake must leave no pixels, retry or late reveal")
                print("PASS: \(visible ? "visible" : "pending") cached wake cleanup on \(interruption)")
            }
        }
        do {
            let (wake, source) = try await makeWake()
            defer { wake.shutdown(); wake.window?.close() }
            await wake.snapshotTask?.value
            try await Task.sleep(nanoseconds: 100_000_000)
            wake.handleLidReading(100)
            try await Task.sleep(nanoseconds: 30_000_000)
            wake.handleLidReading(60)
            for _ in 0..<25 {
                if let view = wake.window?.contentView as? MTKView, wake.renderer?.isRendering == true {
                    wake.renderer?.draw(in: view)
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try check(wake.hasSnapshot && !wake.finishingGesture && source.count == 1
                      && wake.renderer?.opacity == 1,
                      "Reclosing during cached wake return must restore the same image and cancel cleanup "
                      + "(snapshot \(wake.hasSnapshot), finishing \(wake.finishingGesture), "
                      + "captures \(source.count), opacity \(wake.renderer?.opacity ?? -1))")
            wake.handleLidReading(100)
            try await waitForCleanup(wake)
            try checkCleared(wake)
            print("PASS: cached-wake return can reverse without recapture or stale cleanup")
        }
        do {
            let (wake, source) = try await makeWake()
            defer { wake.shutdown(); wake.window?.close() }
            await wake.snapshotTask?.value
            try check(wake.hasSnapshot && wake.snapshotPresented,
                      "Cached wake must reveal its retained screenshot before opening assist")
            let sampleTime = ProcessInfo.processInfo.systemUptime - 0.31
            wake.handleLidReading(70, time: sampleTime + 0.01)
            wake.handleLidReading(80, time: sampleTime + 0.11)
            wake.handleLidReading(90, time: sampleTime + 0.21)
            try check(!wake.finishingGesture,
                      "Cached wake must keep following the lid until five degrees remain")
            wake.handleLidReading(95, time: sampleTime + 0.31)
            try check(wake.finishingGesture && wake.assistedOpeningPeakAngle == 95
                      && source.count == 1,
                      "Cached wake must use the retained image for assisted opening")
            try await waitForCleanup(wake)
            try checkCleared(wake)
            print("PASS: cached wake completes its final five degrees without another screenshot")
        }
        do {
            let (app, source) = try await makeWake()
            defer { app.shutdown(); app.window?.close() }
            await app.snapshotTask?.value
            app.handleLidReading(100)
            try await waitForCleanup(app)
            try checkCleared(app)
            app.handleLidReading(110)
            app.handleLidReading(80)
            try await waitForCapture(source)
            try check(source.count == 2, "The next closing gesture must take its own new image")
            let task = app.snapshotTask
            app.shutdown()
            source.pending?.resume(returning: buffer)
            source.pending = nil
            await task?.value
            try checkCleared(app)
            print("PASS: one screenshot across closing/sleep/opening, release, and fresh capture next cycle")
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
        let initialFrames = app.renderer?.renderedFrameCount ?? 0
        for _ in 0..<50 {
            if (app.renderer?.renderedFrameCount ?? 0) > initialFrames + 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try check((app.renderer?.renderedFrameCount ?? 0) > initialFrames + 1,
                  "The production display link must advance visible frames without manual pumping")
        try await Task.sleep(nanoseconds: 45_000_000)
        try check(app.window!.alphaValue == 1,
                  "Closing must replace the prepared identity frame at full window opacity")
        app.handleLidReading(100)
        try await Task.sleep(nanoseconds: 40_000_000)
        app.handleLidReading(80)
        try await Task.sleep(nanoseconds: 250_000_000)
        try check(app.hasSnapshot && !app.finishingGesture && source.count == 1 && app.window!.alphaValue == 1,
                  "Reclosing must retain one snapshot and reject the old return completion")
        app.handleLidReading(100)
        if let view = app.window?.contentView as? MTKView { app.renderer?.draw(in: view) }
        try check(app.renderer?.manualCompletionIsAdvancing == true,
                  "The manual final degree must keep advancing on the lid trajectory")
        app.cleanupTimer?.fire()
        try check(app.hasSnapshot && app.finishingGesture,
                  "The cleanup watchdog must not cut off progressing manual lid motion")
        try await waitForCleanup(app)
        try checkCleared(app)
        print("PASS: identity entrance, interrupted return, one-snapshot reclose, aligned fade cleanup")

        let (stalled, stalledSource) = try makeGesture()
        defer { stalled.shutdown(); stalled.window?.close() }
        try await waitForCapture(stalledSource)
        try await Task.sleep(nanoseconds: 50_000_000)
        stalledSource.pending?.resume(returning: buffer)
        stalledSource.pending = nil
        await stalled.snapshotTask?.value
        stalled.handleLidReading(100)
        stalled.renderer?.progress = 0 // Simulate suspended display callbacks.
        try await Task.sleep(nanoseconds: 900_000_000)
        try checkCleared(stalled)
        print("PASS: missing display callbacks cannot leave the desktop blocked")
    }
}

// Diagnostics should not register as foreground app launches. UI lifecycle
// checks temporarily exercise regular activation, then terminate via AppKit.
if CommandLine.arguments.contains(where: { ["--lifecycle-test", "--render-test", "--render-benchmark", "--material-preview", "--blur-preview", "--capture-metadata-test"].contains($0) }) {
    setbuf(stdout, nil)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
    }
}

if CommandLine.arguments.contains("--version") {
    print("Glissform \(Bundle.main.object(forInfoDictionaryKey: "GlissformVersion") as? String ?? "Development")")
} else if CommandLine.arguments.contains("--probe") {
    print(LidSensor.probe())
} else if CommandLine.arguments.contains("--capture-metadata-test") {
    Task { @MainActor in
        do {
            try await AppDelegate.captureMetadataSelfTest()
            NSApp.terminate(nil)
        } catch {
            fputs("Capture metadata test failed: \(error)\n", stderr)
            exit(1)
        }
    }
    NSApplication.shared.run()
} else if CommandLine.arguments.contains("--lifecycle-test") {
    _ = NSApplication.shared
    Task { @MainActor in
        do {
            try await AppDelegate.lifecycleSelfTest()
            print("Synthetic lifecycle checks passed")
            NSApp.setActivationPolicy(.accessory)
            NSApp.terminate(nil)
        } catch {
            fputs("Lifecycle test failed: \(error)\n", stderr)
            NSApp.setActivationPolicy(.accessory)
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
} else if CommandLine.arguments.contains("--blur-preview") {
    _ = NSApplication.shared
    do {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/blur-preview")
        try EffectRenderer.materialPreview(outputDirectory: directory, wallpaperOnly: true)
        print("Wallpaper blur previews: \(directory.path)")
    } catch {
        fputs("Blur preview failed: \(error)\n", stderr)
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
