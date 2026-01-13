//
//  HealthKitManager.swift
//  HealthToCalendar
//
//  Created by Kish Parikh on 1/11/26.
//

import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    let healthStore = HKHealthStore()

    @Published var healthCategories: [HealthCategory] = []
    @Published var isAuthorized = false
    @Published var authorizationError: String?

    private let hasCompletedOnboardingKey = "hasCompletedHealthKitOnboarding"

    // Session cache for period stats (avoids refetching when navigating back)
    private var periodStatsCache: [String: MonthlyStats] = [:]
    private var chartDataCache: [String: [ChartDataPoint]] = [:]

    private func periodStatsCacheKey(categoryName: String, from startDate: Date, to endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(categoryName)_\(formatter.string(from: startDate))_\(formatter.string(from: endDate))"
    }

    private func chartDataCacheKey(categoryName: String, from startDate: Date, to endDate: Date, isDaily: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(categoryName)_\(formatter.string(from: startDate))_\(formatter.string(from: endDate))_\(isDaily)"
    }

    func clearSessionCache() {
        periodStatsCache.removeAll()
        chartDataCache.removeAll()
    }

    struct HealthCategory: Identifiable, Equatable, Hashable {
        let id = UUID()
        let name: String
        let dataType: HKSampleType
        let emoji: String
        let shouldAggregateDaily: Bool
        var sampleData: [String] = []
        var isLoading = false

        static func == (lhs: HealthCategory, rhs: HealthCategory) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    init() {
        checkAvailability()

        // Check if user has already completed onboarding
        if UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) {
            isAuthorized = true
            setupHealthCategories()
        }
    }

    func checkAvailability() {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "Health data is not available on this device"
            return
        }
    }

    func requestAuthorization() async {
        let typesToRead: Set<HKObjectType> = [
            // Activity
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,

            // Body Measurements
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!,
            HKObjectType.quantityType(forIdentifier: .leanBodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,

            // Heart
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,

            // Respiratory
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,

            // Nutrition
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!,

            // Sleep
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,

            // Mindfulness
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,

            // Workouts
            HKObjectType.workoutType(),

            // Blood
            HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            await MainActor.run {
                isAuthorized = true
                UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
                setupHealthCategories()
            }
        } catch {
            await MainActor.run {
                authorizationError = "Authorization failed: \(error.localizedDescription)"
            }
        }
    }

    func setupHealthCategories() {
        healthCategories = [
            // Activity
            HealthCategory(name: "Steps", dataType: HKObjectType.quantityType(forIdentifier: .stepCount)!, emoji: "👟", shouldAggregateDaily: true),
            HealthCategory(name: "Distance", dataType: HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!, emoji: "🏃", shouldAggregateDaily: true),
            HealthCategory(name: "Active Cal", dataType: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!, emoji: "🔥", shouldAggregateDaily: true),
            HealthCategory(name: "Resting Cal", dataType: HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!, emoji: "⚡", shouldAggregateDaily: true),
            HealthCategory(name: "Flights", dataType: HKObjectType.quantityType(forIdentifier: .flightsClimbed)!, emoji: "🪜", shouldAggregateDaily: true),
            HealthCategory(name: "Exercise", dataType: HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!, emoji: "💪", shouldAggregateDaily: true),
            HealthCategory(name: "Stand", dataType: HKObjectType.quantityType(forIdentifier: .appleStandTime)!, emoji: "🧍", shouldAggregateDaily: true),

            // Body Measurements
            HealthCategory(name: "Height", dataType: HKObjectType.quantityType(forIdentifier: .height)!, emoji: "📏", shouldAggregateDaily: false),
            HealthCategory(name: "Weight", dataType: HKObjectType.quantityType(forIdentifier: .bodyMass)!, emoji: "⚖️", shouldAggregateDaily: false),
            HealthCategory(name: "BMI", dataType: HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!, emoji: "📊", shouldAggregateDaily: false),
            HealthCategory(name: "Lean Mass", dataType: HKObjectType.quantityType(forIdentifier: .leanBodyMass)!, emoji: "💪", shouldAggregateDaily: false),
            HealthCategory(name: "Body Fat", dataType: HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!, emoji: "📈", shouldAggregateDaily: false),

            // Heart
            HealthCategory(name: "Heart Rate", dataType: HKObjectType.quantityType(forIdentifier: .heartRate)!, emoji: "❤️", shouldAggregateDaily: false),
            HealthCategory(name: "Resting HR", dataType: HKObjectType.quantityType(forIdentifier: .restingHeartRate)!, emoji: "💓", shouldAggregateDaily: false),
            HealthCategory(name: "Walking HR", dataType: HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!, emoji: "🚶‍♂️", shouldAggregateDaily: false),
            HealthCategory(name: "HRV", dataType: HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, emoji: "📉", shouldAggregateDaily: false),

            // Respiratory
            HealthCategory(name: "Respiration", dataType: HKObjectType.quantityType(forIdentifier: .respiratoryRate)!, emoji: "🌬️", shouldAggregateDaily: false),
            HealthCategory(name: "Oxygen", dataType: HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!, emoji: "🫁", shouldAggregateDaily: false),

            // Nutrition
            HealthCategory(name: "Calories", dataType: HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, emoji: "🍽️", shouldAggregateDaily: true),
            HealthCategory(name: "Protein", dataType: HKObjectType.quantityType(forIdentifier: .dietaryProtein)!, emoji: "🥩", shouldAggregateDaily: true),
            HealthCategory(name: "Carbs", dataType: HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!, emoji: "🍞", shouldAggregateDaily: true),
            HealthCategory(name: "Fat", dataType: HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!, emoji: "🥑", shouldAggregateDaily: true),
            HealthCategory(name: "Water", dataType: HKObjectType.quantityType(forIdentifier: .dietaryWater)!, emoji: "💧", shouldAggregateDaily: true),
            HealthCategory(name: "Caffeine", dataType: HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!, emoji: "☕", shouldAggregateDaily: true),

            // Sleep
            HealthCategory(name: "Sleep", dataType: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, emoji: "😴", shouldAggregateDaily: true),

            // Mindfulness
            HealthCategory(name: "Mindfulness", dataType: HKObjectType.categoryType(forIdentifier: .mindfulSession)!, emoji: "🧘", shouldAggregateDaily: true),

            // Workouts
            HealthCategory(name: "Workouts", dataType: HKObjectType.workoutType(), emoji: "🏋️", shouldAggregateDaily: false),

            // Blood
            HealthCategory(name: "Glucose", dataType: HKObjectType.quantityType(forIdentifier: .bloodGlucose)!, emoji: "🩸", shouldAggregateDaily: false),
            HealthCategory(name: "BP Systolic", dataType: HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!, emoji: "💉", shouldAggregateDaily: false),
            HealthCategory(name: "BP Diastolic", dataType: HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!, emoji: "💉", shouldAggregateDaily: false),
        ]
    }

    func getDaysWithData(from startDate: Date, to endDate: Date) async -> Set<Date> {
        let calendar = Calendar.current
        var daysWithData = Set<Date>()

        for category in healthCategories {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: endDate)

            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                daysWithData.insert(day)
            }
        }

        return daysWithData
    }

    func getDaysWithDataAndEmojis(from startDate: Date, to endDate: Date) async -> (days: Set<Date>, emojisByDate: [Date: [String]]) {
        let calendar = Calendar.current
        var daysWithData = Set<Date>()
        var emojisByDate: [Date: [String]] = [:]

        for category in healthCategories {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: endDate)

            for sample in samples {
                let day = calendar.startOfDay(for: sample.startDate)
                daysWithData.insert(day)

                // Add emoji for this category on this day
                if emojisByDate[day] == nil {
                    emojisByDate[day] = []
                }
                if !emojisByDate[day]!.contains(category.emoji) {
                    emojisByDate[day]!.append(category.emoji)
                }
            }
        }

        return (daysWithData, emojisByDate)
    }

    func fetchSampleData(for category: HealthCategory) async -> [String] {
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -7, to: now)!

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: category.dataType,
                predicate: predicate,
                limit: 5,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in

                if let error = error {
                    continuation.resume(returning: ["Error: \(error.localizedDescription)"])
                    return
                }

                guard let samples = samples, !samples.isEmpty else {
                    continuation.resume(returning: ["No data available"])
                    return
                }

                let results = samples.map { sample -> String in
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .medium

                    if let quantitySample = sample as? HKQuantitySample {
                        let quantityType = category.dataType as! HKQuantityType
                        let unit = self.getUnit(for: quantityType)
                        let value = quantitySample.quantity.doubleValue(for: unit)
                        let formattedValue = self.formatValue(value, for: quantityType)
                        let unitName = self.getFriendlyUnitName(for: quantityType)

                        // Show end time if it's different from start time
                        let calendar = Calendar.current
                        if !calendar.isDate(sample.startDate, equalTo: sample.endDate, toGranularity: .minute) {
                            let endTimeFormatter = DateFormatter()
                            endTimeFormatter.timeStyle = .medium
                            return "[\(dateFormatter.string(from: sample.startDate)) - \(endTimeFormatter.string(from: sample.endDate))]\n\(formattedValue) \(unitName)"
                        } else {
                            return "[\(dateFormatter.string(from: sample.startDate))]\n\(formattedValue) \(unitName)"
                        }
                    } else if let categorySample = sample as? HKCategorySample {
                        let endTimeFormatter = DateFormatter()
                        endTimeFormatter.timeStyle = .medium
                        return "[\(dateFormatter.string(from: sample.startDate)) - \(endTimeFormatter.string(from: sample.endDate))]\nValue: \(categorySample.value)"
                    } else if let workout = sample as? HKWorkout {
                        let duration = workout.duration / 60
                        let endTimeFormatter = DateFormatter()
                        endTimeFormatter.timeStyle = .medium
                        var details = "[\(dateFormatter.string(from: sample.startDate)) - \(endTimeFormatter.string(from: sample.endDate))]\n\(workout.workoutActivityType.name) - \(Int(duration)) min"
                        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                           let energy = workout.statistics(for: activeEnergyType)?.sumQuantity() {
                            let calories = energy.doubleValue(for: .kilocalorie())
                            details += ", \(Int(calories)) cal"
                        }
                        return details
                    }

                    return "[\(dateFormatter.string(from: sample.startDate))]"
                }

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

    nonisolated func getUnit(for quantityType: HKQuantityType) -> HKUnit {
        switch quantityType.identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return .count()
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return .mile()
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue:
            return .kilocalorie()
        case HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return .count()
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
             HKQuantityTypeIdentifier.appleStandTime.rawValue:
            return .minute()
        case HKQuantityTypeIdentifier.height.rawValue:
            return .inch()
        case HKQuantityTypeIdentifier.bodyMass.rawValue,
             HKQuantityTypeIdentifier.leanBodyMass.rawValue:
            return .pound()
        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue:
            return .count()
        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
            return .percent()
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.walkingHeartRateAverage.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return .secondUnit(with: .milli)
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return HKUnit.count().unitDivided(by: .minute())
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return .percent()
        case HKQuantityTypeIdentifier.dietaryProtein.rawValue,
             HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue,
             HKQuantityTypeIdentifier.dietaryFatTotal.rawValue:
            return .gram()
        case HKQuantityTypeIdentifier.dietaryWater.rawValue:
            return .fluidOunceUS()
        case HKQuantityTypeIdentifier.dietaryCaffeine.rawValue:
            return .gramUnit(with: .milli)
        case HKQuantityTypeIdentifier.bloodGlucose.rawValue:
            return HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return .millimeterOfMercury()
        default:
            return .count()
        }
    }

    nonisolated func formatValue(_ value: Double, for quantityType: HKQuantityType) -> String {
        let identifier = quantityType.identifier

        // Determine decimal places based on data type
        let decimalPlaces: Int
        let shouldUseThousandsSeparator: Bool

        switch identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.flightsClimbed.rawValue,
             HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
             HKQuantityTypeIdentifier.appleStandTime.rawValue:
            decimalPlaces = 0
            shouldUseThousandsSeparator = true

        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            decimalPlaces = 1
            shouldUseThousandsSeparator = false

        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue:
            decimalPlaces = 0
            shouldUseThousandsSeparator = true

        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.walkingHeartRateAverage.rawValue:
            decimalPlaces = 0
            shouldUseThousandsSeparator = false

        case HKQuantityTypeIdentifier.bodyMass.rawValue,
             HKQuantityTypeIdentifier.leanBodyMass.rawValue:
            decimalPlaces = 1
            shouldUseThousandsSeparator = false

        default:
            decimalPlaces = 1
            shouldUseThousandsSeparator = false
        }

        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = decimalPlaces
        formatter.maximumFractionDigits = decimalPlaces
        formatter.usesGroupingSeparator = shouldUseThousandsSeparator

        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimalPlaces)f", value)
    }

    nonisolated func getFriendlyUnitName(for quantityType: HKQuantityType) -> String {
        switch quantityType.identifier {
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return "steps"
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            return "mi"
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue:
            return "cal"
        case HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return "flights"
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue:
            return "min exercise"
        case HKQuantityTypeIdentifier.appleStandTime.rawValue:
            return "min standing"
        case HKQuantityTypeIdentifier.height.rawValue:
            return "in"
        case HKQuantityTypeIdentifier.bodyMass.rawValue,
             HKQuantityTypeIdentifier.leanBodyMass.rawValue:
            return "lbs"
        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue:
            return "BMI"
        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
            return "%"
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.walkingHeartRateAverage.rawValue:
            return "bpm"
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return "ms"
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return "br/min"
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return "% O₂"
        case HKQuantityTypeIdentifier.dietaryProtein.rawValue:
            return "g protein"
        case HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue:
            return "g carbs"
        case HKQuantityTypeIdentifier.dietaryFatTotal.rawValue:
            return "g fat"
        case HKQuantityTypeIdentifier.dietaryWater.rawValue:
            return "fl oz"
        case HKQuantityTypeIdentifier.dietaryCaffeine.rawValue:
            return "mg"
        case HKQuantityTypeIdentifier.bloodGlucose.rawValue:
            return "mg/dL"
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return "mmHg"
        default:
            return getUnit(for: quantityType).unitString
        }
    }

    func fetchDetailedSampleData(for category: HealthCategory, from startDate: Date, to endDate: Date) async -> [HealthSample] {
        if category.shouldAggregateDaily {
            return await fetchAggregatedDailySamples(for: category, from: startDate, to: endDate)
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: category.dataType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in

                if let error = error {
                    print("Error fetching samples: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let samples = samples, !samples.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }

                let healthSamples = samples.compactMap { sample -> HealthSample? in
                    var details = ""

                    if let quantitySample = sample as? HKQuantitySample {
                        let quantityType = category.dataType as! HKQuantityType
                        let unit = self.getUnit(for: quantityType)
                        let value = quantitySample.quantity.doubleValue(for: unit)
                        let formattedValue = self.formatValue(value, for: quantityType)
                        let unitName = self.getFriendlyUnitName(for: quantityType)
                        details = "\(formattedValue) \(unitName)"
                    } else if let categorySample = sample as? HKCategorySample {
                        details = "Value: \(categorySample.value)"
                    } else if let workout = sample as? HKWorkout {
                        let duration = workout.duration / 60
                        details = "\(workout.workoutActivityType.name) (\(Int(duration)) min"
                        if let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
                           let energy = workout.statistics(for: activeEnergyType)?.sumQuantity() {
                            let calories = energy.doubleValue(for: .kilocalorie())
                            details += ", \(Int(calories)) cal"
                        }
                        details += ")"
                    }

                    return HealthSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        details: details
                    )
                }

                continuation.resume(returning: healthSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchMonthlyStats(for category: HealthCategory, month: Date) async -> MonthlyStats? {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            return nil
        }

        let startDate = monthInterval.start
        let endDate = min(monthInterval.end, Date()) // Don't go past today

        // For workout type, count workouts
        if category.dataType is HKWorkoutType {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: endDate)
            if samples.isEmpty { return nil }

            return MonthlyStats(
                totalValue: Double(samples.count),
                averageValue: 0,
                daysWithData: samples.count,
                formattedTotal: "\(samples.count)",
                formattedAverage: "",
                unitName: samples.count == 1 ? "workout" : "workouts"
            )
        }

        // For category types (sleep, mindfulness), aggregate duration
        if category.dataType is HKCategoryType {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: endDate)
            if samples.isEmpty { return nil }

            var totalMinutes: Double = 0
            let daysSet = Set(samples.map { calendar.startOfDay(for: $0.startDate) })

            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60
                totalMinutes += duration
            }

            let avgMinutes = daysSet.count > 0 ? totalMinutes / Double(daysSet.count) : 0
            let hours = Int(totalMinutes / 60)
            let mins = Int(totalMinutes.truncatingRemainder(dividingBy: 60))
            let avgHours = Int(avgMinutes / 60)
            let avgMins = Int(avgMinutes.truncatingRemainder(dividingBy: 60))

            return MonthlyStats(
                totalValue: totalMinutes,
                averageValue: avgMinutes,
                daysWithData: daysSet.count,
                formattedTotal: hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m",
                formattedAverage: avgHours > 0 ? "\(avgHours)h \(avgMins)m" : "\(avgMins)m",
                unitName: "total"
            )
        }

        // For quantity types
        guard let quantityType = category.dataType as? HKQuantityType else {
            return nil
        }

        var anchorComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        anchorComponents.hour = 0
        guard let anchorDate = calendar.date(from: anchorComponents) else {
            return nil
        }

        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: category.shouldAggregateDaily ? .cumulativeSum : .discreteAverage,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    print("Error fetching monthly stats: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let results = results else {
                    continuation.resume(returning: nil)
                    return
                }

                var totalValue: Double = 0
                var daysWithData = 0
                let unit = self.getUnit(for: quantityType)

                results.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if category.shouldAggregateDaily {
                        if let sum = statistics.sumQuantity() {
                            let value = sum.doubleValue(for: unit)
                            if value > 0 {
                                totalValue += value
                                daysWithData += 1
                            }
                        }
                    } else {
                        if let avg = statistics.averageQuantity() {
                            let value = avg.doubleValue(for: unit)
                            if value > 0 {
                                totalValue += value
                                daysWithData += 1
                            }
                        }
                    }
                }

                if daysWithData == 0 {
                    continuation.resume(returning: nil)
                    return
                }

                let avgValue = totalValue / Double(daysWithData)
                let unitName = self.getFriendlyUnitName(for: quantityType)

                let stats = MonthlyStats(
                    totalValue: totalValue,
                    averageValue: avgValue,
                    daysWithData: daysWithData,
                    formattedTotal: self.formatValue(totalValue, for: quantityType),
                    formattedAverage: self.formatValue(avgValue, for: quantityType),
                    unitName: unitName
                )

                continuation.resume(returning: stats)
            }

            self.healthStore.execute(query)
        }
    }

    func fetchPeriodStats(for category: HealthCategory, from startDate: Date, to endDate: Date) async -> MonthlyStats? {
        // Check cache first
        let cacheKey = periodStatsCacheKey(categoryName: category.name, from: startDate, to: endDate)
        if let cached = periodStatsCache[cacheKey] {
            return cached
        }

        let calendar = Calendar.current
        let effectiveEndDate = min(endDate, Date()) // Don't go past today

        // For workout type, count workouts
        if category.dataType is HKWorkoutType {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: effectiveEndDate)
            if samples.isEmpty { return nil }

            let stats = MonthlyStats(
                totalValue: Double(samples.count),
                averageValue: 0,
                daysWithData: samples.count,
                formattedTotal: "\(samples.count)",
                formattedAverage: "",
                unitName: samples.count == 1 ? "workout" : "workouts"
            )
            await MainActor.run { self.periodStatsCache[cacheKey] = stats }
            return stats
        }

        // For category types (sleep, mindfulness), aggregate duration
        if category.dataType is HKCategoryType {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: effectiveEndDate)
            if samples.isEmpty { return nil }

            var totalMinutes: Double = 0
            let daysSet = Set(samples.map { calendar.startOfDay(for: $0.startDate) })

            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60
                totalMinutes += duration
            }

            let avgMinutes = daysSet.count > 0 ? totalMinutes / Double(daysSet.count) : 0
            let hours = Int(totalMinutes / 60)
            let mins = Int(totalMinutes.truncatingRemainder(dividingBy: 60))
            let avgHours = Int(avgMinutes / 60)
            let avgMins = Int(avgMinutes.truncatingRemainder(dividingBy: 60))

            let stats = MonthlyStats(
                totalValue: totalMinutes,
                averageValue: avgMinutes,
                daysWithData: daysSet.count,
                formattedTotal: hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m",
                formattedAverage: avgHours > 0 ? "\(avgHours)h \(avgMins)m" : "\(avgMins)m",
                unitName: "total"
            )
            await MainActor.run { self.periodStatsCache[cacheKey] = stats }
            return stats
        }

        // For quantity types
        guard let quantityType = category.dataType as? HKQuantityType else {
            return nil
        }

        var anchorComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        anchorComponents.hour = 0
        guard let anchorDate = calendar.date(from: anchorComponents) else {
            return nil
        }

        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: effectiveEndDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: category.shouldAggregateDaily ? .cumulativeSum : .discreteAverage,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    print("Error fetching period stats: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let results = results else {
                    continuation.resume(returning: nil)
                    return
                }

                var totalValue: Double = 0
                var daysWithData = 0
                let unit = self.getUnit(for: quantityType)

                results.enumerateStatistics(from: startDate, to: effectiveEndDate) { statistics, _ in
                    if category.shouldAggregateDaily {
                        if let sum = statistics.sumQuantity() {
                            let value = sum.doubleValue(for: unit)
                            if value > 0 {
                                totalValue += value
                                daysWithData += 1
                            }
                        }
                    } else {
                        if let avg = statistics.averageQuantity() {
                            let value = avg.doubleValue(for: unit)
                            if value > 0 {
                                totalValue += value
                                daysWithData += 1
                            }
                        }
                    }
                }

                if daysWithData == 0 {
                    continuation.resume(returning: nil)
                    return
                }

                let avgValue = totalValue / Double(daysWithData)
                let unitName = self.getFriendlyUnitName(for: quantityType)

                let stats = MonthlyStats(
                    totalValue: totalValue,
                    averageValue: avgValue,
                    daysWithData: daysWithData,
                    formattedTotal: self.formatValue(totalValue, for: quantityType),
                    formattedAverage: self.formatValue(avgValue, for: quantityType),
                    unitName: unitName
                )

                Task {
                    await MainActor.run { self.periodStatsCache[cacheKey] = stats }
                    continuation.resume(returning: stats)
                }
            }

            self.healthStore.execute(query)
        }
    }

    func fetchChartData(for category: HealthCategory, from startDate: Date, to endDate: Date, isDaily: Bool) async -> [ChartDataPoint] {
        // Check cache first
        let cacheKey = chartDataCacheKey(categoryName: category.name, from: startDate, to: endDate, isDaily: isDaily)
        if let cached = chartDataCache[cacheKey] {
            return cached
        }

        let calendar = Calendar.current

        // Determine if this is a single day view (hourly) or multi-day view (daily)
        let daysDiff = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let useHourlyInterval = isDaily && daysDiff <= 1

        // For workout type, return workout counts
        if category.dataType is HKWorkoutType {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: endDate)
            let chartData: [ChartDataPoint]
            if useHourlyInterval {
                // Group by hour
                chartData = createHourlyChartData(from: samples, on: startDate, calendar: calendar)
            } else {
                // Group by day
                chartData = createDailyChartData(from: samples, from: startDate, to: endDate, calendar: calendar)
            }
            await MainActor.run { self.chartDataCache[cacheKey] = chartData }
            return chartData
        }

        // For category types (sleep, mindfulness), return duration in minutes
        if category.dataType is HKCategoryType {
            let samples = await fetchDetailedSampleData(for: category, from: startDate, to: endDate)
            let chartData: [ChartDataPoint]
            if useHourlyInterval {
                chartData = createHourlyChartDataFromDurations(from: samples, on: startDate, calendar: calendar)
            } else {
                chartData = createDailyChartDataFromDurations(from: samples, from: startDate, to: endDate, calendar: calendar)
            }
            await MainActor.run { self.chartDataCache[cacheKey] = chartData }
            return chartData
        }

        // For quantity types
        guard let quantityType = category.dataType as? HKQuantityType else {
            return []
        }

        let interval: DateComponents
        let anchorDate: Date

        if useHourlyInterval {
            interval = DateComponents(hour: 1)
            anchorDate = calendar.startOfDay(for: startDate)
        } else {
            interval = DateComponents(day: 1)
            var anchorComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
            anchorComponents.hour = 0
            anchorDate = calendar.date(from: anchorComponents) ?? startDate
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: category.shouldAggregateDaily ? .cumulativeSum : .discreteAverage,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    print("Error fetching chart data: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let results = results else {
                    continuation.resume(returning: [])
                    return
                }

                var chartData: [ChartDataPoint] = []
                let unit = self.getUnit(for: quantityType)

                if useHourlyInterval {
                    // Create 24-hour slots
                    let dayStart = calendar.startOfDay(for: startDate)
                    for hour in 0..<24 {
                        guard let hourDate = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { continue }

                        var value: Double = 0
                        results.enumerateStatistics(from: hourDate, to: calendar.date(byAdding: .hour, value: 1, to: hourDate)!) { statistics, _ in
                            if category.shouldAggregateDaily {
                                if let sum = statistics.sumQuantity() {
                                    value = sum.doubleValue(for: unit)
                                }
                            } else {
                                if let avg = statistics.averageQuantity() {
                                    value = avg.doubleValue(for: unit)
                                }
                            }
                        }

                        let hourFormatter = DateFormatter()
                        hourFormatter.dateFormat = "ha"
                        let label = hourFormatter.string(from: hourDate)

                        chartData.append(ChartDataPoint(date: hourDate, value: value, label: label))
                    }
                } else {
                    // Create day slots for the entire period
                    var currentDate = calendar.startOfDay(for: startDate)
                    let endOfPeriod = calendar.startOfDay(for: endDate)

                    while currentDate < endOfPeriod {
                        var value: Double = 0
                        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate)!

                        results.enumerateStatistics(from: currentDate, to: nextDay) { statistics, _ in
                            if category.shouldAggregateDaily {
                                if let sum = statistics.sumQuantity() {
                                    value = sum.doubleValue(for: unit)
                                }
                            } else {
                                if let avg = statistics.averageQuantity() {
                                    value = avg.doubleValue(for: unit)
                                }
                            }
                        }

                        let dayFormatter = DateFormatter()
                        dayFormatter.dateFormat = "M/d"
                        let label = dayFormatter.string(from: currentDate)

                        chartData.append(ChartDataPoint(date: currentDate, value: value, label: label))
                        currentDate = nextDay
                    }
                }
                let result = chartData
                Task { @MainActor in
                    self.chartDataCache[cacheKey] = result
                }
                continuation.resume(returning: result)
            }

            self.healthStore.execute(query)
        }
    }

    private func createHourlyChartData(from samples: [HealthSample], on date: Date, calendar: Calendar) -> [ChartDataPoint] {
        let dayStart = calendar.startOfDay(for: date)
        var hourCounts: [Int: Int] = [:]

        for sample in samples {
            let hour = calendar.component(.hour, from: sample.startDate)
            hourCounts[hour, default: 0] += 1
        }

        var chartData: [ChartDataPoint] = []
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "ha"

        for hour in 0..<24 {
            guard let hourDate = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
            let count = hourCounts[hour] ?? 0
            let label = hourFormatter.string(from: hourDate)
            chartData.append(ChartDataPoint(date: hourDate, value: Double(count), label: label))
        }

        return chartData
    }

    private func createDailyChartData(from samples: [HealthSample], from startDate: Date, to endDate: Date, calendar: Calendar) -> [ChartDataPoint] {
        var dayCounts: [Date: Int] = [:]

        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            dayCounts[day, default: 0] += 1
        }

        var chartData: [ChartDataPoint] = []
        var currentDate = calendar.startOfDay(for: startDate)
        let endOfPeriod = calendar.startOfDay(for: endDate)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "M/d"

        while currentDate < endOfPeriod {
            let count = dayCounts[currentDate] ?? 0
            let label = dayFormatter.string(from: currentDate)
            chartData.append(ChartDataPoint(date: currentDate, value: Double(count), label: label))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return chartData
    }

    private func createHourlyChartDataFromDurations(from samples: [HealthSample], on date: Date, calendar: Calendar) -> [ChartDataPoint] {
        let dayStart = calendar.startOfDay(for: date)
        var hourMinutes: [Int: Double] = [:]

        for sample in samples {
            let hour = calendar.component(.hour, from: sample.startDate)
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60
            hourMinutes[hour, default: 0] += duration
        }

        var chartData: [ChartDataPoint] = []
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "ha"

        for hour in 0..<24 {
            guard let hourDate = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
            let minutes = hourMinutes[hour] ?? 0
            let label = hourFormatter.string(from: hourDate)
            chartData.append(ChartDataPoint(date: hourDate, value: minutes, label: label))
        }

        return chartData
    }

    private func createDailyChartDataFromDurations(from samples: [HealthSample], from startDate: Date, to endDate: Date, calendar: Calendar) -> [ChartDataPoint] {
        var dayMinutes: [Date: Double] = [:]

        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60
            dayMinutes[day, default: 0] += duration
        }

        var chartData: [ChartDataPoint] = []
        var currentDate = calendar.startOfDay(for: startDate)
        let endOfPeriod = calendar.startOfDay(for: endDate)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "M/d"

        while currentDate < endOfPeriod {
            let minutes = dayMinutes[currentDate] ?? 0
            let label = dayFormatter.string(from: currentDate)
            chartData.append(ChartDataPoint(date: currentDate, value: minutes, label: label))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return chartData
    }

    private func fetchAggregatedDailySamples(for category: HealthCategory, from startDate: Date, to endDate: Date) async -> [HealthSample] {
        guard let quantityType = category.dataType as? HKQuantityType else {
            return []
        }

        let calendar = Calendar.current
        var anchorComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        anchorComponents.hour = 0
        guard let anchorDate = calendar.date(from: anchorComponents) else {
            return []
        }

        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    print("Error fetching aggregated samples: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let results = results else {
                    continuation.resume(returning: [])
                    return
                }

                var healthSamples: [HealthSample] = []
                let unit = self.getUnit(for: quantityType)

                results.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let value = sum.doubleValue(for: unit)
                        if value > 0 {
                            let dayStart = calendar.startOfDay(for: statistics.startDate)
                            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                            let formattedValue = self.formatValue(value, for: quantityType)
                            let unitName = self.getFriendlyUnitName(for: quantityType)
                            let details = "\(formattedValue) \(unitName)"
                            healthSamples.append(HealthSample(
                                startDate: dayStart,
                                endDate: dayEnd,
                                details: details,
                                isAllDay: true
                            ))
                        }
                    }
                }

                continuation.resume(returning: healthSamples)
            }

            healthStore.execute(query)
        }
    }
}

struct HealthSample {
    let startDate: Date
    let endDate: Date
    let details: String
    var isAllDay: Bool = false
    var numericValue: Double? = nil
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String
}

struct MonthlyStats {
    let totalValue: Double
    let averageValue: Double
    let daysWithData: Int
    let formattedTotal: String
    let formattedAverage: String
    let unitName: String
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .hiking: return "Hiking"
        case .traditionalStrengthTraining: return "Traditional Strength"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        default: return "Workout"
        }
    }
}

