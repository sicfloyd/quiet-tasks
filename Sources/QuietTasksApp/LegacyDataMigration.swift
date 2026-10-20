import Foundation

// Explicit, user-selected import; app/widget never poll old task locations.
struct LegacyDataMigration {
    let destination: GroupFileStore
    let vault: any TokenVault

    func run(from source: URL) throws {
        guard source.standardizedFileURL != destination.directory.standardizedFileURL,
              try destination.read("migration-complete") == nil else { throw StorageError.legacyConflict }
        try SafeFile.checkParents(source)
        var imports: [(String, Data)] = []
        if let data = try SafeFile.read(source.appendingPathComponent("tasks.json")) {
            let tasks = try JSONDecoder.taskDecoder.decode([TaskItem].self, from: data)
            imports.append(("tasks.json", try JSONEncoder.taskEncoder.encode(TaskStore.normalized(tasks))))
        }
        if let data = try SafeFile.read(source.appendingPathComponent("settings.json")) {
            var settings: AppSettings
            if let decoded = try? JSONDecoder.taskDecoder.decode(AppSettings.self, from: data) { settings = decoded }
            else {
                settings = .default
                settings.notifications = try JSONDecoder.taskDecoder.decode(NotificationSettings.self, from: data)
            }
            // Legacy account association is untrusted. Require explicit new consent/client configuration.
            settings.googleSync = .default
            imports.append(("settings.json", try JSONEncoder.taskEncoder.encode(settings)))
        }
        if let data = try SafeFile.read(source.appendingPathComponent("widget-state.json")) {
            _ = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            imports.append(("widget-state.json", data))
        }
        guard !imports.isEmpty else { throw StorageError.invalidData }
        // Validate everything before changing either store. Never merge into a nonempty installation.
        for (name, data) in imports {
            if let existing = try destination.read(name), existing != data { throw StorageError.legacyConflict }
        }
        let tokens = MigratingTokenStore(vault: vault, legacyURLs: [source.appendingPathComponent("google-token.json")])
        _ = try tokens.load()
        for (name, data) in imports { try destination.write(data, name: name) }
        for (name, data) in imports {
            guard try destination.read(name) == data else { throw StorageError.invalidData }
        }
        // Removal is deliberately after verification. If interrupted, retry compares destination bytes.
        for (name, _) in imports { try SafeFile.remove(source.appendingPathComponent(name)) }
        try destination.write(Data("1".utf8), name: "migration-complete")
    }
}
