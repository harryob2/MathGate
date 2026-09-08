# MathGate for iOS

The iOS app. See the [root README](../README.md) for what MathGate is and how the two platforms
compare, and [`docs/math-academy-api.md`](../docs/math-academy-api.md) for the API it talks to.

## Build

Requires Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and iOS 17+.

```bash
swift test --package-path MathGateKit   # gate logic, on macOS, no simulator
xcodegen generate                       # after any project.yml change
open MathGate.xcodeproj
```

`MathGate.xcodeproj` is generated and not committed; `project.yml` is the source of truth.

## Targets

| Target | What it is |
|---|---|
| `MathGate` | The app: status, setup, account, reset time |
| `MathGateMonitor` | `DeviceActivityMonitor` extension. Woken at the daily reset to drop the pass and re-shield |
| `MathGateShield` | `ShieldConfiguration` extension. The copy and colours of the block screen iOS draws |
| `MathGateShieldAction` | `ShieldAction` extension. Re-checks Math Academy when the block screen's button is tapped |
| `MathGateKit` | A local Swift package with the gate logic, shared by all of the above |

`MathGateKit` deliberately does **not** import FamilyControls, ManagedSettings or DeviceActivity.
That keeps it building for macOS, which is what makes `swift test` a sub-second loop with no
simulator — the counterpart of the Android side's plain-JVM tests. Everything that touches Screen
Time lives in `Shared/`, which is compiled into the app and all three extensions.

## Why the design differs from Android

Android's blocker is asked "may this app open?" on every window change, so it answers from a
synchronous cache and treats every failure as "no". iOS offers no such hook. What it offers
instead is a *declarative* shield: `ManagedSettingsStore` state that the OS enforces, surviving
reboots and app termination.

So the iOS gate is inverted. `shouldShieldNow` in the shared state **is** the block:

- The monitor extension sets it at every daily reset, and applies the shield.
- Only a confirmed, in-period Math Academy task clears it.
- If a check cannot run — offline, no time, the app never opened — nothing changes, and the
  shield stays up.

Failing closed therefore needs no special handling; it is what happens when nothing happens.

## What you need to run it

- **A real device.** Screen Time authorisation is unavailable in the simulator, so the simulator
  can exercise the UI and the gate logic but never the shield.
- **The Family Controls entitlement** (`com.apple.developer.family-controls`), which Apple grants
  on request.
- **Your own identifiers if you fork.** Change `MathGateIDs` in
  `MathGateKit/Sources/MathGateKit/Identifiers.swift` and the four `.entitlements` files, and set
  `DEVELOPMENT_TEAM` in Xcode's Signing pane.

The App Group (`group.com.harryobrien.mathgate`) doubles as the Keychain access group, so no team
prefix is hardcoded anywhere.

## Testing against a fake Math Academy

```bash
python3 ../tools/fake_mathacademy.py --port 8799 --tasks 2
```

Then put `http://127.0.0.1:8799` in the app's **Developer** card and tap *Use this base URL*. The
card shows which base URL is actually in effect, which is worth reading before you conclude the
fake server is being used — it is otherwise easy to sit there sending real sign-in attempts to
mathacademy.com.

Set it in the app rather than by writing the App Group plist from the host: `cfprefsd` caches
those, so a host-side `defaults write` is silently ignored by a running app.

Debug builds only. `GateFactory.baseURL()` ignores the override entirely in release, and the
Developer card is inside `#if DEBUG`, so a shipping app cannot be redirected.

One thing to know if you are debugging cookies: `HTTPCookie` refuses to build `Secure` cookies
from an `http://` URL, which would silently drop every Math Academy cookie against a local fake.
`MathAcademyClient.parseCookies` parses against an https URL for that reason, and
`CookieParsingTests` pins the behaviour.
