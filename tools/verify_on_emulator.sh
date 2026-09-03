#!/bin/bash
# End-to-end check of MathGate's blocking behaviour on a throwaway emulator.
# Verifies the three cases that matter, without touching your real phone:
#   1. gate not satisfied            -> blocked app is covered by the block screen
#   2. task done in this period      -> blocked app opens, and NO network call is made
#   3. done, but from a past period  -> blocked again (daily reset works)
#
# Usage: tools/verify_on_emulator.sh            (creates/boots the AVD if needed)
# The gate is exercised with a deliberately undecryptable stored password, so the
# app takes its fail-closed path without needing real Math Academy credentials.
set -u

AVD=MathGateTest
SERIAL=emulator-5554
BLOCKED_PKG=com.google.android.deskclock
BLOCKED_ACT=com.android.deskclock.DeskClock
IMAGE="system-images;android-36;google_apis_playstore;arm64-v8a"
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
: "${JAVA_HOME:=/opt/homebrew/opt/openjdk@17}"
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME" JAVA_HOME
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

adbd() { adb -s "$SERIAL" "$@"; }
fail=0
check() { # $1 = label, $2 = expected substring in topResumedActivity, $3 = actual
  if [[ "$3" == *"$2"* ]]; then echo "  PASS: $1"; else echo "  FAIL: $1 (expected '$2', got: $3)"; fail=1; fi
}

echo "== building debug APK =="
(cd "$REPO" && ./gradlew -q assembleDebug) || { echo "build failed"; exit 1; }

if ! adb devices | grep -q "^$SERIAL"; then
  "$ANDROID_HOME"/emulator/emulator -list-avds | grep -qx "$AVD" || \
    echo no | "$ANDROID_HOME"/cmdline-tools/latest/bin/avdmanager create avd -n "$AVD" -k "$IMAGE" -d pixel_7 --force
  echo "== booting $AVD =="
  nohup "$ANDROID_HOME"/emulator/emulator -avd "$AVD" -no-snapshot-save -no-boot-anim \
    -gpu swiftshader_indirect -no-audio > "$WORK/emulator.log" 2>&1 &
  adbd wait-for-device
  until [[ "$(adbd shell getprop sys.boot_completed | tr -d '\r')" == "1" ]]; do sleep 2; done
fi

echo "== installing =="
adbd install -r "$REPO/app/build/outputs/apk/debug/app-debug.apk" | tail -1
adbd shell am start -n com.mathgate/.MainActivity >/dev/null 2>&1; sleep 3

TZ_DEV=$(adbd shell getprop persist.sys.timezone | tr -d '\r')
NOW_S=$(adbd shell date +%s | tr -d '\r')
read -r PERIOD_START NEXT_RESET <<< "$(python3 - "$TZ_DEV" "$NOW_S" <<'PY'
import sys, datetime
from zoneinfo import ZoneInfo
tz = ZoneInfo(sys.argv[1]); now = datetime.datetime.fromtimestamp(int(sys.argv[2]), tz)
today = now.replace(hour=4, minute=0, second=0, microsecond=0)
start = today - datetime.timedelta(days=1) if now < today else today
print(int(start.timestamp()*1000), int((start+datetime.timedelta(days=1)).timestamp()*1000))
PY
)"
echo "device tz=$TZ_DEV  period start=$PERIOD_START  next reset=$NEXT_RESET"

write_prefs() {
  cat > "$WORK/prefs.xml" <<EOF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="enabled" value="true" />
    <set name="blocked_packages">
        <string>$BLOCKED_PKG</string>
    </set>
    <string name="ma_username">emulator-test@example.com</string>
    <string name="ma_password_blob">deliberately-undecryptable</string>
    <int name="reset_hour" value="4" />
    <int name="reset_minute" value="0" />
$1
</map>
EOF
  adbd shell am force-stop com.mathgate
  base64 < "$WORK/prefs.xml" | tr -d '\n' | \
    adbd shell "run-as com.mathgate sh -c 'base64 -d > /data/data/com.mathgate/shared_prefs/mathgate_prefs.xml'"
  # Rebind the service so it picks up the new prefs in a fresh process.
  adbd shell settings delete secure enabled_accessibility_services >/dev/null; sleep 1
  adbd shell settings put secure enabled_accessibility_services com.mathgate/com.mathgate.MathGateAccessibilityService
  adbd shell settings put secure accessibility_enabled 1; sleep 3
  adbd logcat -c
}

open_blocked_app() {
  adbd shell input keyevent KEYCODE_HOME; sleep 2
  adbd shell am force-stop "$BLOCKED_PKG"; sleep 1
  adbd shell am start -n "$BLOCKED_PKG/$BLOCKED_ACT" >/dev/null 2>&1; sleep 3
  adbd shell dumpsys activity activities 2>/dev/null | grep -m1 "topResumedActivity"
}

echo; echo "== case 1: nothing done today -> must block =="
write_prefs ""
check "blocked app is covered by the block screen" "com.mathgate/.BlockingActivity" "$(open_blocked_app)"

echo; echo "== case 2: task done this period -> must open, with no network =="
write_prefs "    <long name=\"done_until_millis\" value=\"$NEXT_RESET\" />
    <long name=\"done_period_start_millis\" value=\"$PERIOD_START\" />
    <int name=\"done_tasks\" value=\"3\" />
    <int name=\"done_xp\" value=\"21\" />"
check "blocked app opens normally" "$BLOCKED_PKG" "$(open_blocked_app)"
if adbd logcat -d -s MathGate | grep -q "previous-tasks"; then
  echo "  FAIL: made a network call despite the cached pass"; fail=1
else
  echo "  PASS: no network call while cached"
fi

echo; echo "== case 3: done, but in a previous period -> must block again =="
write_prefs "    <long name=\"done_until_millis\" value=\"$((NEXT_RESET - 86400000))\" />
    <long name=\"done_period_start_millis\" value=\"$((PERIOD_START - 86400000))\" />
    <int name=\"done_tasks\" value=\"3\" />
    <int name=\"done_xp\" value=\"21\" />"
check "daily reset re-locks the app" "com.mathgate/.BlockingActivity" "$(open_blocked_app)"

echo
[[ $fail -eq 0 ]] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $fail
