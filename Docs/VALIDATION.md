# Validation record

Date: 2026-10-20. Baseline reviewed: `a5eb18038d2c5a91f11a12dba152e054233ec14f`.
Branch: `security/harden-google-tasks` in `sicfloyd/quiet-tasks`.

## Performed in the Linux cloud workspace

- Verified preliminary findings against current source, project settings, entitlements,
  network calls, and build script before editing. Retained the uploaded review as
  Docs/PRELIMINARY_SECURITY_REVIEW.md; it was absent from the baseline checkout.
- Verified platform Git read and branch push dry-run access. GitHub API requests were
  denied by the egress proxy (403/Forbidden), including an unauthenticated request.
  No personal Google or Apple credentials were used. No Google endpoints were called.
- Parsed all changed Swift source/tests and Package.swift with tree-sitter Swift
  0.7.4 / tree-sitter 0.26.0: no syntax error nodes. This is not Swift compilation,
  type checking, or test execution.
- Parsed the Xcode project with openstep-parser 2.0.3 and validated both source
  build phases include shared storage, referenced source files exist, and all target
  configurations retain sandbox/hardened runtime and parameterized signing.
- Parsed entitlement/Info plists, shared scheme XML, and workflow YAML; checked
  exact App Group setting agreement and read-only workflow repository permissions.
- `bash -n Scripts/prepare-release-signing.sh Scripts/build-signed-release.sh` and
  `git diff --check`: passed.

Validation-only Python packages were installed under `/tmp/quiet-check-tools`; they
are not application dependencies or committed package requirements.

## Not yet executed or established

This machine is Linux and has neither `swift` nor `xcodebuild`. Native compile,
SPM XCTest execution, the test ZIP's actual binary contents, Keychain integration,
signed App Group probe, WidgetKit timeline/desktop behavior, interactive OAuth,
Google revocation, Developer ID signing, and Apple notarization are **unverified**.
The macOS workflow definitions and tests are implemented, not evidence of a passed
run. No actual user's legacy files were migrated or deleted. No Google account was
connected and no binary was deployed or published.

The XCTest suite covers synthetic Keychain round trips/update/delete, mock-vault
migration ordering/failure/conflicts, cleanup attempts after Keychain failure,
unsafe file/link/size/permission boundaries, one-time task import/corruption,
PKCE test vector, exact callback/state handling, redirection rejection, ephemeral
HTTP configuration, settings/client normalization/read-only persistence, mocked
Tasks pagination/mapping/completion/restore/error handling, and local-change merge
behavior during sync. Coverage does not imply those tests have run.

## Required next evidence

1. Record the exact macOS Actions run, Xcode/Swift versions, test counts/results,
   build outcome, and ZIP validation for the reviewed commit.
2. With separately reviewed team/provisioning/secrets, record the signed job and
   app/extension nonce probe results; investigate platform-specific failures.
3. Validate app-to-desktop-widget updates on an authorized remote macOS desktop.
4. Record actual Developer ID signature and notarization acceptance/ticket checks.

Unsigned CI cannot satisfy signed App Group or desktop-widget acceptance. Cleanup
cannot certify unknown backups or old inaccessible app containers. See
Docs/SECURITY_AND_RELEASE.md for explicit cleanup and review steps.
