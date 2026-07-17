// Generated integration file: PetState + watch app engine

//
//  PetState.swift
//  TamaKit — состояние питомца и чистая функция tick()
//
//  Ключевой принцип: tick(state, now) — чистая функция.
//  Это даёт бесплатно: offline-пересчёт («открыл через 6 часов»),
//  unit-тесты и детерминированность.
//
//  Анти-токсичность: показатели никогда не падают до «смерти»,
//  худшие состояния — «голодный» и «скучает».
//

import Foundation

// MARK: - Наблюдаемое состояние (для спрайта и фраз)

public enum Mood: String, Codable, Sendable {
    case sleeping   // спит
    case happy      // радуется
    case hungry     // голодный
    case thirsty    // хочет воды
    case bored      // скучает
    case content    // довольный
}

// MARK: - Окна приёмов пищи

public enum MealWindow: String, Codable, Sendable {
    case breakfast, lunch, dinner, snack

    public static func current(hour: Int) -> MealWindow {
        switch hour {
        case 7..<10:  return .breakfast
        case 12..<15: return .lunch
        case 18..<21: return .dinner
        default:      return .snack
        }
    }

    public var title: String {
        switch self {
        case .breakfast: return "Завтрак"
        case .lunch:     return "Обед"
        case .dinner:    return "Ужин"
        case .snack:     return "Перекус"
        }
    }
}

// MARK: - Состояние

public struct PetState: Codable, Equatable, Sendable {

    // показатели 0…100 (полы ниже — «смерти» нет)
    public var hunger: Double = 78
    public var water: Double = 70
    public var mood: Double = 72

    // личность
    public var persona: Persona = .duckling
    public var traits = TraitVector()
    public var xp: Int = 0

    // косметика (награды цепочек, сезонные костюмы)
    public var cosmetics: Set<String> = []   // напр. "flower", "zombieCostume"

    // квесты
    public var pendingChains: [ChainStep] = []
    public var questsAnsweredToday: Int = 0
    public var lastQuestDay: Date? = nil
    public var completedQuestIDs: [String] = []

    // долговременная память: только значимые решения и сюжетные события
    public var memories: [PetMemory] = []

    // сервисное
    public var lastTick: Date = .now
    public var celebrateUntil: Date = .distantPast

    public init() {}

    // MARK: настройки режима

    public var sleepStartHour: Int = 23
    public var sleepEndHour: Int = 7

    public func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        return h >= sleepStartHour || h < sleepEndHour
    }

    // MARK: производное настроение

    public func currentMood(at date: Date, calendar: Calendar = .current) -> Mood {
        if isNight(date, calendar: calendar) { return .sleeping }
        if date < celebrateUntil { return .happy }
        if hunger < 35 { return .hungry }
        if water  < 30 { return .thirsty }
        if mood   < 35 { return .bored }
        return .content
    }
}

// MARK: - Константы баланса (всё в одном месте — крутить удобно)

public enum Balance {
    // декей в час (день)
    public static let hungerDecayPerHour: Double = 7
    public static let waterDecayPerHour: Double  = 8
    public static let moodDecayPerHour: Double   = 5
    // ночью настроение восстанавливается
    public static let nightMoodRegenPerHour: Double = 3

    // полы — «смерти» нет по конструкции
    public static let hungerFloor: Double = 12
    public static let waterFloor: Double  = 12
    public static let moodFloor: Double   = 15

    // эффекты действий
    public static let feedHunger: Double = 30
    public static let feedMood: Double   = 8
    public static let drinkWater: Double = 35
    public static let drinkMood: Double  = 4
    public static let walkMood: Double   = 22

    // XP
    public static let xpFeed = 5
    public static let xpDrink = 4
    public static let xpWalk = 12       // v2: от HealthKit
    public static let xpQuest = 8
    public static let xpGameMax = 15

    // лимиты (анти-спам)
    public static let questsPerDay = 2
}

// MARK: - tick: чистый пересчёт состояния во времени

public enum Ticker {

    /// Пересчитать состояние с state.lastTick до `now`.
    /// Корректно проживает и 30 секунд, и 3 суток офлайна:
    /// идём по часам, учитывая день/ночь.
    public static func tick(_ state: PetState,
                            now: Date,
                            calendar: Calendar = .current) -> PetState {
        var s = state
        var cursor = s.lastTick
        guard now > cursor else { s.lastTick = now; return s }

        while cursor < now {
            let stepEnd = min(cursor.addingTimeInterval(3600), now)
            let hours = stepEnd.timeIntervalSince(cursor) / 3600

            if s.isNight(cursor, calendar: calendar) {
                s.mood = min(100, s.mood + Balance.nightMoodRegenPerHour * hours)
                // ночью голод/вода не падают — утка спит, а не страдает
            } else {
                s.hunger = max(Balance.hungerFloor, s.hunger - Balance.hungerDecayPerHour * hours)
                s.water  = max(Balance.waterFloor,  s.water  - Balance.waterDecayPerHour  * hours)
                s.mood   = max(Balance.moodFloor,   s.mood   - Balance.moodDecayPerHour   * hours)
            }
            cursor = stepEnd
        }

        // сброс дневного счётчика квестов при смене дня
        if let last = s.lastQuestDay,
           !calendar.isDate(last, inSameDayAs: now) {
            s.questsAnsweredToday = 0
        }

        s.lastTick = now
        return s
    }
}

// MARK: - Действия игрока

public enum PetAction {

    public static func feed(_ s: inout PetState, now: Date = .now) {
        s.hunger = min(100, s.hunger + Balance.feedHunger)
        s.mood   = min(100, s.mood + Balance.feedMood)
        gainXP(&s, Balance.xpFeed)
    }

    public static func drink(_ s: inout PetState, now: Date = .now) {
        s.water = min(100, s.water + Balance.drinkWater)
        s.mood  = min(100, s.mood + Balance.drinkMood)
        gainXP(&s, Balance.xpDrink)
    }

    /// v1 — кнопка; v2 — вызывается по данным HealthKit.
    public static func walk(_ s: inout PetState, now: Date = .now) {
        s.mood = min(100, s.mood + Balance.walkMood)
        s.celebrateUntil = now.addingTimeInterval(6)
        gainXP(&s, Balance.xpWalk)
    }

    public static func finishGame(_ s: inout PetState, score: Int, now: Date = .now) {
        s.mood = min(100, s.mood + Double(min(score * 2, 25)))
        s.celebrateUntil = now.addingTimeInterval(5)
        gainXP(&s, min(score, Balance.xpGameMax))
    }

    /// Начислить XP и, если пора, эволюционировать.
    /// Возвращает новую персону, если эволюция случилась.
    @discardableResult
    public static func gainXP(_ s: inout PetState, _ amount: Int) -> Persona? {
        s.xp += amount
        if let evolved = EvolutionEngine.evolveIfNeeded(persona: s.persona,
                                                        xp: s.xp,
                                                        traits: s.traits) {
            s.persona = evolved
            s.celebrateUntil = Date.now.addingTimeInterval(8)
            return evolved
        }
        return nil
    }
}


// MARK: - watchOS application engine

import SwiftUI

@MainActor
final class PetEngine: ObservableObject {
    static let demoMode = true

    @Published var pet: PetState
    @Published var tick: Int = 0
    @Published var activeQuest: Quest?
    @Published var lastReaction: String?
    @Published var lastEvolution: Persona?

    private let storageKey = "tama.watch.alpha.0.4"
    private var refreshTask: Task<Void, Never>?
    private var lastPhrase: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(PetState.self, from: data) {
            pet = decoded
        } else {
            pet = PetState()
        }

        if Self.demoMode {
            QuestEngine.chainDelay = 25 ... 35
            QuestEngine.memoryRecallChance = 1.0
            MemoryEngine.minimumRecallAge = 30
            MemoryEngine.recallCooldown = 60
        }

        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick += 1
                if self.tick % 5 == 0 { self.refresh() }
            }
        }
    }

    deinit { refreshTask?.cancel() }

    var mood: Mood { pet.currentMood(at: .now) }

    /// Ночная блокировка действий (концепция v1: ночью утка спит,
    /// кнопки гаснут). Тумблер в Alpha tools — чтобы не мешала
    /// вечернему тестированию.
    private static let nightLockKey = "tama.watch.settings.nightLockEnabled"
    @Published var nightLockEnabled: Bool = {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.nightLockKey) == nil
            ? true
            : defaults.bool(forKey: Self.nightLockKey)
    }() {
        didSet {
            UserDefaults.standard.set(nightLockEnabled, forKey: Self.nightLockKey)
        }
    }
    var isNightLocked: Bool { nightLockEnabled && mood == .sleeping }
    var hasDueChain: Bool { pet.pendingChains.contains { $0.fireAt <= .now } }

    var stageLabel: String {
        switch pet.persona {
        case .duckling:
            return "🐥 Утёнок · XP \(pet.xp)"
        case .archetype(let archetype):
            return "🦆 \(archetype.displayName) · XP \(pet.xp)"
        case .profession(let profession):
            return "🦆 \(profession.displayName) · XP \(pet.xp)"
        }
    }

    var phrase: String {
        let category: PhraseCategory
        switch mood {
        case .sleeping: category = .evening
        case .happy: category = .happy
        case .hungry: category = .hungry
        case .thirsty: category = .thirsty
        case .bored: category = .bored
        case .content:
            let hour = Calendar.current.component(.hour, from: .now)
            category = hour < 11 ? .morning : .content
        }
        let selected = PhraseBook.random(for: pet.persona,
                                         category: category,
                                         avoiding: lastPhrase)
            ?? "Кря."
        lastPhrase = selected
        return selected
    }

    func refresh() {
        pet = Ticker.tick(pet, now: .now)
        save()
    }

    func catchUp() {
        refresh()
    }

    func feed() {
        guard !isNightLocked else { return }
        PetAction.feed(&pet)
        save()
    }

    func drink() {
        guard !isNightLocked else { return }
        PetAction.drink(&pet)
        save()
    }

    func walk() {
        guard !isNightLocked else { return }
        PetAction.walk(&pet)
        save()
    }

    func rewardGame(score: Int) {
        // Ночная блокировка запрещает начинать новую игру, но не уничтожает
        // награду за сессию, начатую до перехода в ночной режим.
        PetAction.finishGame(&pet, score: score)
        save()
    }

    func prepareQuest() {
        refresh()
        activeQuest = QuestEngine.dueQuest(for: pet)
        lastReaction = nil
        lastEvolution = nil

        if activeQuest == nil {
            activeQuest = Quest(
                id: "quiet_day",
                icon: "🌙",
                text: "Сегодня историй достаточно. Можно просто побыть рядом.",
                choices: [
                    .init("Кря", deltas: [:], reaction: "Кря."),
                ],
                isChainStep: true,
                awardsXP: false
            )
        }
    }

    @discardableResult
    func answerQuest(index: Int) -> String {
        guard let quest = activeQuest else { return "Квест исчез. Кря." }
        let result = QuestEngine.answer(quest, choiceIndex: index, state: &pet)
        lastReaction = result.reaction
        lastEvolution = result.evolved
        save()
        Task {
            NotificationPlanner.cancelDailyPingIfQuestLimitReached(state: pet)
            await NotificationPlanner.syncChainNotifications(state: pet)
        }
        return result.reaction
    }

    func skipQuest() {
        guard let quest = activeQuest else { return }
        // QuestEngine.skip уже помечает воспоминание просмотренным.
        // Обнуляем activeQuest сразу, чтобы sheet onDismiss не отметил его повторно.
        QuestEngine.skip(quest, state: &pet)
        activeQuest = nil
        lastReaction = nil
        save()
        Task { await NotificationPlanner.syncChainNotifications(state: pet) }
    }

    func finishQuest() {
        // Свайп без ответа = «не сейчас», а не «не хочу»:
        // • воспоминание получает cooldown;
        // • шаг цепочки переносится на новый срок (не удаляется —
        //   случайный свайп не должен навсегда обрывать сюжет);
        // • обычный квест уходит без штрафа и расхода лимита.
        // Осознанный отказ — только явная кнопка «Пропустить» (skipQuest).
        if let quest = activeQuest, lastReaction == nil {
            QuestEngine.postpone(quest, state: &pet)
            save()
        }
        activeQuest = nil
        lastReaction = nil
        Task { await NotificationPlanner.syncChainNotifications(state: pet) }
    }

    // MARK: Alpha tools

    func addTestXP(_ amount: Int = 100) {
        lastEvolution = PetAction.gainXP(&pet, amount)
        save()
    }

    func resetQuestLimit() {
        pet.questsAnsweredToday = 0
        pet.lastQuestDay = nil
        save()
    }

    func cyclePersona() {
        let personas: [Persona] = [.duckling]
            + Archetype.allCases.map { .archetype($0) }
            + Profession.allCases.map { .profession($0) }
        let current = personas.firstIndex(of: pet.persona) ?? 0
        pet.persona = personas[(current + 1) % personas.count]
        save()
    }

    func seedMemoryDemo() {
        let seed = MemorySeed(kind: .kindness,
                              importance: 9,
                              summary: "Ты помог потерявшемуся утёнку найти семью.",
                              tags: ["rescuedDuckling"])
        MemoryEngine.remember(eventID: "alpha_memory",
                              choiceText: "Помочь",
                              seed: seed,
                              state: &pet,
                              now: Date().addingTimeInterval(-120))
        resetQuestLimit()
        save()
    }

    func toggleFlower() {
        if pet.cosmetics.contains("flower") { pet.cosmetics.remove("flower") }
        else { pet.cosmetics.insert("flower") }
        save()
    }

    func resetPet() {
        pet = PetState()
        activeQuest = nil
        lastReaction = nil
        lastEvolution = nil
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(pet) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
