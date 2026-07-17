import SwiftUI

@MainActor
struct CatchBreadGameView: View {
    @EnvironmentObject var engine: PetEngine
    let onDone: () -> Void

    @State private var position = CGPoint(x: 0.5, y: 0.5)
    @State private var score = 0
    @State private var timeLeft = 12
    @State private var finished = false
    @State private var rewarded = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.001)

                if finished {
                    VStack(spacing: 8) {
                        Text("Счёт: ⭐️ \(score)")
                            .font(.system(.headline, design: .rounded))

                        Button("Готово") {
                            grantRewardIfNeeded()
                            onDone()
                        }
                        .tint(.green)
                    }
                } else {
                    Button {
                        score += 1
                        relocate()
                    } label: {
                        Text("🥖")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: position.x * geometry.size.width,
                        y: position.y * geometry.size.height
                    )

                    VStack {
                        HStack {
                            Text("⏱ \(timeLeft)")
                            Spacer()
                            Text("⭐️ \(score)")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)

                        Spacer()
                    }
                }
            }
        }
        // SwiftUI автоматически отменяет task при закрытии экрана.
        // Один цикл заменяет два Combine Timer и не создаёт Swift 6 warnings.
        .task {
            await runGameLoop()
        }
        // Свайп sheet не должен сжигать уже заработанные очки.
        .onDisappear {
            grantRewardIfNeeded()
        }
    }

    private func runGameLoop() async {
        var ticks = 0

        while !Task.isCancelled && !finished {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }

            guard !Task.isCancelled, !finished else { return }
            ticks += 1

            if ticks.isMultiple(of: 10) {
                timeLeft -= 1
                if timeLeft <= 0 {
                    finished = true
                    return
                }
            }

            if ticks.isMultiple(of: 13) {
                relocate()
            }
        }
    }

    private func grantRewardIfNeeded() {
        guard !rewarded else { return }
        rewarded = true

        if score > 0 {
            engine.rewardGame(score: score)
        }
    }

    private func relocate() {
        position = CGPoint(
            x: .random(in: 0.20...0.80),
            y: .random(in: 0.28...0.78)
        )
    }
}
