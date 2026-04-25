import XCTest
@testable import Smux

final class LeftRailFileTreePresentationTests: XCTestCase {
    func testDirectoryPresentationUsesDisclosureAndFolderIcon() {
        let node = makeNode(
            name: "Sources",
            kind: .directory,
            isDocumentCandidate: false,
            childrenState: .notLoaded
        )

        let presentation = LeftRailFileTreeNodePresentation(node: node)

        XCTAssertEqual(presentation.systemImage, "folder")
        XCTAssertEqual(presentation.emphasis, .standard)
        XCTAssertTrue(presentation.showsDisclosure)
        XCTAssertNil(presentation.childrenStatusText)
    }

    func testDocumentCandidatePresentationUsesRestrainedEmphasis() {
        let node = makeNode(
            name: "README.md",
            kind: .file,
            isDocumentCandidate: true,
            childrenState: .loaded([])
        )

        let presentation = LeftRailFileTreeNodePresentation(node: node)

        XCTAssertEqual(presentation.systemImage, "doc.richtext")
        XCTAssertEqual(presentation.emphasis, .documentCandidate)
        XCTAssertFalse(presentation.showsDisclosure)
    }

    func testPlainFilePresentationStaysSecondary() {
        let node = makeNode(
            name: "notes.txt",
            kind: .file,
            isDocumentCandidate: false,
            childrenState: .loaded([])
        )

        let presentation = LeftRailFileTreeNodePresentation(node: node)

        XCTAssertEqual(presentation.systemImage, "doc")
        XCTAssertEqual(presentation.emphasis, .standard)
        XCTAssertFalse(presentation.showsDisclosure)
    }

    func testFailedChildrenPresentationExposesStatusText() {
        let node = makeNode(
            name: "Docs",
            kind: .directory,
            isDocumentCandidate: false,
            childrenState: .failed(message: "Permission denied")
        )

        let presentation = LeftRailFileTreeNodePresentation(node: node)

        XCTAssertEqual(presentation.childrenStatusText, "Unable to load")
    }

    private func makeNode(
        name: String,
        kind: FileTreeNodeKind,
        isDocumentCandidate: Bool,
        childrenState: FileTreeChildrenState
    ) -> FileTreeNode {
        FileTreeNode(
            id: FileTreeNode.ID(),
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            isDocumentCandidate: isDocumentCandidate,
            childrenState: childrenState,
            gitStatus: nil
        )
    }
}
