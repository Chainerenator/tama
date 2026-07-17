//
//  HealthKitService.swift
//  TAMA v2 — мост к HealthKit (только чтение)
//
//  Питомец живёт данными часов: шаги, кольца, тренировки.
//  Никаких медицинских данных (ЭКГ и т.п.) — это питомец, а не медприбор.
//
//  Swift 6 strict: из колбэков HealthKit наружу выходят только
//  Sendable-структуры (числа), сами HKObject не пересекают акторы.
//

import Foundation
import HealthKit

/// Снимок активности за сегодня. Только то, что нужно утке.
struct ActivitySnapshot: Codable, Equatable, Sendable {
    var steps: Int = 0
    var exerciseMinutes: Int = 0
    var standHours: Int = 0
    var moveKcal: Double = 0

    var moveGoalReached = false
    var exerciseGoalReached = false
    var standGoalReached = false

    var allRingsClosed: Bool {
        moveGoalReached && exerciseGoalReached && standGoalReached
    }
}

@MainActor
final class HealthKitService: ObservableObject {

    static let shared = HealthKitService()

    @Published private(set) var snapshot = ActivitySnapshot()
    @Published private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.activitySummaryType()]
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        return types
    }

    /// Запросить доступ (один раз, система запомнит выбор).
    func requestAuthorization() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Обновить снимок. Вызывать при активации сцены и из refresh().
    func refresh() async {
        guard isAvailable else { return }
        var snap = ActivitySnapshot()

        if let steps = await todaySum(.stepCount, unit: .count()) {
            snap.steps = Int(steps)
        }
        if let rings = await todayRings() {
            snap.moveKcal = rings.moveValue
            snap.exerciseMinutes = Int(rings.exerciseValue)
            snap.standHours = Int(rings.standValue)
            snap.moveGoalReached = rings.moveGoal > 0 && rings.moveValue >= rings.moveGoal
            snap.exerciseGoalReached = rings.exerciseGoal > 0 && rings.exerciseValue >= rings.exerciseGoal
            snap.standGoalReached = rings.standGoal > 0 && rings.standValue >= rings.standGoal
        }
        snapshot = snap
    }

    // MARK: - Запросы (наружу — только Sendable-числа)

    private func todaySum(_ id: HKQuantityTypeIdentifier,
                          unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now,
                                                    options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                let value = stats?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private struct RingNumbers: Sendable {
        var moveValue = 0.0, moveGoal = 0.0
        var exerciseValue = 0.0, exerciseGoal = 0.0
        var standValue = 0.0, standGoal = 0.0
    }

    private func todayRings() async -> RingNumbers? {
        var components = Calendar.current.dateComponents([.era, .year, .month, .day],
                                                         from: .now)
        components.calendar = Calendar.current
        let predicate = HKQuery.predicateForActivitySummary(with: components)

        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let s = summaries?.first else {
                    continuation.resume(returning: nil); return
                }
                // Извлекаем числа ЗДЕСЬ: HKActivitySummary не Sendable.
                var numbers = RingNumbers()
                numbers.moveValue = s.activeEnergyBurned.doubleValue(for: .kilocalorie())
                numbers.moveGoal = s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                numbers.exerciseValue = s.appleExerciseTime.doubleValue(for: .minute())
                numbers.exerciseGoal = s.appleExerciseTimeGoal.doubleValue(for: .minute())
                numbers.standValue = s.appleStandHours.doubleValue(for: .count())
                numbers.standGoal = s.appleStandHoursGoal.doubleValue(for: .count())
                continuation.resume(returning: numbers)
            }
            store.execute(query)
        }
    }
}
