// Generated integration file: Traits + Evolution + Memory

//
//  Traits.swift
//  TamaKit — ядро системы характера TAMA Watch
//
//  Шесть скрытых черт. Игроку напрямую не показываются —
//  проявляются через фразы, поведение и эволюцию.
//

import Foundation

/// Скрытая черта характера. Не мораль, а ось личности:
/// «плохих» значений не бывает.
public enum Trait: String, Codable, CaseIterable, Sendable {
    case brave      // 😎 смелость
    case kind       // 🤝 доброта
    case cunning    // 🧠 хитрость
    case polite     // 🎩 вежливость
    case chaos      // 🎉 безуминка
    case luck       // 🍀 удача
}

/// Вектор черт. Только накапливается по ходу жизни питомца —
/// деградации со временем нет (анти-токсичный принцип).
public struct TraitVector: Codable, Equatable, Sendable {
    private var values: [Trait: Int] = [:]

    public init() {}

    public subscript(_ trait: Trait) -> Int {
        get { values[trait] ?? 0 }
        set { values[trait] = newValue }
    }

    /// Применить дельты из ответа на квест (±1…3 на черту).
    public mutating func apply(_ deltas: [Trait: Int]) {
        for (trait, delta) in deltas {
            self[trait] += delta
        }
    }

    /// Сумма нескольких черт — для формул архетипов.
    public func score(_ traits: Trait...) -> Int {
        traits.reduce(0) { $0 + self[$1] }
    }
}


//
//  Evolution.swift
//  TamaKit — двухъярусная эволюция
//
//  ур. 1  Утёнок (0…99 XP)
//  ур. 2  Архетип на 100 XP — по профилю черт
//  ур. 3  Профессия на 300 XP — ветка архетипа + вторичная черта
//
//  ⚠️ Все персонажи — оригинальные архетипы. Никаких образов
//  Disney/WB (Дональд, Даффи и т.п.) — ни во фразах, ни во внешности.
//

import Foundation

// MARK: - Ярус 2: архетипы

public enum Archetype: String, Codable, CaseIterable, Sendable {
    case star   // 🎩 Звезда — смелость + безуминка
    case gent   // 🧐 Джентльмен — вежливость + доброта
    case sly    // 🧢 Хитрюга — хитрость + смелость
    case grump  // 🧣 Ворчун — характер режима (fallback)

    public var displayName: String {
        switch self {
        case .star:  return "Звезда"
        case .gent:  return "Джентльмен"
        case .sly:   return "Хитрюга"
        case .grump: return "Ворчун"
        }
    }
}

// MARK: - Ярус 3: профессии (спрайт-лист tama-sprites)

public enum Profession: String, Codable, CaseIterable, Sendable {
    // ветка Звезды
    case king, musician, artist, chef
    // ветка Джентльмена
    case scientist, detective, captain, astronaut
    // ветка Хитрюги
    case pirate, ninja, engineer, sheriff, hooligan
    // ветка Ворчуна
    case knight, scout, explorer, mage

    // «Зомби» из референса — НЕ эволюция, а сезонный костюм
    // (Хэллоуин): эволюция в зомби нарушила бы анти-токсичный
    // принцип «питомец не умирает».

    public var displayName: String {
        switch self {
        case .king: return "Король";           case .musician: return "Музыкант"
        case .artist: return "Художник";       case .chef: return "Повар"
        case .scientist: return "Учёный";      case .detective: return "Детектив"
        case .captain: return "Капитан";       case .astronaut: return "Космонавт"
        case .pirate: return "Пират";          case .ninja: return "Ниндзя"
        case .engineer: return "Инженер";      case .sheriff: return "Шериф"
        case .hooligan: return "Хулиган";      case .knight: return "Рыцарь"
        case .scout: return "Скаут";           case .explorer: return "Исследователь"
        case .mage: return "Маг"
        }
    }

    public var archetype: Archetype {
        switch self {
        case .king, .musician, .artist, .chef:              return .star
        case .scientist, .detective, .captain, .astronaut:  return .gent
        case .pirate, .ninja, .engineer, .sheriff, .hooligan: return .sly
        case .knight, .scout, .explorer, .mage:             return .grump
        }
    }
}

// MARK: - Персона (текущая ступень)

public enum Persona: Codable, Equatable, Sendable {
    case duckling
    case archetype(Archetype)
    case profession(Profession)

    /// Архетип, чьим «голосом» говорит персона (для слоёных фраз).
    public var voiceArchetype: Archetype? {
        switch self {
        case .duckling:              return nil
        case .archetype(let a):      return a
        case .profession(let p):     return p.archetype
        }
    }
}

// MARK: - Движок эволюции

public enum EvolutionEngine {

    public static let xpForArchetype = 100
    public static let xpForProfession = 300

    /// Порог выраженности профиля: ниже него — Ворчун.
    static let archetypeThreshold = 4

    /// ур.1 → ур.2. Профиль = сумма двух черт; берём максимальный.
    public static func chooseArchetype(from t: TraitVector) -> Archetype {
        let profiles: [(Archetype, Int)] = [
            (.star, t.score(.brave, .chaos)),
            (.gent, t.score(.polite, .kind)),
            (.sly,  t.score(.cunning, .brave)),
        ]
        guard let best = profiles.max(by: { $0.1 < $1.1 }),
              best.1 >= archetypeThreshold else { return .grump }
        return best.0
    }

    /// ур.2 → ур.3. Внутри ветки архетипа побеждает
    /// профессия с максимальной вторичной чертой.
    public static func chooseProfession(archetype: Archetype,
                                        traits t: TraitVector) -> Profession {
        // Особый случай: Хитрюга с отрицательной вежливостью — Хулиган.
        if archetype == .sly, t[.polite] < 0 { return .hooligan }

        let branch: [(Profession, Trait)]
        switch archetype {
        case .star:  branch = [(.king, .brave), (.musician, .kind),
                               (.artist, .chaos), (.chef, .polite)]
        case .gent:  branch = [(.scientist, .cunning), (.detective, .luck),
                               (.captain, .brave), (.astronaut, .chaos)]
        case .sly:   branch = [(.pirate, .brave), (.ninja, .chaos),
                               (.engineer, .polite), (.sheriff, .kind)]
        case .grump: branch = [(.knight, .brave), (.scout, .kind),
                               (.explorer, .luck), (.mage, .chaos)]
        }
        // при равенстве побеждает первый в списке — детерминированно
        return branch.max(by: { t[$0.1] < t[$1.1] })!.0
    }

    /// Проверка эволюции. Возвращает новую персону, если пора.
    public static func evolveIfNeeded(persona: Persona,
                                      xp: Int,
                                      traits: TraitVector) -> Persona? {
        switch persona {
        case .duckling where xp >= xpForArchetype:
            return .archetype(chooseArchetype(from: traits))
        case .archetype(let a) where xp >= xpForProfession:
            return .profession(chooseProfession(archetype: a, traits: traits))
        default:
            return nil
        }
    }
}


//
//  Memory.swift
//  TamaKit — долговременная память питомца
//
//  Память хранит только значимые решения. Она не является журналом всех
//  нажатий: сохранённое событие должно быть пригодно для будущей истории.
//

import Foundation

public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case meeting
    case choice
    case relationship
    case conflict
    case gift
    case achievement
    case embarrassment
    case discovery
    case promise
    case kindness
}

public struct MemorySeed: Codable, Equatable, Sendable {
    public let kind: MemoryKind
    public let importance: Int
    public let summary: String
    public let tags: [String]

    public init(kind: MemoryKind,
                importance: Int,
                summary: String,
                tags: [String] = []) {
        self.kind = kind
        self.importance = importance
        self.summary = summary
        self.tags = tags
    }
}

public struct PetMemory: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let eventID: String
    public let choiceText: String
    public let createdAt: Date
    public let kind: MemoryKind
    public let importance: Int
    public let summary: String
    public let tags: [String]
    public var lastRecalledAt: Date?
    public var recallCount: Int

    public init(id: UUID = UUID(),
                eventID: String,
                choiceText: String,
                createdAt: Date = .now,
                kind: MemoryKind,
                importance: Int,
                summary: String,
                tags: [String] = [],
                lastRecalledAt: Date? = nil,
                recallCount: Int = 0) {
        self.id = id
        self.eventID = eventID
        self.choiceText = choiceText
        self.createdAt = createdAt
        self.kind = kind
        self.importance = max(1, min(10, importance))
        self.summary = summary
        self.tags = tags
        self.lastRecalledAt = lastRecalledAt
        self.recallCount = recallCount
    }
}

@MainActor
public enum MemoryEngine {
    /// События ниже этого порога не попадают в долговременную память.
    public static var minimumImportance = 5

    /// В production воспоминание не возвращается сразу после события.
    /// Для прототипа это значение можно временно уменьшить.
    public static var minimumRecallAge: TimeInterval = 86_400
    public static var recallCooldown: TimeInterval = 7 * 86_400
    public static var maximumMemories = 48

    public static func remember(eventID: String,
                                choiceText: String,
                                seed: MemorySeed,
                                state: inout PetState,
                                now: Date = .now) {
        guard seed.importance >= minimumImportance else { return }

        // Один и тот же смысл не записываем многократно.
        if state.memories.contains(where: {
            $0.eventID == eventID && $0.summary == seed.summary
        }) { return }

        state.memories.append(
            PetMemory(eventID: eventID,
                      choiceText: choiceText,
                      createdAt: now,
                      kind: seed.kind,
                      importance: seed.importance,
                      summary: seed.summary,
                      tags: seed.tags)
        )

        // Сначала сохраняем важное, при равной важности — более новое.
        state.memories.sort {
            if $0.importance == $1.importance { return $0.createdAt > $1.createdAt }
            return $0.importance > $1.importance
        }
        if state.memories.count > maximumMemories {
            state.memories.removeLast(state.memories.count - maximumMemories)
        }
    }

    public static func recallCandidate(in state: PetState,
                                       now: Date = .now) -> PetMemory? {
        state.memories
            .filter { memory in
                guard now.timeIntervalSince(memory.createdAt) >= minimumRecallAge else {
                    return false
                }
                if let last = memory.lastRecalledAt,
                   now.timeIntervalSince(last) < recallCooldown {
                    return false
                }
                return true
            }
            .sorted {
                let left = $0.importance * 10 - $0.recallCount
                let right = $1.importance * 10 - $1.recallCount
                if left == right { return $0.createdAt < $1.createdAt }
                return left > right
            }
            .first
    }

    public static func markRecalled(_ id: UUID,
                                    state: inout PetState,
                                    now: Date = .now) {
        guard let index = state.memories.firstIndex(where: { $0.id == id }) else {
            return
        }
        state.memories[index].lastRecalledAt = now
        state.memories[index].recallCount += 1
    }

    public static func hasTag(_ tag: String, in state: PetState) -> Bool {
        state.memories.contains { $0.tags.contains(tag) }
    }

    public static func recent(in state: PetState, limit: Int = 8) -> [PetMemory] {
        Array(state.memories.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }
}

public enum MemoryQuestFactory {
    /// Ярус давности: воспоминание звучит по-разному спустя день,
    /// неделю и месяц — так память ощущается живой (M4 роадмапа).
    private static func agePhrase(for memory: PetMemory,
                                  now: Date = .now) -> String {
        let days = Int(now.timeIntervalSince(memory.createdAt) / 86_400)
        switch days {
        case ..<1:   return "Совсем свежее воспоминание…"
        case 1:      return "Это было вчера."
        case 2...6:  return "Это было пару дней назад."
        case 7...30: return "Это было ещё на той неделе."
        default:     return "Это было давным-давно."
        }
    }

    public static func quest(for memory: PetMemory) -> Quest {
        let commonID = "memory_\(memory.id.uuidString)"

        // Знакомство состоялось, но романтическая цепочка могла не дойти
        // до финала: никаких упоминаний цветка здесь быть не должно.
        if memory.tags.contains("duckMet"), !memory.tags.contains("romance") {
            return Quest(
                id: commonID,
                icon: "🦆",
                text: agePhrase(for: memory) + " " + "Помнишь ту уточку, с которой вы познакомились у пруда?",
                choices: [
                    .init("😊 Конечно", deltas: [.kind: 1],
                          reaction: "Может, ещё встретимся."),
                    .init("😎 Такое не забывается", deltas: [.brave: 1],
                          reaction: "Уверенность тебе идёт."),
                    .init("😳 До сих пор немного смущаюсь", deltas: [.kind: 1],
                          reaction: "Это было мило, кря."),
                ],
                isChainStep: true,
                recallsMemoryID: memory.id
            )
        }

        if memory.tags.contains("romance") {
            return Quest(
                id: commonID,
                icon: "🌸",
                text: agePhrase(for: memory) + " " + "Ты всё ещё помнишь ту уточку у пруда?",
                choices: [
                    .init("😊 Конечно", deltas: [.kind: 1],
                          reaction: "Я тоже. Хорошая была прогулка."),
                    .init("🎩 Поправить цветок", deltas: [.polite: 1],
                          reaction: "Выглядит безупречно."),
                    .init("😎 Как забыть меня?", deltas: [.brave: 1],
                          reaction: "Справедливо. Такое не забывают."),
                ],
                isChainStep: true,
                recallsMemoryID: memory.id
            )
        }

        if memory.tags.contains("rescuedDuckling") {
            return Quest(
                id: commonID,
                icon: "🐥",
                text: agePhrase(for: memory) + " " + "Тот самый утёнок снова тебя нашёл. Теперь он отлично плавает!",
                choices: [
                    .init("👏 Похвалить", deltas: [.kind: 2],
                          reaction: "Он сияет от гордости."),
                    .init("🏊 Устроить заплыв", deltas: [.brave: 1, .chaos: 1],
                          reaction: "Почти ничья. Почти."),
                    .init("🎩 Поздороваться", deltas: [.polite: 1],
                          reaction: "Он очень рад встрече."),
                ],
                isChainStep: true,
                recallsMemoryID: memory.id
            )
        }

        if memory.tags.contains("hunter") {
            return Quest(
                id: commonID,
                icon: "🌾",
                text: agePhrase(for: memory) + " " + "В камышах кто-то прошептал: «Это снова та статуя?»",
                choices: [
                    .init("🗿 Замереть", deltas: [.chaos: 2],
                          reaction: "Легенда о статуе живёт."),
                    .init("🧠 Тихо уйти", deltas: [.cunning: 1],
                          reaction: "Идеальное исчезновение."),
                    .init("😎 Громко крякнуть", deltas: [.brave: 1],
                          reaction: "Камыши ответили эхом."),
                ],
                isChainStep: true,
                recallsMemoryID: memory.id
            )
        }

        if memory.tags.contains("catFriend") {
            return Quest(
                id: commonID,
                icon: "🐈",
                text: agePhrase(for: memory) + " " + "Тот самый кот оставил у двери маленькое пёрышко.",
                choices: [
                    .init("🤝 Оставить рыбку", deltas: [.kind: 2],
                          reaction: "Дружба продолжается."),
                    .init("🧠 Спрятать подарок", deltas: [.cunning: 1],
                          reaction: "Личная коллекция пополнилась."),
                    .init("🎩 Поблагодарить", deltas: [.polite: 2],
                          reaction: "Кот где-то довольно мурлыкнул."),
                ],
                isChainStep: true,
                recallsMemoryID: memory.id
            )
        }

        return Quest(
            id: commonID,
            icon: "💭",
            text: agePhrase(for: memory) + " " + "Помнишь? \(memory.summary)",
            choices: [
                .init("😊 Помню", deltas: [.kind: 1],
                      reaction: "Хорошо, что у нас есть общая история."),
                .init("🧠 Обдумать", deltas: [.cunning: 1],
                      reaction: "Некоторые события становятся понятнее позже."),
                .init("🎉 Приукрасить историю", deltas: [.chaos: 1],
                      reaction: "Теперь она звучит ещё лучше."),
            ],
            isChainStep: true,
            recallsMemoryID: memory.id
        )
    }
}
