import Keybee
import XCTest

/// The README's samples, verbatim, so they keep compiling.
final class ReadmeSnippetTests: XCTestCase {
    func test_readmeSamplesCompile() async throws {
        let keybee = Keybee(KeybeeConfiguration(
            appID: "app_live_3kD9fQ2mX7pL4vB8nR6tY1wZ",
            publicKeys: [KeybeePublicKey(kid: "sig_0102030405060708090a0b0c0d0e0f10", x: "ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ")],
            storage: .memory
        ))
        let enteredKey = "KB-TEST-PASS-2222-2222"
        guard ProcessInfo.processInfo.environment["KEYBEE_README_NETWORK"] == "1" else {
            // Compile-only by default: the samples below would reach the network.
            _ = await keybee.currentState()
            return
        }

        // At launch: show the stored answer at once, without the network...
        let stored = await keybee.currentState()
        // ...then confirm it. Call check() at launch and now and then while the app runs. Never throws.
        let state = await keybee.check()
        let unlocked = state.isLicensed()

        // When the buyer enters a key.
        do {
            switch try await keybee.activate(key: enteredKey) {
            case .licensed:
                print("Thank you!")
            case .denied(.activationLimitReached, let license):
                print("This key is in use on \(license?.activationsUsed ?? 0) Macs. Deactivate one, then try again.")
            case .denied(.notFound, _):
                print("That key was not found. Check it and try again.")
            case .denied(let reason, _):
                print("This key cannot be used: \(reason).")
            default:
                break
            }
        } catch KeybeeError.invalidGrant(.expired) {
            print("Check this Mac's date and time, then try again.")
        } catch {
            print("Could not reach keybee. Check your connection and try again.")
        }

        // To move the licence to another Mac. Returns .unlicensed once the seat is free.
        if case .unlicensed = try await keybee.deactivate() {
            print("This Mac no longer uses the licence.")
        }

        let unlockedOffline = state.isLicensed(offlineGrace: .untilReconnect)
        _ = (stored, unlocked, unlockedOffline)
    }

    /// The keybee-web Quickstart's samples, verbatim.
    func test_quickstartSamplesCompile() async throws {
        let keybee = Keybee(KeybeeConfiguration(
            appID: "app_test_3kD9fQ2mX7pL4vB8nR6tY1wZ",
            publicKeys: [KeybeePublicKey(kid: "sig_0102030405060708090a0b0c0d0e0f10", x: "ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ")],
            storage: .memory
        ))
        let enteredKey = "KB-TEST-PASS-2222-2222"
        guard ProcessInfo.processInfo.environment["KEYBEE_README_NETWORK"] == "1" else { return }

        do {
            let state = try await keybee.activate(key: enteredKey)
            if state.isLicensed() {
                // Unlock the app.
            }
        } catch {
            // keybee could not be reached. Nothing stored changed; try again later.
        }

        let state = await keybee.check()
        _ = state
    }
}
