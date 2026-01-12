//
//  ContentView.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/11/26.
//

import SwiftUI
import HealthKit
import EventKit

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var calendarManager = CalendarManager()
    @State private var expandedCategories: Set<UUID> = []
    @State private var showingSyncAlert = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSyncSheet = false
    @State private var syncStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var syncEndDate = Date()

    var body: some View {
        NavigationView {
            Group {
                if !healthKitManager.isAuthorized {
                    VStack(spacing: 20) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)

                        Text("Health Data Access")
                            .font(.title)
                            .bold()

                        Text("This app needs access to your health data to sync it with your calendar.")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if let error = healthKitManager.authorizationError {
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                        }

                        Button {
                            Task {
                                await healthKitManager.requestAuthorization()
                            }
                        } label: {
                            Text("Authorize Health Data")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    List {
                        if !calendarManager.syncHistory.isEmpty {
                            Section {
                                ForEach(calendarManager.syncHistory) { history in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(dateRangeString(from: history.startDate, to: history.endDate))
                                                .font(.headline)
                                            Text("\(history.eventCount) events • Synced \(relativeDateString(history.syncedAt))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Button {
                                            Task {
                                                await calendarManager.deleteSyncHistory(history)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            } header: {
                                Text("Sync History")
                            }
                        }

                        Section {
                            Text("Tap categories below to preview health data")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } header: {
                            Text("Health Categories")
                        }

                        ForEach(healthKitManager.healthCategories) { category in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedCategories.contains(category.id) },
                                    set: { isExpanding in
                                        if isExpanding {
                                            expandedCategories.insert(category.id)
                                            Task {
                                                await loadData(for: category)
                                            }
                                        } else {
                                            expandedCategories.remove(category.id)
                                        }
                                    }
                                )
                            ) {
                                if category.isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                    .padding()
                                } else if category.sampleData.isEmpty {
                                    Text("Tap to load data")
                                        .foregroundColor(.secondary)
                                        .italic()
                                } else {
                                    ForEach(category.sampleData, id: \.self) { sample in
                                        Text(sample)
                                            .font(.system(.body, design: .monospaced))
                                            .padding(.vertical, 2)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(category.name)
                                        .font(.headline)

                                    Spacer()

                                    if !category.sampleData.isEmpty {
                                        Text("\(category.sampleData.count) samples")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Health Categories")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 16) {
                                if calendarManager.syncedEventCount > 0 {
                                    Button {
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Label("Undo Sync (\(calendarManager.syncedEventCount))", systemImage: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .disabled(calendarManager.isSyncing)
                                }

                                Button {
                                    showingSyncSheet = true
                                } label: {
                                    if calendarManager.isSyncing {
                                        ProgressView()
                                    } else {
                                        Label("Sync to Calendar", systemImage: "calendar.badge.plus")
                                    }
                                }
                                .disabled(calendarManager.isSyncing)
                            }
                        }
                    }
                    .alert("Sync Status", isPresented: $showingSyncAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(calendarManager.syncStatus ?? "Sync completed")
                    }
                    .confirmationDialog("Delete Synced Events", isPresented: $showingDeleteConfirmation) {
                        Button("Delete \(calendarManager.syncedEventCount) Events", role: .destructive) {
                            Task {
                                await calendarManager.deleteAllSyncedEvents()
                                showingSyncAlert = true
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will permanently delete all \(calendarManager.syncedEventCount) events that were synced from health data.")
                    }
                    .sheet(isPresented: $showingSyncSheet) {
                        SyncDateRangeView(
                            startDate: $syncStartDate,
                            endDate: $syncEndDate,
                            calendarManager: calendarManager,
                            healthKitManager: healthKitManager,
                            showingSyncAlert: $showingSyncAlert,
                            showingSyncSheet: $showingSyncSheet
                        )
                    }
                }
            }
        }
    }

    private func dateRangeString(from startDate: Date, to endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let calendar = Calendar.current
        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return formatter.string(from: startDate)
        } else {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }

    private func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadData(for category: HealthKitManager.HealthCategory) async {
        if let index = healthKitManager.healthCategories.firstIndex(where: { $0.id == category.id }) {
            healthKitManager.healthCategories[index].isLoading = true

            let data = await healthKitManager.fetchSampleData(for: category)

            healthKitManager.healthCategories[index].sampleData = data
            healthKitManager.healthCategories[index].isLoading = false
        }
    }
}

struct SyncDateRangeView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var showingSyncAlert: Bool
    @Binding var showingSyncSheet: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                } header: {
                    Text("Select Date Range")
                } footer: {
                    Text("Choose the date range for health data to sync to your calendar.")
                }

                if !calendarManager.availableCalendars.isEmpty {
                    Section {
                        Picker("Calendar", selection: $calendarManager.selectedCalendar) {
                            ForEach(calendarManager.availableCalendars, id: \.calendarIdentifier) { calendar in
                                HStack {
                                    Circle()
                                        .fill(Color(cgColor: calendar.cgColor))
                                        .frame(width: 12, height: 12)
                                    Text(calendar.title)
                                }
                                .tag(calendar as EKCalendar?)
                            }
                        }
                    } header: {
                        Text("Destination Calendar")
                    } footer: {
                        Text("Choose which calendar to add health events to.")
                    }
                }

                if let existingSync = calendarManager.isDateRangeSynced(from: startDate, to: endDate) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Already Synced", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.headline)

                            Text("This date range was synced on \(formattedDate(existingSync.syncedAt))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("\(existingSync.eventCount) events created")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button {
                        Task {
                            if !calendarManager.isAuthorized {
                                await calendarManager.requestCalendarAccess()
                            }
                            if calendarManager.isAuthorized {
                                await calendarManager.syncHealthDataToCalendar(
                                    healthManager: healthKitManager,
                                    from: startDate,
                                    to: endDate
                                )
                                showingSyncAlert = true
                                showingSyncSheet = false
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if calendarManager.isSyncing {
                                ProgressView()
                            } else {
                                Text("Sync to Calendar")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(calendarManager.isSyncing || calendarManager.isDateRangeSynced(from: startDate, to: endDate) != nil)
                }
            }
            .navigationTitle("Sync Health Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSyncSheet = false
                    }
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
