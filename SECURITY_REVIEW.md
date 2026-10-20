# Security review — 2026-10-20

Reviewed baseline: `a5eb18038d2c5a91f11a12dba152e054233ec14f` in sicfloyd/quiet-tasks. The supplied preliminary review is retained in Docs/PRELIMINARY_SECURITY_REVIEW.md. There was no review document in this checkout at baseline. References in the table below refer to that baseline, not line numbers after refactoring.

## Threat model

Protect Google refresh/access tokens, task titles/notes, account consent, and signing identity. Consider another local user, a malicious local callback client, a corrupted/linked legacy file, network redirects/server failures, compromised CI dependencies, and untrusted PRs. Trust the signed macOS app, Apple's Keychain and sandbox/App Group enforcement, and Google HTTPS endpoints. A compromised same-user session, compromised OS, backups/SSD remnants, Google itself, and stolen Apple signing credentials remain outside the guarantees. A signed widget shares task data but must never receive refresh tokens.

## Verified baseline findings

| Finding | Evidence at baseline | Assessment |
| --- | --- | --- |
| Refresh token JSON, incomplete disconnect cleanup | App.swift (Sources/QuietTasksApp/QuietTasksApp.swift):726–765 | Confirmed plaintext credential persistence; file mode 0600 limits but does not eliminate exposure. Only one selected copy deleted. Privacy claim of Keychain storage was inaccurate. |
| Multiple task/settings copies, including public shared directory | App.swift:237–305, 406–410, 506–510; Sources/QuietTasksWidget/QuietTasksWidget.swift:141–209, 280–285, 410–415 | Confirmed writes to fallback paths. Cross-user readability depends on actual filesystem permissions; it was not tested. Legacy files can also influence current state. |
| Upstream signing identity and App Groups | QuietTasks.xcodeproj/project.pbxproj:382–491; App.entitlements:14; Widget.entitlements:10 | Confirmed fixed upstream team/bundle/group configuration, unsuitable for this fork. |
| Upstream default OAuth client ID; optional shared JSON client secret | App.swift:200–221, 308–350, 1114–1116, 1142–1144 | Confirmed configuration; client ID is public, not a leaked credential. Fork must supply its own desktop client. |
| Disconnect does not revoke authorization | App.swift:1811–1819 | Confirmed local deletion only. Remote grants can remain active. |
| OAuth callback checks state after handling server error | App.swift:1062–1083 | Confirmed error-message injection/denial-of-service opportunity; no verified token theft. PKCE S256, random state, exact redirect matching, and IPv4 loopback binding are present. |
| Shared URLSession and raw server error messages | App.swift:1150–1200, 1322–1331, 1404–1420 | Potential caching, redirect, and sensitive error disclosure risks; no observed credential exfiltration. |
| Read/write Google Tasks scope | App.swift:1031 | Intentional for completion/restore; not a vulnerability. Read-only mode is optional. |

## Dependency and build surface

Baseline has no third-party packages, dependency lockfiles, CI workflows, test targets, downloaded build scripts, or Xcode shell build phases. Frameworks include SwiftUI, WidgetKit, AppKit, AuthenticationServices, CryptoKit, Darwin, Foundation, UserNotifications, and AppIntents. Scripts/make-icon.swift uses AppKit and writes generated PNG files to its command-line output directory; it is not invoked by the build. Network destinations in application source are Google authorization, token, and Tasks HTTPS endpoints plus the HTTP loopback redirect; custom quiettasks URLs open app actions and local task completion requires confirmation. No token logging was found in current source. This is source review, not a full Git-history secret audit or a binary/runtime audit.

## Validation and residual risks

Implementation, test coverage, actual commands/results, and remaining signing/migration limitations are recorded in Docs/VALIDATION.md and Docs/SECURITY_AND_RELEASE.md. macOS compilation, Keychain tests, signed App Group sharing, Developer ID signing, and notarization must be distinguished. An unsigned build cannot validate App Group authorization or widget registration. Never treat an unsigned test artifact as an installable signed release.
