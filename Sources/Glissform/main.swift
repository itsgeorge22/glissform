import AppKit
import MetalKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let enableMenuItem = NSMenuItem(title: "Enable Infinite Screen", action: nil, keyEquivalent: "")
    private let sensor = LidSensor()
    private let capture: DesktopScreenshotSource
    private let desktopAvailable: (CGDirectDisplayID) -> Bool
    private let screenAccessAllowed: () -> Bool
    private let settingsModel = SettingsModel()
    private var settingsWindowController: SettingsWindowController?
    private var window: OverlayWindow?
    private var renderer: EffectRenderer?
    private var motion = ClosingMotion()
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var heartbeat: Timer?
    private var revealTimer: Timer?
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

    init(capture: DesktopScreenshotSource = DesktopCapture(),
         desktopAvailable: @escaping (CGDirectDisplayID) -> Bool = DesktopAvailability.allowsCapture,
         screenAccessAllowed: @escaping () -> Bool = CGPreflightScreenCaptureAccess) {
        self.capture = capture
        self.desktopAvailable = desktopAvailable
        self.screenAccessAllowed = screenAccessAllowed
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
        for (name, inactive) in [(NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handleSessionActivity(inactive: inactive)
                }
            })
        }
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
            guard self.checkScreenAccess(), !self.sleeping else { return }
            self.settingsModel.refreshPermission()
            self.checkSensorHealth()
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
        sensorRestartedAt = Date()
        motion.reset()
        sensor.start(onReading: { [weak self] angle in
            self?.handleLidReading(angle)
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
        guard angle.isFinite, (0...180).contains(angle) else {
            cancelWake("invalid sensor reading")
            endGesture()
            motion.reset()
            return
        }
        lastReading = Date()
        lastLidAngle = angle
        lastLidTime = time
        settingsModel.updateAngle(angle)
        guard settingsModel.animationEnabled else {
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
            switch wakeOpening.observe(angle: angle, time: time, referenceAngle: settingsModel.startAngle,
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
        let progress = beganOpening ? currentProgress : motion.update(angle: angle, time: time)
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
        if !snapshotRequested { prepareGestureSnapshot() }
        showProgress()
    }

    private func connect() {
        guard !starting, !sleeping, !quitting else { return }
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
            cancelWake("screen access revoked")
            endGesture()
            ready = false
            return false
        }
        return true
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
            do {
                guard !Task.isCancelled, token == snapshotToken else { return }
                if openingGesture {
                    guard retainedClosingSnapshot, captureMayPresent() else { discardCapture(); return }
                    retainedClosingSnapshot = false
                    try await renderer.prepareRetainedSnapshot()
                } else {
                    let buffer = try await capture.screenshot(displayID: displayID)
                    guard !Task.isCancelled, token == snapshotToken, motion.active,
                          ready, !sleeping, !quitting else { return }
                    guard captureMayPresent() else { discardCapture(); return }
                    try await renderer.prepareSnapshot(pixelBuffer: buffer)
                }
                guard !Task.isCancelled, token == snapshotToken, motion.active,
                      ready, !sleeping, !quitting else { return }
                guard captureMayPresent() else { discardCapture(); return }
                hasSnapshot = true
                // Raise only after capture: the snapshot retains the normal Dock
                // and menu bar, while their live counterparts stay underneath.
                window?.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
                window?.ignoresMouseEvents = false
                window?.orderFrontRegardless()
                setStatus(openingGesture ? "Animating · Opening" : "Animating · Reopen to reverse")
                // Reveal the prepared identity frame, then blend geometry and
                // opacity together so two handoffs do not accumulate latency.
                entrancePending = !openingGesture
                if openingGesture {
                    logWake("cached frame prepared; reveal requested")
                    clearWakeTracking()
                }
                showProgress()
                revealOverlay()
            } catch {
                guard token == snapshotToken, !Task.isCancelled else { return }
                discardCapture()
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

    private func endGesture(retainingSnapshot: Bool = false) {
        if openingGesture && wakeOpening.pending { clearWakeTracking() }
        openingGesture = false
        finishingGesture = false
        entrancePending = false
        revealTimer?.invalidate()
        revealTimer = nil
        currentProgress = 0
        window?.alphaValue = 0
        window?.ignoresMouseEvents = true
        window?.level = .floating
        renderer?.progress = 0
        sleepPreparationTimer?.invalidate()
        sleepPreparationTimer = nil
        snapshotToken += 1
        snapshotTask?.cancel()
        snapshotTask = nil
        snapshotRequested = false
        hasSnapshot = false
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
        settingsModel.animationEnabled && !sessionInactive && !openingGesture && !finishingGesture
            && hasSnapshot && motion.active && recentClosedLid && renderer?.hasPreparedSnapshot == true
    }

    private func suspend() {
        guard !sleeping else { return }
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
        sleeping = false
        sensorRestartedAt = Date()
        let hadClosedEvidence = wakeOpening.awaitingWake
        let eligible = settingsModel.animationEnabled && retainedClosingSnapshot
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
        guard !screenLocked, !sessionInactive, screenAccessAllowed(), let displayID else { return false }
        return desktopAvailable(displayID)
    }

    private func captureMayPresent() -> Bool {
        guard canUseDesktop() else { return false }
        return !openingGesture || wakeOpening.canPresent(time: ProcessInfo.processInfo.systemUptime,
            referenceAngle: settingsModel.startAngle, desktopAvailable: true)
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
            cancelWake("session inactive")
            endGesture()
            motion.reset()
        }
    }

    private func applyStartAngle(_ angle: Double) {
        guard motion.startAngle != angle else { return }
        cancelWake("starting angle changed")
        endGesture()
        motion.reset()
        motion.startAngle = angle
        UserDefaults.standard.set(angle, forKey: "animationStartAngle")
        setStatus("Ready · Close past \(Int(angle))° to animate")
    }

    private func applyAnimationEnabled(_ enabled: Bool) {
        cancelWake("animation setting changed")
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
    /// Real gesture/cancellation paths with synthetic pixels and no capture permission.
    static func lifecycleSelfTest() async throws {
        let savedSettings = ["animationStartAngle", "animationEnabled"].map {
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
        var storage: CVPixelBuffer?
        let attributes = [kCVPixelBufferMetalCompatibilityKey as String: true,
                          kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as [String: Any]
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &storage)
        guard let buffer = storage else { throw NSError(domain: "Glissform.LifecycleTest", code: 2) }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        func makeGesture(screenAccessAllowed: @escaping () -> Bool = { true }) throws -> (AppDelegate, SyntheticCapture) {
            let source = SyntheticCapture()
            let app = AppDelegate(capture: source, desktopAvailable: { _ in true }, screenAccessAllowed: screenAccessAllowed)
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
            app.settingsModel.configure(animationEnabled: true, startAngle: 100, screenCaptureAllowed: true)
            app.motion.startAngle = 100
            app.handleLidReading(110)
            app.handleLidReading(80)
            return (app, source)
        }
        func checkCleared(_ app: AppDelegate) throws {
            try check(!app.hasSnapshot && !app.snapshotRequested && app.snapshotTask == nil,
                      "Snapshot state must be cleared (alpha \(app.window?.alphaValue ?? -1), finishing \(app.finishingGesture), entrance \(app.entrancePending), paused \((app.window?.contentView as? MTKView)?.isPaused ?? true), visible \(app.window?.isVisible ?? false), occlusion \(app.window?.occlusionState.rawValue ?? 0), progress \(app.renderer?.progress ?? -1))")
            try check(app.window?.alphaValue == 0 && app.window?.ignoresMouseEvents == true,
                      "Interrupted gesture must restore desktop access")
            try check(!app.entrancePending && !app.finishingGesture && app.revealTimer == nil,
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
        func waitForCleanup(_ app: AppDelegate) async throws {
            // Pump synthetic rendering explicitly: MetalKit can suspend display
            // callbacks for a tiny/occluded window or a sleeping display. This
            // checks coordinator/GPU cleanup, not compositor frame delivery.
            for _ in 0..<100 {
                if !app.hasSnapshot { return }
                if let view = app.window?.contentView as? MTKView, !view.isPaused {
                    app.renderer?.draw(in: view)
                }
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
                case "display change": app.restart(startHardware: false)
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
            case "display change": app.restart(startHardware: false)
            default: app.shutdown()
            }
            try await Task.sleep(nanoseconds: 180_000_000)
            try checkCleared(app)
            print("PASS: pause return interrupted by \(interruption)")
        }

        func checkParked(_ app: AppDelegate) throws {
            try check(app.retainedClosingSnapshot && app.renderer?.hasPreparedSnapshot == true,
                      "Sleep must keep the prepared closing image")
            try check(!app.hasSnapshot && !app.snapshotRequested && app.snapshotTask == nil,
                      "Retained pixels must not remain an active gesture")
            try check(app.window?.alphaValue == 0 && app.window?.ignoresMouseEvents == true
                      && app.renderer?.progress == 0 && (app.window?.contentView as? MTKView)?.isPaused == true,
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
        for interruption in ["deadline", "session change", "permission", "disable", "threshold", "quit", "display"] {
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
                    try check(app.hasSnapshot && !app.entrancePending && !app.wakeOpening.pending,
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

// Diagnostics should not register as foreground app launches. UI lifecycle
// checks temporarily exercise regular activation, then terminate via AppKit.
if CommandLine.arguments.contains(where: { ["--lifecycle-test", "--render-test", "--render-benchmark", "--material-preview"].contains($0) }) {
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
