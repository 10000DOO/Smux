import Combine
import Foundation

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var session: TerminalSession?
    @Published var status: TerminalSessionStatus = .idle
    @Published var title = "Terminal"

    func sendInput(_ text: String) {}

    func resize(columns: Int, rows: Int) {}
}
