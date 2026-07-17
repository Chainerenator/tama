import SwiftUI

struct MoreMenuView: View {
    @EnvironmentObject var engine: PetEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showMemory = false
    @State private var showReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("TAMA Alpha 0.5.3.2")
                    .font(.system(.headline, design: .rounded))

                Button("🚶 Прогулка") { engine.walk(); dismiss() }
                    .disabled(engine.isNightLocked)
                Button("📖 Память: \(engine.pet.memories.count)") { showMemory = true }

                Divider()
                Text("Alpha tools")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Button("⭐️ +100 XP") { engine.addTestXP() }
                Button("🎭 Следующий спрайт") { engine.cyclePersona() }
                Button("🌸 Цветок on/off") { engine.toggleFlower() }
                Button("🧠 Добавить память") { engine.seedMemoryDemo() }
                Button("❓ Сбросить лимит квестов") { engine.resetQuestLimit() }
                Button(engine.nightLockEnabled
                       ? "🌙 Ночная блокировка: вкл"
                       : "🌙 Ночная блокировка: выкл") {
                    engine.nightLockEnabled.toggle()
                }
                Button("🏃 Сбросить вехи активности") {
                    ActivityReactor.shared.resetForTesting()
                }
                Button("🔔 Переставить уведомления") {
                    Task {
                        await NotificationPlanner.syncChainNotifications(state: engine.pet)
                        await NotificationPlanner.scheduleDailyPingIfNeeded(state: engine.pet)
                    }
                }
                Button("🐥 Новая утка", role: .destructive) { showReset = true }
            }
        }
        .sheet(isPresented: $showMemory) {
            MemoryView().environmentObject(engine)
        }
        .alert("Начать заново?", isPresented: $showReset) {
            Button("Новая утка", role: .destructive) {
                engine.resetPet(); dismiss()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}
