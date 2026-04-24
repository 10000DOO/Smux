import AppKit
import SwiftUI

struct MarkdownEditorRepresentable: NSViewRepresentable {
    typealias NSViewType = NSView

    var text: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
