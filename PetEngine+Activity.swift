import SwiftUI

struct MainView: View {
    @EnvironmentObject var engine: PetEngine
    @State private var showGames = false
    @State private var showQuest = false
    @State private var showMore = false
    @State private var displayedPhrase = "Кря."

    private var background: LinearGradient {
        switch engine.mood {
        case .sleeping:
            return LinearGradient(colors: [.black, Color(red: 0.12, green: 0.08, blue: 0.28)],
                                  startPoint: .top, endPoint: .bottom)
        case .hungry, .thirsty, .bored:
            return LinearGradient(colors: [Color(red: 0.38, green: 0.25, blue: 0.48),
                                           Color(red: 0.18, green: 0.14, blue: 0.30)],
                                  startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [Color(red: 0.08, green: 0.55, blue: 0.92),
                                           Color(red: 0.16, green: 0.78, blue: 0.48)],
                                  startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    StatBar(icon: "🍞", value: engine.pet.hunger)
                    StatBar(icon: "💧", value: engine.pet.water)
                    StatBar(icon: "💛", value: engine.pet.mood)
                }
                .padding(.horizontal, 4)

                Text(engine.stageLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                TamaSpriteView(persona: engine.pet.persona,
                               mood: engine.mood,
                               phase: engine.tick,
                               cosmetics: engine.pet.cosmetics)
                    .frame(width: 108, height: 108)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        displayedPhrase = engine.phrase
                    }

                Text(displayedPhrase)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white)
                    .frame(height: 27)
                    .padding(.horizontal, 5)

                HStack(spacing: 5) {
                    actionButton("🍞") { engine.feed(); displayedPhrase = engine.phrase }
                        .disabled(engine.isNightLocked)
                    actionButton("💧") { engine.drink(); displayedPhrase = engine.phrase }
                        .disabled(engine.isNightLocked)
                    actionButton(engine.hasDueChain ? "💌" : "❓") {
                        engine.prepareQuest(); showQuest = true
                    }
                    .disabled(engine.isNightLocked)
                    actionButton("🎮") { showGames = true }
                        .disabled(engine.isNightLocked)
                    actionButton("•••", compact: true) { showMore = true }
                }
            }
        }
        .onAppear { displayedPhrase = engine.phrase }
        .sheet(isPresented: $showGames) {
            GameMenuView().environmentObject(engine)
        }
        .sheet(isPresented: $showQuest, onDismiss: { engine.finishQuest() }) {
            QuestFlowView().environmentObject(engine)
        }
        .sheet(isPresented: $showMore) {
            MoreMenuView().environmentObject(engine)
        }
    }

    private func actionButton(_ label: String, compact: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: compact ? 13 : 16, weight: .semibold))
                .frame(width: 31, height: 31)
                .background(Circle().fill(.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
    }
}

struct StatBar: View {
    let icon: String
    let value: Double

    var body: some View {
        HStack(spacing: 1) {
            Text(icon).font(.system(size: 8))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.24))
                    Capsule().fill(.white.opacity(0.90))
                        .frame(width: max(2, geometry.size.width * value / 100))
                }
            }
            .frame(height: 4)
        }
    }
}
