# Validation record

Date: 2026-10-20. Reviewed baseline: `a5eb18038d2c5a91f11a12dba152e054233ec14f`.
Branch: `security/harden-google-tasks` in `sicfloyd/quiet-tasks`.

## Final application source: native macOS CI passed

[Run 39454815319](https://github.com/sicfloyd/quiet-tasks/actions/runs/39454815319)
tested source commit `b57dcbb6d713df3f474b2054a802d043c3c5659c` using Xcode 16.4 /
Apple Swift 6.1.2 on a GitHub-hosted macOS runner. Downloaded logs confirm:

- **32 XCTest tests passed, zero failures**: 9 Google Tasks tests, 6 OAuth/settings
  tests, and 17 storage/migration tests. No tests were skipped or disabled.
- The storage tests include a real Keychain save/read/update/delete round trip
  with a unique service and synthetic values, plus injected-vault migration tests.
- `xcodebuild` reported **BUILD SUCCEEDED** for the unsigned Release app and widget.
- Both app and embedded extension executables passed existence/executable checks.
  The ZIP listing independently confirms `Quiet Tasks.app/Contents/MacOS/Quiet Tasks`
  (3,365,144 bytes) and
  `Quiet Tasks.app/Contents/PlugIns/QuietTasksWidgetExtension.appex/Contents/MacOS/QuietTasksWidgetExtension`
  (1,361,560 bytes).
- Artifact upload succeeded: `12281235290`, **Quiet-Tasks-UNSIGNED-TEST-ONLY**,
  1,283,374 bytes, service-reported artifact digest
  `sha256:ce2e8983bd33db2658758e8ba76e9f046bd1eb3a59b015045d34695a7ba4da19`.
  This is the service artifact digest, not a separately computed inner-ZIP hash.

The tests exercise token migration ordering, Keychain failure, conflicting tokens,
cleanup despite deletion failure, stale-token resurrection prevention, revocation
candidates, malformed/linked/hardlinked/oversized files, private write permissions,
oversized-write preservation, one-time task import/corruption, PKCE's RFC test
vector, callback origin/state/duplicate handling, redirect rejection, ephemeral
HTTP stores, settings/client normalization/read-only persistence, mocked Google
pagination/mapping/completion/restore/revocation/error handling, and preservation
of concurrent local changes during sync. HTTP tests use URLProtocol stubs, not real
Google account requests. The Keychain round trip uses the test executable identity;
it does not validate the eventual signed app's Keychain authorization.

An earlier run, [39453231516](https://github.com/sicfloyd/quiet-tasks/actions/runs/39453231516),
passed 28 tests and the build at `1925dd74b2a530d20f1fe8f589168a32a4a849b1`. Its artifact
was downloaded and inspected locally: both binaries are universal Mach-O, both
Info.plists agree on the test App Group, and no token JSON/certificates/private keys
are included. Inner ZIP SHA-256:
`e0fbb0ec7989a79022f06e9b990bebcf55f75067255af88909bfc36edcea64b2`.
The final-source artifact's download encountered a separate cloud egress denial to
`productionresultssa19.blob.core.windows.net`; the ZIP entries above were verified
from that run's actual archive listing and its artifact metadata, rather than
claiming a local binary inspection of that newer ZIP.

Subsequent documentation and official Node 24 action-pin updates do not change the
Swift sources. Consult [PR checks](https://github.com/sicfloyd/quiet-tasks/pull/1/checks)
for the newest workflow run; this record cites checks actually observed, not future
workflow definitions. Intermediate superseded runs were canceled, not test failures.

## Linux workspace checks

- Verified the uploaded preliminary findings against source, project settings,
  entitlements, filesystem/OAuth/network code, and scripts **before editing**.
  No SECURITY_REVIEW.md existed at baseline; the supplied copy is retained in
  Docs/PRELIMINARY_SECURITY_REVIEW.md.
- All 9 Swift source/test/manifest files parse without syntax error nodes using
  tree-sitter Swift 0.7.4 / tree-sitter 0.26.0. This is syntax parsing, not compilation.
- Parsed the Xcode project with openstep-parser 2.0.3; checked both targets include
  shared storage, referenced sources exist, all configurations use parameterized
  signing, and sandbox/hardened runtime remain enabled.
- Parsed entitlement/Info plists, the shared scheme XML, and workflow YAML; checked
  App Group agreement and read-only repository permissions.
- Release shell scripts pass `bash -n`; `git diff --check` passes. Release scripts
  have not been executed with Apple credentials.
- Official action release tags/commit SHAs and node24 runtimes were checked through
  the actions/checkout and actions/upload-artifact repositories before pin updates.
- Local `swift test --jobs 2` exits 127 because this Linux machine has no Swift;
  this is an unavailable command, not a failed native test suite. macOS validation
  was performed remotely as recorded above.

Validation-only Python packages live under `/tmp/quiet-check-tools`, not in the app's
dependencies. GitHub API/log/artifact network requirements were saved in the cloud
environment draft; saving configuration is separate from publishing an environment.

## Not performed / remaining acceptance work

- **Signed App Group nonce probe and actual desktop WidgetKit updates: unverified.**
  Both require your real matching team/IDs/profiles and an authorized remote macOS
  desktop for timeline/registration behavior. Unsigned CI cannot establish them.
- **Developer ID signing and Apple notarization: incomplete.** Manual release
  scripts, entitlement checks, and protected-environment instructions are present;
  no certificate, profile, signing secret, or notarization result was supplied.
- No Google account was connected; interactive consent, real-account sync/revocation,
  offline disconnect, and live signed-app migration have not been exercised. No
  actual user's legacy files were migrated or deleted.
- Inaccessible old containers need explicit targeted access/cleanup; denial is not
  evidence of absence. Unknown backups and SSD/APFS remnants cannot be certified
  removed. Fresh signed installs must also validate legacy-path access behavior.
- Atomic file replacement prevents partial JSON writes but is not a cross-process
  transaction over a full read/edit/save cycle. Simultaneous app/widget edits can
  still need conflict-handling improvements; local Google-sync merge logic has a
  regression test, not a general multi-process concurrency guarantee.
- No binary was deployed, installed on the user's Mac, or published as a GitHub
  Release. GitHub artifact upload is a test delivery mechanism, not installation.

See Docs/SECURITY_AND_RELEASE.md for secure migration, artifact retrieval,
reviewer-gated signing configuration, and the remaining remote macOS acceptance
steps. Keep the PR in draft until the required signed behavior has been reviewed.
