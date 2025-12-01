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
    }
}
