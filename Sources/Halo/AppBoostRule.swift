/// What an app does to the boost while it's the one in front. Set per app in Settings and saved
/// by raw value.
enum AppBoostRule: String, CaseIterable {
    case boost
    case noBoost

    struct Change: Equatable {
        let isEnabled: Bool
        /// What to put back once an app with no rule comes to the front. Nil when there's
        /// nothing to put back.
        let enabledBefore: Bool?
    }

    var title: String {
        switch self {
        case .boost: return "Boost"
        case .noBoost: return "Don't boost"
        }
    }

    /// Where the boost goes when an app with `rule` comes to the front, nil meaning an app with
    /// no rule. `enabledBefore` is what the boost was before a rule first changed it, so going
    /// from one rule's app to another's still puts back the boost from before either.
    static func change(
        to rule: AppBoostRule?, isEnabled: Bool, enabledBefore: Bool?
    ) -> Change {
        guard let rule else {
            return Change(isEnabled: enabledBefore ?? isEnabled, enabledBefore: nil)
        }
        let wanted = rule == .boost
        guard wanted != isEnabled else {
            return Change(isEnabled: isEnabled, enabledBefore: enabledBefore)
        }
        return Change(isEnabled: wanted, enabledBefore: enabledBefore ?? isEnabled)
    }
}
