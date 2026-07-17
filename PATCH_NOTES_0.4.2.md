//
//  PetEngine+Activity.swift
//  TAMA v2 — применение наград активности к питомцу
//
//  Отдельный файл-расширение: ядро PetEngine не трогаем,
//  внутренние члены доступны в пределах модуля.
//

import Foundation

@MainActor
extension PetEngine {

    /// Обновить HealthKit-снимок и применить награды.
    /// Вызывать при активации сцены и (изредка) из refresh().
    func syncActivity() async {
        await HealthKitService.shared.refresh()
        applyActivityRewards()
    }

    /// Применить награды по текущему снимку (без похода в HealthKit).
    func applyActivityRewards() {
        let rewards = ActivityReactor.shared.evaluate(
            snapshot: HealthKitService.shared.snapshot
        )
        guard !rewards.isEmpty else { return }

        pet.mood = min(100, pet.mood + rewards.moodDelta)
        if rewards.celebrate {
            pet.celebrateUntil = Date.now.addingTimeInterval(8)
        }
        if rewards.xp > 0 {
            lastEvolution = PetAction.gainXP(&pet, rewards.xp)
        }

        // M4 «живая память»: большие вехи активности становятся
        // воспоминаниями — через дни утка сама про них вспомнит.
        for item in rewards.memorySeeds {
            MemoryEngine.remember(eventID: item.eventID,
                                  choiceText: "activity",
                                  seed: item.seed,
                                  state: &pet)
        }

        save()
    }
}
