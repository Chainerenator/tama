import SwiftUI

struct QuestFlowView: View {
    @EnvironmentObject var engine: PetEngine
    @Environment(\.dismiss) private var dismiss
    @State private var reaction: String?

    var body: some View {
        ScrollView {
            if let quest = engine.activeQuest {
                if let reaction {
                    VStack(spacing: 8) {
                        TamaSpriteView(persona: engine.pet.persona,
                                       mood: .happy,
                                       phase: engine.tick,
                                       cosmetics: engine.pet.cosmetics)
                            .frame(width: 78, height: 78)
                        Text(reaction)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                        if let evolved = engine.lastEvolution {
                            Text("Эволюция: \(evolved.title)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        Button("Готово") { dismiss() }.tint(.green)
                    }
                    .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 7) {
                        Text(quest.icon).font(.system(size: 28))
                        Text(quest.text)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)

                        ForEach(Array(quest.choices.enumerated()), id: \.offset) { index, choice in
                            Button {
                                reaction = engine.answerQuest(index: index)
                            } label: {
                                Text(choice.text)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        Button("Пропустить") {
                            engine.skipQuest(); dismiss()
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}

private extension Persona {
    var title: String {
        switch self {
        case .duckling: return "Утёнок"
        case .archetype(let a): return a.displayName
        case .profession(let p): return p.displayName
        }
    }
}
