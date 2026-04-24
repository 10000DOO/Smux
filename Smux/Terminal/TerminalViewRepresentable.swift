import AppKit
import SwiftUI

struct TerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = NSView

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
