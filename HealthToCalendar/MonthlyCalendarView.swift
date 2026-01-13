//
//  MonthlyCalendarView.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/12/26.
//

import SwiftUI

enum TimeRange: String, CaseIterable {
    case threeDays = "3 Days"
    case oneWeek = "1 Week"
    case twoWeeks = "2 Weeks"
    case oneMonth = "1 Month"

    var days: Int {
        switch self {
        case .threeDays: return 3
        case .oneWeek: return 7
        case .twoWeeks: return 14
        case .oneMonth: return 30
        }
    }

    var displayName: String {
        rawValue
    }
}

struct MonthlyCalendarView: View {
    let syncedDays: Set<Date>
    let daysWithData: Set<Date>
    @Binding var selectedDate: Date?
    var startDate: Date? = nil
    var endDate: Date? = nil
    var timeRange: TimeRange? = nil

    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 12) {
            // Days of week
            HStack(spacing: 0) {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            // Calendar grid - 2 weeks
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(calendarDays, id: \.self) { date in
                    let normalizedDate = normalizeDate(date)
                    let isFutureDate = normalizedDate > calendar.startOfDay(for: Date())
                    let isSynced = syncedDays.contains(normalizedDate)
                    let hasData = daysWithData.contains(normalizedDate)
                    let isCurrentlySelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)

                    DayCell(
                        date: date,
                        isSynced: isSynced,
                        hasData: hasData,
                        isToday: calendar.isDateInToday(date),
                        isSelected: isCurrentlySelected,
                        isFuture: isFutureDate
                    )
                    .onTapGesture {
                        // Don't allow selection of future dates or dates without data
                        if !isFutureDate && hasData {
                            // Toggle selection: if already selected, deselect it
                            if let currentSelection = selectedDate,
                               calendar.isDate(currentSelection, inSameDayAs: normalizedDate) {
                                selectedDate = nil
                            } else {
                                selectedDate = normalizedDate
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dayCellAccessibilityLabel(for: normalizedDate, isFuture: isFutureDate, isSynced: isSynced, hasData: hasData, isToday: calendar.isDateInToday(date), isSelected: isCurrentlySelected))
                    .accessibilityHint(dayCellAccessibilityHint(for: normalizedDate, isFuture: isFutureDate, hasData: hasData))
                    .accessibilityAddTraits(dayCellAccessibilityTraits(isFuture: isFutureDate, hasData: hasData, isSelected: isCurrentlySelected))
                    .accessibilityIdentifier("dayCell_\(dateIdentifier(normalizedDate))")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Calendar showing \(calendarDays.count) days")
        }
    }

    private func dayCellAccessibilityLabel(for date: Date, isFuture: Bool, isSynced: Bool, hasData: Bool, isToday: Bool, isSelected: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let dateString = formatter.string(from: date)

        var status = ""
        if isFuture {
            status = "Future date"
        } else if isSynced {
            status = "Synced"
        } else if hasData {
            status = "Has data, not synced"
        } else {
            status = "No data"
        }

        let todayString = isToday ? ", Today" : ""
        let selectedString = isSelected ? ", Selected" : ""

        return "\(dateString)\(todayString)\(selectedString). \(status)"
    }

    private func dayCellAccessibilityHint(for date: Date, isFuture: Bool, hasData: Bool) -> String {
        if isFuture {
            return "Future date, not selectable"
        } else if hasData {
            return "Double tap to view health data for this day"
        } else {
            return "No health data recorded"
        }
    }

    private func dayCellAccessibilityTraits(isFuture: Bool, hasData: Bool, isSelected: Bool) -> AccessibilityTraits {
        var traits: AccessibilityTraits = []
        if !isFuture && hasData {
            traits.insert(.isButton)
        }
        if isSelected {
            traits.insert(.isSelected)
        }
        return traits
    }

    private func dateIdentifier(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private var dateRangeString: String {
        let days = calendarDays
        guard let firstDay = days.first, let lastDay = days.last else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "MMM d, yyyy"

        // If same month, show "Jan 1 - 14, 2026"
        if calendar.isDate(firstDay, equalTo: lastDay, toGranularity: .month) {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "d"
            return "\(formatter.string(from: firstDay)) - \(dayFormatter.string(from: lastDay)), \(calendar.component(.year, from: lastDay))"
        } else {
            // Different months: "Dec 31 - Jan 14"
            return "\(formatter.string(from: firstDay)) - \(formatter.string(from: lastDay))"
        }
    }

    private var calendarDays: [Date] {
        // Use provided date range or default to 14 days ending with tomorrow
        var effectiveEndDate: Date
        var effectiveStartDate: Date

        if let end = endDate, let start = startDate {
            effectiveEndDate = end
            effectiveStartDate = start
        } else {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
            effectiveEndDate = tomorrow
            effectiveStartDate = calendar.date(byAdding: .day, value: -13, to: tomorrow)!
        }

        // Adjust based on time range
        if let range = timeRange {
            switch range {
            case .threeDays:
                // Fill out to show a complete week row
                // Find the start of the week for the first day
                let weekdayOfStart = calendar.component(.weekday, from: effectiveStartDate)
                let daysToSubtract = weekdayOfStart - 1 // Sunday is 1
                effectiveStartDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: effectiveStartDate)!

                // Find the end of the week for the last day
                let lastDay = calendar.date(byAdding: .day, value: -1, to: effectiveEndDate)!
                let weekdayOfEnd = calendar.component(.weekday, from: lastDay)
                let daysToAdd = 7 - weekdayOfEnd // Saturday is 7
                effectiveEndDate = calendar.date(byAdding: .day, value: daysToAdd + 1, to: lastDay)!

            case .oneWeek:
                // No adjustment needed - already showing 7 days
                break

            default:
                break
            }
        }

        // Calculate the number of days in the range
        let dayCount = calendar.dateComponents([.day], from: effectiveStartDate, to: effectiveEndDate).day ?? 14

        return (0..<dayCount).map { offset in
            calendar.date(byAdding: .day, value: offset, to: effectiveStartDate)!
        }
    }

    private func normalizeDate(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

struct DayCell: View {
    let date: Date
    let isSynced: Bool
    let hasData: Bool
    let isToday: Bool
    let isSelected: Bool
    var isFuture: Bool = false

    private let calendar = Calendar.current

    private var syncState: SyncState {
        if isSynced {
            return .synced
        } else if hasData {
            return .notSynced
        } else {
            return .empty
        }
    }

    enum SyncState {
        case synced
        case notSynced
        case empty

        var color: Color {
            switch self {
            case .synced: return .green
            case .notSynced: return .orange
            case .empty: return .gray
            }
        }
    }

    var body: some View {
        // Date number with colored circle around it
        ZStack {
            // Selection background - wraps tightly around circle
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .frame(width: 36, height: 36)
            }

            // Circle frame with sync status indicator
            ZStack {
                Circle()
                    .strokeBorder(circleColor, lineWidth: isSelected ? 2.5 : 2)
                    .frame(width: 28, height: 28)

                // Differentiate Without Color: Add icon indicators for sync status
                if !isSelected && syncState == .synced {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                        .offset(x: 12, y: -12)
                }

                if !isSelected && syncState == .notSynced {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .offset(x: 12, y: -12)
                }
            }

            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .opacity(isFuture || !hasData ? 0.5 : 1.0)
    }

    private var circleColor: Color {
        if isSelected {
            // Show status color when selected (white for empty state)
            return syncState != .empty ? syncState.color : .white
        } else if syncState != .empty {
            return syncState.color
        } else if isToday {
            return Color.primary.opacity(0.3)
        } else {
            return .clear
        }
    }
}

#Preview {
    @Previewable @State var selectedDate: Date? = nil

    MonthlyCalendarView(
        syncedDays: Set([
            Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ].map { Calendar.current.startOfDay(for: $0) }),
        daysWithData: Set([
            Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            Date()
        ].map { Calendar.current.startOfDay(for: $0) }),
        selectedDate: $selectedDate,
        timeRange: .threeDays
    )
    .padding()
}
