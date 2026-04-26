import AppKit
import XCTest
@testable import Smux

final class TerminalInputTranslatorTests: XCTestCase {
    func testNavigationKeysMapToTerminalEscapeSequences() {
        let cases: [(TerminalInputKey, String)] = [
            (.upArrow, "\u{1B}[A"),
            (.downArrow, "\u{1B}[B"),
            (.rightArrow, "\u{1B}[C"),
            (.leftArrow, "\u{1B}[D"),
            (.home, "\u{1B}[H"),
            (.end, "\u{1B}[F"),
            (.pageUp, "\u{1B}[5~"),
            (.pageDown, "\u{1B}[6~")
        ]

        for (key, expectedInput) in cases {
            XCTAssertEqual(TerminalInputTranslator.input(for: key), expectedInput)
        }
    }

    func testEditingAndControlKeysMapToTerminalInput() {
        let cases: [(TerminalInputKey, String)] = [
            (.returnKey, "\r"),
            (.deleteBackward, "\u{7F}"),
            (.deleteForward, "\u{1B}[3~"),
            (.tab, "\t"),
            (.backTab, "\u{1B}[Z"),
            (.escape, "\u{1B}"),
            (.insert, "\u{1B}[2~"),
            (.text("a"), "a")
        ]

        for (key, expectedInput) in cases {
            XCTAssertEqual(TerminalInputTranslator.input(for: key), expectedInput)
        }
    }

    func testShiftTabMapsToBackTabSequence() {
        XCTAssertEqual(
            TerminalInputTranslator.input(for: .tab, modifiers: [.shift]),
            "\u{1B}[Z"
        )
    }

    func testCommandModifiedKeysAreNotForwardedToTerminal() {
        XCTAssertNil(TerminalInputTranslator.input(for: .text("c"), modifiers: [.command]))
        XCTAssertNil(TerminalInputTranslator.input(for: .upArrow, modifiers: [.command]))
    }

    func testScrollPolicyFollowsTailOnlyNearBottom() {
        XCTAssertTrue(
            TerminalScrollPolicy.shouldFollowTail(
                visibleMaxY: 100,
                visibleHeight: 100,
                documentHeight: 100
            )
        )
        XCTAssertTrue(
            TerminalScrollPolicy.shouldFollowTail(
                visibleMaxY: 982,
                visibleHeight: 300,
                documentHeight: 1_000
            )
        )
        XCTAssertFalse(
            TerminalScrollPolicy.shouldFollowTail(
                visibleMaxY: 500,
                visibleHeight: 300,
                documentHeight: 1_000
            )
        )
    }

    func testScrollPolicyClampsRestoredVisibleOrigin() {
        XCTAssertEqual(
            TerminalScrollPolicy.clampedVisibleOriginY(
                -20,
                visibleHeight: 300,
                documentHeight: 1_000
            ),
            0
        )
        XCTAssertEqual(
            TerminalScrollPolicy.clampedVisibleOriginY(
                900,
                visibleHeight: 300,
                documentHeight: 1_000
            ),
            700
        )
    }
}
