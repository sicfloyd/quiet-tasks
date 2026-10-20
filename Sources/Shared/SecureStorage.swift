import Foundation
import Darwin

// Compiled into both targets: no inferred App Group IDs and no writable fallback.
enum StorageError: LocalizedError {
    case unavailableGroup, unsafeFile, invalidData, legacyConflict, cleanupRequired
    var errorDescription: String? {
        switch self {
        case .unavailableGroup: return "The signed App Group is unavailable. Configure matching app/widget entitlements and provisioning; no fallback data will be written."
        case .unsafeFile: return "A storage path is linked, has unsafe ownership/permissions, or is not a regular file. Review migration instructions."
        case .invalidData: return "Stored data could not be read safely. No existing data was overwritten."
        case .legacyConflict: return "Legacy stores conflict. Review and remove obsolete copies before migration."
        case .cleanupRequired: return "Legacy cleanup is incomplete. Remove remaining copies using the migration instructions before connecting Google."
        }
    }
}

enum SafeFile {
    // Legacy data is untrusted even when it is owned by the current user.
    static func read(_ url: URL, maximumSize: Int = 8 * 1024 * 1024) throws -> Data? {
        try checkParents(url.deletingLastPathComponent())
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw StorageError.unsafeFile
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= maximumSize else { throw StorageError.unsafeFile }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        guard data.count <= maximumSize else { throw StorageError.invalidData }
        return data
    }

    static func checkParents(_ directory: URL) throws {
        let path = directory.standardizedFileURL
        guard path.resolvingSymlinksInPath().path == path.path else { throw StorageError.unsafeFile }
        var info = stat()
        if lstat(path.path, &info) != 0 {
            if errno == ENOENT { return }
            throw StorageError.unsafeFile
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
              info.st_mode & 0o022 == 0 else { throw StorageError.unsafeFile }
    }

    static func remove(_ url: URL) throws {
        // Never follow symlinks or remove files belonging to another user.
        guard try read(url) != nil else { return }
        try FileManager.default.removeItem(at: url)
        if FileManager.default.fileExists(atPath: url.path) { throw StorageError.cleanupRequired }
    }
}

struct GroupFileStore {
    let directory: URL
    static let allowedNames: Set<String> = ["tasks.json", "settings.json", "widget-state.json", "migration-complete", "token-migration-complete", "group-probe.json"]

    func url(_ name: String) throws -> URL {
        guard Self.allowedNames.contains(name) else { throw StorageError.unsafeFile }
        try SafeFile.checkParents(directory)
        return directory.appendingPathComponent(name)
    }

    func read(_ name: String) throws -> Data? { try SafeFile.read(url(name)) }

    func write(_ data: Data, name: String) throws {
        let destination = try url(name)
        // Validate existing destination before replacing it; never follow a link.
        _ = try SafeFile.read(destination)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        guard try read(name) == data else { throw StorageError.invalidData }
    }
}

private final class StorageDiagnostics {
    private let lock = NSLock()
    private var message: String?
    func get() -> String? { lock.lock(); defer { lock.unlock() }; return message }
    func set(_ value: String?) { lock.lock(); defer { lock.unlock() }; message = value }
}

enum SharedFiles {
    private static let diagnostics = StorageDiagnostics()
    static var lastError: String? {
        get { diagnostics.get() }
        set { diagnostics.set(newValue) }
    }
    static func store() throws -> GroupFileStore {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "QuietTasksAppGroup") as? String,
              !identifier.isEmpty, !identifier.contains("$("),
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { throw StorageError.unavailableGroup }
        return GroupFileStore(directory: root.resolvingSymlinksInPath().appendingPathComponent("QuietTasks", isDirectory: true))
    }

    static var configurationError: String? {
        do { _ = try store(); return nil } catch { return error.localizedDescription }
    }

    static func read(_ name: String) -> Data? {
        do { return try store().read(name) }
        catch { lastError = error.localizedDescription; return nil }
    }

    @discardableResult static func write(_ data: Data, name: String) -> Bool {
        do { try store().write(data, name: name); return true }
        catch { lastError = error.localizedDescription; return false }
    }
}

// A signed CI probe exercises both actual executable identities without touching tasks or tokens.
// It does not verify WidgetKit UI registration/refresh, which remains a separate acceptance check.
enum GroupSharingProbe {
    static func runIfRequested(writer: Bool) {
        let args = CommandLine.arguments
        guard args.count == 3, args[1] == "--quiettasks-group-probe" else { return }
        guard UUID(uuidString: args[2]) != nil else { Darwin.exit(2) }
        do {
            let store = try SharedFiles.store()
            let expected = Data(args[2].utf8)
            if writer { try store.write(expected, name: "group-probe.json") }
            else {
                guard try store.read("group-probe.json") == expected else { throw StorageError.invalidData }
                try SafeFile.remove(store.url("group-probe.json"))
            }
            Darwin.exit(0)
        } catch {
            // Fixed diagnostic; never print file contents or command-line values.
            fputs("Signed App Group sharing probe failed.\n", stderr)
            Darwin.exit(1)
        }
    }
}
