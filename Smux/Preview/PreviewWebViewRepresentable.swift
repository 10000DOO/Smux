import AppKit
import SwiftUI

struct PreviewWebViewRepresentable: NSViewRepresentable {
    typealias NSViewType = NSView

    var state: PreviewState?

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
