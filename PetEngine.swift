// Generated integration file: Quests + Phrases

//
//  Quests.swift
//  TamaKit — квесты, цепочки и движок развития по ответам
//
//  Микроистория: событие → 3–4 варианта → ±черты → реакция.
//  Правила анти-токсичности:
//   • квест можно проигнорировать — штрафов нет;
//   • «неправильных» ответов не существует;
//   • опасности комедийные, исход всегда безопасный;
//   • не больше Balance.questsPerDay квестов в день.
//

import Foundation

// MARK: - Модели

public struct QuestChoice: Codable, Sendable {
    public let text: String            // текст кнопки (с эмодзи)
    public let deltas: [Trait: Int]    // ±1…3 к чертам
    public let reaction: String        // короткая реакция питомца
    public let startsChain: String?    // id следующего шага цепочки
    public let grantsCosmetic: String? // напр. "flower"
    public let memory: MemorySeed?      // запись в долговременную память

    public init(_ text: String, deltas: [Trait: Int], reaction: String,
                startsChain: String? = nil, grantsCosmetic: String? = nil,
                memory: MemorySeed? = nil) {
        self.text = text
        self.deltas = deltas
        self.reaction = reaction
        self.startsChain = startsChain
        self.grantsCosmetic = grantsCosmetic
        self.memory = memory
    }
}

public struct Quest: Codable, Sendable {
    public let id: String
    public let icon: String
    public let text: String
    public let choices: [QuestChoice]
    /// Шаг цепочки не попадает в случайный пул.
    public let isChainStep: Bool
    /// Для динамического квеста-воспоминания.
    public let recallsMemoryID: UUID?
    /// Служебные карточки вроде quiet_day не должны выдавать XP.
    public let awardsXP: Bool

    public init(id: String, icon: String, text: String,
                choices: [QuestChoice], isChainStep: Bool = false,
                recallsMemoryID: UUID? = nil, awardsXP: Bool = true) {
        self.id = id; self.icon = icon; self.text = text
        self.choices = choices; self.isChainStep = isChainStep
        self.recallsMemoryID = recallsMemoryID
        self.awardsXP = awardsXP
    }
}

/// Отложенный шаг цепочки («мир живёт своей жизнью»).
public struct ChainStep: Codable, Equatable, Sendable {
    public let questID: String
    public let fireAt: Date
    public init(questID: String, fireAt: Date) {
        self.questID = questID; self.fireAt = fireAt
    }
}

// MARK: - Движок

@MainActor
public enum QuestEngine {

    /// Задержка шага цепочки: 1–2 дня (живой мир, а не викторина).
    public static var chainDelay: ClosedRange<TimeInterval> = (86_400 ... 172_800)
    /// Доля обычных запросов, которые заменяются возвратом старой памяти.
    public static var memoryRecallChance: Double = 0.18

    /// Есть ли что показать прямо сейчас (вызывать из tick/onAppear).
    public static func dueQuest(for state: PetState, now: Date = .now) -> Quest? {
        // 1) созревшие шаги цепочек — приоритет
        if let step = state.pendingChains.first(where: { $0.fireAt <= now }),
           let quest = QuestCatalog.byID[step.questID] {
            return quest
        }
        // 2) воспоминание — бонусный контент со своим cooldown.
        // Оно не расходует дневной лимит, но приходит ТОЛЬКО по шансу:
        // гарантированный показ после исчерпания лимита позволял бы
        // «доить» весь запас воспоминаний за один вечер, отправляя их
        // в недельный cooldown. Память — редкая награда, а не заглушка.
        let dailyLimitReached = state.questsAnsweredToday >= Balance.questsPerDay
        if Double.random(in: 0...1) < memoryRecallChance,
           let memory = MemoryEngine.recallCandidate(in: state, now: now) {
            return MemoryQuestFactory.quest(for: memory)
        }

        // 3) обычный квест — только если дневной лимит не исчерпан.
        guard !dailyLimitReached else { return nil }
        let fresh = QuestCatalog.randomPool.filter {
            !state.completedQuestIDs.contains($0.id)
        }
        return (fresh.isEmpty ? QuestCatalog.randomPool : fresh).randomElement()
    }

    /// Игрок выбрал вариант. Мутирует состояние, возвращает реакцию
    /// и (если случилась) новую персону после эволюции.
    public static func answer(_ quest: Quest, choiceIndex: Int,
                              state: inout PetState,
                              now: Date = .now) -> (reaction: String, evolved: Persona?) {
        guard quest.choices.indices.contains(choiceIndex) else {
            return ("Квест растерял варианты. Кря.", nil)
        }
        let choice = quest.choices[choiceIndex]

        state.traits.apply(choice.deltas)
        state.completedQuestIDs.append(quest.id)
        // Пул пройден целиком — открываем заново, чтобы «свежие»
        // квесты не заканчивались навсегда.
        let poolIDs = Set(QuestCatalog.randomPool.map(\.id))
        if poolIDs.isSubset(of: Set(state.completedQuestIDs)) {
            state.completedQuestIDs.removeAll { poolIDs.contains($0) }
        }
        if state.completedQuestIDs.count > 120 {
            state.completedQuestIDs.removeFirst(state.completedQuestIDs.count - 120)
        }
        state.pendingChains.removeAll { $0.questID == quest.id }

        if quest.isChainStep == false {
            state.questsAnsweredToday += 1
            state.lastQuestDay = now
        }
        if let seed = choice.memory {
            MemoryEngine.remember(eventID: quest.id, choiceText: choice.text,
                                  seed: seed, state: &state, now: now)
        }
        if let memoryID = quest.recallsMemoryID {
            MemoryEngine.markRecalled(memoryID, state: &state, now: now)
        }
        if let cosmetic = choice.grantsCosmetic {
            state.cosmetics.insert(cosmetic)
        }
        if let next = choice.startsChain {
            let delay = TimeInterval.random(in: chainDelay)
            state.pendingChains.append(ChainStep(questID: next, fireAt: now + delay))
        }
        state.celebrateUntil = now.addingTimeInterval(4)

        let evolved: Persona?
        if quest.awardsXP {
            evolved = PetAction.gainXP(&state, Balance.xpQuest)
        } else {
            evolved = nil
        }
        return (choice.reaction, evolved)
    }

    /// Игрок проигнорировал квест — никакого штрафа.
    public static func skip(_ quest: Quest, state: inout PetState,
                            now: Date = .now) {
        state.pendingChains.removeAll { $0.questID == quest.id }
        // Пропущенное воспоминание не должно возвращаться немедленно снова.
        if let memoryID = quest.recallsMemoryID {
            MemoryEngine.markRecalled(memoryID, state: &state, now: now)
        }
        // обычный квест просто уходит; счётчик дня не тратим
    }

    /// «Не сейчас»: свайп шита без ответа. В отличие от skip,
    /// шаг цепочки НЕ удаляется, а переносится на новый срок —
    /// случайный свайп на маленьком экране не должен навсегда
    /// обрывать сюжет, который игрок ждал два дня.
    /// Воспоминание всё так же уходит в cooldown.
    public static func postpone(_ quest: Quest, state: inout PetState,
                                now: Date = .now) {
        if let memoryID = quest.recallsMemoryID {
            MemoryEngine.markRecalled(memoryID, state: &state, now: now)
            return
        }
        if let index = state.pendingChains.firstIndex(where: { $0.questID == quest.id }) {
            let delay = TimeInterval.random(in: chainDelay)
            state.pendingChains[index] = ChainStep(questID: quest.id,
                                                   fireAt: now + delay)
        }
        // обычный квест (включая quiet_day) просто уходит без последствий
    }
}

// MARK: - Каталог: 15 базовых квестов + 2 цепочки

public enum QuestCatalog {

    public static let all: [Quest] = randomPool + chainSteps
    public static let byID: [String: Quest] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    // ---- случайный пул ----------------------------------------------------

    public static let randomPool: [Quest] = [

        Quest(id: "beauty", icon: "🦆",
              text: "Вы встретили очень красивую уточку. Что сказать?",
              choices: [
            .init("😎 «Привет, красотка!»", deltas: [.brave: 2, .chaos: 1],
                  reaction: "Она улыбнулась. Кажется. Кря!", startsChain: "beauty2",
                  memory: .init(kind: .meeting, importance: 8, summary: "Ты смело познакомился с уточкой у пруда.", tags: ["duckMet", "duckNPC"])),
            .init("🎩 «Добрый вечер, мадемуазель»", deltas: [.polite: 3],
                  reaction: "Очень галантно вышло.", startsChain: "beauty2",
                  memory: .init(kind: .meeting, importance: 8, summary: "Ты галантно познакомился с уточкой у пруда.", tags: ["duckMet", "duckNPC"])),
            .init("😅 «Э… привет…»", deltas: [.kind: 1],
                  reaction: "Мило и честно. Она хихикнула.", startsChain: "beauty2",
                  memory: .init(kind: .meeting, importance: 7, summary: "Ты немного смутился, знакомясь с уточкой.", tags: ["duckMet", "duckNPC"])),
            .init("🏃 Сделать вид, что не заметил", deltas: [.cunning: 1, .brave: -1],
                  reaction: "Ну… бывает и так."),
        ]),

        Quest(id: "hunter", icon: "🏹",
              text: "В кустах появился охотник!",
              choices: [
            .init("🪶 Заклевать его", deltas: [.brave: 3, .chaos: 1],
                  reaction: "Охотник в шоке убежал. Пока что…", startsChain: "hunter2",
                  memory: .init(kind: .conflict, importance: 8, summary: "Ты прогнал комедийного охотника из кустов.", tags: ["hunter"])),
            .init("🏃 Убежать", deltas: [.cunning: 1],
                  reaction: "Скорость — тоже талант."),
            .init("🌿 Спрятаться", deltas: [.cunning: 2],
                  reaction: "Мастер маскировки, кря."),
            .init("🗿 Притвориться статуей", deltas: [.chaos: 3],
                  reaction: "Охотник протёр глаза и ушёл."),
        ]),

        Quest(id: "fries", icon: "🍟",
              text: "На земле лежит картошка фри.",
              choices: [
            .init("😋 Съесть сразу", deltas: [.brave: 1],
                  reaction: "Ням. Без комментариев."),
            .init("🤝 Поделиться", deltas: [.kind: 3],
                  reaction: "Воробьи в восторге."),
            .init("🏠 Отнести домой", deltas: [.cunning: 1, .kind: 1],
                  reaction: "Запасливость — добродетель."),
            .init("🎩 Не трогать", deltas: [.polite: 2],
                  reaction: "Мало ли где она лежала."),
        ]),

        Quest(id: "goose", icon: "🪿",
              text: "Огромный гусь перегородил дорогу.",
              choices: [
            .init("🥊 Начать драку", deltas: [.brave: 3],
                  reaction: "Ничья. Но какой характер!"),
            .init("🎩 Вежливо попросить пройти", deltas: [.polite: 3],
                  reaction: "Гусь удивился и пропустил."),
            .init("🧠 Обойти", deltas: [.cunning: 2],
                  reaction: "Зачем конфликты, когда есть обходные пути."),
            .init("📣 Громко накрякать", deltas: [.chaos: 2],
                  reaction: "Гусь зааплодировал крыльями."),
        ]),

        Quest(id: "fisherman", icon: "🎣",
              text: "Рыбак поймал большую рыбу.",
              choices: [
            .init("🧠 Украсть", deltas: [.cunning: 2, .chaos: 1],
                  reaction: "Операция «Рыба» прошла успешно. Почти."),
            .init("🎩 Попросить кусочек", deltas: [.polite: 2],
                  reaction: "Рыбак не устоял перед манерами."),
            .init("🤝 Помочь", deltas: [.kind: 3],
                  reaction: "Вдвоём вытащили. Кусочек — ваш."),
            .init("🚶 Уйти", deltas: [.cunning: 1],
                  reaction: "Не наша рыба — не наши проблемы."),
        ]),

        Quest(id: "mirror", icon: "🪞",
              text: "Вы нашли зеркало.",
              choices: [
            .init("😎 Любоваться собой", deltas: [.brave: 1, .chaos: 1],
                  reaction: "Красота — страшная сила."),
            .init("🤪 Скорчить рожицу", deltas: [.chaos: 2],
                  reaction: "Зеркало, кажется, хихикнуло."),
            .init("🚶 Пройти мимо", deltas: [.cunning: 1],
                  reaction: "Некогда, дела."),
            .init("✨ Почистить зеркало", deltas: [.polite: 2, .kind: 1],
                  reaction: "Теперь блестит. Как и вы."),
        ]),

        Quest(id: "rain", icon: "🌧",
              text: "Начался ливень!",
              choices: [
            .init("💃 Танцевать", deltas: [.chaos: 3],
                  reaction: "Лучший танец сезона дождей."),
            .init("🏠 Искать укрытие", deltas: [.cunning: 2],
                  reaction: "Сухо и стратегично."),
            .init("🏊 Плавать в луже", deltas: [.chaos: 2, .luck: 1],
                  reaction: "Личный бассейн! Кря!"),
            .init("😴 Спать под шум дождя", deltas: [.luck: 1],
                  reaction: "Лучшая колыбельная — ливень."),
        ]),

        Quest(id: "lostDuckling", icon: "🐥",
              text: "Маленький утёнок потерялся и плачет.",
              choices: [
            .init("🤝 Помочь найти маму", deltas: [.kind: 3],
                  reaction: "Семья воссоединилась. Все крякают от счастья.",
                  memory: .init(kind: .kindness, importance: 9, summary: "Ты помог потерявшемуся утёнку найти семью.", tags: ["rescuedDuckling"])),
            .init("🏊 Научить плавать, чтобы отвлечь", deltas: [.kind: 2, .brave: 1],
                  reaction: "Утёнок уже почти чемпион."),
            .init("📣 Позвать взрослых уток", deltas: [.polite: 2],
                  reaction: "Организованно и правильно."),
            .init("🤳 Сделать селфи", deltas: [.chaos: 2, .kind: -1],
                  reaction: "Утёнок засмеялся. Ладно, потом помогли."),
        ]),

        Quest(id: "coin", icon: "🪙",
              text: "Под лапой блестит монета.",
              choices: [
            .init("💰 Забрать", deltas: [.cunning: 1],
                  reaction: "В хозяйстве пригодится."),
            .init("🤝 Отдать хозяину", deltas: [.kind: 2],
                  reaction: "Честная утка — счастливая утка."),
            .init("🍬 Купить вкусняшку", deltas: [.luck: 1],
                  reaction: "Инвестиция в хорошее настроение."),
            .init("🕳 Закопать на чёрный день", deltas: [.chaos: 2, .cunning: 1],
                  reaction: "Пиратские замашки, кря."),
        ]),

        Quest(id: "crow", icon: "🐦",
              text: "Ворона смеётся над вами.",
              choices: [
            .init("😂 Посмеяться вместе", deltas: [.kind: 2],
                  reaction: "Смех продлевает жизнь. Даже утиную."),
            .init("😤 Обидеться", deltas: [.brave: -1],
                  reaction: "Ну и пусть. Хмф."),
            .init("🎭 Ответить шуткой", deltas: [.cunning: 2, .chaos: 1],
                  reaction: "Ворона зависла. Победа интеллекта."),
            .init("⚔️ Дуэль взглядов", deltas: [.brave: 3],
                  reaction: "Ворона моргнула первой!"),
        ]),

        Quest(id: "cat", icon: "🐈",
              text: "Кот внимательно смотрит на вас.",
              choices: [
            .init("🎩 Поздороваться", deltas: [.polite: 2],
                  reaction: "Кот кивнул. Уважение."),
            .init("🏃 Убежать", deltas: [.cunning: 1],
                  reaction: "Осторожность — не трусость."),
            .init("🪶 Клюнуть первым", deltas: [.brave: 2, .chaos: 1],
                  reaction: "Кот такого не ожидал."),
            .init("🤝 Подружиться", deltas: [.kind: 3, .luck: 1],
                  reaction: "Невероятный союз. Кот мурчит.",
                  memory: .init(kind: .relationship, importance: 8, summary: "Ты подружился с котом у пруда.", tags: ["catFriend"])),
        ]),

        Quest(id: "bread", icon: "🥖",
              text: "Кто-то бросил целую булку!",
              choices: [
            .init("😋 Всё съесть", deltas: [.brave: 1],
                  reaction: "Рекорд. Не повторять."),
            .init("🤝 Разделить с друзьями", deltas: [.kind: 3],
                  reaction: "Пир на весь пруд."),
            .init("🧠 Спрятать половину", deltas: [.cunning: 2],
                  reaction: "Стратегический запас создан."),
            .init("🐦 Покормить других птиц", deltas: [.kind: 2, .polite: 1],
                  reaction: "Воробьи назвали вас святой уткой."),
        ]),

        Quest(id: "photographer", icon: "📸",
              text: "Турист хочет вас сфотографировать.",
              choices: [
            .init("😎 Позировать", deltas: [.brave: 2],
                  reaction: "Обложка журнала обеспечена."),
            .init("🤪 Смешная морда", deltas: [.chaos: 2],
                  reaction: "Фото стало мемом. Вы знамениты."),
            .init("🕊 Улететь в кадре", deltas: [.cunning: 1],
                  reaction: "Загадочность — тоже стиль."),
            .init("🥖 Потребовать оплату хлебом", deltas: [.cunning: 3],
                  reaction: "Сделка века: фото за булку."),
        ]),

        Quest(id: "elder", icon: "🦆",
              text: "Старый селезень предлагает совет.",
              choices: [
            .init("👂 Выслушать", deltas: [.polite: 2],
                  reaction: "Мудрость лишней не бывает."),
            .init("🗣 Перебить", deltas: [.brave: 1, .polite: -1],
                  reaction: "Селезень вздохнул. Молодёжь…"),
            .init("🤝 Поблагодарить", deltas: [.kind: 2],
                  reaction: "Селезень растрогался."),
            .init("🙃 Сделать наоборот", deltas: [.chaos: 3],
                  reaction: "…и это тоже сработало?!"),
        ]),

        Quest(id: "door", icon: "🚪",
              text: "Посреди леса стоит дверь.",
              choices: [
            .init("😎 Открыть", deltas: [.brave: 2, .chaos: 1],
                  reaction: "За дверью — другая сторона леса. Но как эффектно!",
                  memory: .init(kind: .discovery, importance: 7, summary: "Ты открыл странную дверь посреди леса.", tags: ["forestDoor"])),
            .init("🎩 Постучать", deltas: [.polite: 2],
                  reaction: "Никто не открыл, но манеры засчитаны."),
            .init("👀 Заглянуть в щель", deltas: [.cunning: 2],
                  reaction: "Разведка прежде всего."),
            .init("🚶 Уйти", deltas: [.luck: 1],
                  reaction: "Некоторые двери лучше не трогать."),
        ]),
    ]

    // ---- шаги цепочек (в случайный пул не попадают) ------------------------

    public static let chainSteps: [Quest] = [

        // Цепочка «Роман» 🌹: beauty → beauty2 (💌) → beauty3 (🌹, цветок)
        Quest(id: "beauty2", icon: "💌",
              text: "Та самая уточка прислала письмо! Ответить?",
              choices: [
            .init("✍️ Написать ответ", deltas: [.kind: 2, .brave: 1],
                  reaction: "Письмо отправлено. Сердечко стучит.", startsChain: "beauty3"),
            .init("😳 Ответить смайликом", deltas: [.kind: 1, .chaos: 1],
                  reaction: "🦆❤️ — лаконично!", startsChain: "beauty3"),
            .init("📖 Спросить совета у хозяина", deltas: [.polite: 2, .kind: 1],
                  reaction: "Вдвоём сочинили отличный ответ.", startsChain: "beauty3"),
            .init("🙈 Спрятать письмо под крыло", deltas: [.cunning: 1],
                  reaction: "Пусть полежит. Пока."),
        ], isChainStep: true),

        Quest(id: "beauty3", icon: "🌹",
              text: "Она приглашает вас на прогулку у пруда!",
              choices: [
            .init("🚶 Конечно, пойти!", deltas: [.brave: 2, .kind: 2, .luck: 1],
                  reaction: "Прогулка удалась! Она подарила цветок 🌸",
                  grantsCosmetic: "flower",
                  memory: .init(kind: .gift, importance: 10, summary: "Уточка подарила тебе цветок после прогулки.", tags: ["romance", "flower"])),
            .init("🧺 Прийти с корзинкой хлеба", deltas: [.polite: 3, .kind: 1],
                  reaction: "Пикник у пруда. Идеально. И цветок 🌸",
                  grantsCosmetic: "flower",
                  memory: .init(kind: .gift, importance: 10, summary: "После пикника у пруда ты получил цветок.", tags: ["romance", "flower"])),
            .init("💃 Прийти и станцевать", deltas: [.chaos: 3],
                  reaction: "Она смеялась до слёз. Цветок ваш 🌸",
                  grantsCosmetic: "flower",
                  memory: .init(kind: .gift, importance: 10, summary: "Твой танец рассмешил уточку, и она подарила цветок.", tags: ["romance", "flower"])),
            .init("😴 Проспать", deltas: [.luck: -1],
                  reaction: "Эх… Но она не обиделась."),
        ], isChainStep: true),

        // Цепочка «Погоня» 🏃: hunter → hunter2 (финал безопасный)
        Quest(id: "hunter2", icon: "📢",
              text: "Охотник вернулся с друзьями! Что делаем?",
              choices: [
            .init("🏃 Убегать зигзагами", deltas: [.brave: 1, .cunning: 1],
                  reaction: "Все запутались и разошлись. Кря."),
            .init("🌾 Спрятаться в камышах", deltas: [.cunning: 2],
                  reaction: "Никто ничего не нашёл. Профи."),
            .init("🗿 Снова статуя", deltas: [.chaos: 2, .luck: 1],
                  reaction: "Теперь они спорят, была ли утка вообще."),
            .init("🪿 Позвать на помощь гуся", deltas: [.kind: 1, .brave: 1],
                  reaction: "Гусь всех разогнал. Дружба!"),
        ], isChainStep: true),
    ]
}


//
//  Phrases.swift
//  TamaKit — слоёная система фраз
//
//  Устройство:
//   • Утёнок и 4 архетипа — полные пулы (30 фраз: 7 категорий).
//   • Каждая профессия — «колорит» из 12 фраз, который ДОБАВЛЯЕТСЯ
//     к пулу её архетипа. Итого профессия говорит 40+ репликами
//     без дублирования текста.
//  Тон везде: тёплый, слегка ироничный, никогда не обвиняющий.
//  Все фразы оригинальные (без цитат Disney/WB).
//

import Foundation

public enum PhraseCategory: String, Codable, CaseIterable, Sendable {
    case morning    // проснулся
    case hungry     // голодный
    case thirsty    // хочет воды
    case bored      // скучает
    case content    // довольный
    case happy      // радуется
    case evening    // устал, пора спать
}

public enum PhraseBook {

    /// Главная точка входа: пул фраз для персоны и категории.
    public static func phrases(for persona: Persona,
                               category: PhraseCategory) -> [String] {
        switch persona {
        case .duckling:
            return duckling[category] ?? []
        case .archetype(let a):
            return base(for: a)[category] ?? []
        case .profession(let p):
            let inherited = base(for: p.archetype)[category] ?? []
            let flavor = professionFlavor[p]?[category] ?? []
            return flavor + inherited   // колорит показываем чаще
        }
    }

    /// Случайная фраза без повтора предыдущей.
    public static func random(for persona: Persona,
                              category: PhraseCategory,
                              avoiding last: String? = nil) -> String? {
        var pool = phrases(for: persona, category: category)
        if pool.count > 1, let last { pool.removeAll { $0 == last } }
        return pool.randomElement()
    }

    static func base(for archetype: Archetype) -> [PhraseCategory: [String]] {
        switch archetype {
        case .star:  return star
        case .gent:  return gent
        case .sly:   return sly
        case .grump: return grump
        }
    }

    // =====================================================================
    // ПОЛНЫЕ ПУЛЫ (по 30 фраз)
    // =====================================================================

    // ---- Утёнок (ур. 1, нейтрально-милый) ----
    static let duckling: [PhraseCategory: [String]] = [
        .morning: [
            "Доброе утро! Я бы позавтракала.",
            "Проснулась! Где завтрак, кря?",
            "Утро! Сегодня будет хороший день.",
            "Кря. Потягу-у-ушки…",
        ],
        .hungry: [
            "Кря. Я бы что-нибудь съела.",
            "Кажется, время подкрепиться. Нам обоим.",
            "Хлебушек сам себя не съест.",
            "В животике крякает.",
            "Я не жалуюсь, но… еда?",
        ],
        .thirsty: [
            "Водички бы. Тебе, кстати, тоже.",
            "Кря-кря. Пить хочется.",
            "Горлышко пересохло.",
            "Вода — лучший друг утки.",
        ],
        .bored: [
            "Мы давно сидим. Пройдёмся чуть-чуть?",
            "Скучновато. Может, поиграем?",
            "Я насчитала ноль шагов за час. Кря.",
            "Полетать бы… ну или хотя бы походить.",
            "Эй. Я тут. Скучаю.",
        ],
        .content: [
            "Хороший день, кря.",
            "Мне нравится наш режим.",
            "Сижу. Наблюдаю. Одобряю.",
            "Всё как надо.",
            "Ты рядом — и хорошо.",
        ],
        .happy: [
            "Кря-кря! Вот это я понимаю!",
            "Отличная прогулка. Я почти летала!",
            "Мы молодцы. Оба.",
            "Ура-а-а! Кря!",
            "Вот это денёк!",
        ],
        .evening: [
            "Зеваю… День был хороший.",
            "Пора в домик. Спокойной ночи.",
        ],
    ]

    // ---- Звезда 🎩 (смелость + безуминка) ----
    static let star: [PhraseCategory: [String]] = [
        .morning: [
            "Звезда проснулась. Можно начинать день.",
            "Утро. Мой выход, кря!",
            "Публика ждёт. Я почти готов.",
            "Доброе утро. Гримёрку и завтрак!",
        ],
        .hungry: [
            "Звёзды не ждут обед. Это обед ждёт звёзд. Но недолго!",
            "Это МОЙ хлебушек. Где он?",
            "Гению нужен антракт. И бутерброд.",
            "Кормите артиста, иначе концерт отменяется.",
            "В контракте написано: обед по расписанию!",
        ],
        .thirsty: [
            "Минеральной! Для голоса!",
            "Гению нужна вода. Немедленно, кря.",
            "Без воды не берутся верхние ноты.",
            "Воды! Сцена ждать не будет.",
        ],
        .bored: [
            "Публика заскучала. И я тоже.",
            "Дорогу таланту! Пойдём покажемся миру.",
            "Мой выход задерживается. Непорядок.",
            "Без зрителей я тускнею. Кря.",
            "Прогулка — это тоже гастроли.",
        ],
        .content: [
            "Я великолепен. Как всегда.",
            "Гений за работой. Не мешать.",
            "Кря. Совершенство требует покоя.",
            "Сегодняшний я — лучший я.",
            "Аншлаг у меня в душе.",
        ],
        .happy: [
            "Аплодисменты! Овации!",
            "Видали?! Вот это класс!",
            "Триумф! Мой. Ну и твой немножко.",
            "Бис! Ещё раз так же!",
            "Это войдёт в мои мемуары.",
        ],
        .evening: [
            "Занавес. Звезде нужен сон красоты.",
            "Гастроли окончены. До завтра, поклонники.",
        ],
    ]

    // ---- Джентльмен 🧐 (вежливость + доброта) ----
    static let gent: [PhraseCategory: [String]] = [
        .morning: [
            "Доброе утро. Позвольте узнать, что на завтрак?",
            "Прекрасное утро, не находите?",
            "Проснулся. Готов к добрым делам.",
            "Утро начинается с манер. И овсянки.",
        ],
        .hungry: [
            "Не сочтите за дерзость, но обед был бы кстати.",
            "Кря. Лёгкий голод. Ничего страшного, я подожду.",
            "Трапеза по расписанию — признак хорошего тона.",
            "Я бы не отказался от небольшого угощения.",
            "Голод — не повод терять манеры.",
        ],
        .thirsty: [
            "Стакан воды, будьте любезны.",
            "Немного воды — и я снова в форме.",
            "Позвольте освежиться.",
            "Воды комнатной температуры, если можно.",
        ],
        .bored: [
            "Не желаете ли прогуляться? Погода дивная.",
            "Позвольте предложить небольшой моцион.",
            "Праздность утомляет сильнее работы.",
            "Свежий воздух пойдёт нам на пользу.",
            "Небольшая прогулка — и день заиграет.",
        ],
        .content: [
            "Всё в полном порядке, благодарю.",
            "Прекрасный день, не правда ли? Кря.",
            "Гармония. Иначе не скажешь.",
            "Весьма, весьма недурно.",
            "Благодарю за заботу. Это взаимно.",
        ],
        .happy: [
            "Восхитительно! Браво нам.",
            "Чудесно провели время, кря.",
            "Снимаю цилиндр. Великолепно!",
            "Такие дни хочется вписать в дневник.",
            "Позвольте выразить восторг!",
        ],
        .evening: [
            "Пора отойти ко сну. Благодарю за день.",
            "Спокойной ночи. Завтра будем не хуже.",
        ],
    ]

    // ---- Хитрюга 🧢 (хитрость + смелость) ----
    static let sly: [PhraseCategory: [String]] = [
        .morning: [
            "Утро. У меня уже три плана на день.",
            "Проснулся раньше будильника. Так и задумано.",
            "Утро — лучшее время для хитрых идей.",
            "Кря. План на день: завтрак. Остальное по обстановке.",
        ],
        .hungry: [
            "Есть план: ты меня кормишь, я не ворчу. Все в плюсе.",
            "Где-то тут был припрятан хлебушек…",
            "Голодный хитрец — опасный хитрец.",
            "Обед — это инвестиция в моё хорошее поведение.",
            "Так, тайник пуст. Переходим к плану Б: ты.",
        ],
        .thirsty: [
            "Вода. Срочно. Потом объясню зачем.",
            "Пить. Это часть плана, кря.",
            "Без воды мозг хитрит хуже.",
            "Обменяю одну гениальную идею на стакан воды.",
        ],
        .bored: [
            "Скучно. Пойдём поищем приключений?",
            "У меня есть одна идейка… кря-кря.",
            "Сидеть на месте — не мой метод.",
            "Разведка местности ещё никому не вредила.",
            "Скука — это нераскрытое дело.",
        ],
        .content: [
            "Всё идёт по плану.",
            "Неплохо. Как я и рассчитывал.",
            "Ситуация под контролем. Моим.",
            "Кря. Всё схвачено.",
            "День складывается подозрительно хорошо.",
        ],
        .happy: [
            "Ха! Сработало!",
            "Говорил же — план надёжный!",
            "Гениально. Даже для меня.",
            "Вот это комбинация! Запишем.",
            "Удача любит подготовленных. Меня то есть.",
        ],
        .evening: [
            "Сворачиваем операции. До завтра.",
            "Сон — тоже часть плана.",
        ],
    ]

    // ---- Ворчун 🧣 (характер режима) ----
    static let grump: [PhraseCategory: [String]] = [
        .morning: [
            "Подъём! Завтрак сам себя не съест!",
            "Утро. Ворчать начну после завтрака.",
            "Опять утро. Ну ладно, хорошее.",
            "Встал. Требую кашу и уважение.",
        ],
        .hungry: [
            "Обед?! Опять опаздывает! Кря!",
            "Я тут, между прочим, голодаю. Безобразие.",
            "Ну и сервис… Ладно, жду.",
            "Режим питания нарушен! Так и запишем.",
            "Ворчу, потому что голодный. Логично же.",
        ],
        .thirsty: [
            "Воды! Сколько можно ждать!",
            "В горле пересохло, а всем всё равно. Кря.",
            "Без воды буду ворчать вдвое громче.",
            "Воды, пожалуйста. Да, я сказал «пожалуйста». Не привыкай.",
        ],
        .bored: [
            "Сидим. Опять сидим. Возмутительно!",
            "Никто со мной не гуляет. Так и запишем.",
            "Кря. Скука — это нарушение режима!",
            "В моё время утки гуляли по три раза в день!",
            "Я не скучаю. Я возмущаюсь молча.",
        ],
        .content: [
            "Хм. Ну ладно. Неплохо.",
            "Так уж и быть, я доволен.",
            "Порядок. Порядок я уважаю.",
            "Не к чему придраться. Подозрительно.",
            "Ладно. Признаю. Хороший день.",
        ],
        .happy: [
            "Кря! Вот это другое дело!",
            "Ну наконец-то повеселились как следует!",
            "Ладно-ладно, признаю: было здорово.",
            "Так бы каждый день!",
            "Ворчать не о чем. Странное чувство.",
        ],
        .evening: [
            "Отбой по расписанию. Хоть что-то по расписанию!",
            "Спать. И чтобы утром завтрак вовремя!",
        ],
    ]

    // =====================================================================
    // КОЛОРИТ ПРОФЕССИЙ (по 12 фраз, добавляются к пулу архетипа)
    // =====================================================================

    static let professionFlavor: [Profession: [PhraseCategory: [String]]] = [

        // ---- ветка Звезды ----
        .king: [
            .morning: ["Королевство проснулось вместе со мной.",
                       "Утро. Корону и завтрак."],
            .hungry:  ["Королевский обед задерживается. Казнить не буду, но запомню.",
                       "Даже король не может править на пустой желудок."],
            .bored:   ["Скучно. Объявляю королевскую прогулку!",
                       "Трон удобный, но лапы затекают."],
            .content: ["В королевстве покой и порядок.",
                       "Правлю. Доволен. Кря."],
            .happy:   ["Королевский указ: сегодня отличный день!",
                       "Пир на весь мир! Ну, на нас двоих."],
            .evening: ["Король удаляется в опочивальню.",
                       "Даже короли ложатся по режиму."],
        ],
        .musician: [
            .morning: ["Утро начинается с ля-минора… нет, с завтрака.",
                       "Проснулся с мелодией в голове. Кря-кря-кря — уже хит."],
            .hungry:  ["Голодный музыкант играет грустное.",
                       "Покорми меня — и я сочиню тебе оду."],
            .bored:   ["Без движения нет ритма. Пойдём!",
                       "Тишина хороша только между нотами."],
            .content: ["Сегодня всё звучит правильно.",
                       "Наш день — в мажоре."],
            .happy:   ["Это была симфония, а не прогулка!",
                       "Бис! Браво! Кря!"],
            .evening: ["Колыбельную себе — и спать.",
                       "Финальный аккорд дня. До завтра."],
        ],
        .artist: [
            .morning: ["Утро — чистый холст.",
                       "Проснулся. Ищу вдохновение и завтрак."],
            .hungry:  ["Голодный художник рисует только еду.",
                       "Натюрморт с хлебушком. Срочно."],
            .bored:   ["Серо как-то. Добавим красок — пойдём гулять!",
                       "Муза ушла. Догоним её на прогулке?"],
            .content: ["Сегодняшний день — тёплая палитра.",
                       "Смотрю на мир. Красиво, кря."],
            .happy:   ["Шедевр! Этот день — шедевр!",
                       "Вот это композиция! Запомню и нарисую."],
            .evening: ["Закат — лучшая картина. Спокойной ночи.",
                       "Кисти помыты, утка спит."],
        ],
        .chef: [
            .morning: ["Утро! Что у нас в меню?",
                       "Завтрак — главное блюдо дня, кря."],
            .hungry:  ["Шеф голодный — кухня в опасности.",
                       "Дегустация просрочена! Требую обед."],
            .bored:   ["Пойдём! Нагуляем аппетит.",
                       "Скука — как суп без соли."],
            .content: ["День приготовлен идеально.",
                       "Всё по рецепту. Одобряю."],
            .happy:   ["Пальчики оближешь, а не день!",
                       "Комплимент от шефа: мы молодцы!"],
            .evening: ["Кухня закрыта. Все спать.",
                       "Завтра — новое меню. Спокойной ночи."],
        ],

        // ---- ветка Джентльмена ----
        .scientist: [
            .morning: ["Утро. Начинаем эксперимент «Хороший день».",
                       "Гипотеза: завтрак повысит настроение. Проверим?"],
            .hungry:  ["Уровень глюкозы критически низок. Кря.",
                       "Наука доказала: голодная утка — грустная утка."],
            .bored:   ["Данных мало. Нужна полевая вылазка!",
                       "Застой — враг исследований. Идём!"],
            .content: ["Показатели в норме. Эксперимент успешен.",
                       "Наблюдаю. Фиксирую. Доволен."],
            .happy:   ["Эврика! Отличный результат!",
                       "Публикуем: лучший день в истории наблюдений!"],
            .evening: ["Лабораторный журнал закрыт. Спать.",
                       "Сон — важнейший эксперимент. Начинаем."],
        ],
        .detective: [
            .morning: ["Утро. Новое дело: где завтрак?",
                       "Проснулся. Улики указывают на хороший день."],
            .hungry:  ["Дело о пропавшем обеде. Подозреваемый — ты.",
                       "Голод. Элементарно, кря."],
            .bored:   ["Застой в расследовании. Нужен обход территории!",
                       "Скука подозрительна. Проверим окрестности?"],
            .content: ["Все дела раскрыты. Отдыхаю.",
                       "Ничего подозрительного. Даже приятно."],
            .happy:   ["Дело закрыто блестяще!",
                       "Вот это поворот! Отличный день!"],
            .evening: ["Архив закрыт. Детектив спит.",
                       "Завтра — новые загадки. Спокойной ночи."],
        ],
        .captain: [
            .morning: ["Свистать всех на завтрак!",
                       "Утро. Курс — на хороший день."],
            .hungry:  ["Камбуз пуст! Бунт на корабле близко.",
                       "Капитан требует провиант, кря."],
            .bored:   ["Штиль. Команде — прогулка!",
                       "Засиделись в порту. Отдать швартовы!"],
            .content: ["Идём ровным курсом.",
                       "На борту порядок. Капитан доволен."],
            .happy:   ["Семь футов под килем! Отличный день!",
                       "Полный вперёд! Вот это ход!"],
            .evening: ["Вахта окончена. Отбой.",
                       "Бросаем якорь до утра."],
        ],
        .astronaut: [
            .morning: ["Подъём! Стыковка с завтраком через минуту.",
                       "Доброе утро, Земля. Кря."],
            .hungry:  ["Запасы на борту исчерпаны!",
                       "Космический обед… где он?"],
            .bored:   ["Невесомость — это когда весь день сидишь. Идём!",
                       "Запрашиваю разрешение на выход… на прогулку."],
            .content: ["Полёт нормальный.",
                       "Все системы в норме, кря."],
            .happy:   ["Это маленький шаг для утки… и отличный день!",
                       "Орбита счастья достигнута!"],
            .evening: ["Переход в спящий режим.",
                       "До связи утром. Отбой."],
        ],

        // ---- ветка Хитрюги ----
        .pirate: [
            .morning: ["Йо-хо-хо! Где мой завтрак, кря?",
                       "Утро. Поднять паруса и настроение!"],
            .hungry:  ["Сундук с провиантом пуст! Непорядок!",
                       "Голодный пират — гроза холодильника."],
            .bored:   ["Засиделись на суше. Идём за приключениями!",
                       "Скука — хуже штиля."],
            .content: ["Добыча есть, команда сыта. Красота.",
                       "Спокойное море. Подозрительно, но приятно."],
            .happy:   ["Вот это сокровище, а не день!",
                       "Йо-хо-хо! Кря-кря-кря!"],
            .evening: ["Пират ложится в трюм. До утра.",
                       "Карта под подушкой, сон по курсу."],
        ],
        .ninja: [
            .morning: ["…я уже давно проснулся. Ты не заметил.",
                       "Утро. Бесшумно требую завтрак."],
            .hungry:  ["Даже ниндзя не может красться на пустой желудок.",
                       "Миссия «Обед». Статус: ожидание."],
            .bored:   ["Навыки ржавеют. Тренировочная вылазка?",
                       "Слишком тихо. Даже для меня. Идём."],
            .content: ["Равновесие достигнуто.",
                       "Тень довольна. То есть я."],
            .happy:   ["Молниеносно и великолепно!",
                       "Миссия выполнена безупречно!"],
            .evening: ["Растворяюсь в ночи. То есть сплю.",
                       "Даже тени отдыхают."],
        ],
        .engineer: [
            .morning: ["Утро. Запускаем систему «Хороший день».",
                       "Проснулся. Механизмы смазаны, нужен завтрак."],
            .hungry:  ["Топливо на нуле! Требуется дозаправка.",
                       "Без обеда КПД падает катастрофически."],
            .bored:   ["Простой оборудования! Нужна прогулка.",
                       "Идём — проверим ходовую часть. Мою."],
            .content: ["Всё работает как часы.",
                       "Система стабильна. Инженер доволен."],
            .happy:   ["Механизм дня сработал идеально!",
                       "Вот это производительность!"],
            .evening: ["Плановое отключение. До утра.",
                       "Техобслуживание сном. Начинаем."],
        ],
        .sheriff: [
            .morning: ["Утро. В городе спокойно. Пока что.",
                       "Шериф проснулся. Завтрак, живо, кря."],
            .hungry:  ["Нарушение! Обед не явился вовремя.",
                       "Голодный шериф строже вдвойне."],
            .bored:   ["Пора на обход территории!",
                       "В городе слишком тихо. Проверим?"],
            .content: ["Порядок в городе. Порядок в душе.",
                       "Всё по закону. Одобряю."],
            .happy:   ["За такой день — медаль нам обоим!",
                       "Йи-ха! Кря!"],
            .evening: ["Участок закрыт. Шериф спит.",
                       "Ночная смена — у звёзд. Отбой."],
        ],
        .hooligan: [
            .morning: ["Ну чё, проснулись? Завтрак где?",
                       "Утро. Кто рано встаёт — тому весь хлеб."],
            .hungry:  ["Эй! Хлеб сюда, быстро! …пожалуйста.",
                       "Голодный я — вредный я."],
            .bored:   ["Скукота-а-а. Пошли наводить движуху! Ну, гулять.",
                       "Сидеть — это для голубей. Идём!"],
            .content: ["Ладно, день ничё так.",
                       "Не трогайте меня, я доволен."],
            .happy:   ["Вот это движуха! Кря!",
                       "Ха! Красота, а не день!"],
            .evening: ["Всё, разошлись. Я спать.",
                       "Даже хулиганам нужен режим. Но никому не говори."],
        ],

        // ---- ветка Ворчуна ----
        .knight: [
            .morning: ["Рассвет! Рыцарь готов к подвигам. После завтрака.",
                       "Утро. Доспехи начищены, желудок пуст."],
            .hungry:  ["Даже дракона не одолеть на пустой желудок!",
                       "Провиант! Во имя режима!"],
            .bored:   ["Рыцарь без похода ржавеет. Идём!",
                       "Подвиги сами себя не совершат."],
            .content: ["Честь соблюдена, режим тоже.",
                       "На страже твоего дня. Всё спокойно."],
            .happy:   ["Победа! Славная победа!",
                       "Этот день достоин баллады!"],
            .evening: ["Меч в ножны, рыцарь — в постель.",
                       "Стража сменяется сном."],
        ],
        .scout: [
            .morning: ["Подъём! Скаут всегда готов. К завтраку.",
                       "Утро! Проверим снаряжение и кашу."],
            .hungry:  ["Запасы в рюкзаке кончились!",
                       "Скаут голодный — костёр грустный."],
            .bored:   ["Тропа зовёт! Идём разведаем.",
                       "Настоящий скаут не сидит на месте."],
            .content: ["Лагерь в порядке, скаут доволен.",
                       "Хороший день для похода. Любой день хороший."],
            .happy:   ["Значок за лучший день — наш!",
                       "Вот это поход! Кря!"],
            .evening: ["Костёр потушен, скаут спит.",
                       "Палатка ждёт. Отбой."],
        ],
        .explorer: [
            .morning: ["Утро! Что сегодня откроем?",
                       "Проснулся. Экспедиция «Завтрак» начинается."],
            .hungry:  ["Провизия на исходе! Кря.",
                       "Великие открытия начинаются с обеда."],
            .bored:   ["Белые пятна на карте ждут! Идём.",
                       "Исследователь в четырёх стенах — печальное зрелище."],
            .content: ["Экспедиция идёт по плану.",
                       "Открытие дня: всё хорошо."],
            .happy:   ["Терра инкогнита покорена!",
                       "Это открытие века! Ну, дня."],
            .evening: ["Записал в дневник экспедиции. Спать.",
                       "Завтра — новые земли. Отбой."],
        ],
        .mage: [
            .morning: ["Утро. Восстанавливаю ману завтраком.",
                       "Проснулся. Предсказываю хороший день."],
            .hungry:  ["Мана на нуле! Нужен хлеб силы.",
                       "Даже магия не работает на голодный желудок."],
            .bored:   ["Застой магии! Нужна прогулка-ритуал.",
                       "Хрустальный шар показывает: пора гулять."],
            .content: ["Магический баланс достигнут.",
                       "Всё заколдовано правильно."],
            .happy:   ["Абра-кря-дабра! Волшебный день!",
                       "Заклинание счастья сработало!"],
            .evening: ["Гашу волшебный огонь. Спать.",
                       "Сон — древнейшая магия. Практикую."],
        ],
    ]
}
