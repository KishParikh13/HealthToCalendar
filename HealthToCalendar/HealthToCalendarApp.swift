//
//  HealthToCalendarApp.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/11/26.
//

import SwiftUI
import CoreData

@main
struct HealthToCalendarApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
