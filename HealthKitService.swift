import SwiftUI

@main
struct TamaDuckAlphaApp: App {
    @StateObject private var engine = PetEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(engine)
                .task {
                    await HealthKitService.shared.requestAuthorization()
                    await NotificationPlanner.requestAuthorization()
                    await engine.syncActivity()
                    await NotificationPlanner.syncChainNotifications(state: engine.pet)
                    await NotificationPlanner.scheduleDailyPingIfNeeded(state: engine.pet)
                }
        }
        .onChange(of: scenePhase, initial: false) { _, phase in
            switch phase {
            case .active:
                engine.refresh()
                Task {
                    await engine.syncActivity()
                    await NotificationPlanner.syncChainNotifications(state: engine.pet)
                    await NotificationPlanner.scheduleDailyPingIfNeeded(state: engine.pet)
                }
            default:
                engine.save()
                Task {
                    await NotificationPlanner.syncChainNotifications(state: engine.pet)
                }
            }
        }
    }
}
