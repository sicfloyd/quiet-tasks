# Cloud development, migration, and release

The app remains native SwiftUI + WidgetKit, targets macOS 14+, and retains App
Sandbox and hardened runtime. Development can be done in this Linux workspace;
all native compilation/tests run on GitHub-hosted macOS runners. No Google account
or Apple credentials are needed for the unsigned test workflow. Do not disable
Gatekeeper or install the unsigned artifact as a release.

## Unsigned test artifact

1. Open this fork's **Actions → macOS test build**. A push to
   `security/harden-google-tasks` or a PR triggers it; workflow_dispatch can run it
   manually. Fork Actions may first need enabling in repository settings.
2. Select the run for the exact reviewed commit. Check both `swift test` and
   `xcodebuild` completed successfully, rather than just a workflow being present.
3. Under **Artifacts**, download **Quiet-Tasks-UNSIGNED-TEST-ONLY**. GitHub wraps
   the uploaded `Quiet-Tasks-UNSIGNED-TEST-ONLY.zip` in an artifact download.
   Its inner ZIP must contain `Quiet Tasks.app/Contents/PlugIns/QuietTasksWidgetExtension.appex`.
   Artifacts expire after seven days. They are not published GitHub Releases.

The workflow uses read-only repository permissions, pinned action commits, no
signing secrets, no personal credentials, no pull_request_target, and synthetic
HTTP test responses. Unsigned compilation cannot prove App Group authorization,
Keychain behavior in the signed app, widget registration, or end-user installability.

## Signing parameters

Supply these build settings together; example defaults are deliberately unsuitable
for distribution and the upstream developer's signing team is never required:

| Setting | Value |
| --- | --- |
| `QUIET_TASKS_TEAM` | Your Apple Developer Team ID |
| `QUIET_TASKS_APP_BUNDLE_ID` | Your unique app identifier |
| `QUIET_TASKS_WIDGET_BUNDLE_ID` | App identifier plus your widget suffix |
| `QUIET_TASKS_APP_GROUP` | One exact App Group supported by your profiles for both targets |
| `QUIET_TASKS_APP_PROFILE` / `QUIET_TASKS_WIDGET_PROFILE` | Separate matching distribution profile UUIDs for manual signing |

Both Info.plists carry the configured group, both entitlement files expand that
same setting, and the shared storage source calls `containerURL` only for that ID.
Never fabricate a `Library/Group Containers` writable fallback. Apple Developer ID
App Group provisioning requirements must be checked for your membership and macOS
SDK. The release scripts verify profile team, bundle ID, expiry, distribution type,
and group; unavailable or mismatching provisioning fails the build. Client IDs are
public configuration, but supply your own Desktop app OAuth ID in Settings. Enable
Google Tasks API and configure the consent screen in your own Google Cloud project.
A desktop client with PKCE is used; no upstream ID or shared-file client secret is
loaded. If your Google project requires a different client authentication policy,
stop and investigate it rather than committing a secret or weakening PKCE.

## Legacy migration and safe cleanup

Do not run old and new app/widget versions concurrently during migration. Older
versions can recreate copies after cleanup. Before migrating real data, review
these instructions and keep any necessary *task-only* backup in a location you
control; avoid backing up `google-token.json`. Revoke the old app's grant in Google
Account → Security → connections/third-party access. This is especially important
if plaintext tokens were previously backed up or readable by another user.

Recognized old locations include:

- `/Users/Shared/QuietTasks`
- `~/Library/Application Support/QuietTasks`
- The old app's sandbox `Data/Library/Application Support/QuietTasks` under its
  `~/Library/Containers/<old-app-bundle-id>` directory
- `~/Library/Group Containers/group.ai.aifund.quiettasks/QuietTasks`
- `~/Library/Group Containers/group.com.rakeshutekar.quiettasksnative/QuietTasks`

The new app does not continuously import task/settings data from those paths.
Use **Settings → Google Tasks → Migrate legacy data folder…** once, on a new empty
installation, to select the intended old QuietTasks directory. The file picker
grants temporary sandbox access. It validates tasks/settings, clears legacy Google
connection settings, verifies destination bytes, and only then removes imported
source task/settings/widget-state files. A migration marker prevents repeated
imports and stale task resurrection. Conflicting destination data is rejected;
resolve it deliberately rather than overwriting it. If a migration is interrupted,
retry before editing data; already-written destination bytes must agree.

On first launch, recognized token locations are checked locally. The unconnected Settings view also offers **Clear credentials / revoke access** for failed authorizations or migration conflicts. Token migration
uses a non-shared Keychain item scoped to the app bundle ID, reads only owned regular
files under owned, non-group/world-writable, non-linked directories, rejects
multiple different credentials, verifies a Keychain read-back, then removes all
recognized legacy copies. A save/delete/cleanup failure is reported, and failed
first-run migration disables automatic sync. A non-secret migration marker prevents stale token files from being imported again after a completed migration or disconnect. Connecting also repeats the local
credential checks before requesting Google authorization. No token JSON is ever
written by the new implementation.

Sandbox access to old containers or another user's files is **not guaranteed**.
Permission denial is a cleanup failure, not evidence that no copy exists. Use the
explicit folder picker for accessible data and manually inspect/remove obsolete
copies that the new sandbox cannot access. Do not grant blanket disk access, change
another user's ownership, or follow symlinks to make cleanup pass. New installations
that hit denied legacy paths need the same targeted access/cleanup investigation;
the app deliberately does not silently skip those paths. Search old app containers
when changing bundle IDs: the new app cannot enumerate every previous sandbox or
backup. Never claim all legacy data was removed merely because one folder imported.

After verifying the migrated tasks and reviewing every known old folder, remove
remaining obsolete `tasks.json`, `settings.json`, `widget-state.json`,
`google-token.json`, and `google-oauth.json` from those old folders only. Do not
recursively delete directories containing unrelated files. The old OAuth JSON may
contain a client secret; the new app neither imports nor reads it. Revoke old grants
again if necessary, then connect with your own client ID. File removal cannot erase
APFS snapshots, Time Machine backups, SSD remnants, or copies elsewhere. No runtime
cleanup of a user's actual files has been performed in this task.

## Manual release candidate (separate, approval gated)

Signing and notarization are **incomplete until a real successful run is recorded**.
The repository contains a manual job, not signing credentials or completed Apple
provisioning. No automatic GitHub Release, deployment, or installation is performed.

Before enabling the job, a repository administrator must create the
`release-signing` GitHub environment, configure **required reviewers** (prevent
self-review where supported), and restrict allowed deployment refs to reviewed
protected commits. Environment protection is configured in GitHub settings, not
created by workflow YAML. Set the environment variable
`RELEASE_APPROVAL_CONFIGURED=true` **only after confirming these protections**.
If your GitHub plan does not support required reviewers for this repository, do
not populate signing secrets or run this job. The variable is an explicit operator
attestation, not a technical substitute for GitHub's reviewer enforcement.

Store the following only as protected environment secrets:

- `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `DEVELOPER_ID_IDENTITY`
- `APP_PROFILE_BASE64`, `WIDGET_PROFILE_BASE64` (matching Developer ID profiles)
- `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` (Apple notarization API key)

Run **Manual signed release candidate** with the exact reviewed full commit SHA,
your team ID, both bundle IDs, and the provisioned group ID. The reviewer should
inspect that commit's workflow and scripts before granting access to secrets.
Never run the signing job against untrusted PR code. Certificates/keys go into
temporary runner files and a temporary Keychain, are cleaned in an always step,
and are never uploaded. Do not enable shell tracing. The job builds with separate
profiles, verifies embedded signatures/entitlements, runs a signed app/extension
App Group nonce probe, submits to Apple notarization, requires `Accepted`, staples,
checks the ticket and Gatekeeper assessment, and uploads only a review-required
signed ZIP. A direct extension probe may be unsupported by a runner/runtime; its
failure must be investigated, not removed or relabeled as a pass.

The nonce probe uses the two actual signed executable identities and a dedicated
non-task file. It proves container access/read-after-write if it passes; it does
**not** prove WidgetKit UI registration or timeline behavior. Before final
installation/distribution, validate on an authorized remote macOS 14+ desktop
(or your own reviewed external test service, keeping work off your Mac): launch
the app, create/update/complete a synthetic local task, add the widget, verify its
updates, restart both, and verify one-container persistence. Test Keychain access,
legacy migration and disconnect offline/online with a dedicated test Google account
only after separate authorization; never use a personal account automatically.
Record versions, entitlements, steps, results, and signing/notarization run IDs.
No remote desktop or test Google account has been provisioned by this change.

After reviewing the resulting ZIP and recorded acceptance tests, a maintainer may
manually publish a GitHub Release through the GitHub UI. Publication is a separate
review decision; the workflow has no contents-write permission and never publishes
or deploys a release.
