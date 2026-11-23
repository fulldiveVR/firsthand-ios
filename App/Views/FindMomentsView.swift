#if os(iOS)
import FirsthandCore
import SwiftUI

extension AnalysisProgress {
    var phaseTitle: String {
        switch phase {
        case .scanning: String(localized: "Looking for recent photos")
        case .analyzing: String(localized: "Analyzing photos")
        case .choosing: String(localized: "Choosing the best moment")
        }
    }

    /// Short status line, also used by the system progress UI of the first scan.
    var subtitle: String {
        guard phase == .analyzing, total > 0 else { return phaseTitle }
        return String(localized: "\(completed) of \(total) photos")
    }
}

enum SystemSettings {
    @MainActor
    static func open() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
#endif
