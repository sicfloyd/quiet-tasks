# Quiet Tasks Privacy Policy

Quiet Tasks is a native macOS app and WidgetKit extension. It has no analytics,
advertising, tracking SDKs, or developer-operated data service.

## Local task data

The signed app and widget store tasks, notes, subtasks, deadlines, priorities,
recurrences, notification preferences, appearance, and widget state in one
provisioned macOS App Group container. Both targets must be signed for that exact
group. An unavailable group stops storage access; the app does not write fallback
copies in `/Users/Shared/QuietTasks` or Application Support. Task data is local
JSON, not application-level encrypted storage; the user session, OS, disk
protection, and backups determine its protection at rest. The widget can access
shared task data, including imported Google task content.

## Google Tasks

Sync is optional and requires your own Google Desktop OAuth client ID and
interactive consent. Default access is the Google Tasks read/write scope, used
for completing and restoring tasks. Optional read-only mode must be selected
before connecting; changing scope or client ID requires disconnect/reconnect.
The app uses PKCE S256, random state, an IPv4 loopback HTTP callback, and Google's
HTTPS authorization, token, revocation, and Tasks endpoints. No client secret is
loaded from a shared JSON configuration.

Refresh tokens are stored as non-synchronizing, device-local generic-password
Keychain items accessible while the user session's Keychain is unlocked. Tokens
are not stored in shared task/settings files and the widget has no token-store
implementation. Access tokens stay in memory. HTTP requests use an ephemeral
session without persistent caches/cookies/credential storage; redirects are
rejected. Token contents and server response bodies are not logged.

Disconnect stops sync, attempts to clear the Keychain item and recognized legacy
token files, removes cached Google tasks, and attempts HTTPS token revocation.
Offline revocation and inaccessible or conflicting legacy files can fail; the UI
reports incomplete cleanup and instructs you to revoke access through Google
Account permissions. Other backups or copies made outside recognized locations
cannot be discovered reliably by this sandboxed application.

## Migration and deletion

Earlier versions wrote plaintext `google-token.json` and task/settings copies to
multiple directories. Local token migration verifies the Keychain write before
removing recognized, safely accessible legacy copies. Conflicting tokens,
unreadable files, symlinks, unsafe ownership/permissions, or cleanup failures
require intervention; they are not treated as successful migration. A one-time,
user-selected data-folder import validates task data and verifies destination
writes before removing the imported source files. It does not poll old task
locations afterward. See [migration and release instructions](Docs/SECURITY_AND_RELEASE.md).

Deleting files cannot securely erase SSD snapshots, backups, or previously copied
tokens. Revoke old Google authorization if you used a version with plaintext
storage. Review old folders manually; uninstalling the app alone does not
necessarily remove App Group data, Keychain entries, or Google grants.

## Notifications and cloud builds

Optional deadline reminders use local macOS notifications, which may expose task
titles on the lock screen according to your notification settings. No task data
or Google login is needed for CI: tests use synthetic data and mocked HTTP.
GitHub Actions artifacts contain application binaries; never put real user data,
certificates, passwords, or tokens in the repository or artifact contents.

For security reports, contact the fork maintainer privately through GitHub's
security reporting facilities when available. Avoid including tokens or private
task data in public issues.
