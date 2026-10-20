# Quiet Tasks

Quiet Tasks is a minimal macOS to-do app with a real desktop widget.

I wanted a simple task widget that could live on the macOS desktop like the built-in widgets, show only the tasks that still need attention, and stay visually quiet. I could not find one that felt right, so this project exists for anyone who wants the same thing.

Feel free to download it, use it, fork it, and contribute.

## What It Does

- Native macOS app built with SwiftUI.
- Real WidgetKit desktop widget, available in small, medium, and large sizes.
- Open, Today, All Tasks, and Done views.
- Add, edit, delete, complete, and restore tasks.
- Optional deadlines with a compact date/time popover.
- Low, Normal, and High priority options.
- Global notification defaults for deadline reminders.
- One-level subtasks with completion tracking.
- Daily, weekly, and monthly recurring tasks.
- Pinned tasks that stay above the regular list.
- System, light, and dark appearance modes for the app and widget.
- Optional Google Tasks sync for showing a Google task list in Quiet Tasks.
- Widget shows open tasks only, plus progress for what is currently active.
- Completing local tasks from the widget uses an inline confirmation. Google task completion opens the app to sync back to Google.
- No account or cloud service required for local tasks.

## Why This Is Better

Most to-do apps are either full productivity suites or they do not behave like a proper macOS desktop widget. Quiet Tasks is intentionally smaller:

- It is built around the desktop widget first.
- It keeps the widget readable and minimal instead of busy.
- It keeps completed tasks out of the widget so the desktop stays clean.
- It can show pinned tasks, priority, and subtasks without turning the widget into a dashboard.
- It gives the full app enough tools to manage tasks without turning into a project-management app.
- It is open source, so anyone can improve it.

## Requirements

- macOS with desktop widgets support.
- Xcode installed.
- Swift and WidgetKit support from the installed Xcode toolchain.

The app and widget require one correctly provisioned, signed App Group. There is
no writable fallback path. Refresh tokens use macOS Keychain, never shared JSON.
See [security review](SECURITY_REVIEW.md), [cloud build and migration instructions](Docs/SECURITY_AND_RELEASE.md),
and [actual validation results](Docs/VALIDATION.md).

## Personal testing with a free Apple Account

The cloud workflow also attempts ad-hoc signing without paid Apple credentials.
See [personal installation and testing](Docs/PERSONAL_TESTING.md) for the downloadable
app, actual signature/container diagnostics, supported per-app Gatekeeper review,
and macOS widget checks. Ad-hoc signing does not establish App Group authorization
or WidgetKit registration; those may fail. Local Xcode is not needed to build or
inspect the artifact. Sandbox, Keychain storage, and the one-container policy stay
enabled. No Google account is connected by CI.

## Download

Use this fork's **Actions → macOS test build → Artifacts** for the explicitly
unsigned test-only ZIP containing the app and embedded WidgetKit extension. It is
not a signed installation release. Do not bypass Gatekeeper to use it. A separate
manual, protected release-candidate workflow supports your own Developer ID and
notarization; signing, notarization, and signed widget behavior remain unverified
until actually performed and recorded.

## Google Tasks Sync

Quiet Tasks can import tasks from one Google Tasks list and show them in the app and widget. Completing or restoring a Google task in Quiet Tasks syncs that status back to Google Tasks. Google Tasks sync runs after connect, when the app becomes active, when you press Refresh, and every minute while the app is running. Editing, deleting, and subtask writes still happen in Google Tasks.

To use it in the app:

1. Supply your own Google Cloud Desktop OAuth client ID in **Settings → Google Tasks → Advanced**.
2. Optionally select read-only mode before connecting. Default mode permits completion/restore.
3. Click **Connect Google** and explicitly approve access; choose a task list, then click **Sync Now**.
4. Disconnect before changing client ID or scope. Disconnect attempts revocation and local credential cleanup; review any reported failures.

This fork requires your own Google Cloud project:

1. In Google Cloud, open **APIs & Services -> Library** and enable **Google Tasks API**.
2. Open **APIs & Services -> OAuth consent screen** and configure the app. If the publishing status is **Testing**, add your Google account as a test user.
3. Open **APIs & Services -> Credentials -> Create Credentials -> OAuth client ID**.
4. Select **Application type: Desktop app**, name it `Quiet Tasks`, and create it.
5. Copy the generated **Client ID**. You do not need to add a redirect URI for a Desktop app; Quiet Tasks uses a temporary localhost callback during sign-in.
6. Open **Quiet Tasks -> Settings -> Google Tasks -> Advanced** and paste the Desktop OAuth client ID.

Quiet Tasks requests the Google Tasks scope:

```text
https://www.googleapis.com/auth/tasks
```

If you connected before completion sync was added, disconnect and reconnect Google Tasks once so Google grants the write scope.

Google Tasks due dates are date-only. If a Google task has a due date, Quiet Tasks shows the date without an exact time.

## Cloud development and builds

Keep development in the cloud checkout and use GitHub-hosted macOS runners for
native builds. The normal workflow runs `swift test --jobs 2` and `xcodebuild`,
checks for the embedded widget, and uploads a test ZIP. No Google login or Apple
signing credentials are needed. See [detailed instructions](Docs/SECURITY_AND_RELEASE.md)
for artifacts, one-time legacy migration, configurable signing IDs, and the
approval-gated manual release candidate.

On a macOS runner, the unsigned compilation check is:

```bash
swift test --jobs 2
xcodebuild -project QuietTasks.xcodeproj -scheme "Quiet Tasks" \
  -configuration Release -derivedDataPath XcodeDerivedData \
  -destination 'generic/platform=macOS' -jobs 2 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

This does not validate App Group access, signed app Keychain authorization,
WidgetKit registration, or Google account behavior. Never install or deploy
artifacts automatically. The signed release workflow requires your own team,
app/widget bundle IDs, App Group, separate matching profiles, protected secrets,
and explicit review. A remote macOS desktop acceptance test is still required.

## Contributing

Contributions are welcome. Useful areas to improve:

- Signed release packaging.
- App Group storage for production signing.
- Keyboard shortcuts.
- Two-way Google Tasks sync.
- Better recurring tasks.
- iCloud sync as an optional feature.
- More widget configuration options while keeping the default UI quiet.

Please keep the app minimal, native, and calm. The point is a useful task widget that does not visually take over the desktop.

## License

MIT. Use it freely.
