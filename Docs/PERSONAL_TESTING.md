# Personal installation experiment without paid credentials

This path builds entirely on GitHub-hosted macOS. You do not need local Xcode to
download, inspect, or attempt the resulting `.app`. It does **not** use your free
Personal Team or an Apple-issued certificate, and it is not notarized. Team ID stays
empty. Defaults remain configurable:

- App: `com.personal.quiettasks`
- Widget: `com.personal.quiettasks.widget`
- App Group: `group.com.personal.quiettasks`

Security fixes remain in place: app-only Keychain refresh tokens, sandbox and
hardened runtime, one App Group for shared data, no writable fallback directory,
no token JSON writes, and no upstream OAuth client ID. No Google account or Apple
credentials are used by the build or nonce probes.

## Download the artifacts

In this fork, open **Actions → macOS test build**, select the run for the reviewed
commit, and inspect its results. There are three artifacts:

1. **Quiet-Tasks-UNSIGNED-TEST-ONLY**: build-only reference, not an installation release.
2. **Quiet-Tasks-ADHOC-PERSONAL-TEST**: ZIP containing `Quiet Tasks.app`, including
   its embedded `QuietTasksWidgetExtension.appex`. The extension is signed first,
   then the app, with `codesign --sign -`, sandbox and hardened runtime retained.
3. **Quiet-Tasks-ADHOC-DIAGNOSTICS**: actual entitlement plists, signature checks,
   ZIP checksum, `RESULTS.md`, and `runtime-results.json`. If signing fails,
   diagnostics are uploaded where available and the signing step fails; an
   ad-hoc app artifact is not claimed to exist.

Read the diagnostics before installation. A successful workflow means compilation,
tests, static signature/entitlement verification, and packaging succeeded. The
runtime results are separate: an unsupported App Group probe or Gatekeeper rejection
is explicitly recorded even when the experimental artifact can be produced.

## What CI verifies, and what it cannot establish

The workflow runs the existing security/sync tests with synthetic credentials,
builds the app and widget, and checks both executable paths. It then makes a
separate copy for ad-hoc signing, verifies both signatures strictly, inspects the
actual signed entitlements, and checks that sandbox, hardened runtime, and the
same configured App Group remain present. It does not add debugging, unsigned-memory,
or disabled-library-validation exceptions.

Two actual executable identities perform a bounded synthetic nonce write/read in
the configured container. No tasks or tokens are accessed. A successful probe
establishes read-after-write on that CI host only. A failure, timeout, or process
termination is recorded with its exit status. `spctl` assessment is also recorded;
it does not change Gatekeeper policy. No GUI app is launched for normal use by CI.

**An entitlement embedded in an ad-hoc signature is a declaration, not an Apple
capability grant.** No provisioning profile or Apple team authorization is created.
The nonce probe does not verify desktop widget registration, timeline refresh, or
Keychain access by the eventual signed app. A free Apple Account does not give this
cloud job a provisioned App Group or Developer ID identity. Exact launch/capability
behavior must be checked on your macOS version. A Personal Team workflow is distinct
from ad-hoc signing; it has not been attempted with your account.

## Review and install on your Mac (macOS 14+)

1. Review the PR, CI results, and diagnostics. Download the ad-hoc ZIP and its
   diagnostics from that exact run. Compare `shasum -a 256` of the inner app ZIP
   with the hash in `ZIP-SHA256.txt` from that run. Do not compare a GitHub wrapper
   ZIP or a different run's checksum.
2. Extract the inner ZIP with Archive Utility. Keep any old version closed,
   including its widget. Preserve existing data; follow the migration guide
   before replacing an older installation. Copy the reviewed `Quiet Tasks.app`
   into Applications using Finder. This is your manual installation decision;
   the workflow does not install it for you.
3. Use the built-in macOS tools (no Xcode needed) to inspect the installed copy:

   ```bash
   codesign --verify --deep --strict --verbose=2 "/Applications/Quiet Tasks.app"
   codesign --verify --strict --verbose=2 "/Applications/Quiet Tasks.app/Contents/PlugIns/QuietTasksWidgetExtension.appex"
   codesign -dv --verbose=4 "/Applications/Quiet Tasks.app"
   codesign -d --entitlements :- "/Applications/Quiet Tasks.app"
   codesign -d --entitlements :- "/Applications/Quiet Tasks.app/Contents/PlugIns/QuietTasksWidgetExtension.appex"
   spctl --assess --type execute --verbose=2 "/Applications/Quiet Tasks.app"
   ```

   Static signatures should verify, display `Signature=adhoc`, and retain sandbox
   and the configured group. Ad-hoc signatures lack Apple developer identity and
   notarization. Gatekeeper may reject them even when `codesign` verification passes.
4. Try opening the app through Finder. If macOS offers a per-app **Open Anyway**
   control in **System Settings → Privacy & Security**, use it only after your
   review, if you choose to trust this exact build. That is a per-app user approval,
   not a guarantee of capability support. If macOS reports an invalid/damaged
   signature, kills the process, or provides no supported approval path, stop and
   record that result. Do not disable Gatekeeper, strip quarantine, disable SIP,
   remove sandbox entitlements, or grant blanket disk access to force it to run.

## Test with synthetic local data first

If the app opens, an unavailable App Group should produce an explicit storage
error, not create `/Users/Shared/QuietTasks` or another fallback. Stop there if
storage fails; the app/widget cannot be considered usable in this configuration.

If container access is available, create a synthetic local task, add the Quiet Tasks
widget through **Edit Widgets**, and verify the task appears. Edit, complete, and
restore it in the app, check widget updates, try widget completion, then restart
the app and widget to verify persistence. Check both small and larger widget sizes.
A missing widget in the gallery is a registration failure, not an installation pass.

For a separate non-task container check, Terminal can run the same nonce probe:

```bash
nonce="$(uuidgen)"
"/Applications/Quiet Tasks.app/Contents/MacOS/Quiet Tasks" --quiettasks-group-probe "$nonce"
# Record the first exit status before running the extension:
echo "$?"
"/Applications/Quiet Tasks.app/Contents/PlugIns/QuietTasksWidgetExtension.appex/Contents/MacOS/QuietTasksWidgetExtension" --quiettasks-group-probe "$nonce"
echo "$?"
```

Only two zero exits verify this probe. Do not infer success from an empty Terminal
window. Direct extension execution may itself be unsupported; desktop WidgetKit
behavior is a separate check. Do not authorize Google until local storage/sharing
works and you separately choose to test sync. Your own Desktop OAuth client ID is
required; the Keychain migration and cleanup instructions still apply. Never paste
refresh tokens into issues or chat. No account testing is performed automatically.

Record macOS version, run/commit ID, signature results, the exact visible error,
probe exit statuses, whether the widget appears, and whether updates work. Console
can help inspect sandbox or WidgetKit errors; redact personal task/account data.
No terminal log containing a token is needed.

## If it does not work

A denied App Group, invalid entitlement, killed process, unavailable widget, or
Gatekeeper refusal is a real limitation of this attempt. There is no secure
fallback that can be silently enabled while retaining the current sharing design.
Installing Xcode alone does not grant App Group authorization. Local Xcode would
be relevant only if you later choose a supported Personal Team development-signing
experiment; that is not required for the cloud build and is not promised to supply
App Groups. An Apple-issued, correctly provisioned signing route may be necessary
for the full native widget. The optional paid Developer ID/notarization workflow
remains documented separately for a future reviewed choice, not a prerequisite
for generating this experimental artifact.
