import XCTest
@testable import Smux

final class FileTreeStoreTests: XCTestCase {
    @MainActor
    func testDocumentCandidateClassificationUsesMarkdownAndMermaidExtensions() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeFile(named: "README.md", in: rootURL)
        try writeFile(named: "Notes.markdown", in: rootURL)
        try writeFile(named: "diagram.mmd", in: rootURL)
        try writeFile(named: "flow.mermaid", in: rootURL)
        try writeFile(named: "plain.txt", in: rootURL)
        try makeDirectory(named: "folder.md", in: rootURL)

        let store = FileTreeStore()
        try await store.loadRoot(rootURL: rootURL)

        let children = loadedChildren(of: try XCTUnwrap(store.root))
        let candidatesByName = Dictionary(uniqueKeysWithValues: children.map {
            ($0.name, $0.isDocumentCandidate)
        })

        XCTAssertEqual(candidatesByName["README.md"], true)
        XCTAssertEqual(candidatesByName["Notes.markdown"], true)
        XCTAssertEqual(candidatesByName["diagram.mmd"], true)
        XCTAssertEqual(candidatesByName["flow.mermaid"], true)
        XCTAssertEqual(candidatesByName["plain.txt"], false)
        XCTAssertEqual(candidatesByName["folder.md"], false)
    }

    @MainActor
    func testSelectedDocumentCandidateURLReturnsOnlySelectedMarkdownOrMermaidFile() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeFile(named: "README.md", in: rootURL)
        try writeFile(named: "plain.txt", in: rootURL)

        let store = FileTreeStore()
        try await store.loadRoot(rootURL: rootURL)

        let root = try XCTUnwrap(store.root)
        let markdownNode = try XCTUnwrap(child(named: "README.md", in: root))
        let plainTextNode = try XCTUnwrap(child(named: "plain.txt", in: root))

        store.selectedNodeID = markdownNode.id
        XCTAssertEqual(store.selectedDocumentCandidateURL, markdownNode.url)

        store.selectedNodeID = plainTextNode.id
        XCTAssertNil(store.selectedDocumentCandidateURL)

        store.selectedNodeID = root.id
        XCTAssertNil(store.selectedDocumentCandidateURL)
    }

    @MainActor
    func testChildrenSortDirectoriesBeforeFilesThenByLocalizedName() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeFile(named: "b.md", in: rootURL)
        try makeDirectory(named: "b-dir", in: rootURL)
        try writeFile(named: "a.md", in: rootURL)
        try makeDirectory(named: "a-dir", in: rootURL)

        let store = FileTreeStore()
        try await store.loadRoot(rootURL: rootURL)

        let children = loadedChildren(of: try XCTUnwrap(store.root))

        XCTAssertEqual(children.map(\.name), ["a-dir", "b-dir", "a.md", "b.md"])
    }

    @MainActor
    func testLoadRootCreatesDirectoryRootWithImmediateChildren() async throws {
        let rootURL = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try writeFile(named: "README.md", in: rootURL)

        let store = FileTreeStore()
        try await store.loadRoot(rootURL: rootURL)

        let root = try XCTUnwrap(store.root)

        XCTAssertEqual(root.url, rootURL)
        XCTAssertEqual(root.name, rootURL.lastPathComponent)
        XCTAssertEqual(root.kind, .directory)
        XCTAssertFalse(root.isDocumentCandidate)
        XCTAssertEqual(loadedChildren(of: root).map(\.name), ["README.md"])
    }

    @MainActor
    func testExpandLoadsDirectoryChildrenLazily() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let docsURL = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let childURL = docsURL.appendingPathComponent("Nested.md", isDirectory: false)
        let directoryID = FileTreeNode.ID()
        let loader = RecordingFileTreeLoader(
            root: FileTreeNode(
                id: FileTreeNode.ID(),
                url: rootURL,
                name: "root",
                kind: .directory,
                isDocumentCandidate: false,
                childrenState: .loaded([
                    FileTreeNode(
                        id: directoryID,
                        url: docsURL,
                        name: "Docs",
                        kind: .directory,
                        isDocumentCandidate: false,
                        childrenState: .notLoaded,
                        gitStatus: nil
                    ),
                ]),
                gitStatus: nil
            ),
            childrenByDirectoryURL: [
                docsURL: [
                    FileTreeNode(
                        id: FileTreeNode.ID(),
                        url: childURL,
                        name: "Nested.md",
                        kind: .file,
                        isDocumentCandidate: true,
                        childrenState: .loaded([]),
                        gitStatus: nil
                    ),
                ],
            ]
        )
        let store = FileTreeStore(loader: loader, watcher: ManualFileWatcher())

        try await store.loadRoot(rootURL: rootURL)

        XCTAssertTrue(loader.loadedChildrenURLs.isEmpty)
        XCTAssertEqual(child(named: "Docs", in: try XCTUnwrap(store.root))?.childrenState, .notLoaded)

        try await store.expand(nodeID: directoryID)

        XCTAssertEqual(loader.loadedChildrenURLs, [docsURL])

        let root = try XCTUnwrap(store.root)
        let docsNode = try XCTUnwrap(child(named: "Docs", in: root))

        XCTAssertEqual(loadedChildren(of: docsNode).map(\.name), ["Nested.md"])
    }

    @MainActor
    func testWorkspaceRootWatchEventReloadsRoot() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let watcher = ManualFileWatcher()
        let loader = SequencedRootFileTreeLoader(
            roots: [
                makeRoot(url: rootURL, childNames: ["Before.md"]),
                makeRoot(url: rootURL, childNames: ["After.md"]),
            ]
        )
        let store = FileTreeStore(
            loader: loader,
            watcher: watcher,
            fileWatchDebounceInterval: 0
        )

        try await store.loadRoot(rootURL: rootURL)

        XCTAssertEqual(loadedChildren(of: try XCTUnwrap(store.root)).map(\.name), ["Before.md"])

        watcher.emit(FileWatchEvent(scope: .workspaceRoot(rootURL), kind: .contentsChanged))
        try await waitUntil {
            loader.loadedRootURLs.count == 2
        }

        XCTAssertEqual(loader.loadedRootURLs, [rootURL, rootURL])
        XCTAssertEqual(loadedChildren(of: try XCTUnwrap(store.root)).map(\.name), ["After.md"])
    }

    @MainActor
    func testClearStopsWorkspaceRootWatching() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let watcher = ManualFileWatcher()
        let loader = SequencedRootFileTreeLoader(
            roots: [
                makeRoot(url: rootURL, childNames: ["Before.md"]),
                makeRoot(url: rootURL, childNames: ["After.md"]),
            ]
        )
        let store = FileTreeStore(
            loader: loader,
            watcher: watcher,
            fileWatchDebounceInterval: 0
        )

        try await store.loadRoot(rootURL: rootURL)
        store.clear()

        watcher.emit(FileWatchEvent(scope: .workspaceRoot(rootURL), kind: .contentsChanged))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(store.root)
        XCTAssertEqual(loader.loadedRootURLs, [rootURL])
    }

    private func makeTemporaryRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTreeStoreTests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        return rootURL
    }

    private func makeDirectory(named name: String, in rootURL: URL) throws {
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func writeFile(named name: String, in rootURL: URL) throws {
        try Data().write(to: rootURL.appendingPathComponent(name, isDirectory: false))
    }

    private func loadedChildren(of node: FileTreeNode) -> [FileTreeNode] {
        guard case .loaded(let children) = node.childrenState else {
            XCTFail("Expected loaded children for \(node.name).")
            return []
        }

        return children
    }

    private func child(named name: String, in node: FileTreeNode) -> FileTreeNode? {
        loadedChildren(of: node).first { $0.name == name }
    }

    private func makeRoot(url: URL, childNames: [String]) -> FileTreeNode {
        FileTreeNode(
            id: FileTreeNode.ID(),
            url: url,
            name: url.lastPathComponent,
            kind: .directory,
            isDocumentCandidate: false,
            childrenState: .loaded(
                childNames.map { childName in
                    FileTreeNode(
                        id: FileTreeNode.ID(),
                        url: url.appendingPathComponent(childName, isDirectory: false),
                        name: childName,
                        kind: .file,
                        isDocumentCandidate: true,
                        childrenState: .loaded([]),
                        gitStatus: nil
                    )
                }
            ),
            gitStatus: nil
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await condition() {
                return
            }

            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for condition.")
    }
}

private final class RecordingFileTreeLoader: FileTreeLoading {
    private let root: FileTreeNode
    private let childrenByDirectoryURL: [URL: [FileTreeNode]]
    private(set) var loadedChildrenURLs: [URL] = []

    init(root: FileTreeNode, childrenByDirectoryURL: [URL: [FileTreeNode]]) {
        self.root = root
        self.childrenByDirectoryURL = childrenByDirectoryURL
    }

    func loadRoot(at rootURL: URL) async throws -> FileTreeNode {
        root
    }

    func loadChildren(of directoryURL: URL) async throws -> [FileTreeNode] {
        loadedChildrenURLs.append(directoryURL)
        return childrenByDirectoryURL[directoryURL, default: []]
    }
}

private final class SequencedRootFileTreeLoader: FileTreeLoading {
    private var roots: [FileTreeNode]
    private(set) var loadedRootURLs: [URL] = []

    init(roots: [FileTreeNode]) {
        self.roots = roots
    }

    func loadRoot(at rootURL: URL) async throws -> FileTreeNode {
        loadedRootURLs.append(rootURL)
        return roots.removeFirst()
    }

    func loadChildren(of directoryURL: URL) async throws -> [FileTreeNode] {
        []
    }
}
