# keybee Swift SDK

Licensing for Mac apps sold with [keybee](https://keybee.app): activate a licence key, check it at launch, keep working offline, and free a seat. No dependencies; macOS 13 and later; Swift 6.

## Install

In Xcode, choose File > Add Package Dependencies and enter `https://github.com/Serious-Business-Software/keybee-swift`, or in `Package.swift`:

```swift
.package(url: "https://github.com/Serious-Business-Software/keybee-swift", from: "0.1.0")
```

## Configure

Embed your app id and every public key your account publishes for it (`GET https://api.keybee.app/v2/apps/{app_id}/jwks`). Embedding the keys, instead of fetching them, means nobody can swap them on the buyer's network.

```swift
import Keybee

let keybee = Keybee(KeybeeConfiguration(
    appID: "app_live_3kD9fQ2mX7pL4vB8nR6tY1wZ",
    publicKeys: [KeybeePublicKey(kid: "sig_0102030405060708090a0b0c0d0e0f10", x: "ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ")]
))
```

Create one `Keybee` for the app and keep it. Use an `app_test_...` id while you build: `KB-TEST-PASS-2222-2222` always activates and nothing is charged. Never ship a test app id.

## Use

```swift
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
```

To switch this Mac to a different key, call `deactivate()` first. Activating another key replaces the stored licence, but the old key's seat stays claimed until it is freed.

An error never changes what is stored: a buyer who is licensed stays licensed when keybee cannot be reached, and a mistyped key never replaces a working licence.

## States

| State | Meaning | Unlock? |
|---|---|---|
| `licensed` | keybee said yes, and the answer has not expired | Yes |
| `denied(reason, license)` | keybee said no: revoked, refunded, expired, not found, seat limit | No; tell the buyer why |
| `needsValidation(license)` | the stored answer expired and keybee cannot be reached | Your choice (below) |
| `unlicensed` | no key on this Mac | No |
| `storageUnavailable` | the Keychain cannot be read right now | Do not treat as unlicensed; try again shortly |
| `adoptionPending` | only when moving from keybee's earlier API | Use your previous answer |

## Offline

A Mac works offline for 30 days after its last successful check, and the SDK asks keybee again after 7 days whenever it can. After 30 days offline, `isLicensed()` is false until the Mac reconnects. To keep paid features on and show a "connect to the internet to confirm your licence" note instead:

```swift
let unlockedOffline = state.isLicensed(offlineGrace: .untilReconnect)
```

A clock set back is noticed and answered with a check, never a lockout.

## Key rotation

When your account adds a signing key, ship an update that embeds it next to the current one before you activate it. Builds that never update keep working until their stored answer expires. See [Grants](https://keybee.app/docs/grants/).

## Storage

One Keychain item, service `<bundle id>.keybee`, not synced. Apps with the keychain-access-groups entitlement can use the data protection Keychain: `storage: .keychain(dataProtection: true)`. Previews and tests can use `storage: .memory`.

## License

MIT. See `LICENSE`.
