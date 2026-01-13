//
//  HealthCategoryViews.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/12/26.
//

import SwiftUI
import HealthKit
import Charts

struct HealthCategoryCard: View {
    let category: HealthKitManager.HealthCategory
    var monthlyStats: MonthlyStats? = nil
    var isDisabled: Bool = false
    let onTap: () -> Void

    private var accessibilityLabelText: String {
        if category.isLoading {
            return "\(category.name), loading"
        } else if let stats = monthlyStats {
            let value = category.shouldAggregateDaily ? stats.formattedTotal : stats.formattedAverage
            return "\(category.name), \(value) \(stats.unitName)"
        } else if !category.sampleData.isEmpty {
            return "\(category.name), data available"
        } else {
            return "\(category.name), no data"
        }
    }

    var body: some View {
        Button(action: {
            if !isDisabled {
                onTap()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(category.emoji)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text(category.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if category.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let stats = monthlyStats {
                    if category.shouldAggregateDaily {
                        Text("\(stats.formattedTotal)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    } else {
                        Text("\(stats.formattedAverage)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                } else if !category.sampleData.isEmpty {
                    Text("View")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                } else {
                    Text("--")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            .opacity(isDisabled ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(isDisabled ? "No data available" : "Double tap to view details")
        .accessibilityIdentifier("healthCategory_\(category.name)")
        .accessibilityAddTraits(isDisabled ? [] : .isButton)
    }
}

struct MonthlySummaryHeader: View {
    let monthName: String
    let daysWithData: Int
    let totalCategories: Int
    let isLoading: Bool
    var aiSummary: String? = nil
    var isGeneratingAI: Bool = false
    var onGenerateAI: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(monthName) Summary")
                        .font(.headline)
                    if isLoading {
                        Text("Loading stats...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(daysWithData) days tracked \u{2022} \(totalCategories) categories")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // AI Summary
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text("Monthly Insights")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Spacer()

                    if totalCategories > 0, let onGenerateAI = onGenerateAI {
                        Button {
                            onGenerateAI()
                        } label: {
                            if isGeneratingAI {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text(aiSummary == nil ? "Generate" : "Regenerate")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingAI)
                    }
                }

                if let summary = aiSummary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                } else if totalCategories == 0 {
                    Text("No health data to summarize")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text("Tap Generate for AI insights on your monthly health trends")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.top, 12)
        }
    }
}

struct SampleBarChart: View {
    let chartData: [ChartDataPoint]
    let unitName: String
    let isHourly: Bool
    var authoritativeTotal: String? = nil  // Use this instead of computing from chart data

    @State private var selectedDate: Date? = nil

    private var selectedDataPoint: ChartDataPoint? {
        guard let selectedDate = selectedDate else { return nil }
        let calendar = Calendar.current
        return chartData.first { dataPoint in
            if isHourly {
                return calendar.isDate(dataPoint.date, equalTo: selectedDate, toGranularity: .hour)
            } else {
                return calendar.isDate(dataPoint.date, equalTo: selectedDate, toGranularity: .day)
            }
        }
    }

    // Fixed Y-axis scale to prevent rescaling on selection
    private var yAxisMax: Double {
        let maxValue = chartData.map { $0.value }.max() ?? 0
        // Add 10% padding at top
        return maxValue * 1.1
    }

    private var chartAccessibilityLabel: String {
        let total = authoritativeTotal ?? formatValue(chartData.reduce(0) { $0 + $1.value })
        let peak = formatValue(chartData.map { $0.value }.max() ?? 0)
        let activeCount = chartData.filter { $0.value > 0 }.count
        let periodType = isHourly ? "hours" : "days"
        return "Bar chart showing \(unitName). Total: \(total). Peak: \(peak). Active \(periodType): \(activeCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chartData.isEmpty || chartData.allSatisfy({ $0.value == 0 }) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("No data in this period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Chart: No data available for this period")
            } else {
                // Selection info displayed above chart
                HStack {
                    Spacer()
                    if let selected = selectedDataPoint, selected.value > 0 {
                        HStack(spacing: 4) {
                            Text(formatValue(selected.value))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(formatTimeLabel(selected.date))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }
                .frame(height: 28)

                Chart(chartData) { dataPoint in
                    BarMark(
                        x: .value("Time", dataPoint.date, unit: isHourly ? .hour : .day),
                        y: .value("Value", dataPoint.value)
                    )
                    .foregroundStyle(barColor(for: dataPoint))
                    .cornerRadius(isHourly ? 2 : 4)
                }
                .chartXSelection(value: $selectedDate)
                .chartYScale(domain: 0...yAxisMax)
                .chartXAxis {
                    if isHourly {
                        AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        }
                    } else {
                        AxisMarks(values: .stride(by: .day, count: max(1, chartData.count / 7))) { value in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day())
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .frame(height: 200)
                .accessibilityLabel(chartAccessibilityLabel)
                .accessibilityHint("Interactive chart. Swipe to explore data points")

                // Summary stats - use authoritative total if provided
                let computedTotal = chartData.reduce(0) { $0 + $1.value }
                let nonZeroCount = chartData.filter { $0.value > 0 }.count
                let maxValue = chartData.map { $0.value }.max() ?? 0

                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(authoritativeTotal ?? formatValue(computedTotal))
                            .font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Total: \(authoritativeTotal ?? formatValue(computedTotal)) \(unitName)")

                    VStack(alignment: .leading) {
                        Text("Peak")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatValue(maxValue))
                            .font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Peak: \(formatValue(maxValue)) \(unitName)")

                    VStack(alignment: .leading) {
                        Text(isHourly ? "Active Hours" : "Active Days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(nonZeroCount)")
                            .font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(isHourly ? "Active hours" : "Active days"): \(nonZeroCount)")

                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    private func barColor(for dataPoint: ChartDataPoint) -> AnyGradient {
        if let selected = selectedDataPoint, selected.id == dataPoint.id {
            return Color.blue.gradient
        }
        return dataPoint.value > 0 ? Color.blue.opacity(0.6).gradient : Color.gray.opacity(0.3).gradient
    }

    private func formatTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        if isHourly {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }

    private func formatValue(_ value: Double) -> String {
        if value >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        } else if value == floor(value) {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }
}

struct HealthCategoryDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let category: HealthKitManager.HealthCategory
    let healthKitManager: HealthKitManager
    let selectedDate: Date?
    let periodStats: MonthlyStats?  // Pre-computed stats from main view for consistency

    @State private var chartData: [ChartDataPoint] = []
    @State private var isLoadingChart = true

    private var isDaily: Bool {
        selectedDate != nil
    }

    private var dateRangeDescription: String {
        if let date = selectedDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        } else {
            return "Past 14 Days"
        }
    }

    private var unitName: String {
        if let quantityType = category.dataType as? HKQuantityType {
            return healthKitManager.getFriendlyUnitName(for: quantityType)
        } else if category.dataType is HKCategoryType {
            return "min"
        } else if category.dataType is HKWorkoutType {
            return "workouts"
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with icon
                    HStack {
                        Text(category.emoji)
                            .font(.largeTitle)
                            .accessibilityHidden(true)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(dateRangeDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(isDaily ? "24 Hours" : "14 Days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(category.name) details for \(dateRangeDescription), showing \(isDaily ? "24 hour" : "14 day") view")

                    // Bar Chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isDaily ? "Activity by Hour" : "Activity by Day")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .accessibilityAddTraits(.isHeader)

                        if isLoadingChart {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .accessibilityLabel("Loading chart data")
                                Spacer()
                            }
                            .frame(height: 200)
                        } else {
                            SampleBarChart(
                                chartData: chartData,
                                unitName: unitName,
                                isHourly: isDaily,
                                authoritativeTotal: periodStats?.formattedTotal
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Close \(category.name) details")
                    .accessibilityIdentifier("doneButton_\(category.name)")
                }
            }
            .task {
                await loadChartData()
            }
        }
    }

    private func loadChartData() async {
        isLoadingChart = true

        let calendar = Calendar.current
        let startDate: Date
        let endDate: Date

        if let date = selectedDate {
            // Daily view: show 24 hours for the selected day
            startDate = calendar.startOfDay(for: date)
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
        } else {
            // Monthly view: show past 14 days
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
            startDate = calendar.date(byAdding: .day, value: -13, to: tomorrow)!
            endDate = tomorrow
        }

        let data = await healthKitManager.fetchChartData(
            for: category,
            from: startDate,
            to: endDate,
            isDaily: isDaily
        )

        await MainActor.run {
            chartData = data
            isLoadingChart = false
        }
    }
}

#Preview("Category Card") {
    HealthCategoryCard(
        category: HealthKitManager.HealthCategory(
            name: "Steps",
            dataType: HKObjectType.quantityType(forIdentifier: .stepCount)!,
            emoji: "👟",
            shouldAggregateDaily: true,
            sampleData: ["1/11/26, 10:00 AM: 8234.00 count"],
            isLoading: false
        ),
        onTap: {}
    )
    .padding()
}

#Preview("Bar Chart") {
    SampleBarChart(
        chartData: [
            ChartDataPoint(date: Date().addingTimeInterval(-3600 * 5), value: 1200, label: "7AM"),
            ChartDataPoint(date: Date().addingTimeInterval(-3600 * 4), value: 800, label: "8AM"),
            ChartDataPoint(date: Date().addingTimeInterval(-3600 * 3), value: 0, label: "9AM"),
            ChartDataPoint(date: Date().addingTimeInterval(-3600 * 2), value: 2500, label: "10AM"),
            ChartDataPoint(date: Date().addingTimeInterval(-3600 * 1), value: 1800, label: "11AM"),
            ChartDataPoint(date: Date(), value: 950, label: "12PM")
        ],
        unitName: "steps",
        isHourly: true
    )
    .padding()
}
