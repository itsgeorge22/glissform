import Foundation

@main
struct ChargingFeedbackChecks {
    static func main() {
        var battery = ChargingPowerTransition(initial: false)
        precondition(!battery.update(false), "Repeated battery notifications must stay quiet")
        precondition(battery.update(true), "Connecting external power must play once")
        precondition(!battery.update(true), "Repeated AC notifications must stay quiet")
        precondition(!battery.update(false), "Disconnecting must stay quiet")
        precondition(battery.update(true), "A new connection must play again")

        var launchedPluggedIn = ChargingPowerTransition(initial: true)
        precondition(!launchedPluggedIn.update(true), "Launch on AC must stay quiet")
        var unavailable = ChargingPowerTransition(initial: nil)
        precondition(!unavailable.update(true), "Unknown initial state must not invent a connection")
        print("PASS: charging transition triggers once per battery-to-external connection")

        var low = LowBatteryTransition(external: false, percent: 22)
        precondition(!low.update(external: false, percent: 21), "Above threshold stays quiet")
        precondition(low.update(external: false, percent: 20), "Crossing to 20% triggers once")
        precondition(!low.update(external: false, percent: 20), "Duplicate 20% notification stays quiet")
        precondition(!low.update(external: false, percent: 19), "Further discharge stays quiet")
        precondition(!low.update(external: true, percent: 20), "Connecting power stays quiet")
        precondition(!low.update(external: false, percent: 20), "Unplugging at 20% stays quiet")
        precondition(!low.update(external: false, percent: 23), "Rearming above threshold stays quiet")
        precondition(low.update(external: false, percent: 19), "A later crossing triggers again")
        var startedLow = LowBatteryTransition(external: false, percent: 20)
        precondition(!startedLow.update(external: false, percent: 19), "Launch below threshold never replays")
        var unknown = LowBatteryTransition(external: nil, percent: nil)
        precondition(!unknown.update(external: false, percent: 20), "Unknown baseline must not invent a low event")
        print("PASS: low-battery ripple triggers once on a battery-only crossing to 20%")
    }
}
