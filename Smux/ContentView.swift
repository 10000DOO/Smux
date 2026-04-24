//
//  ContentView.swift
//  Smux
//
//  Created by 이건준 on 4/24/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var panelStore = PanelStore()
    @StateObject private var notificationStore = NotificationStore()

    var body: some View {
        WorkspaceShellView(
            workspaceStore: workspaceStore,
            panelStore: panelStore,
            notificationStore: notificationStore
        )
    }
}

#Preview {
    ContentView()
}
