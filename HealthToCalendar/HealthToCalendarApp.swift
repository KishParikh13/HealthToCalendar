//
//  HealthToCalendarApp.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/11/26.
//

import SwiftUI
import CoreData
import PostHog

@main
struct HealthToCalendarApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        let env = ProcessInfo.processInfo.environment
        guard let apiKey = env["POSTHOG_API_KEY"], !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            #if DEBUG
            print("Warning: POSTHOG_API_KEY not set in environment. Skipping PostHog setup.")
            #endif
            return
        }
        let host = (env["POSTHOG_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "https://us.i.posthog.com"

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.debug = true
        #if os(iOS)
        config.sessionReplay = true
        config.sessionReplayConfig.maskAllImages = false
        config.sessionReplayConfig.maskAllTextInputs = true
        config.sessionReplayConfig.screenshotMode = true
        #endif
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.capture("app_open", properties: [
            "platform": "iOS",
            "sessionReplayEnabled": true
        ])
        
        PostHogSDK.shared.capture("button_clicked", properties: ["button_name": "signup", "$process_person_profile": false])

        
        PostHogSDK.shared.flush()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

