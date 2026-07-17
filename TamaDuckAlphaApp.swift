import SwiftUI

struct GameMenuView: View {
    @EnvironmentObject var engine: PetEngine
    @Environment(\.dismiss) private var dismiss
    @State private var choice: Int?

    var body: some View {
        switch choice {
        case 1:
            LeftRightGameView(onDone: { dismiss() }).environmentObject(engine)
        case 2:
            CatchBreadGameView(onDone: { dismiss() }).environmentObject(engine)
        default:
            VStack(spacing: 10) {
                Text("Выбери игру 🎮")
                    .font(.system(.headline, design: .rounded))
                Button("⬅️ Лево или право?") { choice = 1 }
                Button("🥖 Поймай хлеб!") { choice = 2 }
            }
            .padding(.horizontal, 4)
        }
    }
}
