import SwiftUI
import AppKit

@main
struct CentralStationApp: App {
    @State private var coordinator = TaskCoordinator()
    @State private var errorMessage: String?
    @State private var hasStarted = false

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.applicationIconImage = AppIcon.generate()
    }

    var body: some Scene {
        Window("Claude Central Station", id: "main") {
            Group {
                if hasStarted {
                    ContentView(coordinator: coordinator)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Failed to Start")
                            .font(.title2.bold())
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    ProgressView("Starting Claude Central Station...")
                        .padding()
                }
            }
            .frame(minWidth: 800, minHeight: 500)
            .task {
                await startup()
            }
            .onDisappear {
                coordinator.stop()
            }
        }
        .defaultSize(width: 1100, height: 700)

        // Pop-out terminal windows
        WindowGroup("Terminal", id: "terminal", for: String.self) { $taskId in
            if let taskId, let task = coordinator.tasks.first(where: { $0.id == taskId }) {
                PopOutTerminalView(task: task, coordinator: coordinator)
            } else {
                Text("Task not found")
                    .foregroundStyle(.secondary)
            }
        }
        .defaultSize(width: 800, height: 500)
    }

    private func startup() async {
        guard !hasStarted && errorMessage == nil else { return }

        Notifier.requestPermission()

        coordinator.projectPath = FileManager.default.currentDirectoryPath

        // Load persisted tasks from previous sessions
        coordinator.loadPersistedTasks()

        // Optionally load a config file if one exists
        let args = CommandLine.arguments
        var configPath: String?

        if args.count > 1 {
            configPath = args[1]
        } else {
            let cwd = FileManager.default.currentDirectoryPath
            let candidates = ["tasks.yaml", "tasks.yml", "tasks.json"]
            configPath = candidates
                .map { (cwd as NSString).appendingPathComponent($0) }
                .first { FileManager.default.fileExists(atPath: $0) }
        }

        do {
            if let configPath {
                try coordinator.loadConfig(from: configPath)
            }
            hasStarted = true
            try await coordinator.start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
