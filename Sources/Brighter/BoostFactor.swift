/// How much brighter than SDR white the boost goes, as a multiplier.
enum BoostFactor {
    /// The XDR panel holds 1000 nits across the whole screen against 500 for SDR white. Past 2x
    /// it can only brighten small areas, so full-screen content would clip.
    static let range: ClosedRange<Double> = 1.0...2.0
    static let defaultValue = 1.5
    static let defaultsKey = "boostFactor"
    /// How far one press of the brighter or dimmer shortcut moves it: 10% on the menu's label.
    static let step = 0.1

    /// One shortcut step up (positive) or down (negative) from `factor`, kept in range.
    static func stepped(_ factor: Double, by steps: Int) -> Double {
        let value = factor + Double(steps) * step
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Reads a stored value back into range. Anything that isn't a number gets the default.
    static func clamped(_ stored: Any?) -> Double {
        guard let value = stored as? Double, value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
