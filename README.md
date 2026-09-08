<p align="center">
  <img src="screenshots/mathgate_logo.png" width="120" alt="MathGate logo" />
</p>
<h1 align="center">MathGate</h1>
<p align="center"><em>MATHEMATICA REGINA SCIENTIARUM</em></p>

<p align="center">
  Block distracting apps until you have done a Math Academy task today. Pick which apps to lock — the moment you complete any lesson, review, multistep or quiz, everything unlocks until tomorrow.
</p>

<p align="center">
  <a href="https://mathgate.co"><strong>mathgate.co</strong></a>
  ·
  <a href="#android">Android</a>
  ·
  <a href="#ios">iOS</a>
  ·
  <a href="docs/math-academy-api.md">API notes</a>
</p>

## What it does

- **Any task counts** — a lesson, review, multistep or quiz all satisfy the gate
- **You choose the apps** — lock whatever you actually lose time to
- **Configurable daily reset** — defaults to 04:00, so a late night still counts as the same day
- **Fails closed** — no connection, a bad sign-in or an unexpected response all keep your apps locked
- **Quiet after the first pass** — once a task is found, no further network calls until the next reset
- **No server, no account** — MathGate talks to Math Academy directly from your phone, nothing else
- **Credentials stay on the device** — Android Keystore on one side, the Keychain on the other

## Layout

```
android/    Kotlin app. AccessibilityService blocker, plain Activities, no Compose.
ios/        Swift app. Screen Time (FamilyControls) shielding, SwiftUI, three extensions.
  MathGateKit/   The gate logic both iOS targets share. Pure Foundation, tests on macOS.
docs/       Notes that belong to neither platform — chiefly the Math Academy API contract.
tools/      Cross-platform dev scripts: API probe, fake server, icon generation.
screenshots/
```

The two apps share no code. They deliberately share a **contract** — the same gate rule, the same
period arithmetic, the same reading of Math Academy's API — written down once in
[`docs/math-academy-api.md`](docs/math-academy-api.md). Changing how the gate decides means
changing it in both places.

## How it works

The rule is the same on both platforms: **if no task has been completed since the daily reset,
the chosen apps stay shut.** How that is enforced is not, because the two operating systems offer
very different tools.

| | Android | iOS |
|---|---|---|
| Blocking mechanism | `AccessibilityService` watches window changes and covers a blocked app in ~100 ms | Screen Time `ManagedSettingsStore` shields the apps at OS level |
| Who draws the block screen | The app (`BlockingActivity`) | The OS, styled by a `ShieldConfiguration` extension |
| Default state | Nothing; the service decides per app launch | Shielded; the shield is OS state that persists |
| Closing the gate each day | Cached pass expires at the reset | `DeviceActivityMonitor` extension wakes at the reset and re-shields |
| Re-checking after finishing a task | "Retry" on the block screen | "Check Math Academy" on the shield, handled by a `ShieldAction` extension |
| Background checks | The service is always live | Opportunistic `BGAppRefreshTask` only — a bonus, never the guarantee |

The iOS design is inverted on purpose. Android asks "may this app open?" on every window change,
so a failure to answer has to be treated as "no". iOS has no equivalent hook, but its shield is
declarative state that survives reboots and app termination, so the gate is closed by default and
only a confirmed Math Academy pass opens it. Both fail closed; iOS gets there by construction.

## Android

Requires JDK 17+ and the Android SDK (build-tools 36). Minimum Android 8.0 (API 26).

```bash
cd android
./gradlew testDebugUnitTest assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Unit tests run on the JVM with no device or emulator: period arithmetic across a British Summer
Time change, task parsing, cookie handling, re-login on an expired session, backoff after a wrong
password, and the cache and single-flight behaviour of the coordinator.
`MathAcademyClientTest` drives the real HTTP client against a loopback fake of mathacademy.com.

End-to-end behaviour is checked on a throwaway emulator, without a Math Academy account:

```bash
android/tools/verify_on_emulator.sh
```

That asserts the three cases that matter: a blocked app is covered when nothing is done, it opens
with no network call once the day's pass is cached, and it is blocked again when that pass
belongs to a previous period.

### Setup on the phone

1. Install and open MathGate
2. **Accessibility service** — enable MathGate. If Android says "Restricted setting", open App
   info → ⋮ → *Allow restricted settings*
3. **Battery** — set to unrestricted, so the system does not stop the service
4. **Select blocked apps**
5. **Math Academy account** — enter your username and password, then *Sign in & test*
6. Turn on **Blocking enabled**

## iOS

Requires Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and iOS 17+.

```bash
cd ios
swift test --package-path MathGateKit   # the gate logic, on macOS, no simulator
xcodegen generate                       # after any project.yml change
open MathGate.xcodeproj
```

**A real device and the Family Controls entitlement are required to actually block anything.**
Screen Time authorisation is unavailable in the simulator, so the simulator can exercise the UI
and the gate logic but never the shield itself. Apple grants
`com.apple.developer.family-controls` on request; a fork will need its own team, bundle IDs and
App Group.

### Setup on the phone

1. Install and open MathGate
2. **Screen Time access** — tap Allow and approve the system prompt
3. **Blocked apps** — choose them in the system picker. MathGate never learns which apps you
   picked: iOS hands it opaque tokens, by design
4. **Math Academy account** — enter your username and password, then *Sign in & test*
5. Turn on **Blocking enabled**

## Privacy

MathGate has no backend and no analytics. Your Math Academy username, password and session
cookies are stored in the app's private storage — encrypted with an Android Keystore key on
Android, in the Keychain on iOS. The only network destination is `www.mathacademy.com`. Nothing
is sent anywhere else, and uninstalling deletes everything it stored.

On iOS, the apps you choose are represented by opaque tokens issued by the system. MathGate
cannot read which apps they are, and neither can anyone reading its stored data.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: keep the two platforms' gate
behaviour identical, never log or commit credentials, and add a test for anything that decides
whether the gate opens.

## Not affiliated with Math Academy

MathGate is an independent project. It signs in as you and reads your own completed tasks, the
same way your browser does. It is not endorsed by or connected to Math Academy in any way.

## License

[GNU General Public License v3.0](LICENSE). If you distribute a modified version, it has to be
free software too.
