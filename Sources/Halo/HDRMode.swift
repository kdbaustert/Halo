import CoreGraphics
import Darwin

/// Whether macOS drives an external display in HDR mode, the "High Dynamic Range" switch in
/// System Settings > Displays. A display has no headroom to boost into until it's on. There's no
/// public call to flip it, so this goes through the private SkyLight ones that switch uses.
@MainActor
enum HDRMode {
    private typealias Query = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias SetEnabled = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    private struct Calls {
        let supports: Query
        let isEnabled: Query
        let setEnabled: SetEnabled
    }

    /// Nil if a macOS update removes the framework or any of the calls, and then HDR mode is left
    /// as it is.
    private static let calls: Calls? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
            let supports = dlsym(handle, "SLSDisplaySupportsHDRMode"),
            let isEnabled = dlsym(handle, "SLSDisplayIsHDRModeEnabled"),
            let setEnabled = dlsym(handle, "SLSDisplaySetHDRModeEnabled")
        else { return nil }
        return Calls(
            supports: unsafeBitCast(supports, to: Query.self),
            isEnabled: unsafeBitCast(isEnabled, to: Query.self),
            setEnabled: unsafeBitCast(setEnabled, to: SetEnabled.self))
    }()

    /// False for the built-in display, which has its headroom without a mode to switch.
    static func canSwitchOn(_ displayID: CGDirectDisplayID) -> Bool {
        guard let calls else { return false }
        return calls.supports(displayID) && !calls.isEnabled(displayID)
    }

    /// The display blanks for a moment, then posts a screen-parameter change once the mode is in.
    static func setEnabled(_ enabled: Bool, for displayID: CGDirectDisplayID) -> Bool {
        guard let calls else { return false }
        return calls.setEnabled(displayID, enabled) == 0
    }
}
