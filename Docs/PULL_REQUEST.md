Harden Google Tasks credentials and shared widget storage; add macOS test CI

The previous app wrote refresh tokens to JSON, replicated task data across fallback
paths, and used upstream signing/OAuth identifiers. This change keeps SwiftUI and
WidgetKit, moves refresh tokens into Keychain, restricts task/settings writes to
one configured signed App Group, adds checked one-time migration/cleanup, requires
an explicitly supplied desktop OAuth client ID, and hardens callback/HTTP handling.
Read-only sync is optional; completion/restore remain the default.

Threat model: local users and unsafe legacy files, callback spoofing, credential
persistence/redirects, and untrusted CI inputs. Confirmed baseline findings and
file/line references are in SECURITY_REVIEW.md; runtime risks are distinguished
from source-confirmed behavior. Tokens remain outside shared data. File cleanup
cannot erase backups, and inaccessible old containers require explicit cleanup.

Tests added cover token storage/migration failures and conflicts, filesystem
boundaries, settings, PKCE/state, mocked Google Tasks sync/completion/errors, and
concurrent local-change merge behavior. Linux validation performed: Swift syntax
parsing (not compilation), project/entitlement/plist/scheme/workflow consistency,
release shell syntax, and git diff checks. Native tests and xcodebuild have NOT
been executed locally: Swift/Xcode are unavailable here. See Docs/VALIDATION.md
for exact evidence and outstanding acceptance checks; do not infer CI success
from workflow definitions.

The macOS workflow runs XCTest via SwiftPM and xcodebuild, verifies the app embeds
the widget executable, and uploads Quiet-Tasks-UNSIGNED-TEST-ONLY. Retrieve it via
this fork's Actions → macOS test build → exact commit run → Artifacts. It is an
unsigned test artifact, not an installation release. A separate manual job supports
protected Developer ID/profile/notarization secrets and checks signatures, App
Group sharing, notarization acceptance, and Gatekeeper without bypasses. Required
GitHub environment reviewers must be configured before adding secrets.

Apple team/provisioning, signed widget behavior, interactive OAuth, signing, and
notarization remain incomplete until actually performed. No Google account was
connected, personal credentials used, binary deployed, or GitHub Release published.
Migration/release instructions and the updated privacy policy describe these limits.
