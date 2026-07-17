import SwiftUI

struct MemoryView: View {
    @EnvironmentObject var engine: PetEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Память")
                    .font(.system(.headline, design: .rounded))

                if engine.pet.memories.isEmpty {
                    Text("Важных воспоминаний пока нет. Они появятся после значимых решений в квестах.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(MemoryEngine.recent(in: engine.pet, limit: 12)) { memory in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(icon(for: memory.kind))
                                Text(memory.summary)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            Text(memory.createdAt, style: .relative)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            if memory.recallCount > 0 {
                                Text("Вспоминал: \(memory.recallCount)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                    }
                }

                Text("Диагностика Alpha")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                ForEach(Trait.allCases, id: \.rawValue) { trait in
                    HStack {
                        Text(traitTitle(trait))
                            .font(.system(size: 10))
                        Spacer()
                        Text("\(engine.pet.traits[trait])")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func icon(for kind: MemoryKind) -> String {
        switch kind {
        case .meeting: return "🦆"
        case .choice: return "🔀"
        case .relationship: return "🤝"
        case .conflict: return "🏹"
        case .gift: return "🎁"
        case .achievement: return "🏆"
        case .embarrassment: return "😳"
        case .discovery: return "🚪"
        case .promise: return "💬"
        case .kindness: return "💛"
        }
    }

    private func traitTitle(_ trait: Trait) -> String {
        switch trait {
        case .brave: return "😎 Смелость"
        case .kind: return "🤝 Доброта"
        case .cunning: return "🧠 Хитрость"
        case .polite: return "🎩 Вежливость"
        case .chaos: return "🎉 Безуминка"
        case .luck: return "🍀 Удача"
        }
    }
}
