import XCTest
import Foundation
@testable import QuietTasksLogic

final class StubGoogleProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw StorageError.invalidData }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class GoogleTasksTests: XCTestCase {
    var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubGoogleProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() {
        session.invalidateAndCancel()
        StubGoogleProtocol.handler = nil
    }
    func testTaskListPaginationAndAuthorization() async throws {
        var requests = 0
        StubGoogleProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "tasks.googleapis.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
            if requests == 1 { return (200, #"{"items":[{"id":"b","title":"Beta"}],"nextPageToken":"next"}"#) }
            XCTAssertTrue(request.url!.query!.contains("pageToken=next"))
            return (200, #"{"items":[{"id":"a","title":"Alpha"}]}"#)
        }
        let lists = try await GoogleTasksClient.fetchTaskLists(accessToken: "synthetic", session: session)
        XCTAssertEqual(lists.map(\.id), ["a", "b"])
        XCTAssertEqual(requests, 2)
    }
    func testRepeatedPageTokenFailsInsteadOfLooping() async {
        StubGoogleProtocol.handler = { _ in (200, #"{"items":[],"nextPageToken":"same"}"#) }
        do {
            _ = try await GoogleTasksClient.fetchTaskLists(accessToken: "synthetic", session: session)
            XCTFail("Repeated pagination token must fail")
        } catch { XCTAssertTrue(error is GoogleSyncError) }
    }
    func testGoogleErrorDoesNotExposeServerBody() async {
        StubGoogleProtocol.handler = { _ in (403, #"{"error":{"message":"synthetic-secret"}}"#) }
        do {
            _ = try await GoogleTasksClient.fetchTaskLists(accessToken: "synthetic", session: session)
            XCTFail("403 must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("403"))
            XCTAssertFalse(error.localizedDescription.contains("synthetic-secret"))
        }
    }
    func testMalformedResponseFails() async {
        StubGoogleProtocol.handler = { _ in (200, "not-json") }
        do {
            _ = try await GoogleTasksClient.fetchTaskLists(accessToken: "synthetic", session: session)
            XCTFail("Invalid JSON must fail")
        } catch { XCTAssertTrue(error is DecodingError) }
    }
    func testNetworkFailurePropagates() async {
        StubGoogleProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await GoogleTasksClient.fetchTaskLists(accessToken: "synthetic", session: session)
            XCTFail("Network failure must propagate")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
    func testCompletionAndRestoreUsePatch() async throws {
        var count = 0
        StubGoogleProtocol.handler = { request in
            count += 1
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.host, "tasks.googleapis.com")
            // URLProtocol can represent body as a stream. The endpoint and method remain observable.
            return (200, count == 1 ? #"{"id":"task","status":"completed"}"# : #"{"id":"task","status":"needsAction"}"#)
        }
        let completed = try await GoogleTasksClient.setCompletion(accessToken: "synthetic", taskListID: "list", taskID: "task", done: true, completedAt: Date(), session: session)
        let restored = try await GoogleTasksClient.setCompletion(accessToken: "synthetic", taskListID: "list", taskID: "task", done: false, completedAt: Date(), session: session)
        XCTAssertEqual(completed.status, "completed")
        XCTAssertEqual(restored.status, "needsAction")
        XCTAssertEqual(count, 2)
    }
    func testMappingPreservesGoogleTaskAndSubtaskBoundaries() throws {
        let data = Data(#"{"items":[{"id":"parent","title":" Parent ","status":"needsAction"},{"id":"child","parent":"parent","title":"Child","status":"completed"}]}"#.utf8)
        let response = try JSONDecoder.googleDecoder.decode(GoogleTasksResponse.self, from: data)
        let tasks = GoogleTasksClient.mappedTasks(from: response.items!, taskListID: "list", taskListTitle: "List")
        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(tasks[0].isGoogleTask)
        XCTAssertEqual(tasks[0].externalID, "parent")
        XCTAssertEqual(tasks[0].title, "Parent")
        XCTAssertEqual(tasks[0].taskSubtasks.first?.done, true)
    }
    @MainActor func testSyncMergePreservesConcurrentLocalChangesAndDeletion() {
        let now = Date()
        func task(_ id: String, updated: Date? = nil, source: TaskSource? = nil) -> TaskItem {
            TaskItem(id: id, title: id, deadline: nil, done: false, createdAt: now.addingTimeInterval(-100),
                     notes: nil, priority: nil, updatedAt: updated, completedAt: nil, source: source)
        }
        let merged = TaskModel.mergedLocalTasksForGoogleSync(
            latestSavedTasks: [task("kept"), task("from-widget"), task("old-google", source: .google)],
            currentTasks: [task("kept", updated: now.addingTimeInterval(1)), task("deleted"), task("new", updated: now.addingTimeInterval(1))],
            syncStartedAt: now, startingTaskIDs: ["kept", "deleted"])
        XCTAssertEqual(Set(merged.map(\.id)), ["kept", "from-widget", "new"])
        XCTAssertEqual(merged.first(where: { $0.id == "kept" })?.updatedAt, now.addingTimeInterval(1))
    }
}
