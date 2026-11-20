import Keybee
import XCTest

@MainActor
final class LicenseModel {
    private let keybee = Keybee(KeybeeConfiguration(appID: "app_test_Swift5", publicKeys: [], fingerprint: .v1Compatible, storage: .memory))
    var unlocked = false

    func refresh() async {
        let state = await keybee.check()
        unlocked = state.isLicensed(offlineGrace: .untilReconnect)
    }

    func activate(_ key: String) async -> String {
        do {
            let state = try await keybee.activate(key: key)
            if case .denied(.activationLimitReached, _) = state { return "deactivate another Mac" }
            return state.isLicensed() ? "ok" : "no"
        } catch {
            return "try again"
        }
    }
}

final class Swift5ConsumerTests: XCTestCase {
    @MainActor
    func test_mainActorAppCanUseTheSDK() async {
        let model = LicenseModel()
        await model.refresh()
        XCTAssertFalse(model.unlocked)
    }
}
