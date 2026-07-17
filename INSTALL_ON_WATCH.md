//
//  NotificationPlanner.swift
//  TAMA v2 — локальные уведомления квестов и цепочек
//
//  Правила:
//   • не больше 2 уведомлений на один календарный день;
//   • тизеры без спойлеров;
//   • дневной пинг не переносится при каждом открытии приложения;
//   • пропущенное уведомление ничего не ломает — квест ждёт в приложении.
//

import Foundation
import UserNotifications

@MainActor
enum NotificationPlanner {

    static let chainPrefix = "tama.chain."
    static let dailyPingID = "tama.daily.ping"
    private static let maxNotificationsPerDay = 2

    private static let chainTeasers: [String: String] = [
        "beauty2": "💌 Кажется, вам письмо…",
        "beauty3": "🌹 Вас ждут у пруда.",
        "hunter2": "📢 В камышах подозрительно шумно…",
    ]

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Синхронизировать уведомления цепочек с pendingChains.
    /// Лимит применяется отдельно к каждому календарному дню.
    static func syncChainNotifications(state: PetState, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(chainPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        let existingDaily = pending.first { $0.identifier == dailyPingID }
        var usedByDay: [Date: Int] = [:]
        if let dailyDate = fireDate(for: existingDaily?.trigger, now: now, calendar: calendar) {
            usedByDay[calendar.startOfDay(for: dailyDate), default: 0] += 1
        }

        let upcoming = state.pendingChains
            .filter { $0.fireAt > now }
            .sorted { $0.fireAt < $1.fireAt }

        for step in upcoming {
            let day = calendar.startOfDay(for: step.fireAt)
            guard usedByDay[day, default: 0] < maxNotificationsPerDay else { continue }

            let content = UNMutableNotificationContent()
            content.title = "TAMA"
            content.body = chainTeasers[step.questID] ?? "🦆 Что-то происходит…"
            content.sound = .default
            content.userInfo = ["questID": step.questID]

            let interval = max(1, step.fireAt.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval,
                                                            repeats: false)
            let request = UNNotificationRequest(
                identifier: chainPrefix + step.questID,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            usedByDay[day, default: 0] += 1
        }
    }

    /// Один мягкий пинг в текущий день, с 11:00 до 17:00.
    /// Если он уже запланирован, повторный вызов ничего не меняет.
    static func scheduleDailyPingIfNeeded(state: PetState, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let pending = await center.pendingNotificationRequests()

        // Главное исправление: не удалять и не переносить уже стоящий пинг.
        if pending.contains(where: { $0.identifier == dailyPingID }) { return }
        guard state.questsAnsweredToday < Balance.questsPerDay else { return }

        let startOfToday = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(bySettingHour: 11, minute: 0, second: 0,
                                               of: startOfToday),
              let windowEnd = calendar.date(bySettingHour: 17, minute: 0, second: 0,
                                             of: startOfToday),
              now < windowEnd else { return }

        // Два уведомления в день максимум, включая цепочки.
        let notificationsToday = pending.compactMap {
            fireDate(for: $0.trigger, now: now, calendar: calendar)
        }.filter { calendar.isDate($0, inSameDayAs: now) }.count
        guard notificationsToday < maxNotificationsPerDay else { return }

        let earliest = max(windowStart, now.addingTimeInterval(60))
        guard earliest < windowEnd else { return }
        let fireAt = Date(timeIntervalSince1970: Double.random(
            in: earliest.timeIntervalSince1970 ... windowEnd.timeIntervalSince1970
        ))

        let content = UNMutableNotificationContent()
        content.title = "TAMA"
        content.body = "🦆 У меня тут кое-что случилось. Расскажу при встрече!"
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute],
                                                  from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components,
                                                    repeats: false)
        let request = UNNotificationRequest(identifier: dailyPingID,
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    /// Удалить дневной пинг после исчерпания лимита квестов.
    static func cancelDailyPingIfQuestLimitReached(state: PetState) {
        guard state.questsAnsweredToday >= Balance.questsPerDay else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyPingID])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func fireDate(for trigger: UNNotificationTrigger?,
                                 now: Date,
                                 calendar: Calendar) -> Date? {
        // У базового UNNotificationTrigger нет nextTriggerDate() —
        // метод объявлен на конкретных подклассах, нужен даункаст.
        switch trigger {
        case let calendarTrigger as UNCalendarNotificationTrigger:
            return calendarTrigger.nextTriggerDate()
        case let intervalTrigger as UNTimeIntervalNotificationTrigger:
            return intervalTrigger.nextTriggerDate()
        default:
            return nil
        }
    }

}
