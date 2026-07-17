//
//  ActivityReactor.swift
//  TAMA v2 — превращает данные HealthKit в реакции питомца
//
//  Принципы:
//   • реакции только позитивные: за движение хвалим, за сидение НЕ наказываем
//     (мягкое «скучает» уже есть в базовой механике настроения);
//   • каждая веха срабатывает один раз в день;
//   • XP от активности ограничен дневным капом, чтобы не ломать баланс;
//   • леджер хранится ОТДЕЛЬНО от PetState (свой ключ UserDefaults) —
//     не трогаем схему сохранения и не ломаем существующие сейвы.
//

import Foundation

struct ActivityRewards: Sendable {
    var moodDelta: Double = 0
    var xp: Int = 0
    var celebrate = false
    var messages: [String] = []
    /// Большие вехи попадают в Memory Engine (M4: «живая память»).
    var memorySeeds: [(eventID: String, seed: MemorySeed)] = []
    var isEmpty: Bool { moodDelta == 0 && xp == 0 && messages.isEmpty }
}

@MainActor
final class ActivityReactor {

    static let shared = ActivityReactor()

    // ---- баланс ----
    static let stepMilestones = [2_000, 5_000, 8_000, 12_000]
    static let xpPerMilestone = 6
    static let moodPerMilestone: Double = 8
    static let ringsXP = 15
    static let ringsMood: Double = 20
    static let dailyHealthXPCap = 40

    // ---- дневной леджер (отдельно от PetState) ----
    private struct Ledger: Codable {
        var dayKey: String
        var milestonesHit: [Int] = []
        var ringsCelebrated = false
        var xpGranted = 0
    }

    private let ledgerKey = "tama.activity.ledger.v1"
    private var ledger: Ledger

    private init() {
        let today = Self.dayKey(for: .now)
        if let data = UserDefaults.standard.data(forKey: ledgerKey),
           let saved = try? JSONDecoder().decode(Ledger.self, from: data),
           saved.dayKey == today {
            ledger = saved
        } else {
            ledger = Ledger(dayKey: today)
        }
    }

    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func rollDayIfNeeded(now: Date) {
        let today = Self.dayKey(for: now)
        if ledger.dayKey != today { ledger = Ledger(dayKey: today) }
    }

    private func saveLedger() {
        if let data = try? JSONEncoder().encode(ledger) {
            UserDefaults.standard.set(data, forKey: ledgerKey)
        }
    }

    /// Оценить снимок и вернуть награды. Мутирует только свой леджер;
    /// применение к PetState — на вызывающей стороне (PetEngine+Activity).
    func evaluate(snapshot: ActivitySnapshot, now: Date = .now) -> ActivityRewards {
        rollDayIfNeeded(now: now)
        var rewards = ActivityRewards()

        // 1) вехи шагов — по одной за день каждая
        for milestone in Self.stepMilestones
        where snapshot.steps >= milestone && !ledger.milestonesHit.contains(milestone) {
            ledger.milestonesHit.append(milestone)
            rewards.moodDelta += Self.moodPerMilestone
            rewards.xp += Self.xpPerMilestone
            rewards.messages.append(milestoneMessage(milestone))
            // 12000 — день-рекорд, такое утка запоминает надолго
            if milestone == 12_000 {
                rewards.memorySeeds.append((
                    eventID: "activity_steps_\(ledger.dayKey)",
                    seed: MemorySeed(kind: .achievement, importance: 6,
                                     summary: "Мы прошли двенадцать тысяч шагов за один день!",
                                     tags: ["activity", "steps"])
                ))
            }
        }

        // 2) все кольца закрыты — маленький праздник, один раз в день
        if snapshot.allRingsClosed && !ledger.ringsCelebrated {
            ledger.ringsCelebrated = true
            rewards.moodDelta += Self.ringsMood
            rewards.xp += Self.ringsXP
            rewards.celebrate = true
            rewards.messages.append("Все кольца закрыты! Устраиваю праздник, кря! 🎉")
            rewards.memorySeeds.append((
                eventID: "activity_rings_\(ledger.dayKey)",
                seed: MemorySeed(kind: .achievement, importance: 5,
                                 summary: "Мы закрыли все кольца активности.",
                                 tags: ["activity", "rings"])
            ))
        }

        // 3) дневной кап XP от здоровья
        let allowed = max(0, Self.dailyHealthXPCap - ledger.xpGranted)
        rewards.xp = min(rewards.xp, allowed)
        ledger.xpGranted += rewards.xp

        if !rewards.isEmpty { saveLedger() }
        return rewards
    }

    private func milestoneMessage(_ steps: Int) -> String {
        switch steps {
        case 2_000:  return "2000 шагов! Разминка засчитана, кря."
        case 5_000:  return "5000 шагов! Я почти летала рядом с тобой!"
        case 8_000:  return "8000! Мы сегодня в отличной форме."
        default:     return "\(steps) шагов?! Ты машина. Я горжусь!"
        }
    }

    /// Для Alpha tools: сбросить дневной леджер.
    func resetForTesting() {
        ledger = Ledger(dayKey: Self.dayKey(for: .now))
        saveLedger()
    }
}
