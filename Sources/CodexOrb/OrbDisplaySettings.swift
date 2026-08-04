import CoreGraphics
import Foundation

enum OrbDisplaySettings {
    static let show24hKey = "orb.show.24h"
    static let show48hKey = "orb.show.48h"

    static let panelWidth: CGFloat = 80
    static let orbStep: CGFloat = 76

    static var show24h: Bool {
        UserDefaults.standard.object(forKey: show24hKey) as? Bool ?? true
    }

    static var show48h: Bool {
        UserDefaults.standard.object(forKey: show48hKey) as? Bool ?? true
    }

    static var panelHeight: CGFloat {
        panelHeight(show24h: show24h, show48h: show48h)
    }

    static func panelHeight(show24h: Bool, show48h: Bool) -> CGFloat {
        let orbCount = 1 + (show24h ? 1 : 0) + (show48h ? 1 : 0)
        return CGFloat(orbCount) * orbStep
    }
}
