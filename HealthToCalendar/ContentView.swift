//
//  ContentView.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/11/26.
//

import SwiftUI
import HealthKit
import EventKit
import FoundationModels

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var calendarManager = CalendarManager()
    @State private var selectedCategory: HealthKitManager.HealthCategory?
    @State private var showingSyncAlert = false
    @State private var showingSyncSheet = false
    @State private var syncStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var syncEndDate = Date()
    @State private var daysWithData: Set<Date> = []
    @State private var selectedDate: Date? = nil
    @State private var aiSummary: String? = nil
    @State private var isGeneratingAI = false
    @State private var monthlySummary: MonthlySummaryData? = nil
    @State private var isLoadingMonthlySummary = false
    @State private var monthlyCategoryStats: [String: MonthlyStats] = [:]
    @State private var dailyCategoryStats: [String: MonthlyStats] = [:]
    @State private var isLoadingDailyData = false

    // Time range navigation
    @State private var selectedTimeRange: TimeRange = .twoWeeks
    @State private var timeRangeOffset: Int = 0  // 0 = current, -1 = previous period, etc.
    @State private var pendingTimeRange: TimeRange? = nil

    // Persistence for AI summaries
    private let summaryStorage = AISummaryStorage.shared

    // Session cache for AI summaries (keyed by date range)
    @State private var periodSummaryCache: [String: String] = [:]

    private func periodSummaryCacheKey(from startDate: Date, to endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: startDate))_\(formatter.string(from: endDate))"
    }

    // Computed properties for date range
    private var currentEndDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        if timeRangeOffset == 0 {
            return tomorrow
        } else {
            // Go back by offset * days
            return calendar.date(byAdding: .day, value: timeRangeOffset * selectedTimeRange.days, to: tomorrow)!
        }
    }

    private var currentStartDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -selectedTimeRange.days, to: currentEndDate)!
    }

    private var canGoForward: Bool {
        timeRangeOffset < 0
    }

    private var unsyncedDaysInRange: Set<Date> {
        let syncedDays = calendarManager.getSyncedDays()
        return daysWithData.subtracting(syncedDays)
    }

    private var dateRangeDisplayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let calendar = Calendar.current
        let endDisplayDate = calendar.date(byAdding: .day, value: -1, to: currentEndDate)!

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: endDisplayDate)

        return "\(formatter.string(from: currentStartDate)) - \(formatter.string(from: endDisplayDate)), \(year)"
    }

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
                    ScrollView {
                        VStack(spacing: 20) {
                            // Date header with dropdown and date range
                            HStack(spacing: 6) {
                                // Time range dropdown menu
                                Menu {
                                    ForEach(TimeRange.allCases, id: \.self) { range in
                                        Button {
                                            pendingTimeRange = range
                                            Task { @MainActor in
                                                try? await Task.sleep(nanoseconds: 200_000_000)
                                                if let pending = pendingTimeRange {
                                                    selectedTimeRange = pending
                                                    timeRangeOffset = 0
                                                    pendingTimeRange = nil
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(range.displayName)
                                                if selectedTimeRange == range {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(selectedTimeRange.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Text(dateRangeDisplayString)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Spacer()

                                HStack(spacing: 16) {
                                    Button {
                                        timeRangeOffset -= 1
                                    } label: {
                                        Image(systemName: "chevron.left")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }

                                    Button {
                                        timeRangeOffset += 1
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .font(.body)
                                            .foregroundColor(canGoForward ? .primary : .secondary.opacity(0.5))
                                    }
                                    .disabled(!canGoForward)
                                }
                            }
                            .padding(.horizontal)

                            // Monthly Calendar
                            MonthlyCalendarView(
                                syncedDays: calendarManager.getSyncedDays(),
                                daysWithData: daysWithData,
                                selectedDate: $selectedDate,
                                startDate: currentStartDate,
                                endDate: currentEndDate,
                                timeRange: selectedTimeRange
                            )
                            .padding(.horizontal)
                            .task(id: "\(selectedTimeRange)-\(timeRangeOffset)") {
                                await loadDaysWithData()
                            }

                            // Summary (when no date selected)
                            if selectedDate == nil {
                                VStack(alignment: .leading, spacing: 0) {
                                    // AI Summary Section
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: "sparkles")
                                                .foregroundColor(.purple)
                                            Text("\(selectedTimeRange.displayName) Summary")
                                                .font(.headline)
                                                .foregroundColor(.secondary)

                                            Spacer()

                                            if !daysWithData.isEmpty && aiSummary != nil {
                                                Button {
                                                    Task {
                                                        await generateMonthlySummary(forceRegenerate: true)
                                                    }
                                                } label: {
                                                    if isGeneratingAI {
                                                        ProgressView()
                                                            .scaleEffect(0.8)
                                                    } else {
                                                        Image(systemName: "arrow.clockwise")
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(isGeneratingAI)
                                            }
                                        }

                                        if isGeneratingAI {
                                            HStack {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                Text("Generating summary...")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }
                                        } else if let summary = aiSummary {
                                            Text(summary)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                        } else if daysWithData.isEmpty {
                                            Text("No health data in this period")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        } else {
                                            Text("Loading summary...")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                    }
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                }
                            }

                            // Selected Date Details
                            if let selectedDate = selectedDate {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(formattedSelectedDate(selectedDate))
                                                .font(.headline)
                                            if calendarManager.getSyncedDays().contains(selectedDate) {
                                                Label("Synced", systemImage: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            } else {
                                                Label("Unsynced", systemImage: "circle.dashed")
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                            }
                                        }

                                        Spacer()

                                        Button {
                                            self.selectedDate = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal)

                                    // AI Summary
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: "sparkles")
                                                .foregroundColor(.purple)
                                            Text("Daily Summary")
                                                .font(.headline)
                                                .foregroundColor(.secondary)

                                            Spacer()

                                            if !filteredHealthCategories().isEmpty && aiSummary != nil {
                                                Button {
                                                    Task {
                                                        await generateAISummary(for: selectedDate, forceRegenerate: true)
                                                    }
                                                } label: {
                                                    if isGeneratingAI {
                                                        ProgressView()
                                                            .scaleEffect(0.8)
                                                    } else {
                                                        Image(systemName: "arrow.clockwise")
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(isGeneratingAI)
                                            }
                                        }

                                        if isGeneratingAI {
                                            HStack {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                Text("Generating summary...")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }
                                        } else if let summary = aiSummary {
                                            Text(summary)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                        } else if filteredHealthCategories().isEmpty {
                                            Text("No health data to summarize")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        } else {
                                            Text("Loading summary...")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .italic()
                                        }
                                    }
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                    .padding(.top, 12)
                                }
                            }

                            // 2-Column Grid Layout
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(filteredHealthCategories()) { category in
                                    HealthCategoryCard(
                                        category: category,
                                        monthlyStats: selectedDate == nil ? monthlyCategoryStats[category.name] : dailyCategoryStats[category.name],
                                        isDisabled: selectedDate == nil && monthlyCategoryStats[category.name] == nil
                                    ) {
                                        Task {
                                            await loadData(for: category)
                                            selectedCategory = category
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 20)

                            if selectedDate != nil && isLoadingDailyData {
                                VStack(spacing: 12) {
                                    ProgressView()
                                    Text("Loading health data...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            } else if selectedDate != nil && filteredHealthCategories().isEmpty && !isLoadingDailyData {
                                VStack(spacing: 12) {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                    Text("No health data for this day")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }

                            // Action Buttons (below category cards)
                            if let selectedDate = selectedDate {
                                HStack(spacing: 12) {
                                    Button {
                                        shareHealthData(for: selectedDate)
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        if let url = URL(string: "x-apple-health://") {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        Label("Open Health", systemImage: "heart.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 20)
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if !daysWithData.isEmpty {
                            let unsyncedCount = unsyncedDaysInRange.count
                            if unsyncedCount > 0 {
                                Button {
                                    if let minDate = unsyncedDaysInRange.min(),
                                       let maxDate = unsyncedDaysInRange.max() {
                                        syncStartDate = minDate
                                        syncEndDate = maxDate
                                    }
                                    showingSyncSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "calendar.badge.plus")
                                        Text("Sync \(unsyncedCount) Day\(unsyncedCount == 1 ? "" : "s")")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(calendarManager.isSyncing)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            }
                        }
                    }
                    .navigationTitle("Health to Calendar")
                    .toolbar {
                        if timeRangeOffset != 0 {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button {
                                    timeRangeOffset = 0
                                } label: {
                                    Text("Today")
                                }
                            }
                        }
                    }
                    .alert("Sync Status", isPresented: $showingSyncAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(calendarManager.syncStatus ?? "Sync completed")
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
                    .sheet(item: $selectedCategory) { category in
                        HealthCategoryDetailSheet(
                            category: category,
                            healthKitManager: healthKitManager,
                            selectedDate: selectedDate,
                            periodStats: selectedDate == nil ? monthlyCategoryStats[category.name] : dailyCategoryStats[category.name]
                        )
                    }
                    .onChange(of: selectedDate) { oldValue, newValue in
                        Task {
                            if let date = newValue {
                                // Load persisted summary for this date
                                aiSummary = summaryStorage.getSummary(for: date)
                                await loadDataForSelectedDate()
                                // Auto-generate if no summary exists
                                if aiSummary == nil && !filteredHealthCategories().isEmpty {
                                    await generateAISummary(for: date, forceRegenerate: false)
                                }
                            } else {
                                // Clear and reload for the new time range
                                aiSummary = nil
                                await loadMonthlyData()
                                // Load from cache or generate summary
                                if !daysWithData.isEmpty {
                                    await generateMonthlySummary(forceRegenerate: false)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedTimeRange) { oldValue, newValue in
                        // Reset selection-related state; offset is set when applying pendingTimeRange
                        selectedDate = nil
                        aiSummary = nil
                        Task { @MainActor in
                            // Let the menu dismiss before starting heavy work
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await loadMonthlyData()
                            if !daysWithData.isEmpty {
                                await generateMonthlySummary(forceRegenerate: false)
                            }
                        }
                    }
                    .onChange(of: timeRangeOffset) { oldValue, newValue in
                        selectedDate = nil
                        aiSummary = nil
                        Task { @MainActor in
                            // Small delay to avoid blocking gesture/UI animations
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await loadMonthlyData()
                            if !daysWithData.isEmpty {
                                await generateMonthlySummary(forceRegenerate: false)
                            }
                        }
                    }
                    .task {
                        // Load data on initial view appearance
                        if selectedDate == nil {
                            await loadDaysWithData()
                            await loadMonthlyData()
                            // Auto-generate if no summary exists
                            if aiSummary == nil && !daysWithData.isEmpty {
                                await generateMonthlySummary(forceRegenerate: false)
                            }
                        }
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

    private func loadDaysWithData() async {
        let days = await healthKitManager.getDaysWithData(from: currentStartDate, to: currentEndDate)
        daysWithData = days
    }

    private func filteredHealthCategories() -> [HealthKitManager.HealthCategory] {
        if selectedDate == nil {
            // When no date is selected, show all categories (they will be displayed as disabled)
            return healthKitManager.healthCategories
        }

        // Filter categories that have data on the selected date
        return healthKitManager.healthCategories.filter { category in
            !category.sampleData.isEmpty
        }
    }

    private func loadDataForSelectedDate() async {
        guard let selectedDate = selectedDate else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Clear previous daily stats and set loading state
        await MainActor.run {
            dailyCategoryStats = [:]
            isLoadingDailyData = true
        }

        for (index, category) in healthKitManager.healthCategories.enumerated() {
            await MainActor.run {
                healthKitManager.healthCategories[index].isLoading = true
            }

            // Fetch samples for display
            let samples = await healthKitManager.fetchDetailedSampleData(
                for: category,
                from: startOfDay,
                to: endOfDay
            )

            // Fetch daily stats for the card
            let stats = await healthKitManager.fetchPeriodStats(
                for: category,
                from: startOfDay,
                to: endOfDay
            )

            await MainActor.run {
                if let stats = stats {
                    dailyCategoryStats[category.name] = stats
                }

                // Format sample data for display - or clear if no data
                if samples.isEmpty {
                    healthKitManager.healthCategories[index].sampleData = []
                } else {
                    let sampleStrings = samples.map { sample in
                        let dateFormatter = DateFormatter()
                        dateFormatter.timeStyle = .short
                        if sample.isAllDay {
                            return sample.details
                        } else {
                            return "\(dateFormatter.string(from: sample.startDate)): \(sample.details)"
                        }
                    }
                    healthKitManager.healthCategories[index].sampleData = sampleStrings
                }

                healthKitManager.healthCategories[index].isLoading = false
            }
        }

        await MainActor.run {
            isLoadingDailyData = false
        }
    }

    private func formattedSelectedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return formatter.string(from: date)
        }
    }

    private func shareHealthData(for date: Date) {
        // Prepare share data
        var shareText = "Health Data for \(formattedSelectedDate(date))\n\n"

        for category in filteredHealthCategories() {
            if !category.sampleData.isEmpty {
                shareText += "\(category.emoji) \(category.name)\n"
                if let firstSample = category.sampleData.first {
                    shareText += "  \(firstSample)\n"
                }
                shareText += "\n"
            }
        }

        // Show share sheet
        let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func generateAISummary(for date: Date, forceRegenerate: Bool = false) async {
        // Check if we already have a persisted summary and shouldn't regenerate
        if !forceRegenerate, let existingSummary = summaryStorage.getSummary(for: date) {
            await MainActor.run {
                aiSummary = existingSummary
            }
            return
        }

        isGeneratingAI = true
        defer { isGeneratingAI = false }

        do {
            let summary = try await generateOnDeviceSummary()
            await MainActor.run {
                aiSummary = summary
                // Persist the summary
                summaryStorage.saveSummary(summary, for: date)
            }
        } catch {
            await MainActor.run {
                aiSummary = "Unable to generate summary: \(error.localizedDescription)"
            }
        }
    }

    private func generateOnDeviceSummary() async throws -> String {
        let categories = filteredHealthCategories()
        guard !categories.isEmpty else {
            return "No health data available for this day."
        }

        // Prepare health data summary for the AI
        var healthDataText = ""
        for category in categories {
            if !category.sampleData.isEmpty {
                let data = category.sampleData.first ?? ""
                healthDataText += "\(category.emoji) \(category.name): \(data)\n"
            }
        }

        // Create prompt for Apple Intelligence
        let prompt = """
        Based on this health data, write a brief 1-2 sentence encouraging summary highlighting the most important activities and achievements:

        \(healthDataText)

        Be specific with numbers, friendly, and encouraging. Focus on the most significant metrics.
        """

        // Use Apple's Foundation Models
        let response = try await LanguageModelSession().respond(to: prompt)

        // Extract text from response
        let trimmedResponse = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !trimmedResponse.isEmpty {
            return trimmedResponse
        } else {
            // Fallback if AI doesn't return anything
            return "You tracked \(categories.count) health metrics today. Great job staying active!"
        }
    }

    private func extractNumericValue(from text: String) -> Double? {
        // Extract first numeric value from text like "1,234.5 steps"
        let pattern = "[0-9,]+(\\.[0-9]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        let numericString = String(text[range]).replacingOccurrences(of: ",", with: "")
        return Double(numericString)
    }

    private func loadMonthlyData() async {
        isLoadingMonthlySummary = true
        defer { isLoadingMonthlySummary = false }

        // Fetch data for all categories for the selected period
        var categoryStats: [CategoryStat] = []
        var topMetrics: [TopMetric] = []
        var newMonthlyCategoryStats: [String: MonthlyStats] = [:]

        for category in healthKitManager.healthCategories {
            // Fetch stats for the selected period
            if let stats = await healthKitManager.fetchPeriodStats(for: category, from: currentStartDate, to: currentEndDate) {
                categoryStats.append(CategoryStat(
                    name: category.name,
                    emoji: category.emoji,
                    sampleCount: stats.daysWithData
                ))

                newMonthlyCategoryStats[category.name] = stats

                // Add to top metrics for aggregated categories
                if category.shouldAggregateDaily {
                    topMetrics.append(TopMetric(
                        name: category.name,
                        emoji: category.emoji,
                        value: "\(stats.formattedTotal) \(stats.unitName)"
                    ))
                }
            }
        }

        // Sort top metrics by priority (steps, calories, distance)
        topMetrics.sort { metric1, metric2 in
            let priority1 = getMetricPriority(metric1.name)
            let priority2 = getMetricPriority(metric2.name)
            return priority1 < priority2
        }

        await MainActor.run {
            monthlySummary = MonthlySummaryData(
                totalDaysWithData: daysWithData.count,
                totalCategories: categoryStats.count,
                categoryStats: categoryStats,
                topMetrics: Array(topMetrics.prefix(5))
            )
            monthlyCategoryStats = newMonthlyCategoryStats
        }
    }

    private func generateMonthlySummary(forceRegenerate: Bool = false) async {
        let cacheKey = periodSummaryCacheKey(from: currentStartDate, to: currentEndDate)

        // Check session cache first (fastest)
        if !forceRegenerate, let cachedSummary = periodSummaryCache[cacheKey] {
            await MainActor.run {
                aiSummary = cachedSummary
            }
            return
        }

        // Check persisted storage
        if !forceRegenerate, let existingSummary = summaryStorage.getMonthlySummary() {
            await MainActor.run {
                aiSummary = existingSummary
                periodSummaryCache[cacheKey] = existingSummary
            }
            return
        }

        isGeneratingAI = true
        defer { isGeneratingAI = false }

        guard let summary = monthlySummary else {
            await MainActor.run {
                aiSummary = "No data available to summarize."
            }
            return
        }

        do {
            // Prepare data for AI
            var healthDataText = "Period: \(selectedTimeRange.displayName)\n"
            healthDataText += "Days with data: \(summary.totalDaysWithData)\n"
            healthDataText += "Metrics tracked: \(summary.totalCategories)\n\n"

            if !summary.topMetrics.isEmpty {
                healthDataText += "Top metrics:\n"
                for metric in summary.topMetrics {
                    healthDataText += "\(metric.emoji) \(metric.name): \(metric.value)\n"
                }
            }

            // Create prompt for Apple Intelligence
            let prompt = """
            Based on this \(selectedTimeRange.displayName.lowercased()) health data summary, write a brief 2-3 sentence encouraging overview of the health activities and achievements:

            \(healthDataText)

            Be specific with the numbers provided, friendly, and encouraging. Highlight the most significant accomplishments and provide motivation.
            """

            // Use Apple's Foundation Models
            let response = try await LanguageModelSession().respond(to: prompt)

            await MainActor.run {
                let trimmedResponse = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !trimmedResponse.isEmpty {
                    aiSummary = trimmedResponse
                    // Save to session cache and persist
                    periodSummaryCache[cacheKey] = trimmedResponse
                    summaryStorage.saveMonthlySummary(trimmedResponse)
                } else {
                    // Fallback
                    let fallback = "You tracked \(summary.totalCategories) health metrics across \(summary.totalDaysWithData) days in the past two weeks. Keep up the great work!"
                    aiSummary = fallback
                    periodSummaryCache[cacheKey] = fallback
                    summaryStorage.saveMonthlySummary(fallback)
                }
            }
        } catch {
            await MainActor.run {
                aiSummary = "Unable to generate summary: \(error.localizedDescription)"
            }
        }
    }

    private func getMetricPriority(_ name: String) -> Int {
        // Define priority order for displaying metrics
        // Names must match HealthKitManager.setupHealthCategories()
        switch name {
        case "Steps": return 0
        case "Active Cal": return 1
        case "Distance": return 2
        case "Exercise": return 3
        case "Calories": return 4
        case "Sleep": return 5
        case "Water": return 6
        default: return 99
        }
    }
}

struct MonthlySummaryData {
    let totalDaysWithData: Int
    let totalCategories: Int
    let categoryStats: [CategoryStat]
    let topMetrics: [TopMetric]
}

struct CategoryStat {
    let name: String
    let emoji: String
    let sampleCount: Int
}

struct TopMetric {
    let name: String
    let emoji: String
    let value: String
}

struct SyncDateRangeView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var showingSyncAlert: Bool
    @Binding var showingSyncSheet: Bool

    @State private var previewEvents: [CalendarEventPreview] = []
    @State private var isLoadingPreview = false
    @State private var groupedEvents: [(date: Date, events: [CalendarEventPreview])] = []

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

                // Preview Section
                Section {
                    if isLoadingPreview {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Loading preview...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    } else if previewEvents.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            Text("No health data in this date range")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(previewEvents.count) events will be added")
                                .font(.headline)

                            ForEach(groupedEvents.prefix(3), id: \.date) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(sectionHeaderString(for: group.date))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)

                                    ForEach(group.events.prefix(3)) { event in
                                        HStack(spacing: 8) {
                                            Text(event.emoji)
                                            Text(event.categoryName)
                                                .font(.subheadline)
                                            Spacer()
                                            Text(event.details)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, 8)
                                    }

                                    if group.events.count > 3 {
                                        Text("+ \(group.events.count - 3) more")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 8)
                                    }
                                }
                            }

                            if groupedEvents.count > 3 {
                                Text("+ \(groupedEvents.count - 3) more days")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Preview")
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
                                Text("Add to Calendar")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(calendarManager.isSyncing || calendarManager.isDateRangeSynced(from: startDate, to: endDate) != nil || previewEvents.isEmpty)
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
            .task(id: "\(startDate)-\(endDate)") {
                await loadPreview()
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func loadPreview() async {
        isLoadingPreview = true
        previewEvents = await calendarManager.fetchPreviewEvents(
            healthManager: healthKitManager,
            from: startDate,
            to: endDate
        )
        groupEventsByDate()
        isLoadingPreview = false
    }

    private func groupEventsByDate() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: previewEvents) { event -> Date in
            calendar.startOfDay(for: event.startDate)
        }
        groupedEvents = grouped.map { (date: $0.key, events: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func sectionHeaderString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return formatter.string(from: date)
        }
    }
}

// MARK: - AI Summary Storage

class AISummaryStorage {
    static let shared = AISummaryStorage()

    private let userDefaults = UserDefaults.standard
    private let dailySummaryPrefix = "ai_summary_daily_"
    private let monthlySummaryKey = "ai_summary_monthly"
    private let monthlySummaryDateKey = "ai_summary_monthly_date"

    private init() {}

    // Daily summaries - keyed by date
    func getSummary(for date: Date) -> String? {
        let key = dailySummaryKey(for: date)
        return userDefaults.string(forKey: key)
    }

    func saveSummary(_ summary: String, for date: Date) {
        let key = dailySummaryKey(for: date)
        userDefaults.set(summary, forKey: key)
    }

    private func dailySummaryKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return dailySummaryPrefix + formatter.string(from: date)
    }

    // Monthly/Two-week summary - stored with a timestamp to invalidate when data changes significantly
    func getMonthlySummary() -> String? {
        // Check if summary was generated today (to keep it fresh daily)
        guard let storedDate = userDefaults.object(forKey: monthlySummaryDateKey) as? Date else {
            return nil
        }

        let calendar = Calendar.current
        // Invalidate if not from today
        if !calendar.isDateInToday(storedDate) {
            return nil
        }

        return userDefaults.string(forKey: monthlySummaryKey)
    }

    func saveMonthlySummary(_ summary: String) {
        userDefaults.set(summary, forKey: monthlySummaryKey)
        userDefaults.set(Date(), forKey: monthlySummaryDateKey)
    }
}

#Preview {
    ContentView()
}

