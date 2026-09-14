# Implementation notes

- **LidSensor.swift:** read-only IOKit HID access, Apple vendor/product `05ac:8104`, usage `0020:008a`, feature report 1. Whole-degree values are read on a serial worker at 30 Hz, with bounded reconnect backoff. Protocol support is undocumented.
- **ClosingMotion.swift:** gesture and threshold state, including awake reversal and startup/reset behavior.
- **DesktopCapture.swift:** one native-resolution sRGB ScreenCaptureKit screenshot per gesture, excluding Glissform itself. No stream is started. Pixels remain in memory.
- **EffectRenderer.swift:** runtime-compiled Metal projection and frost/shadow, with a fixed viewpoint approximation. Camera distance is four screen heights, eye height 1.1 screen heights, and rotation gain 0.867. The gradient runs from the bottom to a top 5% black plateau at full displayed progress.
- **MotionSmoothing.swift:** two-stage adaptive filtering for quantized angles and 180 ms boundary handoffs. Large movements/reversals use a fast response; slow steps deliberately trade a small delay for smoother motion.
- **main.swift:** menu controls, snapshot preparation/reveal, overlay ordering and click blocking, sensor/capture coordination, and cleanup across sleep, display changes, cancellation, and quit.

The first screenshot frame is rendered while the window is transparent. An 80 ms fade reveals the unchanged screenshot before the angle handoff begins. Returning to flat precedes an 80 ms exit fade. Snapshot tokens and renderer transition generations reject stale asynchronous work.

This is a frozen image viewed through a simulated moving panel. It does not track the viewer's head, intercept the lock screen, or keep the system awake.
