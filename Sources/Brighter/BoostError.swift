import CoreGraphics

enum BoostError: Error, Equatable {
    case gammaRead(display: CGDirectDisplayID, error: CGError)
    case gammaWrite(display: CGDirectDisplayID, error: CGError)
    case metalUnavailable

    var message: String {
        switch self {
        case let .gammaRead(display, error):
            "Couldn't read the gamma table of display \(display) (CGError \(error.rawValue))."
        case let .gammaWrite(display, error):
            "Couldn't set the gamma table of display \(display) (CGError \(error.rawValue))."
        case .metalUnavailable:
            "Metal isn't available, so the display can't be switched into EDR mode."
        }
    }
}
