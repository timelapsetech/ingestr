import Foundation

/// How strictly copied files are checked after writing to the destination.
enum CopyVerificationMode: String, CaseIterable, Identifiable {
    case none
    case full
    case sizeOnly

    var id: String { rawValue }

    static let userDefaultsKey = "copyVerificationMode"

    /// Short labels for pickers.
    var menuTitle: String {
        switch self {
        case .none: return "None"
        case .full: return "Full (byte check)"
        case .sizeOnly: return "Size only"
        }
    }
}
