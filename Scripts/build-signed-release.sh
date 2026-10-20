#!/bin/bash
set -euo pipefail
: "${TEAM_ID:?}" "${APP_ID:?}" "${WIDGET_ID:?}" "${GROUP_ID:?}" "${SIGNING_IDENTITY:?}" "${RUNNER_TEMP:?}"
xcodebuild -project QuietTasks.xcodeproj -scheme 'Quiet Tasks' -configuration Release \
  -derivedDataPath XcodeDerivedData -destination 'generic/platform=macOS' -jobs 2 \
  -xcconfig "$RUNNER_TEMP/signing-settings.xcconfig" \
  QUIET_TASKS_TEAM="$TEAM_ID" QUIET_TASKS_APP_BUNDLE_ID="$APP_ID" \
  QUIET_TASKS_WIDGET_BUNDLE_ID="$WIDGET_ID" QUIET_TASKS_APP_GROUP="$GROUP_ID" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--keychain $RUNNER_TEMP/quiet-release.keychain-db --timestamp" build
app='XcodeDerivedData/Build/Products/Release/Quiet Tasks.app'
widget="$app/Contents/PlugIns/QuietTasksWidgetExtension.appex"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 "$widget"
codesign -d --entitlements :- "$app" > "$RUNNER_TEMP/signed-app-entitlements.plist"
codesign -d --entitlements :- "$widget" > "$RUNNER_TEMP/signed-widget-entitlements.plist"
python3 - <<'PY'
import os, pathlib, plistlib
root = pathlib.Path(os.environ['RUNNER_TEMP'])
for kind, bundle in [('app', os.environ['APP_ID']), ('widget', os.environ['WIDGET_ID'])]:
    with (root / ('signed-' + kind + '-entitlements.plist')).open('rb') as f:
        e = plistlib.load(f)
    assert e.get('com.apple.security.app-sandbox') is True, 'Sandbox missing'
    assert e.get('com.apple.security.application-groups') == [os.environ['GROUP_ID']], 'Incorrect group'
    assert e.get('com.apple.developer.team-identifier') == os.environ['TEAM_ID'], 'Incorrect team'
    assert e.get('com.apple.application-identifier', e.get('application-identifier')) == os.environ['TEAM_ID'] + '.' + bundle
    assert not e.get('get-task-allow', False), 'Debug entitlement present'
PY
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$app" dist/Quiet-Tasks-signed.zip
# Direct app execution can check its own container. A widget extension is an XPC service:
# direct execution aborts before WidgetBundle initialization and cannot verify shared reads.
# WidgetKit launch/timeline/read-after-write remains an explicit remote-desktop acceptance check.
nonce="$(uuidgen)"
"$app/Contents/MacOS/Quiet Tasks" --quiettasks-group-probe "$nonce"
printf '%s\n' 'Main-app container write passed. WidgetKit shared reads and timeline behavior remain UNVERIFIED; validate through the desktop widget before installation/distribution approval.'
