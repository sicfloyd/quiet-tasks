import XCTest
import Foundation
import Security
@testable import QuietTasksLogic

final class MemoryVault: TokenVault {
    var token: String?
    var failSave = false
    var failDelete = false
    func load() throws -> String? { token }
    func save(_ value: String) throws {
        if failSave { throw StorageError.invalidData }
        token = value
    }
    func delete() throws {
        if failDelete { throw StorageError.cleanupRequired }
        token = nil
    }
}

final class StorageTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func legacy(_ token: String, name: String = "google-token.json") throws -> URL {
        let url = root.appendingPathComponent(name)
        try JSONSerialization.data(withJSONObject: ["refreshToken": token]).write(to: url)
        return url
    }
    func testMigrationVerifiesKeychainBeforeRemovingEveryCopy() throws {
        let vault = MemoryVault()
        let urls = try [legacy("synthetic", name: "a.json"), legacy("synthetic", name: "b.json")]
        let store = MigratingTokenStore(vault: vault, legacyURLs: urls)
        XCTAssertEqual(try store.load(), "synthetic")
        XCTAssertEqual(vault.token, "synthetic")
        for url in urls { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertEqual(try store.load(), "synthetic")
    }
    func testKeychainFailurePreservesLegacyForRecovery() throws {
        let vault = MemoryVault(); vault.failSave = true
        let url = try legacy("synthetic")
        XCTAssertThrowsError(try MigratingTokenStore(vault: vault, legacyURLs: [url]).load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testConflictingTokensAreNotGuessedOrDeleted() throws {
        let vault = MemoryVault(); vault.token = "account-a"
        let url = try legacy("account-b")
        XCTAssertThrowsError(try MigratingTokenStore(vault: vault, legacyURLs: [url]).load())
        XCTAssertEqual(vault.token, "account-a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testDisconnectCleansLegacyEvenWhenKeychainDeletionFails() throws {
        let vault = MemoryVault(); vault.failDelete = true
        let url = try legacy("synthetic")
        XCTAssertThrowsError(try MigratingTokenStore(vault: vault, legacyURLs: [url]).delete())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testMalformedLegacyBlocksMigration() throws {
        let url = root.appendingPathComponent("google-token.json")
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try MigratingTokenStore(vault: MemoryVault(), legacyURLs: [url]).load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testSymlinkCannotBeReadOrCleanedAsToken() throws {
        let target = try legacy("synthetic")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try SafeFile.read(link))
        XCTAssertThrowsError(try SafeFile.remove(link))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
    func testHardlinkedFileIsRejected() throws {
        let target = try legacy("synthetic")
        try FileManager.default.linkItem(at: target, to: root.appendingPathComponent("hardlink"))
        XCTAssertThrowsError(try SafeFile.read(target))
    }
    func testOversizedFileRejected() throws {
        let target = try legacy("synthetic")
        XCTAssertThrowsError(try SafeFile.read(target, maximumSize: 1))
    }
    func testWritableLegacyDirectoryIsRejected() throws {
        let target = try legacy("synthetic")
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)
        XCTAssertThrowsError(try SafeFile.read(target))
    }
    func testOnlyAllowlistedTaskStoreNamesCanBeWritten() throws {
        let store = GroupFileStore(directory: root)
        for name in ["../tasks.json", "google-token.json", "/tmp/tasks.json", "other.json"] {
            XCTAssertThrowsError(try store.write(Data(), name: name))
        }
        try store.write(Data("[]".utf8), name: "tasks.json")
        XCTAssertEqual(try store.read("tasks.json"), Data("[]".utf8))
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("tasks.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testExistingSymlinkDestinationCannotBeOverwritten() throws {
        let target = try legacy("synthetic", name: "private")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("tasks.json"), withDestinationURL: target)
        XCTAssertThrowsError(try GroupFileStore(directory: root).write(Data(), name: "tasks.json"))
        XCTAssertNotNil(try SafeFile.read(target))
    }
    func testOneTimeTaskMigrationVerifiesAndRemovesSelectedFiles() throws {
        let source = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data("[]".utf8).write(to: source.appendingPathComponent("tasks.json"))
        let destination = GroupFileStore(directory: root.appendingPathComponent("group"))
        let migration = LegacyDataMigration(destination: destination, vault: MemoryVault())
        try migration.run(from: source)
        XCTAssertEqual(try JSONDecoder.taskDecoder.decode([TaskItem].self, from: XCTUnwrap(destination.read("tasks.json"))), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("tasks.json").path))
        XCTAssertThrowsError(try migration.run(from: source))
    }
    func testTaskMigrationRejectsCorruptionBeforeDeletingSource() throws {
        let source = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = source.appendingPathComponent("tasks.json")
        try Data("{broken}".utf8).write(to: file)
        let destination = GroupFileStore(directory: root.appendingPathComponent("group"))
        XCTAssertThrowsError(try LegacyDataMigration(destination: destination, vault: MemoryVault()).run(from: source))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(try destination.read("tasks.json"))
    }
    func testDisconnectFindsEveryReadableCredentialDespiteConflict() throws {
        let vault = MemoryVault(); vault.token = "synthetic-a"
        let url = try legacy("synthetic-b")
        let store = MigratingTokenStore(vault: vault, legacyURLs: [url])
        let candidates = store.revocationCandidates()
        XCTAssertEqual(candidates.tokens, ["synthetic-a", "synthetic-b"])
        XCTAssertTrue(candidates.complete)
        try store.delete()
        XCTAssertNil(vault.token)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testCompletedMigrationNeverResurrectsLegacyCredential() throws {
        let vault = MemoryVault()
        let url = try legacy("stale-synthetic")
        let store = MigratingTokenStore(vault: vault, legacyURLs: [url], migrationAllowed: false)
        XCTAssertNil(try store.load())
        XCTAssertNil(vault.token)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testOversizedWritePreservesExistingDataAndPrivateDirectory() throws {
        let store = GroupFileStore(directory: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try store.write(Data("[]".utf8), name: "tasks.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertThrowsError(try store.write(Data(repeating: 0, count: GroupFileStore.maximumFileSize + 1), name: "tasks.json"))
        XCTAssertEqual(try store.read("tasks.json"), Data("[]".utf8))
    }
    func testRealKeychainRoundTripUpdateAndDelete() throws {
        // Unique service; synthetic data only; cleans its own item even on failure.
        let vault = KeychainTokenVault(service: "QuietTasks.SecurityTests." + UUID().uuidString)
        defer { try? vault.delete() }
        XCTAssertNil(try vault.load())
        try vault.save("synthetic-first")
        XCTAssertEqual(try vault.load(), "synthetic-first")
        try vault.save("synthetic-rotated")
        XCTAssertEqual(try vault.load(), "synthetic-rotated")
        try vault.delete()
        XCTAssertNil(try vault.load())
    }
}

final class OAuthTests: XCTestCase {
    func testRFC7636S256Vector() {
        XCTAssertEqual(GoogleOAuthClient.pkceChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testExactCallbackAndStateRequired() throws {
        let redirect = "http://127.0.0.1:43210/"
        XCTAssertEqual(try GoogleOAuthClient.validatedCode(callbackURL: URL(string: redirect + "?state=random&code=synthetic")!, redirectURI: redirect, state: "random"), "synthetic")
        for callback in [
            "http://localhost:43210/?state=random&code=a", "http://127.0.0.1:43211/?state=random&code=a",
            "https://127.0.0.1:43210/?state=random&code=a", "http://127.0.0.1:43210/wrong?state=random&code=a",
            redirect + "?state=wrong&code=a", redirect + "?code=a", redirect + "?state=random&state=random&code=a",
            redirect + "?state=random&code=a&code=b", redirect + "?state=random&code=", redirect + "?state=random&code=a#fragment"
        ] {
            XCTAssertThrowsError(try GoogleOAuthClient.validatedCode(callbackURL: URL(string: callback)!, redirectURI: redirect, state: "random"))
        }
    }
    func testOAuthErrorsDoNotDisplayUntrustedServerText() {
        XCTAssertThrowsError(try GoogleOAuthClient.validatedCode(callbackURL: URL(string: "http://127.0.0.1:43210/?state=random&error=denied&error_description=SECRET")!, redirectURI: "http://127.0.0.1:43210/", state: "random")) { error in
            XCTAssertFalse(error.localizedDescription.contains("SECRET"))
        }
    }
    func testNoPersistentHTTPStores() {
        let config = GoogleHTTP.session.configuration
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
    }
    func testRedirectsAreRejected() {
        let delegate = GoogleHTTP()
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        let task = GoogleHTTP.session.dataTask(with: url)
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        delegate.urlSession(GoogleHTTP.session, task: task, willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://example.invalid")!)) { XCTAssertNil($0) }
        task.cancel() // Task is never resumed; no network operation occurs.
    }
    func testSettingsRequireOwnClientAndPreserveReadOnlyChoice() throws {
        XCTAssertEqual(GoogleSyncSettings.default.effectiveClientID, "")
        var settings = AppSettings.default
        settings.googleSync.clientID = "  custom.apps.googleusercontent.com  "
        settings.googleSync.readOnly = true
        let restored = try JSONDecoder.taskDecoder.decode(AppSettings.self, from: JSONEncoder.taskEncoder.encode(settings))
        XCTAssertTrue(restored.googleSync.readOnly == true)
        XCTAssertEqual(SettingsStore.normalized(restored).googleSync.effectiveClientID, "custom.apps.googleusercontent.com")
        settings.googleSync.clientID = "820308341063-legacy.apps.googleusercontent.com"
        XCTAssertEqual(SettingsStore.normalized(settings).googleSync, .default)
    }
}
