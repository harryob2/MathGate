# Contributing to MathGate

MathGate is a self-control tool, so the bar is a little different from most small apps: a bug
that opens the gate when it should not is worse than a crash. The rules below all follow from
that.

## The three rules that matter

**1. Fail closed.** Every state except a confirmed, in-period Math Academy task keeps apps
locked — offline, wrong password, an API change, an exception you did not expect. If you add a
new outcome, it blocks unless you can point at the task that justifies opening.

**2. Never log, print or commit credentials.** Not the password, not the `session` cookie, not
`session.sig`. Log status codes, redirect targets and cookie *names*. This applies to test
fixtures too: use obviously fake values like `EXAMPLE-SESSION-NOT-A-REAL-ONE`, never something
copied from a real session.

**3. Keep the two platforms' behaviour identical.** Android and iOS share no code, but they must
agree on what "done" means, when the day rolls over, and how Math Academy's API is read. The
contract lives in [`docs/math-academy-api.md`](docs/math-academy-api.md). Change it there first,
then in both apps.

## Tests

Anything that decides whether the gate opens needs a test, and that test must not need a phone.

```bash
cd android && ./gradlew testDebugUnitTest      # JVM, no emulator
cd ios && swift test --package-path MathGateKit # macOS, no simulator
```

Both suites drive the real HTTP client against a loopback fake of mathacademy.com rather than
stubbing the network layer, because the failures that have actually bitten this project were in
the network layer: a sentinel value that overflowed, and `Secure` cookies being silently dropped.

Device-level behaviour that genuinely cannot be tested on a workstation:

```bash
android/tools/verify_on_emulator.sh   # block / unlock / daily reset on a throwaway AVD
```

iOS shielding has no equivalent: Screen Time authorisation is unavailable in the simulator, so
the shield can only be verified by hand on a real device with the Family Controls entitlement.
Say so in the pull request when that is what you did.

## Working without a Math Academy account

You do not need one, and you should not use a real one for routine work:

```bash
python3 tools/fake_mathacademy.py --port 8799 --tasks 0   # or --tasks 3 to satisfy the gate
```

Both apps honour a debug-only base URL override pointing at it — a SharedPreferences key on
Android, the **Developer** card on iOS. Release builds ignore it entirely, so there is no way to
redirect a shipping app.

Check the override actually took effect before assuming your requests are local. Failed
sign-in attempts against the real mathacademy.com are the thing this fake server exists to
avoid.

## Style

Match the file you are editing. Both codebases favour plain platform APIs and few dependencies:
Activities and XML on Android, not Compose; SwiftUI and Foundation on iOS, with the shared logic
in `MathGateKit` deliberately free of `FamilyControls` so it keeps building — and testing — on
macOS.

Comments explain *why*, especially where the code looks odd on purpose. Several things here are
odd on purpose: the fixed `GMT-0800` label in the date cursor, the omitted `minumum` parameter,
parsing cookies against an https URL. Those comments are load-bearing; do not tidy them away.

## Forking the iOS app

You will need your own Apple developer team, your own bundle identifiers, and your own App Group.
Change `MathGateIDs` in `ios/MathGateKit/Sources/MathGateKit/Identifiers.swift` and the four
`.entitlements` files. The Family Controls entitlement has to be requested from Apple.

## License

Contributions are accepted under the [GPL-3.0](LICENSE), the licence the project ships under.
