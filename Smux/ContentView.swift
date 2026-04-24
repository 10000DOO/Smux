//
//  ContentView.swift
//  Smux
//
//  Created by 이건준 on 4/24/26.
//

import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var appComposition = AppComposition()
    @State private var isWorkspaceImporterPresented = false

    var body: some View {
        WorkspaceShellView(
            workspaceStore: appComposition.workspaceStore,
            panelStore: appComposition.panelStore,
            notificationStore: appComposition.notificationStore
        )
        .toolbar {
            Button {
                appComposition.workspaceStore.clearOpenError()
                isWorkspaceImporterPresented = true
            } label: {
                Label("Open Workspace", systemImage: "folder")
            }
        }
        .fileImporter(
            isPresented: $isWorkspaceImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                await appComposition.openWorkspace(from: result)
            }
        }
    }
}

@MainActor
private final class AppComposition: ObservableObject {
    let workspaceStore: WorkspaceStore
    let panelStore: PanelStore
    let notificationStore: NotificationStore
    let recentWorkspaceStore: RecentWorkspaceStore
    let workspaceRepository: any WorkspaceRepository
    let workspaceCoordinator: WorkspaceCoordinator
    let commandRouter: AppCommandRouter
    private let logger = Logger(subsystem: "Smux", category: "AppComposition")

    init() {
        let workspaceStore = WorkspaceStore()
        let panelStore = PanelStore()
        let systemNotificationDeliverer = UserNotificationCenterNotifier()
        let notificationStore = NotificationStore(systemNotifier: systemNotificationDeliverer)
        let recentWorkspaceStore = RecentWorkspaceStore()
        let workspaceRepository = FileBackedWorkspaceRepository()
        let workspaceCoordinator = WorkspaceCoordinator(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            workspaceRepository: workspaceRepository,
            recentWorkspaceStore: recentWorkspaceStore
        )

        self.workspaceStore = workspaceStore
        self.panelStore = panelStore
        self.notificationStore = notificationStore
        self.recentWorkspaceStore = recentWorkspaceStore
        self.workspaceRepository = workspaceRepository
        self.workspaceCoordinator = workspaceCoordinator
        self.commandRouter = AppCommandRouter(
            workspaceOpening: workspaceCoordinator,
            documentOpening: workspaceCoordinator,
            terminalCommanding: workspaceCoordinator,
            panelCommanding: workspaceCoordinator
        )
        systemNotificationDeliverer.prepare { [logger] result in
            switch result {
            case .success(true):
                break
            case .success(false):
                logger.notice("System notification authorization was not granted.")
            case let .failure(error):
                logger.error("Failed to prepare system notifications: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func openWorkspace(from result: Result<[URL], any Error>) async {
        do {
            guard let rootURL = try result.get().first else {
                workspaceStore.openErrorMessage = "No workspace folder was selected."
                return
            }

            workspaceStore.clearOpenError()
            try await commandRouter.openWorkspace(rootURL: rootURL)
        } catch {
            guard !isUserCancellation(error) else {
                return
            }

            workspaceStore.openErrorMessage = "Failed to open workspace: \(error.localizedDescription)"
        }
    }

    private func isUserCancellation(_ error: any Error) -> Bool {
        guard let cocoaError = error as? CocoaError else {
            return false
        }

        return cocoaError.code == .userCancelled
    }
}

#Preview {
    ContentView()
}
