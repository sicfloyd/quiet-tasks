#!/bin/bash
# Personal-test experiment only: retain sandbox/runtime protections and never use a signing identity.
set -euo pipefail
app_source="${1:?Pass the unsigned app path}"
mkdir -p dist/adhoc-diagnostics dist/adhoc-staging
diagnostics="$PWD/dist/adhoc-diagnostics"
app="$PWD/dist/adhoc-staging/Quiet Tasks.app"
test ! -e "$app"
ditto "$app_source" "$app"
widget="$app/Contents/PlugIns/QuietTasksWidgetExtension.appex"
export ADHOC_APP="$app" ADHOC_WIDGET="$widget" ADHOC_DIAGNOSTICS="$diagnostics"
python3 - <<'PY'
import os, pathlib, plistlib
root = pathlib.Path(os.environ['ADHOC_DIAGNOSTICS'])
infos = []
for kind, variable, source in [('app', 'ADHOC_APP', 'App.entitlements'), ('widget', 'ADHOC_WIDGET', 'Widget.entitlements')]:
    bundle = pathlib.Path(os.environ[variable])
    with (bundle / 'Contents/Info.plist').open('rb') as f:
        info = plistlib.load(f)
    infos.append(info)
    group = info['QuietTasksAppGroup']
    assert group and '$(' not in group
    with open(source, 'rb') as f:
        entitlements = plistlib.load(f)
    assert entitlements['com.apple.security.app-sandbox'] is True
    assert entitlements['com.apple.security.application-groups'] == ['$(QUIET_TASKS_APP_GROUP)']
    entitlements['com.apple.security.application-groups'] = [group]
    with (root / (kind + '-requested-entitlements.plist')).open('wb') as f:
        plistlib.dump(entitlements, f)
assert infos[0]['QuietTasksAppGroup'] == infos[1]['QuietTasksAppGroup']
assert infos[1]['CFBundleIdentifier'].startswith(infos[0]['CFBundleIdentifier'] + '.')
PY
# Sign nested code first. Do not use --deep to conceal a missing nested signature.
codesign --force --sign - --options runtime --entitlements "$diagnostics/widget-requested-entitlements.plist" "$widget"
codesign --force --sign - --options runtime --entitlements "$diagnostics/app-requested-entitlements.plist" "$app"
codesign --verify --strict --verbose=2 "$widget" 2> "$diagnostics/widget-verification.txt"
codesign --verify --deep --strict --verbose=2 "$app" 2> "$diagnostics/app-verification.txt"
for kind in app widget; do
  bundle="$app"
  if test "$kind" = widget; then bundle="$widget"; fi
  codesign -d --entitlements :- "$bundle" > "$diagnostics/$kind-actual-entitlements.plist" 2> "$diagnostics/$kind-entitlement-inspection.txt"
  codesign -dv --verbose=4 "$bundle" 2> "$diagnostics/$kind-signature.txt"
done
python3 - <<'PY'
import os, pathlib, plistlib
root = pathlib.Path(os.environ['ADHOC_DIAGNOSTICS'])
for kind in ['app', 'widget']:
    with (root / (kind + '-requested-entitlements.plist')).open('rb') as f:
        requested = plistlib.load(f)
    with (root / (kind + '-actual-entitlements.plist')).open('rb') as f:
        actual = plistlib.load(f)
    for key, value in requested.items():
        assert actual.get(key) == value, f'{kind}: entitlement missing or changed: {key}'
    for key in ['com.apple.security.get-task-allow', 'get-task-allow',
                'com.apple.security.cs.disable-library-validation', 'com.apple.security.cs.allow-unsigned-executable-memory']:
        assert not actual.get(key, False), f'{kind}: unexpected weakened entitlement'
    signature = (root / (kind + '-signature.txt')).read_text()
    assert 'Signature=adhoc' in signature, f'{kind}: not ad-hoc'
    assert 'runtime' in signature, f'{kind}: hardened runtime missing'
print('Ad-hoc signatures and requested sandbox/App Group entitlements verified for both bundles.')
PY
# Runtime authorization is a different result from static signature verification.
python3 - <<'PY'
import json, os, pathlib, platform, plistlib, signal, subprocess, uuid
root = pathlib.Path(os.environ['ADHOC_DIAGNOSTICS'])
app = pathlib.Path(os.environ['ADHOC_APP'])
widget = pathlib.Path(os.environ['ADHOC_WIDGET'])
nonce = str(uuid.uuid4())
def run(command):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = process.communicate(timeout=25)
        return {'exit_code': process.returncode, 'stdout': out[-8192:], 'stderr': err[-8192:], 'timed_out': False}
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        return {'exit_code': None, 'stdout': '', 'stderr': 'Timed out after 25 seconds; process group terminated.', 'timed_out': True}
write = run([str(app / 'Contents/MacOS/Quiet Tasks'), '--quiettasks-group-probe', nonce])
read = run([str(widget / 'Contents/MacOS/QuietTasksWidgetExtension'), '--quiettasks-group-probe', nonce])
with (widget / 'Contents/Info.plist').open('rb') as f:
    widget_id = plistlib.load(f)['CFBundleIdentifier']
registration = run(['/usr/bin/pluginkit', '-a', str(widget)])
listing = run(['/usr/bin/pluginkit', '-m', '-v', '-i', widget_id])
unregistration = run(['/usr/bin/pluginkit', '-r', str(widget)])
sharing = 'passed-on-CI-host' if write['exit_code'] == read['exit_code'] == 0 else 'failed-or-unavailable'
if 'An XPC Service cannot be run directly' in read['stderr']:
    sharing = 'NOT VERIFIED: direct XPC extension launch unsupported'
assessment = run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', str(app)])
result = {
    'macos_version': platform.mac_ver()[0], 'architecture': platform.machine(),
    'workflow_commit': os.environ.get('GITHUB_SHA'),
    'static_signature_and_entitlement_verification': 'passed',
    'app_group_writer': write, 'extension_group_reader': read,
    'group_read_after_write': sharing,
    'plugin_registration_attempt': registration, 'plugin_registry_listing': listing,
    'plugin_registration_cleanup': unregistration,
    'gatekeeper_assessment': assessment,
    'widgetkit_desktop_registration_and_timeline': 'NOT TESTED',
    'finder_launch_and_runtime_sandbox_enforcement': 'NOT TESTED',
    'personal_mac_installation': 'NOT TESTED',
    'apple_signing_team': 'UNSET', 'apple_notarization': 'NOT PERFORMED',
}
(root / 'runtime-results.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
summary = ('## Ad-hoc personal-test experiment\n\n'
           'Static app/extension signatures and sandbox/App Group declarations: **passed**.\n\n'
           f'CI App Group nonce read-after-write: **{result["group_read_after_write"]}** '
           f'(writer exit {write["exit_code"]}, extension exit {read["exit_code"]}).\n\n'
           f'Gatekeeper assessment exit: **{assessment["exit_code"]}** (see diagnostics).\n\n'
           f'PluginKit registration exit: **{registration["exit_code"]}**; registry query exit: **{listing["exit_code"]}**. These are registry checks, not widget execution.\n\n'
           '**WidgetKit desktop registration, personal Mac installation, Apple signing and notarization: not verified.** '
           'An embedded entitlement is not Apple authorization. Runtime probe failures are recorded, not treated as passes.\n')
(root / 'RESULTS.md').write_text(summary)
if os.environ.get('GITHUB_STEP_SUMMARY'):
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f: f.write(summary)
PY
ditto -c -k --sequesterRsrc --keepParent "$app" dist/Quiet-Tasks-ADHOC-PERSONAL-TEST.zip
shasum -a 256 dist/Quiet-Tasks-ADHOC-PERSONAL-TEST.zip > "$diagnostics/ZIP-SHA256.txt"
