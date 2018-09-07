//import Logboard
//
//let logger: Logboard = Logboard.with(HaishinKitIdentifier)
//

import Foundation
import os

public enum CMSampleBufferType: String {
    case video
    case audio
}

struct SignpostLog {
    static let subsystem = "com.filmicpro.hashinkit"
    static let encoder = OSLog(subsystem: subsystem, category: "Encoder")
    static let stream = OSLog(subsystem: subsystem, category: "Stream")
    static let preview = OSLog(subsystem: subsystem, category: "Preview")
}
