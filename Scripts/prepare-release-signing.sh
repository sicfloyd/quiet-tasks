#!/bin/bash
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?}" "${CERTIFICATE_BASE64:?}" "${CERTIFICATE_PASSWORD:?}"
: "${APP_PROFILE_BASE64:?}" "${WIDGET_PROFILE_BASE64:?}" "${TEAM_ID:?}" "${APP_ID:?}" "${WIDGET_ID:?}" "${GROUP_ID:?}"
printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$RUNNER_TEMP/quiet-certificate.p12"
printf '%s' "$APP_PROFILE_BASE64" | base64 --decode > "$RUNNER_TEMP/app-profile.provisionprofile"
printf '%s' "$WIDGET_PROFILE_BASE64" | base64 --decode > "$RUNNER_TEMP/widget-profile.provisionprofile"
security cms -D -i "$RUNNER_TEMP/app-profile.provisionprofile" > "$RUNNER_TEMP/app-profile.plist"
security cms -D -i "$RUNNER_TEMP/widget-profile.provisionprofile" > "$RUNNER_TEMP/widget-profile.plist"
python3 - <<'PY'
import datetime, os, pathlib, plistlib
root = pathlib.Path(os.environ['RUNNER_TEMP'])
profiles = []
for kind, bundle in [('app', os.environ['APP_ID']), ('widget', os.environ['WIDGET_ID'])]:
    with (root / (kind + '-profile.plist')).open('rb') as f:
        p = plistlib.load(f)
    e = p['Entitlements']
    assert p['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Expired profile'
    assert p['TeamIdentifier'] == [os.environ['TEAM_ID']], 'Wrong profile team'
    assert e.get('com.apple.developer.team-identifier') == os.environ['TEAM_ID']
    assert e.get('com.apple.application-identifier', e.get('application-identifier')) == os.environ['TEAM_ID'] + '.' + bundle
    assert os.environ['GROUP_ID'] in e.get('com.apple.security.application-groups', []), 'App Group missing from profile'
    assert not e.get('get-task-allow', False), 'Development profile is not a release profile'
    assert p.get('ProvisionsAllDevices') is True, 'Use a Developer ID distribution profile'
    profiles.append(p['UUID'])
# Xcode target settings consume separate profiles. No secret values in this config.
(root / 'signing-settings.xcconfig').write_text(
    'QUIET_TASKS_APP_PROFILE = ' + profiles[0] + '\nQUIET_TASKS_WIDGET_PROFILE = ' + profiles[1] + '\n')
PY
keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$RUNNER_TEMP/quiet-release.keychain-db"
security set-keychain-settings -lut 21600 "$RUNNER_TEMP/quiet-release.keychain-db"
security unlock-keychain -p "$keychain_password" "$RUNNER_TEMP/quiet-release.keychain-db"
security import "$RUNNER_TEMP/quiet-certificate.p12" -k "$RUNNER_TEMP/quiet-release.keychain-db" \
  -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$RUNNER_TEMP/quiet-release.keychain-db" >/dev/null
# Dedicated GitHub-hosted runner, not a developer's machine.
security list-keychains -d user -s "$RUNNER_TEMP/quiet-release.keychain-db"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
python3 - <<'PY'
import os, pathlib, plistlib, shutil
root = pathlib.Path(os.environ['RUNNER_TEMP'])
for kind in ['app', 'widget']:
    with (root / (kind + '-profile.plist')).open('rb') as f:
        profile = plistlib.load(f)
    for directory in ['Library/MobileDevice/Provisioning Profiles', 'Library/Developer/Xcode/UserData/Provisioning Profiles']:
        destination = pathlib.Path.home() / directory
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / (kind + '-profile.provisionprofile'), destination / (profile['UUID'] + '.provisionprofile'))
PY
