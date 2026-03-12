import SwiftUI
import SwiftTerm
import AppKit

/// Wraps a shared LocalProcessTerminalView (from TerminalStore) so it can be
/// moved between the main window and pop-out windows without restarting the process.
struct EmbeddedTerminalView: NSViewRepresentable {
    let task: AppTask
    let onProcessExit: @MainActor () -> Void

    func makeNSView(context: Context) -> NSView {
        let termView = TerminalStore.shared.terminal(for: task, onProcessExit: onProcessExit)
        // Remove from previous superview so it can be re-parented here
        termView.removeFromSuperview()

        // Wrap in a container so SwiftUI manages sizing
        let container = NSView(frame: .zero)
        container.addSubview(termView)
        termView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            termView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            termView.topAnchor.constraint(equalTo: container.topAnchor),
            termView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Auto-focus the terminal
        DispatchQueue.main.async {
            termView.window?.makeFirstResponder(termView)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
