import SwiftUI

/// Stage-based orchard shooter — 99 levels (index 0…98), procedural difficulty curve.
enum GameProgression {
    static let maxStageIndex = 98
    static let saveVersion = 3

    enum WeaponStyle: String, CaseIterable {
        case pulse, twin, spread, rail, plasma, missile, prism, nova

        var displayName: String {
            switch self {
            case .pulse: return "脉冲炮"
            case .twin: return "双联激光"
            case .spread: return "散射弹幕"
            case .rail: return "磁轨穿甲"
            case .plasma: return "等离子球"
            case .missile: return "追踪飞弹"
            case .prism: return "棱镜折射"
            case .nova: return "新星爆发"
            }
        }
    }

    struct OrchardTheme {
        let skyTop: Color
        let skyMid: Color
        let skyWarm: Color
        let skyBottom: Color
        let sunCore: Color
        let horizon: Color
        let ground: Color
        let groundDeep: Color
        let mist: Color
        let starTint: Color
    }

    struct BeamProfile {
        let style: WeaponStyle
        let volley: [(dx: CGFloat, vx: CGFloat, damage: Int)]
        let speed: CGFloat
        let length: CGFloat
        let width: CGFloat
        let glow: Color
        let gradient: LinearGradient
        let tier: Int
        let trailScale: CGFloat
        let sparkle: Bool
        let explosive: Bool
        let blastRadius: CGFloat
        let splashDamage: Int
    }

    struct StageDefinition {
        let index: Int
        let name: String
        let subtitle: String
        let fruits: [FruitKind]
        let weapon: WeaponStyle
        let killQuota: Int
        let themeBand: Int
    }

    private static let legacyStageNames: [String] = [
        "初醒果园", "青枝试炼", "橙光走廊", "蜜桃哨站", "葡园弹幕",
        "草莓风暴", "蜜瓜穿甲", "芒果双刃", "椰子重域", "菠萝矩阵",
        "荔枝闪击", "火龙核心", "榴莲堡垒", "杨桃棱镜", "山竹深渊",
        "西瓜泰坦", "异果前线", "光谱果园", "终焉果域", "百果神域",
    ]

    private static let zonePrefixes = ["晨曦", "午照", "暮光", "星野", "云巅", "秘境", "深林", "潮汐", "极光"]
    private static let zoneSuffixes = ["哨站", "试炼", "走廊", "风暴", "矩阵", "前线", "堡垒", "神域", "果园"]

    static func stage(index: Int) -> StageDefinition {
        let i = clampStage(index)
        return StageDefinition(
            index: i,
            name: stageName(for: i),
            subtitle: stageSubtitle(for: i),
            fruits: fruits(for: i),
            weapon: weapon(for: i),
            killQuota: killQuota(for: i),
            themeBand: themeBand(for: i)
        )
    }

    static func clampStage(_ index: Int) -> Int {
        min(maxStageIndex, max(0, index))
    }

    private static func stageName(for index: Int) -> String {
        if index < legacyStageNames.count { return legacyStageNames[index] }
        let prefix = zonePrefixes[(index / 11) % zonePrefixes.count]
        let suffix = zoneSuffixes[index % zoneSuffixes.count]
        return "\(prefix)·\(suffix)"
    }

    private static func stageSubtitle(for index: Int) -> String {
        let w = weapon(for: index)
        switch index {
        case 0...4: return "轻松热身 · \(w.displayName)"
        case 5...14: return "节奏提升 · \(w.displayName)"
        case 15...34: return "精英来袭 · \(w.displayName)"
        case 35...59: return "高压果潮 · \(w.displayName)"
        default: return "终局试炼 · \(w.displayName)"
        }
    }

    /// Soft early, firm mid, demanding late — short wins first, endurance later.
    static func killQuota(for index: Int) -> Int {
        let i = clampStage(index)
        switch i {
        case 0...4: return 16 + i * 4                 // 16…32  ~教学
        case 5...14: return 34 + (i - 5) * 5           // 34…79
        case 15...34: return 82 + (i - 15) * 6         // 82…196
        case 35...59: return 205 + (i - 35) * 7        // 205…373
        default: return 385 + (i - 60) * 8             // 385…689
        }
    }

    /// 0…1 pressure used by spawn / speed / HP. Early stays gentle.
    static func stagePressure(for index: Int) -> CGFloat {
        let i = CGFloat(clampStage(index))
        // Ease-in curve: slow climb early, steeper after ~30.
        return min(1, (i / 28) * 0.45 + pow(i / 98, 1.35) * 0.55)
    }

    /// Spawn cadence (ms). Tutorial breathes; late stages keep pressure without spam.
    static func spawnIntervalMs(stageIndex: Int, wave: Int) -> Int {
        let p = stagePressure(for: stageIndex)
        let wavePush = min(4, max(0, wave)) * (28 + Int(p * 40))
        let base = Int(1380 - p * 780) - wavePush
        let floor: Int
        switch stageIndex {
        case 0...4: floor = 820
        case 5...14: floor = 620
        case 15...34: floor = 460
        case 35...59: floor = 360
        default: floor = 300
        }
        return max(floor, base)
    }

    /// Extra burst chance after a spawn tick (0…1).
    static func extraSpawnChance(stageIndex: Int, wave: Int) -> Double {
        let p = Double(stagePressure(for: stageIndex))
        let w = Double(min(4, max(0, wave)))
        if stageIndex < 5 { return 0 }
        if stageIndex < 15 { return wave >= 3 ? 0.12 : 0.04 }
        return min(0.42, 0.08 + p * 0.22 + w * 0.04)
    }

    /// Soft cap on on-screen fruit.
    static func softCap(stageIndex: Int, wave: Int) -> Int {
        let base: Int
        switch stageIndex {
        case 0...4: base = 5
        case 5...14: base = 7
        case 15...34: base = 9
        default: base = 11
        }
        return base + min(wave, stageIndex < 15 ? 2 : 4)
    }

    /// Fall-speed multiplier vs tutorial baseline.
    static func fallSpeedScale(stageIndex: Int, wave: Int) -> CGFloat {
        let p = stagePressure(for: stageIndex)
        return 0.52 + p * 0.72 + CGFloat(min(wave, 4)) * (0.03 + p * 0.035)
    }

    /// HP for a fruit kind at this stage/wave.
    static func bubbleHP(kind: OrbKind, stageIndex: Int, wave: Int) -> Int {
        let p = stagePressure(for: stageIndex)
        let w = max(0, wave)
        switch kind {
        case .normal:
            return max(1, 1 + Int(p * 4) + w / 3 + stageIndex / 28)
        case .swarm:
            return 1
        case .zig:
            return max(2, 2 + Int(p * 3) + w / 2 + stageIndex / 24)
        case .elite:
            return max(4, 4 + Int(p * 8) + w + stageIndex / 14)
        case .titan:
            return max(10, 10 + Int(p * 18) + w * 2 + stageIndex / 8)
        }
    }

    /// Which enemy kinds may appear. Hard types unlock by stage, then by wave.
    static func pickOrbKind(stageIndex: Int, wave: Int, roll: Int = Int.random(in: 0..<100)) -> OrbKind {
        let r = roll
        // Hard unlock gates — early levels stay readable.
        let allowSwarm = stageIndex >= 3
        let allowZig = stageIndex >= 8
        let allowElite = stageIndex >= 15
        let allowTitan = stageIndex >= 26

        switch wave {
        case 0:
            if allowSwarm, r < (stageIndex < 8 ? 8 : 18) { return .swarm }
            return .normal
        case 1:
            if allowZig, r < 18 { return .zig }
            if allowSwarm, r < 40 { return .swarm }
            return .normal
        case 2:
            if allowElite, r < 12 { return .elite }
            if allowZig, r < 35 { return .zig }
            if allowSwarm, r < 58 { return .swarm }
            return .normal
        case 3:
            if allowTitan, r < 8 { return .titan }
            if allowElite, r < 28 { return .elite }
            if allowZig, r < 50 { return .zig }
            if allowSwarm, r < 70 { return .swarm }
            return .normal
        default:
            if allowTitan, r < (10 + min(18, stageIndex / 4)) { return .titan }
            if allowElite, r < 40 { return .elite }
            if allowZig, r < 58 { return .zig }
            if allowSwarm, r < 76 { return .swarm }
            return .normal
        }
    }

    private static func weapon(for index: Int) -> WeaponStyle {
        let all = WeaponStyle.allCases
        // Hold starter weapons longer, then rotate through arsenal.
        if index < 6 { return .pulse }
        if index < 12 { return index.isMultiple(of: 2) ? .twin : .pulse }
        if index < 20 { return [.twin, .spread, .pulse][index % 3] }
        return all[(index - 8) % all.count]
    }

    private static func themeBand(for index: Int) -> Int {
        min(5, index / 17)
    }

    /// Unlock more fruit types as levels progress; higher levels mix exotics.
    static func fruits(for index: Int) -> [FruitKind] {
        let catalog = FruitKind.catalog
        let baseCount = min(catalog.count, max(2, 2 + index / 2))
        var pool = Array(catalog.prefix(baseCount))
        let spice = min(4, 1 + index / 20)
        for j in 0..<spice {
            let pick = catalog[(index * 5 + j * 13 + 7) % catalog.count]
            if !pool.contains(pick) { pool.append(pick) }
        }
        if index >= 30, !pool.contains(catalog.last!) {
            pool.append(catalog.last!)
        }
        return pool
    }

    static func fireIntervalNs(stage: StageDefinition) -> UInt64 {
        let ms: Int = {
            switch stage.weapon {
            case .pulse: return 620
            case .twin: return 540
            case .spread: return 660
            case .rail: return 700
            case .plasma: return 580
            case .missile: return 840
            case .prism: return 560
            case .nova: return 740
            }
        }()
        // Firepower eases in with stage so early play stays readable.
        let ease = Int(stagePressure(for: stage.index) * 220)
        return UInt64(max(360, ms - ease)) * 1_000_000
    }

    static func shotExplodes(on kind: OrbKind, fruitValue: Int, stage: StageDefinition) -> Bool {
        switch stage.weapon {
        case .plasma, .nova, .missile: return kind == .titan || kind == .elite || fruitValue >= 40
        case .rail: return kind == .titan || fruitValue >= 55
        case .prism: return kind == .elite || kind == .titan
        default: return kind == .titan && stage.index >= 8
        }
    }

    static func fruit(for stage: StageDefinition, kind: OrbKind) -> FruitKind {
        let pool = stage.fruits
        func pick(_ candidates: [FruitKind]) -> FruitKind {
            let allowed = candidates.filter { pool.contains($0) }
            return (allowed.isEmpty ? pool : allowed).randomElement() ?? pool.first ?? .apple
        }
        let cheap = pool.filter { $0.value <= 22 }
        let mid = pool.filter { $0.value > 22 && $0.value <= 42 }
        let premium = pool.filter { $0.value > 42 }

        switch kind {
        case .normal:
            if !cheap.isEmpty, Int.random(in: 0..<100) < 70 { return cheap.randomElement() ?? pool.randomElement() ?? .apple }
            if !mid.isEmpty, Int.random(in: 0..<100) < 50 { return mid.randomElement() ?? pool.randomElement() ?? .apple }
            return pool.randomElement() ?? .apple
        case .swarm:
            return pick(Array(pool.prefix(min(6, pool.count))))
        case .elite:
            if !premium.isEmpty { return premium.randomElement() ?? pool.last ?? .apple }
            return pool.max(by: { $0.value < $1.value }) ?? pool.last ?? .apple
        case .zig:
            return pick(mid.isEmpty ? pool : mid)
        case .titan:
            return pool.max(by: { $0.value < $1.value }) ?? pool.last ?? .apple
        }
    }

    static func orchardTheme(for stage: StageDefinition) -> OrchardTheme {
        orchardTheme(band: stage.themeBand)
    }

    static func orchardTheme(band: Int) -> OrchardTheme {
        switch band {
        case 0:
            return OrchardTheme(
                skyTop: Color(red: 0.35, green: 0.58, blue: 0.95),
                skyMid: Color(red: 0.72, green: 0.78, blue: 0.98),
                skyWarm: Color(red: 1.0, green: 0.78, blue: 0.52),
                skyBottom: Color(red: 1.0, green: 0.90, blue: 0.68),
                sunCore: Color(red: 1.0, green: 0.94, blue: 0.62),
                horizon: Color(red: 0.38, green: 0.74, blue: 0.42),
                ground: Color(red: 0.18, green: 0.46, blue: 0.28),
                groundDeep: Color(red: 0.10, green: 0.30, blue: 0.18),
                mist: Color.white.opacity(0.16),
                starTint: Color.white
            )
        case 1:
            return OrchardTheme(
                skyTop: Color(red: 0.18, green: 0.62, blue: 0.92),
                skyMid: Color(red: 0.45, green: 0.82, blue: 0.95),
                skyWarm: Color(red: 0.98, green: 0.88, blue: 0.55),
                skyBottom: Color(red: 0.92, green: 0.96, blue: 0.78),
                sunCore: Color(red: 1.0, green: 0.98, blue: 0.72),
                horizon: Color(red: 0.22, green: 0.78, blue: 0.52),
                ground: Color(red: 0.12, green: 0.52, blue: 0.32),
                groundDeep: Color(red: 0.06, green: 0.34, blue: 0.20),
                mist: Color.white.opacity(0.14),
                starTint: Color(red: 0.85, green: 1.0, blue: 0.95)
            )
        case 2:
            return OrchardTheme(
                skyTop: Color(red: 0.92, green: 0.42, blue: 0.38),
                skyMid: Color(red: 1.0, green: 0.62, blue: 0.42),
                skyWarm: Color(red: 1.0, green: 0.78, blue: 0.38),
                skyBottom: Color(red: 1.0, green: 0.88, blue: 0.62),
                sunCore: Color(red: 1.0, green: 0.72, blue: 0.28),
                horizon: Color(red: 0.55, green: 0.38, blue: 0.22),
                ground: Color(red: 0.32, green: 0.22, blue: 0.14),
                groundDeep: Color(red: 0.18, green: 0.12, blue: 0.08),
                mist: Color(red: 1.0, green: 0.85, blue: 0.55).opacity(0.18),
                starTint: Color(red: 1.0, green: 0.92, blue: 0.65)
            )
        case 3:
            return OrchardTheme(
                skyTop: Color(red: 0.22, green: 0.14, blue: 0.48),
                skyMid: Color(red: 0.48, green: 0.28, blue: 0.72),
                skyWarm: Color(red: 0.92, green: 0.55, blue: 0.78),
                skyBottom: Color(red: 0.78, green: 0.45, blue: 0.62),
                sunCore: Color(red: 1.0, green: 0.65, blue: 0.82),
                horizon: Color(red: 0.28, green: 0.18, blue: 0.42),
                ground: Color(red: 0.14, green: 0.10, blue: 0.28),
                groundDeep: Color(red: 0.08, green: 0.05, blue: 0.16),
                mist: Color(red: 0.85, green: 0.55, blue: 1.0).opacity(0.12),
                starTint: Color(red: 0.95, green: 0.75, blue: 1.0)
            )
        case 4:
            return OrchardTheme(
                skyTop: Color(red: 0.04, green: 0.08, blue: 0.28),
                skyMid: Color(red: 0.12, green: 0.18, blue: 0.42),
                skyWarm: Color(red: 0.28, green: 0.35, blue: 0.62),
                skyBottom: Color(red: 0.18, green: 0.28, blue: 0.48),
                sunCore: Color(red: 0.85, green: 0.92, blue: 1.0),
                horizon: Color(red: 0.08, green: 0.22, blue: 0.32),
                ground: Color(red: 0.04, green: 0.14, blue: 0.18),
                groundDeep: Color(red: 0.02, green: 0.08, blue: 0.12),
                mist: Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.10),
                starTint: Color(red: 0.75, green: 0.88, blue: 1.0)
            )
        default:
            return OrchardTheme(
                skyTop: Color(red: 0.08, green: 0.05, blue: 0.22),
                skyMid: Color(red: 0.35, green: 0.12, blue: 0.45),
                skyWarm: Color(red: 1.0, green: 0.72, blue: 0.28),
                skyBottom: Color(red: 0.55, green: 0.22, blue: 0.38),
                sunCore: Color(red: 1.0, green: 0.86, blue: 0.35),
                horizon: Color(red: 0.42, green: 0.18, blue: 0.52),
                ground: Color(red: 0.12, green: 0.06, blue: 0.18),
                groundDeep: Color(red: 0.06, green: 0.03, blue: 0.10),
                mist: Color(red: 1.0, green: 0.78, blue: 0.35).opacity(0.14),
                starTint: Color(red: 1.0, green: 0.92, blue: 0.55)
            )
        }
    }

    static func beamProfile(for stage: StageDefinition) -> BeamProfile {
        let tier = min(7, stage.index / 14)
        let power = 1 + stage.index / 12
        let (glow, gradient) = beamColors(style: stage.weapon, tier: tier)

        let volley: [(CGFloat, CGFloat, Int)] = {
            switch stage.weapon {
            case .pulse: return [(0, 0, power)]
            case .twin: return [(-14, 0, power), (14, 0, power)]
            case .spread: return [(-22, -40, power), (0, 0, power + 1), (22, 40, power)]
            case .rail: return [(0, 0, power + 1)]
            case .plasma: return [(0, 0, power + 1)]
            case .missile: return [(-10, -20, power), (10, 20, power)]
            case .prism: return [(-26, -55, power), (-10, -15, power), (0, 0, power + 1), (10, 15, power), (26, 55, power)]
            case .nova: return [(-16, -30, power), (0, 0, power + 2), (16, 30, power)]
            }
        }()

        let width: CGFloat = {
            switch stage.weapon {
            case .rail: return min(6.5, 3.2 + CGFloat(stage.index) * 0.025)
            case .plasma, .nova: return min(13, 6 + CGFloat(stage.index) * 0.05)
            case .missile: return 7
            case .prism: return 4.5
            default: return min(8, 3.5 + CGFloat(stage.index) * 0.03)
            }
        }()

        let length: CGFloat = {
            switch stage.weapon {
            case .rail: return min(78, 38 + CGFloat(stage.index) * 0.35)
            case .missile: return min(40, 22 + CGFloat(stage.index) * 0.15)
            case .plasma, .nova: return min(48, 26 + CGFloat(stage.index) * 0.18)
            default: return min(44, 22 + CGFloat(stage.index) * 0.16)
            }
        }()

        let speed: CGFloat = min(920, 400 + CGFloat(stage.index) * 4)
        let explosive = stage.weapon == .plasma || stage.weapon == .nova || stage.weapon == .missile
        let blastRadius: CGFloat = explosive ? (38 + CGFloat(stage.index) * 0.6) : 0
        let splashDamage = explosive ? (stage.index >= 24 ? 2 : 1) : 0

        return BeamProfile(
            style: stage.weapon,
            volley: volley,
            speed: speed,
            length: length,
            width: width,
            glow: glow,
            gradient: gradient,
            tier: tier,
            trailScale: 1.0 + CGFloat(tier) * 0.22,
            sparkle: stage.index >= 6,
            explosive: explosive,
            blastRadius: blastRadius,
            splashDamage: splashDamage
        )
    }

    private static func beamColors(style: WeaponStyle, tier: Int) -> (Color, LinearGradient) {
        switch style {
        case .pulse:
            return (
                Color(red: 0.45, green: 0.98, blue: 0.72),
                LinearGradient(colors: [.white, Color(red: 0.45, green: 0.98, blue: 0.72), Color(red: 0.2, green: 0.75, blue: 0.55)], startPoint: .bottom, endPoint: .top)
            )
        case .twin:
            return (
                Color(red: 0.55, green: 0.88, blue: 1.0),
                LinearGradient(colors: [.white, Color(red: 0.55, green: 0.88, blue: 1.0), Color(red: 0.2, green: 0.55, blue: 0.95)], startPoint: .bottom, endPoint: .top)
            )
        case .spread:
            return (
                Color(red: 1.0, green: 0.82, blue: 0.35),
                LinearGradient(colors: [.white, Color(red: 1.0, green: 0.82, blue: 0.35), Color(red: 1.0, green: 0.55, blue: 0.15)], startPoint: .bottom, endPoint: .top)
            )
        case .rail:
            return (
                Color(red: 0.75, green: 0.92, blue: 1.0),
                LinearGradient(colors: [.white, Color(red: 0.85, green: 0.95, blue: 1.0), Color(red: 0.35, green: 0.72, blue: 1.0)], startPoint: .bottom, endPoint: .top)
            )
        case .plasma:
            return (
                Color(red: 0.85, green: 0.45, blue: 1.0),
                LinearGradient(colors: [.white, Color(red: 0.85, green: 0.45, blue: 1.0), Color(red: 0.55, green: 0.15, blue: 0.85)], startPoint: .bottom, endPoint: .top)
            )
        case .missile:
            return (
                Color(red: 1.0, green: 0.55, blue: 0.35),
                LinearGradient(colors: [.white, Color(red: 1.0, green: 0.72, blue: 0.35), Color(red: 0.95, green: 0.28, blue: 0.12)], startPoint: .bottom, endPoint: .top)
            )
        case .prism:
            return (
                Color(red: 0.35, green: 0.95, blue: 0.85),
                LinearGradient(colors: [Color(red: 1, green: 0.6, blue: 0.8), Color(red: 0.5, green: 0.9, blue: 1), Color(red: 0.6, green: 1, blue: 0.7)], startPoint: .leading, endPoint: .trailing)
            )
        case .nova:
            return (
                Color(red: 1.0, green: 0.92, blue: 0.55),
                LinearGradient(colors: [.white, Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 1.0, green: 0.35, blue: 0.25)], startPoint: .bottom, endPoint: .top)
            )
        }
    }

    static func shootSoundTier(stage: StageDefinition) -> Int {
        min(7, stage.index / 14)
    }

    static var totalFruitCount: Int { FruitKind.catalog.count }
    static func unlockedFruits(level: Int) -> [FruitKind] {
        fruits(for: level)
    }
}

// MARK: - Fruits

enum FruitKind: Hashable {
    case apple, greenApple, banana, orange, lemon, pear, peach, cherry, grape, strawberry
    case blueberry, kiwi, melon, mango, coconut, avocado, pineapple, papaya, lychee, guava
    case dragonFruit, passionFruit, pomegranate, durian, rambutan, jackfruit, starfruit, watermelon, mangosteen, fig
    case apricot, plum, raspberry, tangerine, grapefruit, longan, persimmon, cranberry, blackberry, pomelo

    static let catalog: [FruitKind] = [
        .apple, .greenApple, .banana, .orange, .lemon, .tangerine, .grapefruit, .pear, .peach, .cherry,
        .plum, .apricot, .grape, .strawberry, .blueberry, .raspberry, .blackberry, .cranberry,
        .kiwi, .melon, .guava, .papaya, .mango, .longan, .persimmon, .pomelo,
        .coconut, .avocado, .lychee, .passionFruit, .dragonFruit, .pomegranate,
        .pineapple, .rambutan, .starfruit, .fig, .mangosteen, .jackfruit, .durian, .watermelon,
    ]

    static var allCases: [FruitKind] { catalog }

    var value: Int {
        switch self {
        case .apple: return 5
        case .greenApple: return 6
        case .banana: return 8
        case .orange: return 10
        case .lemon: return 12
        case .tangerine: return 13
        case .pear: return 14
        case .peach: return 16
        case .cherry: return 18
        case .plum: return 19
        case .apricot: return 20
        case .grape: return 20
        case .strawberry: return 22
        case .blueberry: return 24
        case .raspberry: return 25
        case .blackberry: return 26
        case .cranberry: return 27
        case .kiwi: return 26
        case .melon: return 28
        case .guava: return 30
        case .papaya: return 32
        case .mango: return 34
        case .longan: return 35
        case .persimmon: return 36
        case .pomelo: return 37
        case .grapefruit: return 38
        case .coconut: return 36
        case .avocado: return 38
        case .lychee: return 40
        case .passionFruit: return 42
        case .dragonFruit: return 45
        case .pomegranate: return 48
        case .pineapple: return 50
        case .rambutan: return 52
        case .starfruit: return 55
        case .fig: return 58
        case .mangosteen: return 62
        case .jackfruit: return 68
        case .durian: return 75
        case .watermelon: return 80
        }
    }

    var name: String {
        switch self {
        case .apple: return "苹果"
        case .greenApple: return "青苹果"
        case .banana: return "香蕉"
        case .orange: return "橙子"
        case .lemon: return "柠檬"
        case .tangerine: return "柑橘"
        case .grapefruit: return "柚子"
        case .pear: return "梨"
        case .peach: return "桃子"
        case .cherry: return "樱桃"
        case .plum: return "李子"
        case .apricot: return "杏子"
        case .grape: return "葡萄"
        case .strawberry: return "草莓"
        case .blueberry: return "蓝莓"
        case .raspberry: return "树莓"
        case .blackberry: return "黑莓"
        case .cranberry: return "蔓越莓"
        case .kiwi: return "猕猴桃"
        case .melon: return "蜜瓜"
        case .mango: return "芒果"
        case .coconut: return "椰子"
        case .avocado: return "牛油果"
        case .pineapple: return "菠萝"
        case .watermelon: return "西瓜"
        case .papaya: return "木瓜"
        case .lychee: return "荔枝"
        case .longan: return "龙眼"
        case .persimmon: return "柿子"
        case .pomelo: return "文旦"
        case .guava: return "番石榴"
        case .dragonFruit: return "火龙果"
        case .passionFruit: return "百香果"
        case .pomegranate: return "石榴"
        case .durian: return "榴莲"
        case .rambutan: return "红毛丹"
        case .jackfruit: return "菠萝蜜"
        case .starfruit: return "杨桃"
        case .mangosteen: return "山竹"
        case .fig: return "无花果"
        }
    }

    /// System emoji — iOS renders these as detailed 3D-style produce glyphs.
    var emoji: String {
        switch self {
        case .apple: return "🍎"
        case .greenApple: return "🍏"
        case .banana: return "🍌"
        case .orange: return "🍊"
        case .lemon: return "🍋"
        case .tangerine: return "🍊"
        case .grapefruit: return "🍊"
        case .pear: return "🍐"
        case .peach: return "🍑"
        case .cherry: return "🍒"
        case .plum: return "🍑"
        case .apricot: return "🍑"
        case .grape: return "🍇"
        case .strawberry: return "🍓"
        case .blueberry: return "🫐"
        case .raspberry: return "🍓"
        case .blackberry: return "🫐"
        case .cranberry: return "🍒"
        case .kiwi: return "🥝"
        case .melon: return "🍈"
        case .guava: return "🍈"
        case .papaya: return "🥭"
        case .mango: return "🥭"
        case .longan: return "🍈"
        case .persimmon: return "🍊"
        case .pomelo: return "🍊"
        case .coconut: return "🥥"
        case .avocado: return "🥑"
        case .lychee: return "🍒"
        case .passionFruit: return "🍋"
        case .dragonFruit: return "🍓"
        case .pomegranate: return "🍎"
        case .pineapple: return "🍍"
        case .rambutan: return "🍒"
        case .starfruit: return "⭐"
        case .fig: return "🍇"
        case .mangosteen: return "🍇"
        case .jackfruit: return "🍍"
        case .durian: return "🥝"
        case .watermelon: return "🍉"
        }
    }

    var accent: Color {
        switch self {
        case .apple: return Color(red: 0.95, green: 0.28, blue: 0.32)
        case .greenApple: return Color(red: 0.45, green: 0.82, blue: 0.38)
        case .banana: return Color(red: 1.0, green: 0.82, blue: 0.22)
        case .orange: return Color(red: 1.0, green: 0.55, blue: 0.18)
        case .lemon: return Color(red: 1.0, green: 0.88, blue: 0.28)
        case .tangerine: return Color(red: 1.0, green: 0.62, blue: 0.22)
        case .grapefruit: return Color(red: 1.0, green: 0.72, blue: 0.55)
        case .pear: return Color(red: 0.78, green: 0.88, blue: 0.32)
        case .peach: return Color(red: 1.0, green: 0.62, blue: 0.48)
        case .cherry: return Color(red: 0.92, green: 0.18, blue: 0.32)
        case .plum: return Color(red: 0.62, green: 0.28, blue: 0.72)
        case .apricot: return Color(red: 1.0, green: 0.68, blue: 0.38)
        case .grape: return Color(red: 0.58, green: 0.32, blue: 0.88)
        case .strawberry: return Color(red: 0.98, green: 0.32, blue: 0.42)
        case .blueberry: return Color(red: 0.35, green: 0.42, blue: 0.92)
        case .raspberry: return Color(red: 0.92, green: 0.28, blue: 0.48)
        case .blackberry: return Color(red: 0.32, green: 0.18, blue: 0.48)
        case .cranberry: return Color(red: 0.82, green: 0.18, blue: 0.32)
        case .kiwi: return Color(red: 0.55, green: 0.72, blue: 0.28)
        case .melon: return Color(red: 0.72, green: 0.92, blue: 0.48)
        case .mango: return Color(red: 1.0, green: 0.72, blue: 0.18)
        case .coconut: return Color(red: 0.62, green: 0.48, blue: 0.32)
        case .avocado: return Color(red: 0.32, green: 0.62, blue: 0.28)
        case .pineapple: return Color(red: 1.0, green: 0.78, blue: 0.22)
        case .watermelon: return Color(red: 0.28, green: 0.78, blue: 0.42)
        case .papaya: return Color(red: 1.0, green: 0.58, blue: 0.22)
        case .lychee: return Color(red: 0.95, green: 0.35, blue: 0.45)
        case .longan: return Color(red: 0.92, green: 0.78, blue: 0.42)
        case .persimmon: return Color(red: 0.95, green: 0.48, blue: 0.18)
        case .pomelo: return Color(red: 1.0, green: 0.88, blue: 0.62)
        case .guava: return Color(red: 0.42, green: 0.82, blue: 0.48)
        case .dragonFruit: return Color(red: 0.95, green: 0.35, blue: 0.72)
        case .passionFruit: return Color(red: 0.62, green: 0.28, blue: 0.82)
        case .pomegranate: return Color(red: 0.82, green: 0.12, blue: 0.22)
        case .durian: return Color(red: 0.92, green: 0.82, blue: 0.28)
        case .rambutan: return Color(red: 0.92, green: 0.22, blue: 0.32)
        case .jackfruit: return Color(red: 1.0, green: 0.88, blue: 0.32)
        case .starfruit: return Color(red: 1.0, green: 0.92, blue: 0.35)
        case .mangosteen: return Color(red: 0.72, green: 0.22, blue: 0.42)
        case .fig: return Color(red: 0.58, green: 0.32, blue: 0.52)
        }
    }
}

// MARK: - Bonus vegetables (score only, random spawn)

enum VegKind: Hashable, CaseIterable {
    case carrot, tomato, broccoli, corn, eggplant, bellPepper, pumpkin, cucumber, mushroom, cabbage

    static func randomBonus() -> VegKind {
        allCases.randomElement() ?? .carrot
    }

    var bonusPoints: Int {
        switch self {
        case .carrot: return 35
        case .tomato: return 40
        case .broccoli: return 42
        case .corn: return 38
        case .eggplant: return 45
        case .bellPepper: return 40
        case .pumpkin: return 55
        case .cucumber: return 32
        case .mushroom: return 48
        case .cabbage: return 36
        }
    }

    var name: String {
        switch self {
        case .carrot: return "胡萝卜"
        case .tomato: return "番茄"
        case .broccoli: return "西兰花"
        case .corn: return "玉米"
        case .eggplant: return "茄子"
        case .bellPepper: return "彩椒"
        case .pumpkin: return "南瓜"
        case .cucumber: return "黄瓜"
        case .mushroom: return "蘑菇"
        case .cabbage: return "卷心菜"
        }
    }

    var accent: Color {
        switch self {
        case .carrot: return Color(red: 1.0, green: 0.55, blue: 0.18)
        case .tomato: return Color(red: 0.92, green: 0.22, blue: 0.22)
        case .broccoli: return Color(red: 0.28, green: 0.62, blue: 0.32)
        case .corn: return Color(red: 1.0, green: 0.82, blue: 0.28)
        case .eggplant: return Color(red: 0.48, green: 0.28, blue: 0.72)
        case .bellPepper: return Color(red: 0.92, green: 0.32, blue: 0.28)
        case .pumpkin: return Color(red: 0.95, green: 0.52, blue: 0.12)
        case .cucumber: return Color(red: 0.42, green: 0.78, blue: 0.38)
        case .mushroom: return Color(red: 0.82, green: 0.68, blue: 0.52)
        case .cabbage: return Color(red: 0.52, green: 0.82, blue: 0.48)
        }
    }
}

enum OrbKind {
    case normal, swarm, elite, zig, titan
}
