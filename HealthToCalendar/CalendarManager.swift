//
//  CalendarManager.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/11/26.
//

import Foundation
import EventKit
import HealthKit
import Combine
import PostHog

struct SyncHistory: Codable, Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let syncedAt: Date
    let eventCount: Int
    let eventIDs: [String]

    init(startDate: Date, endDate: Date, eventCount: Int, eventIDs: [String]) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.syncedAt = Date()
        self.eventCount = eventCount
        self.eventIDs = eventIDs
    }
}

struct CalendarEventPreview: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let details: String
    let emoji: String
    let categoryName: String
}

class CalendarManager: ObservableObject {
    let eventStore = EKEventStore()
    private let healthSyncMarker = "[HealthToCalendar-Synced]"
    private let syncHistoryKey = "syncHistory"

    @Published var isAuthorized = false
    @Published var syncStatus: String?
    @Published var isSyncing = false
    @Published var syncedEventCount = 0
    @Published var syncHistory: [SyncHistory] = []
    @Published var selectedCalendar: EKCalendar?
    @Published var availableCalendars: [EKCalendar] = []

    init() {
        loadSyncHistory()
        updateSyncedEventCount()
    }

    private func loadSyncHistory() {
        if let data = UserDefaults.standard.data(forKey: syncHistoryKey),
           let history = try? JSONDecoder().decode([SyncHistory].self, from: data) {
            syncHistory = history.sorted { $0.syncedAt > $1.syncedAt }
        }
    }

    private func saveSyncHistory() {
        if let data = try? JSONEncoder().encode(syncHistory) {
            UserDefaults.standard.set(data, forKey: syncHistoryKey)
        }
    }

    private func updateSyncedEventCount() {
        syncedEventCount = syncHistory.reduce(0) { $0 + $1.eventCount }
    }

    func isDateRangeSynced(from startDate: Date, to endDate: Date) -> SyncHistory? {
        let calendar = Calendar.current
        return syncHistory.first { history in
            calendar.isDate(history.startDate, inSameDayAs: startDate) &&
            calendar.isDate(history.endDate, inSameDayAs: endDate)
        }
    }

    func getSyncedDays() -> Set<Date> {
        let calendar = Calendar.current
        var syncedDays = Set<Date>()

        for history in syncHistory {
            var currentDate = calendar.startOfDay(for: history.startDate)
            let endDate = calendar.startOfDay(for: history.endDate)

            while currentDate <= endDate {
                syncedDays.insert(currentDate)
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
        }

        return syncedDays
    }

    func fetchPreviewEvents(healthManager: HealthKitManager, from startDate: Date, to endDate: Date) async -> [CalendarEventPreview] {
        var previewEvents: [CalendarEventPreview] = []

        // Add 1 day to endDate to make it inclusive (HealthKit queries use exclusive end dates)
        let calendar = Calendar.current
        let adjustedEndDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate

        for category in healthManager.healthCategories {
            let samples = await healthManager.fetchDetailedSampleData(for: category, from: startDate, to: adjustedEndDate)

            for sample in samples {
                let preview = CalendarEventPreview(
                    title: "\(category.emoji) \(category.name)",
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    isAllDay: sample.isAllDay,
                    details: sample.details,
                    emoji: category.emoji,
                    categoryName: category.name
                )
                previewEvents.append(preview)
            }
        }

        return previewEvents.sorted { $0.startDate > $1.startDate }
    }

    func requestCalendarAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                isAuthorized = granted
                if granted {
                    loadAvailableCalendars()
                    PostHogSDK.shared.capture("calendar_authorization_granted", properties: [
                        "calendars_count": availableCalendars.count
                    ])
                } else {
                    syncStatus = "Calendar access denied"
                    PostHogSDK.shared.capture("calendar_authorization_denied")
                }
            }
        } catch {
            await MainActor.run {
                syncStatus = "Calendar access error: \(error.localizedDescription)"
                PostHogSDK.shared.capture("calendar_authorization_failed", properties: [
                    "error": error.localizedDescription
                ])
            }
        }
    }

    func loadAvailableCalendars() {
        availableCalendars = eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
        selectedCalendar = eventStore.defaultCalendarForNewEvents
    }

    func syncHealthDataToCalendar(healthManager: HealthKitManager, from startDate: Date, to endDate: Date, enabledCategories: Set<String>? = nil) async {
        if let existingSync = isDateRangeSynced(from: startDate, to: endDate) {
            await MainActor.run {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                syncStatus = "Date range already synced on \(formatter.string(from: existingSync.syncedAt))"
            }
            return
        }

        PostHogSDK.shared.capture("calendar_sync_started", properties: [
            "start_date": ISO8601DateFormatter().string(from: startDate),
            "end_date": ISO8601DateFormatter().string(from: endDate),
            "categories_count": enabledCategories?.count ?? healthManager.healthCategories.count
        ])

        await MainActor.run {
            isSyncing = true
            syncStatus = "Syncing health data to calendar..."
        }

        var eventsCreated = 0
        var eventsFailed = 0
        var createdEventIDs: [String] = []

        // Add 1 day to endDate to make it inclusive (HealthKit queries use exclusive end dates)
        let calendar = Calendar.current
        let adjustedEndDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate

        // Filter categories if enabledCategories is provided
        let categoriesToSync = enabledCategories != nil
            ? healthManager.healthCategories.filter { enabledCategories!.contains($0.name) }
            : healthManager.healthCategories

        for category in categoriesToSync {
            let samples = await healthManager.fetchDetailedSampleData(for: category, from: startDate, to: adjustedEndDate)

            for sample in samples {
                do {
                    let eventID = try await createCalendarEvent(for: sample, category: category)
                    createdEventIDs.append(eventID)
                    eventsCreated += 1
                } catch {
                    eventsFailed += 1
                }
            }
        }

        let newHistory = SyncHistory(
            startDate: startDate,
            endDate: endDate,
            eventCount: eventsCreated,
            eventIDs: createdEventIDs
        )

        await MainActor.run {
            syncHistory.insert(newHistory, at: 0)
            saveSyncHistory()
            updateSyncedEventCount()
            isSyncing = false
            syncStatus = "Sync complete: \(eventsCreated) events created\(eventsFailed > 0 ? ", \(eventsFailed) failed" : "")"
            PostHogSDK.shared.capture("calendar_sync_completed", properties: [
                "events_created": eventsCreated,
                "events_failed": eventsFailed,
                "success": eventsFailed == 0
            ])
        }
    }

    func createCalendarEvent(for sample: HealthSample, category: HealthKitManager.HealthCategory) async throws -> String {
        let event = EKEvent(eventStore: eventStore)

        event.title = "\(category.emoji) \(sample.details)"
        event.startDate = sample.startDate
        event.endDate = sample.endDate
        event.isAllDay = sample.isAllDay
        event.notes = healthSyncMarker
        event.calendar = selectedCalendar ?? eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    func deleteAllSyncedEvents() async {
        await MainActor.run {
            isSyncing = true
            syncStatus = "Deleting synced events..."
        }

        var deletedCount = 0
        var failedCount = 0

        for history in syncHistory {
            for eventID in history.eventIDs {
                if let event = eventStore.event(withIdentifier: eventID) {
                    do {
                        try eventStore.remove(event, span: .thisEvent)
                        deletedCount += 1
                    } catch {
                        failedCount += 1
                    }
                }
            }
        }

        await MainActor.run {
            syncHistory.removeAll()
            saveSyncHistory()
            syncedEventCount = 0
            isSyncing = false
            syncStatus = "Deleted \(deletedCount) events\(failedCount > 0 ? ", \(failedCount) failed" : "")"
        }
    }

    func deleteSyncHistory(_ history: SyncHistory) async {
        await MainActor.run {
            isSyncing = true
            syncStatus = "Deleting events..."
        }

        var deletedCount = 0
        var failedCount = 0

        for eventID in history.eventIDs {
            if let event = eventStore.event(withIdentifier: eventID) {
                do {
                    try eventStore.remove(event, span: .thisEvent)
                    deletedCount += 1
                } catch {
                    failedCount += 1
                }
            }
        }

        await MainActor.run {
            syncHistory.removeAll { $0.id == history.id }
            saveSyncHistory()
            updateSyncedEventCount()
            isSyncing = false
            syncStatus = "Deleted \(deletedCount) events\(failedCount > 0 ? ", \(failedCount) failed" : "")"
        }
    }
}
