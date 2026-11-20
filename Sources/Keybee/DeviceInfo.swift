import Foundation
import SystemConfiguration

/// Details sent with each request so the seller can tell a buyer's Macs apart.
struct DeviceInfo: Sendable, Equatable {
    let name: String
    let appVersion: String?

    static func current() -> DeviceInfo {
        let name = SCDynamicStoreCopyComputerName(nil, nil) as String?
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return DeviceInfo(name: clip(name?.isEmpty == false ? name! : "Mac", 255), appVersion: version.map { clip($0, 64) })
    }

    private static func clip(_ s: String, _ max: Int) -> String {
        s.count > max ? String(s.prefix(max)) : s
    }
}
