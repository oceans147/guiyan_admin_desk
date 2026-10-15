import CoreGraphics
import Foundation
let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in info {
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? -1
    if pid == 90737, (w[kCGWindowName as String] as? String) != nil {
        print(w[kCGWindowNumber as String] as? Int ?? -1)
    }
}
