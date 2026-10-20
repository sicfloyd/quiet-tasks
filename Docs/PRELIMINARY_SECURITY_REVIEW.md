# Quiet Tasks — preliminary source-level security review

Date checked: 2026-10-20
Upstream: https://github.com/rakeshutekar/quiet-tasks

This is a targeted inspection of publicly available source, **not** a complete vulnerability assessment, live binary analysis, or assurance that the app is safe. The source tree could change after this date. Recheck current `main` and dependencies before using it.

## Confirmed areas requiring attention

### 1. High priority — refresh token persisted in JSON

`Sources/QuietTasksApp/QuietTasksApp.swift`, `GoogleTokenStore` (approximately lines 673–709) serializes a Google OAuth refresh token into `google-token.json`. It attempts file mode 0600, but storage is not macOS Keychain. It can also read from `/Users/Shared/QuietTasks/google-token.json`. Its `deleteRefreshToken` routine deletes just the selected primary path, potentially leaving a legacy copy. In contrast, `PRIVACY.md` claims tokens are kept in Keychain.

**Fix:** Use `Security.framework` Keychain services for refresh tokens, protect items as appropriate for the user session, migrate preexisting token files carefully, remove all legacy token copies after verifying successful migration, ensure disconnect clears relevant Keychain entries, update privacy documentation. Remember filesystem deletion may not securely erase old SSD data; users who previously signed in can revoke the app's Google access and reconnect.

### 2. High priority — user task data copied across directories

`TaskStore.write` (~lines 378–383) and `SettingsStore.write` (~lines 469–475) iterate over *all* `SharedFiles.candidateDirectories` (which includes `/Users/Shared/QuietTasks`) and attempt to write JSON copies. The WidgetKit source repeats the pattern. This expands privacy exposure and complicates data deletion/migration. `/Users/Shared` may be accessible to other local users depending on permissions.

**Fix:** Choose one dedicated, signed App Group container for shared tasks/settings; keep tokens outside of it in Keychain; allow only **read-only** migration from legacy locations and delete/stop using them after a verified migration. Add tests for read, write, migration, app/widget agreement, and cleanup.

### 3. Release configuration belongs to upstream developer

`QuietTasks.xcodeproj/project.pbxproj` has `DEVELOPMENT_TEAM = 5CUS7DQX48`, `PRODUCT_BUNDLE_IDENTIFIER = ai.aifund.quiettasks` and a widget extension bundle ID based on that. `App.entitlements` and `Widget.entitlements` include `group.ai.aifund.quiettasks`.

**Fix:** Assign your own unique bundle IDs, signing team, and App Group identifier consistently for BOTH targets and the shared-storage code. Ensure your provisioning setup supports App Groups. Do not accidentally use upstream signing identity.

### 4. OAuth permissions

The app requests `https://www.googleapis.com/auth/tasks` (Google Tasks read/write), which makes sense if you want to mark tasks complete but exceeds the privileges needed for a display-only widget. Consider a read-only mode requesting `https://www.googleapis.com/auth/tasks.readonly` until editing is explicitly enabled. For a fork, configure your own Google OAuth desktop client ID.

## Positive observations (not guarantees)

- Google OAuth authorization includes PKCE challenge/verifier and state validation (`GoogleOAuthClient.authorize` ~lines 953–1014).
- Authorization callback binds to `127.0.0.1` on a transient port and validates host/port/path.
- API and token requests visibly use HTTPS to Google's endpoints.
- App and widget entitlement files turn on the app sandbox and specify an App Group (which still needs matching valid signing).

## Additional recommended checks

- Scan *all* repository files and git history for credentials, unexpected network endpoints, dangerous shell invocations, logging of sensitive values, and any downloaded build scripts.
- Review indirect dependencies and transitive build tools, if any are later added.
- Test OAuth cancellation, token revocation, expired tokens, and failures in shared storage.
- Check entitlement behavior, widget freshness, and login/logout on a real Mac.
- For end-user distribution, sign with your Developer ID and notarize with Apple; do not equate a clean compilation or notarization with a comprehensive security audit.

## Source references

- https://raw.githubusercontent.com/rakeshutekar/quiet-tasks/main/Sources/QuietTasksApp/QuietTasksApp.swift
- https://raw.githubusercontent.com/rakeshutekar/quiet-tasks/main/Sources/QuietTasksWidget/QuietTasksWidget.swift
- https://raw.githubusercontent.com/rakeshutekar/quiet-tasks/main/QuietTasks.xcodeproj/project.pbxproj
- https://github.com/rakeshutekar/quiet-tasks/blob/main/App.entitlements
- https://github.com/rakeshutekar/quiet-tasks/blob/main/Widget.entitlements
- https://github.com/rakeshutekar/quiet-tasks/blob/main/PRIVACY.md
