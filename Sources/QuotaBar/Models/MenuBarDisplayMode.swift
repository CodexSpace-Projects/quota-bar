import Foundation
import QuotaBarCore

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndPercentage
    case resetAndPercentage
    case percentage
    case icon
    case activity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconAndPercentage: return AppLocalization.text("Icon + percentage")
        case .resetAndPercentage: return AppLocalization.text("Reset + percentage")
        case .percentage: return AppLocalization.text("Percentage only")
        case .icon: return AppLocalization.text("Icon only")
        case .activity: return AppLocalization.text("Usage history")
        }
    }
}
