//
//  lovableeApp.swift
//  
//
//  Created by Anthony Verruijt on 29/11/2025.
//

import SwiftUI

@main
struct lovableeApp: App {
    @StateObject private var pushManager = PushNotificationManager()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var didAttachDelegate = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pushManager)
                .onAppear {
                    guard !didAttachDelegate else { return }
                    appDelegate.pushManager = pushManager
                    didAttachDelegate = true
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guard WidgetDataStore.shared.hasStoredSession else { return }
            print("🎨 App became active - syncing widget")
            Task {
                await WidgetSyncService.shared.syncWidgetWithLatestDoodle()
            }
        }
    }
}
