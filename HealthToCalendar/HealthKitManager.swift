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

    struct HealthCategory: Identifiable {
        let id = UUID()
        let name: String
        let dataType: HKSampleType
        let emoji: String
        let shouldAggregateDaily: Bool
        var sampleData: [String] = []
        var isLoading = false
    }

    init() {
        checkAvailability()
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
            HealthCategory(name: "Step Count", dataType: HKObjectType.quantityType(forIdentifier: .stepCount)!, emoji: "👟", shouldAggregateDaily: true),
            HealthCategory(name: "Walking + Running Distance", dataType: HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!, emoji: "🏃", shouldAggregateDaily: true),
            HealthCategory(name: "Active Energy", dataType: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!, emoji: "🔥", shouldAggregateDaily: true),
            HealthCategory(name: "Basal Energy", dataType: HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!, emoji: "⚡", shouldAggregateDaily: true),
            HealthCategory(name: "Flights Climbed", dataType: HKObjectType.quantityType(forIdentifier: .flightsClimbed)!, emoji: "🪜", shouldAggregateDaily: true),
            HealthCategory(name: "Exercise Time", dataType: HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!, emoji: "💪", shouldAggregateDaily: true),
            HealthCategory(name: "Stand Time", dataType: HKObjectType.quantityType(forIdentifier: .appleStandTime)!, emoji: "🧍", shouldAggregateDaily: true),

            // Body Measurements
            HealthCategory(name: "Height", dataType: HKObjectType.quantityType(forIdentifier: .height)!, emoji: "📏", shouldAggregateDaily: false),
            HealthCategory(name: "Weight", dataType: HKObjectType.quantityType(forIdentifier: .bodyMass)!, emoji: "⚖️", shouldAggregateDaily: false),
            HealthCategory(name: "Body Mass Index", dataType: HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!, emoji: "📊", shouldAggregateDaily: false),
            HealthCategory(name: "Lean Body Mass", dataType: HKObjectType.quantityType(forIdentifier: .leanBodyMass)!, emoji: "💪", shouldAggregateDaily: false),
            HealthCategory(name: "Body Fat Percentage", dataType: HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!, emoji: "📈", shouldAggregateDaily: false),

            // Heart
            HealthCategory(name: "Heart Rate", dataType: HKObjectType.quantityType(forIdentifier: .heartRate)!, emoji: "❤️", shouldAggregateDaily: false),
            HealthCategory(name: "Resting Heart Rate", dataType: HKObjectType.quantityType(forIdentifier: .restingHeartRate)!, emoji: "💓", shouldAggregateDaily: false),
            HealthCategory(name: "Walking Heart Rate", dataType: HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!, emoji: "🚶‍♂️", shouldAggregateDaily: false),
            HealthCategory(name: "Heart Rate Variability", dataType: HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, emoji: "📉", shouldAggregateDaily: false),

            // Respiratory
            HealthCategory(name: "Respiratory Rate", dataType: HKObjectType.quantityType(forIdentifier: .respiratoryRate)!, emoji: "🌬️", shouldAggregateDaily: false),
            HealthCategory(name: "Oxygen Saturation", dataType: HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!, emoji: "🫁", shouldAggregateDaily: false),

            // Nutrition
            HealthCategory(name: "Calories Consumed", dataType: HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, emoji: "🍽️", shouldAggregateDaily: true),
            HealthCategory(name: "Protein", dataType: HKObjectType.quantityType(forIdentifier: .dietaryProtein)!, emoji: "🥩", shouldAggregateDaily: true),
            HealthCategory(name: "Carbohydrates", dataType: HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!, emoji: "🍞", shouldAggregateDaily: true),
            HealthCategory(name: "Total Fat", dataType: HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!, emoji: "🥑", shouldAggregateDaily: true),
            HealthCategory(name: "Water", dataType: HKObjectType.quantityType(forIdentifier: .dietaryWater)!, emoji: "💧", shouldAggregateDaily: true),
            HealthCategory(name: "Caffeine", dataType: HKObjectType.quantityType(forIdentifier: .dietaryCaffeine)!, emoji: "☕", shouldAggregateDaily: true),

            // Sleep
            HealthCategory(name: "Sleep Analysis", dataType: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, emoji: "😴", shouldAggregateDaily: true),

            // Mindfulness
            HealthCategory(name: "Mindful Minutes", dataType: HKObjectType.categoryType(forIdentifier: .mindfulSession)!, emoji: "🧘", shouldAggregateDaily: true),

            // Workouts
            HealthCategory(name: "Workouts", dataType: HKObjectType.workoutType(), emoji: "🏋️", shouldAggregateDaily: false),

            // Blood
            HealthCategory(name: "Blood Glucose", dataType: HKObjectType.quantityType(forIdentifier: .bloodGlucose)!, emoji: "🩸", shouldAggregateDaily: false),
            HealthCategory(name: "Blood Pressure (Systolic)", dataType: HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!, emoji: "💉", shouldAggregateDaily: false),
            HealthCategory(name: "Blood Pressure (Diastolic)", dataType: HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!, emoji: "💉", shouldAggregateDaily: false),
        ]
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
                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .short

                    if let quantitySample = sample as? HKQuantitySample {
                        let unit = self.getUnit(for: category.dataType as! HKQuantityType)
                        let value = quantitySample.quantity.doubleValue(for: unit)
                        return "\(dateFormatter.string(from: sample.startDate)): \(String(format: "%.2f", value)) \(unit.unitString)"
                    } else if let categorySample = sample as? HKCategorySample {
                        return "\(dateFormatter.string(from: sample.startDate)): \(categorySample.value)"
                    } else if let workout = sample as? HKWorkout {
                        let duration = workout.duration / 60
                        return "\(dateFormatter.string(from: sample.startDate)): \(workout.workoutActivityType.name) - \(String(format: "%.0f", duration)) min"
                    }

                    return "\(dateFormatter.string(from: sample.startDate))"
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
                        let unit = self.getUnit(for: category.dataType as! HKQuantityType)
                        let value = quantitySample.quantity.doubleValue(for: unit)
                        details = "\(String(format: "%.2f", value)) \(unit.unitString)"
                    } else if let categorySample = sample as? HKCategorySample {
                        details = "Value: \(categorySample.value)"
                    } else if let workout = sample as? HKWorkout {
                        let duration = workout.duration / 60
                        details = "\(workout.workoutActivityType.name) - \(String(format: "%.0f", duration)) minutes"
                        if let distance = workout.totalDistance {
                            let miles = distance.doubleValue(for: .mile())
                            details += ", \(String(format: "%.2f", miles)) miles"
                        }
                        if let energy = workout.totalEnergyBurned {
                            let calories = energy.doubleValue(for: .kilocalorie())
                            details += ", \(String(format: "%.0f", calories)) cal"
                        }
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

                            let details = "\(String(format: "%.2f", value)) \(unit.unitString)"
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
