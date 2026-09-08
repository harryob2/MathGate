# MathGate for Android

The Android app. See the [root README](../README.md) for what MathGate is and how the two
platforms compare, and [`docs/math-academy-api.md`](../docs/math-academy-api.md) for the API it
talks to.

## Build

Requires JDK 17+ and the Android SDK (build-tools 36). Create `local.properties` with
`sdk.dir=/path/to/Android/sdk` if it is missing.

```bash
./gradlew testDebugUnitTest assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Architecture

| File | Purpose |
|------|---------|
| `MathGateAccessibilityService.kt` | Detects a blocked app coming to the foreground and launches the blocker |
| `GateStatusCoordinator.kt` | Synchronous cache plus single-flight background refresh; persists the daily pass |
| `MathAcademyClient.kt` | Form login, session cookies, `/api/previous-tasks`, automatic re-login on expiry |
| `MathAcademyGateApi.kt` | Maps client results and failures onto a `GateStatus`, all of which fail closed |
| `TaskSummariser.kt` | Counts tasks completed since the period start and sums awarded XP |
| `MaDateFormat.kt` | Builds the JavaScript-style date cursor the API expects |
| `SetCookieParser.kt` | Reads cookie values and expiry out of `Set-Cookie` headers |
| `ResetTime.kt` | Period arithmetic for the configurable daily reset |
| `SecretStore.kt` | AES-GCM encryption of the password with an Android Keystore key |
| `Prefs.kt` | SharedPreferences storage for settings, cookies and the cached pass |
| `MainActivity.kt` | Status, setup, account and reset-time screen |
| `AppSelectionActivity.kt` | App picker with icons, social media pinned to the top |
| `BlockingActivity.kt` | Full-screen blocker with the reason and a re-check button |

Two constraints shape most of this:

- `onAccessibilityEvent` runs on the main thread, so `GateStatusCoordinator.status()` is
  synchronous, O(1) and never touches the network. Every fetch goes through its IO executor.
- Only `GateStatus.Done` returns `allowsAccess == true`. Adding a status means adding a blocked
  one unless you mean otherwise.

## Permissions

| Permission | Why |
|------------|-----|
| `BIND_ACCESSIBILITY_SERVICE` | Detect which app has come to the foreground so it can be blocked |
| `INTERNET` | Sign in to mathacademy.com and read your completed tasks |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Ask to be exempted so the OS does not stop the service |

No usage-access, overlay, notification or boot permission is requested.

## Testing on a device against a fake Math Academy

Debug builds only, so release behaviour is untouched.

```bash
python3 ../tools/fake_mathacademy.py --port 8799 --tasks 0
adb reverse tcp:8799 tcp:8799
# set "debug_base_url" to http://127.0.0.1:8799 in the app's SharedPreferences, then sign in
# with any username and password: the fake accepts anything.
```

On Android 16, `Log.i`/`Log.d` are hidden in logcat. The app logs through `MgLog` (at error
level); filter with `adb logcat -s MathGate`.
