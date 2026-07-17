import SwiftUI

struct PixelSpriteView: View {
    let grid: [String]

    private static let palette: [Character: Color] = [
        "B": .black,
        "Y": Color(red: 1.00, green: 0.82, blue: 0.08),
        "O": Color(red: 1.00, green: 0.48, blue: 0.04),
        "W": .white,
        "S": Color(white: 0.72),
        "D": Color(red: 0.34, green: 0.20, blue: 0.10),
        "R": Color(red: 0.76, green: 0.10, blue: 0.14),
        "G": Color(red: 0.18, green: 0.55, blue: 0.24),
        "N": Color(red: 0.08, green: 0.20, blue: 0.44),
        "L": Color(red: 0.35, green: 0.72, blue: 0.98),
        "P": Color(red: 0.96, green: 0.28, blue: 0.60),
        "U": Color(red: 0.48, green: 0.22, blue: 0.66),
        "Q": Color(red: 0.95, green: 0.68, blue: 0.08),
        "C": Color(red: 0.38, green: 0.90, blue: 0.82),
        "M": Color(red: 0.52, green: 0.54, blue: 0.58),
    ]

    var body: some View {
        Canvas { context, size in
            let rows = grid.count
            let columns = grid.map(\.count).max() ?? 1
            guard rows > 0, columns > 0 else { return }
            let cell = floor(min(size.width / CGFloat(columns),
                                 size.height / CGFloat(rows)))
            let x0 = (size.width - cell * CGFloat(columns)) / 2
            let y0 = (size.height - cell * CGFloat(rows)) / 2

            for (y, row) in grid.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = Self.palette[character] else { continue }
                    let rect = CGRect(x: x0 + CGFloat(x) * cell,
                                      y: y0 + CGFloat(y) * cell,
                                      width: cell + 0.25,
                                      height: cell + 0.25)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .drawingGroup(opaque: false, colorMode: .nonLinear)
    }
}

struct TamaSpriteView: View {
    let persona: Persona
    let mood: Mood
    let phase: Int
    let cosmetics: Set<String>

    var body: some View {
        PixelSpriteView(grid: TamaSpriteCatalog.frame(persona: persona,
                                                      mood: mood,
                                                      phase: phase,
                                                      cosmetics: cosmetics))
    }
}

private struct PixelGrid {
    let width: Int
    let height: Int
    private var cells: [Character]

    init(width: Int = 20, height: Int = 20) {
        self.width = width
        self.height = height
        cells = Array(repeating: ".", count: width * height)
    }

    mutating func set(_ x: Int, _ y: Int, _ value: Character) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        cells[y * width + x] = value
    }

    mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ value: Character) {
        for y in min(y0, y1)...max(y0, y1) {
            for x in min(x0, x1)...max(x0, x1) { set(x, y, value) }
        }
    }

    mutating func points(_ values: [(Int, Int)], _ value: Character) {
        for (x, y) in values { set(x, y, value) }
    }

    mutating func oval(cx: Double, cy: Double, rx: Double, ry: Double,
                       fill: Character, border: Character = "B") {
        let minX = Int(cx - rx - 1), maxX = Int(cx + rx + 1)
        let minY = Int(cy - ry - 1), maxY = Int(cy + ry + 1)
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = (Double(x) - cx) / rx
                let dy = (Double(y) - cy) / ry
                let d = dx * dx + dy * dy
                if d <= 1.0 {
                    set(x, y, d >= 0.68 ? border : fill)
                }
            }
        }
    }

    func rows() -> [String] {
        (0..<height).map { y in
            let start = y * width
            return String(cells[start..<(start + width)])
        }
    }
}

enum TamaSpriteCatalog {
    static func frame(persona: Persona, mood: Mood, phase: Int,
                      cosmetics: Set<String>) -> [String] {
        var grid = PixelGrid()
        let bodyColor: Character = isDark(persona) ? "S" : "Y"
        drawDuck(in: &grid, bodyColor: bodyColor, mood: mood, phase: phase)
        // Моргание: раз в 8 фаз (~5–6 c при тике 0.7 c) утка прикрывает
        // глаза на один кадр. Спящую не трогаем — у неё глаза уже закрыты.
        if mood != .sleeping, phase % 8 == 0 {
            grid.rect(9, 5, 11, 6, bodyColor)   // стереть глаз любого настроения
            grid.rect(9, 6, 11, 6, "B")         // закрытое веко
        }
        applyPersona(persona, to: &grid)
        applyCosmetics(cosmetics, to: &grid)
        return grid.rows()
    }

    static func directionFrame(left: Bool) -> [String] {
        var grid = PixelGrid()
        drawDuck(in: &grid, bodyColor: "Y", mood: .content, phase: 0)
        if left {
            // стереть правый клюв ЦЕЛИКОМ, включая чёрную обводку на x=14
            grid.rect(14, 7, 18, 8, ".")
            // стереть белый блик content-глаза (10..11, 5..6)
            grid.rect(9, 5, 11, 6, "Y")
            // зеркальный клюв слева: обводка + оранжевый верх
            grid.rect(1, 7, 5, 8, "B")
            grid.rect(1, 7, 4, 7, "O")
            // глаз на левой стороне головы
            grid.set(8, 6, "B")
        } else {
            // вправо утка смотрит по умолчанию — ничего стирать не нужно
            grid.set(11, 6, "B")
        }
        return grid.rows()
    }

    private static func isDark(_ persona: Persona) -> Bool {
        switch persona {
        case .archetype(.sly): return true
        case .profession(let p): return p.archetype == .sly
        default: return false
        }
    }

    private static func drawDuck(in g: inout PixelGrid, bodyColor: Character,
                                 mood: Mood, phase: Int) {
        // tail, body, head
        g.points([(2, 12), (3, 11), (3, 12), (4, 12)], "B")
        g.oval(cx: 9.0, cy: 13.0, rx: 6.5, ry: 4.4, fill: bodyColor)
        g.oval(cx: 10.2, cy: 6.8, rx: 5.0, ry: 4.7, fill: bodyColor)
        g.oval(cx: 7.0, cy: 12.8, rx: 2.8, ry: 2.4, fill: bodyColor)

        // beak
        g.rect(14, 7, 18, 8, "B")
        g.rect(15, 7, 18, 7, "O")

        // eyes / expression
        switch mood {
        case .sleeping:
            g.rect(9, 6, 11, 6, "B")
            g.points([(16, 3), (17, 2), (18, 2), (17, 1)], "W")
        case .happy:
            g.points([(9, 6), (10, 5), (11, 6)], "B")
        case .bored:
            g.rect(9, 6, 11, 6, "B")
            g.set(10, 7, bodyColor)
        case .hungry, .thirsty:
            g.rect(9, 5, 11, 5, "B")
            g.set(10, 7, "W")
        case .content:
            g.rect(10, 5, 11, 6, "W")
            g.set(11, 6, "B")
        }

        // feet, two-frame walk
        if phase % 2 == 0 {
            g.rect(6, 17, 8, 17, "O")
            g.rect(12, 17, 14, 17, "O")
        } else {
            g.rect(5, 17, 7, 17, "O")
            g.rect(13, 17, 15, 17, "O")
        }
    }

    private static func applyPersona(_ persona: Persona, to g: inout PixelGrid) {
        switch persona {
        case .duckling:
            // rounder baby tuft
            g.points([(8, 2), (9, 1), (10, 2)], "Y")
        case .archetype(let a):
            applyArchetype(a, to: &g)
        case .profession(let p):
            applyProfession(p, to: &g)
        }
    }

    private static func applyArchetype(_ a: Archetype, to g: inout PixelGrid) {
        switch a {
        case .star:
            topHat(&g); g.rect(8, 10, 11, 11, "P"); g.set(7, 10, "B"); g.set(12, 10, "B")
        case .gent:
            topHat(&g); monocle(&g); g.rect(8, 10, 11, 11, "W")
        case .sly:
            g.rect(6, 2, 14, 3, "R"); g.points([(4, 3), (5, 4), (3, 4)], "R")
        case .grump:
            g.rect(4, 10, 14, 12, "R"); g.rect(3, 11, 5, 14, "R")
            g.points([(8, 4), (9, 5), (12, 4), (11, 5)], "B")
        }
    }

    private static func applyProfession(_ p: Profession, to g: inout PixelGrid) {
        switch p {
        case .king:
            g.points([(7, 3), (7, 1), (9, 3), (10, 0), (11, 3), (13, 1), (13, 3)], "Q")
            g.rect(7, 3, 13, 4, "Q"); g.set(10, 2, "R")
        case .musician:
            g.rect(6, 3, 14, 3, "N"); g.rect(5, 4, 6, 8, "N"); g.rect(14, 4, 15, 8, "N")
            g.points([(2, 6), (3, 5), (3, 8), (4, 7)], "P")
        case .artist:
            g.rect(7, 2, 14, 3, "R"); g.rect(6, 3, 12, 4, "R")
            g.rect(16, 11, 16, 16, "D"); g.set(16, 10, "P")
        case .chef:
            g.oval(cx: 10, cy: 2.5, rx: 4.5, ry: 2.5, fill: "W")
            g.rect(7, 4, 13, 5, "W"); g.rect(7, 11, 13, 15, "W")
        case .scientist:
            g.rect(7, 5, 13, 7, "W"); g.rect(8, 6, 9, 6, "L"); g.rect(11, 6, 12, 6, "L")
            g.rect(15, 12, 17, 16, "C"); g.set(16, 11, "W")
        case .detective:
            g.rect(6, 2, 14, 3, "D"); g.rect(8, 1, 12, 2, "D"); g.rect(11, 0, 14, 1, "D")
            g.rect(16, 11, 17, 15, "D"); g.oval(cx: 16.5, cy: 10, rx: 1.5, ry: 1.5, fill: "W")
        case .captain:
            g.rect(6, 2, 14, 4, "W"); g.rect(7, 1, 13, 2, "N"); g.set(10, 2, "Q")
            g.rect(5, 11, 14, 12, "N")
        case .astronaut:
            g.oval(cx: 10, cy: 6.5, rx: 6.0, ry: 6.0, fill: "L", border: "W")
            g.oval(cx: 10, cy: 7, rx: 4.7, ry: 4.5, fill: "Y")
            g.rect(7, 12, 13, 15, "W"); g.points([(8, 13), (10, 13), (12, 13)], "L")
        case .pirate:
            g.rect(5, 2, 15, 4, "B"); g.points([(4, 4), (16, 4), (7, 1), (13, 1)], "B")
            g.set(10, 2, "W"); g.rect(9, 5, 11, 6, "B"); g.rect(12, 6, 14, 6, "B")
        case .ninja:
            g.rect(5, 3, 15, 9, "B"); g.rect(7, 5, 13, 7, "S"); g.rect(8, 6, 9, 6, "B")
            g.rect(14, 3, 18, 4, "R")
        case .engineer:
            g.rect(5, 2, 15, 4, "Q"); g.rect(7, 1, 13, 2, "Q")
            g.rect(7, 5, 13, 7, "W"); g.rect(8, 6, 9, 6, "L"); g.rect(11, 6, 12, 6, "L")
            g.rect(16, 11, 16, 17, "M"); g.points([(15, 10), (17, 10)], "M")
        case .sheriff:
            g.rect(5, 2, 15, 3, "D"); g.rect(7, 0, 13, 3, "D")
            g.points([(10, 11), (9, 12), (11, 12), (10, 13)], "Q")
        case .hooligan:
            g.rect(6, 2, 14, 4, "R"); g.rect(4, 3, 7, 4, "R")
            g.points([(7, 12), (8, 13), (9, 12), (10, 13), (11, 12)], "M")
        case .knight:
            g.rect(6, 2, 14, 8, "M"); g.rect(7, 5, 13, 6, "B"); g.points([(8, 6), (12, 6)], "W")
            g.oval(cx: 16, cy: 13, rx: 2.2, ry: 3.2, fill: "N", border: "M")
        case .scout:
            g.rect(6, 2, 14, 3, "G"); g.rect(7, 1, 12, 2, "G"); g.rect(12, 3, 16, 4, "G")
            g.rect(8, 10, 12, 12, "R"); g.rect(3, 11, 5, 15, "D")
        case .explorer:
            g.rect(5, 2, 15, 3, "Q"); g.rect(7, 0, 13, 3, "Q"); g.rect(8, 2, 12, 2, "D")
            g.oval(cx: 16, cy: 13, rx: 2, ry: 2, fill: "W", border: "D"); g.set(16, 12, "R")
        case .mage:
            g.points([(10, 0), (9, 1), (8, 2), (7, 3), (6, 4), (5, 5)], "U")
            g.rect(5, 5, 15, 6, "U"); g.points([(8, 3), (12, 4), (10, 1)], "Q")
            g.rect(17, 9, 17, 17, "D"); g.set(17, 8, "C")
        }
    }

    private static func topHat(_ g: inout PixelGrid) {
        g.rect(7, 0, 13, 4, "N")
        g.rect(5, 4, 15, 5, "N")
    }

    private static func monocle(_ g: inout PixelGrid) {
        g.oval(cx: 11.5, cy: 6, rx: 1.8, ry: 1.8, fill: "W", border: "Q")
        g.rect(13, 7, 13, 11, "Q")
    }

    private static func applyCosmetics(_ cosmetics: Set<String>, to g: inout PixelGrid) {
        if cosmetics.contains("flower") {
            g.points([(4, 4), (3, 3), (5, 3), (3, 5), (5, 5)], "P")
            g.set(4, 4, "Q")
        }
        if cosmetics.contains("zombieCostume") {
            g.rect(5, 11, 14, 15, "G")
            g.points([(7, 12), (10, 14), (13, 12)], "S")
        }
    }
}
