import CoreGraphics
import Darwin

/// The built-in display's brightness as the brightness keys and Control Center set it, 0 to 1.
/// Apple Silicon has no public call for this (IODisplayGetFloatParameter finds nothing there), so
/// it goes through the private DisplayServices framework that Control Center itself uses.
@MainActor
enum SystemBrightness {
    private typealias GetBrightness =
        @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    /// Nil if a macOS update removes the framework or the call, and then the boost simply stops
    /// following brightness.
    private static let getBrightness: GetBrightness? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY),
            let symbol = dlsym(handle, "DisplayServicesGetBrightness")
        else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private static let maxDisplays = 16

    /// Nil with the lid closed, or when the call fails.
    static func builtInLevel() -> Float? {
        guard let getBrightness, let displayID = builtInDisplayID() else { return nil }
        var level: Float = 0
        guard getBrightness(displayID, &level) == 0 else { return nil }
        return level
    }

    private static func builtInDisplayID() -> CGDirectDisplayID? {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: maxDisplays)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(maxDisplays), &displayIDs, &count) == .success
        else { return nil }
        return displayIDs.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}

/// Keeps the boost to a screen at full brightness. Dimming from 100% turns it off, and getting
/// back to 100% turns it on again, but only if this rule was what turned it off. Switching the
/// boost on by hand while dimmed is left alone until the next drop from 100%.
enum FullBrightnessRule {
    enum Change: Equatable {
        case suspend
        case resume
    }

    /// The top of the brightness slider can read a hair under 1 after float rounding.
    static let fullLevel: Float = 0.995

    static func isFull(_ level: Float) -> Bool {
        level >= fullLevel
    }

    static func change(
        from previous: Float, to level: Float, isEnabled: Bool, isWaiting: Bool
    ) -> Change? {
        if isEnabled && isFull(previous) && !isFull(level) { return .suspend }
        if isWaiting && isFull(level) { return .resume }
        return nil
    }
}
