import Foundation
import SwiftUI

enum L10n {
    static let languageKey = "lad.language"
    static var languageCode: String {
        let saved = UserDefaults.standard.string(forKey: languageKey) ?? "system"
        if saved == "en" || saved == "ru" { return saved }
        return Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
    }
    static func text(_ source: String) -> String {
        guard languageCode == "en", let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return source }
        return NSLocalizedString(source, tableName: "Localizable", bundle: bundle, value: source, comment: "")
    }
    static func format(_ source: String, _ arguments: CVarArg...) -> String {
        String(format: text(source), locale: Locale(identifier: languageCode), arguments: arguments)
    }
}

enum Palette {
    static let canvas = Color(red: 0.982, green: 0.974, blue: 0.948)
    static let ink = Color(red: 0.17, green: 0.24, blue: 0.19)
    static let sage = Color(red: 0.29, green: 0.42, blue: 0.33)
    static let paleSage = Color(red: 0.89, green: 0.92, blue: 0.85)
    static let terracotta = Color(red: 0.73, green: 0.39, blue: 0.27)
    static let peach = Color(red: 0.96, green: 0.87, blue: 0.79)
    static let muted = Color(red: 0.48, green: 0.52, blue: 0.47)
    static let line = Color(red: 0.90, green: 0.89, blue: 0.84)
}

enum AllergenMatching {
    private static let glutenCereals: Set<String> = ["Пшеница", "Рожь", "Ячмень", "Овёс"]

    static func conflicts(selected: [String], recipe: [String]) -> Bool {
        let restrictions = Set(selected)
        let listed = Set(recipe)
        if !restrictions.isDisjoint(with: listed) { return true }
        if restrictions.contains("Злаки с глютеном") && !listed.isDisjoint(with: glutenCereals) { return true }
        if listed.contains("Злаки с глютеном") && !restrictions.isDisjoint(with: glutenCereals) { return true }
        return false
    }
}

struct Ingredient: Identifiable, Codable {
    var name: String
    var amount: Double?
    var unit: String
    var category: String
    var alternatives: [String]? = nil
    var amountMax: Double? = nil
    var aiEstimated: Bool? = nil
    var id: String { "\(name)|\(unit)" }
}

struct EnergyEstimate {
    let knownBatchKcal: Int
    let unresolvedNames: [String]
    let usesEstimatedMeasures: Bool
    let aiEstimatedNames: [String]
}

enum EnergyEstimator {
    // Approximate reference energy per 100 g of raw ingredient. A household unit
    // is an editorial estimate, never an alteration of the source ingredient list.
    private static let kcalPer100g: [String: Double] = [
        "Лосось": 208, "Картофель": 77, "Брокколи": 34, "Йогурт натуральный": 60,
        "Лимон": 29, "Творог": 121, "Яйцо": 143, "Мука": 364, "Ягоды": 50,
        "Чечевица красная": 352, "Томаты": 18, "Лук": 40, "Морковь": 41,
        "Овсяные хлопья": 389, "Молоко": 50, "Банан": 89, "Хлеб": 265,
        "Куриное филе": 120, "Гречка": 343, "Огурец": 15, "Макароны": 350,
        "Кабачок": 17, "Цукини": 17, "Сыр": 350, "Филе индейки": 114,
        "Рис": 365, "Бурый рис": 370, "Перец сладкий": 26, "Сладкий перец": 26,
        "Минтай": 72, "Хек": 82, "Сметана": 200, "Цветная капуста": 25,
        "Шампиньоны": 22, "Рисовая мука": 366, "Ржаная мука": 335,
        "Сельдерей": 16, "Мясной фарш": 250, "Растительное масло": 884,
        "Капуста": 25, "Свёкла": 43, "Яблоко": 52, "Чеснок": 149,
        "Чернослив": 240, "Говядина": 200, "Ванилин": 288, "Майоран": 271,
        "Любисток": 42, "Сушёный чеснок": 331, "Соль": 0, "Чёрный перец": 251,
        "Кориандр": 298, "Укроп": 43, "Аджика": 60, "Зелень": 30,
        "Специи": 300, "Лимонный сок": 22, "Рисовая лапша": 364,
        "Лавровый лист": 313, "Душистый перец": 263, "Специи для плова": 300,
        "Зелёный лук": 32, "Паприка": 282, "Майонез": 680,
        "Разрыхлитель": 53
    ]
    private static let pieceGrams: [String: Double] = [
        "Лимон": 58, "Яйцо": 50, "Банан": 118, "Лук": 110,
        "Морковь": 75, "Цукини": 200, "Кабачок": 200, "Томаты": 120,
        "Куриное филе": 200,
        "Сладкий перец": 120, "Перец сладкий": 120, "Шампиньоны": 18,
        "Яблоко": 150, "Чернослив": 10, "Огурец": 150
    ]
    static func estimatedGrams(for ingredient: Ingredient) -> Double? {
        guard let amount = ingredient.amount, amount > 0 else { return nil }
        switch ingredient.unit {
        case "г", "мл": return amount
        case "шт.": return pieceGrams[ingredient.name].map { amount * $0 }
        case "зуб.": return ingredient.name == "Чеснок" ? amount * 3 : nil
        case "головка": return ingredient.name == "Чеснок" ? amount * 40 : nil
        case "филе": return ["Куриное филе": 200, "Минтай": 150, "Хек": 150][ingredient.name].map { amount * $0 }
        case "ст. л.": return ["Йогурт натуральный": 15, "Рисовая мука": 10,
                                 "Ржаная мука": 10][ingredient.name].map { amount * $0 }
        case "ч. л.": return ["Растительное масло": 5, "Сметана": 5,
                                "Сельдерей": 3, "Майонез": 5][ingredient.name].map { amount * $0 }
        case "стакан": return ["Бурый рис": 180, "Рис": 180][ingredient.name].map { amount * $0 }
        case "ломтик": return ingredient.name == "Сельдерей" ? amount * 10 : nil
        case "щепотка": return amount * 0.5
        default: return nil
        }
    }
    static func evaluate(_ ingredients: [Ingredient]) -> EnergyEstimate {
        var known = 0.0
        var unresolved: [String] = []
        var estimatedMeasure = false
        var aiEstimated: [String] = []
        for ingredient in ingredients {
            if ingredient.aiEstimated == true { aiEstimated.append(ingredient.name) }
            guard let amount = ingredient.amount, amount > 0,
                  let density = kcalPer100g[ingredient.name] else {
                unresolved.append(ingredient.name)
                continue
            }
            guard let grams = estimatedGrams(for: ingredient) else { unresolved.append(ingredient.name); continue }
            if ingredient.unit != "г" && ingredient.unit != "мл" { estimatedMeasure = true }
            let averageAmount = ingredient.amountMax.map { (amount + $0) / (2 * amount) } ?? 1
            known += grams * averageAmount * density / 100
        }
        return EnergyEstimate(knownBatchKcal: Int(known.rounded()),
                              unresolvedNames: unresolved, usesEstimatedMeasures: estimatedMeasure,
                              aiEstimatedNames: aiEstimated)
    }
}

enum CookingDifficulty: String, Codable {
    case easy, moderate, involved

    var label: String {
        switch self {
        case .easy: return "Легко"
        case .moderate: return "Средняя"
        case .involved: return "Много действий"
        }
    }
}

struct NutrientValue: Codable {
    var amount: Double
    var unit: String
    var source: String
    var coverage: Double
}

struct Recipe: Identifiable {
    let id: String
    let title: String
    let caption: String
    let image: String
    let cuisine: String
    let minutes: Int
    let kcal: Int?
    let protein: Int?
    let allergens: [String]
    let ingredients: [Ingredient]
    let steps: [String]
    var allergensVerified: Bool = false
    var mealKinds: [Int] = [0, 1, 2]
    var nutrients: [String: NutrientValue] = [:]
    var remoteImage: Bool = false
    var stepImageIDs: [String?] = []
    var difficulty: CookingDifficulty? = nil
    var energyEstimate: EnergyEstimate? = nil
    var baseServings: Double = 1
    var servingsEstimated: Bool = false
    var kcalEstimated: Bool = false
    var isPrivate: Bool { id.hasPrefix("private:") }
    var isUnavailable: Bool { id == "unavailable" || id == "unplanned" }
    var isUnplanned: Bool { id == "unplanned" }
    var isPlanEligible: Bool {
        !isUnavailable && !ingredients.isEmpty && ingredients.allSatisfy { ($0.amount ?? 0) > 0 } &&
        (!isPrivate || allergensVerified)
    }

    static let unavailable = Recipe(id: "unavailable", title: "Закрытый рецепт недоступен", caption: "Подключите каталог, чтобы снова открыть это блюдо.", image: "", cuisine: "Закрытая библиотека", minutes: 0, kcal: nil, protein: nil, allergens: [], ingredients: [], steps: [])
    static let unplanned = Recipe(id: "unplanned", title: "Блюдо не выбрано", caption: "Выберите курс и составьте меню.", image: "", cuisine: "", minutes: 0, kcal: nil, protein: nil, allergens: [], ingredients: [], steps: [])

    private struct PublicDemoBundle: Decodable { let recipes: [PrivateRecipePayload] }

    static let all: [Recipe] = {
        guard let url = Bundle.main.url(forResource: "public-recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(PublicDemoBundle.self, from: data) else { return [] }
        let recipes = bundle.recipes.compactMap { $0.recipe(privateAccess: false, remoteImage: false) }
        guard recipes.count == bundle.recipes.count, Set(recipes.map(\.id)).count == recipes.count else { return [] }
        return recipes
    }()
}

struct FamilyMember: Identifiable, Codable {
    var id: String
    var name: String
    var goal: String
    var portion: Double
    var allergies: [String]
    var ageYears: Int? = nil
    var dailyEnergyTarget: Int? = nil
    var heightCm: Double? = nil
    var weightKg: Double? = nil
    var measuredFatMassKg: Double? = nil
    var measuredMuscleMassKg: Double? = nil
    var fatPercent: Double? {
        guard let weightKg, let measuredFatMassKg, weightKg > 0,
              measuredFatMassKg >= 0, measuredFatMassKg <= weightKg else { return nil }
        return measuredFatMassKg / weightKg * 100
    }
    var musclePercent: Double? {
        guard let weightKg, let measuredMuscleMassKg, weightKg > 0,
              measuredMuscleMassKg >= 0, measuredMuscleMassKg <= weightKg else { return nil }
        return measuredMuscleMassKg / weightKg * 100
    }
    var initials: String { String(name.prefix(1)) }
    var ageLabel: String? {
        guard let ageYears else { return nil }
        if L10n.languageCode == "en" { return "\(ageYears) years" }
        let suffix: String
        if (11...14).contains(ageYears % 100) { suffix = "лет" }
        else if ageYears % 10 == 1 { suffix = "год" }
        else if (2...4).contains(ageYears % 10) { suffix = "года" }
        else { suffix = "лет" }
        return "\(ageYears) \(suffix)"
    }
}

struct PantryItem: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var quantity: Double?
    var unit: String
    var category: String
    var expiresOn: Date? = nil
}

struct PurchaseReceipt: Identifiable, Codable {
    var id: String
    var productName: String
    var quantity: Double
    var unit: String
    var purchasedAt: Date
}

struct MealSlot: Identifiable, Codable {
    var id: String
    var day: Int
    var kind: Int
    var recipeID: String
    var memberIDs: [String]
}

struct DemoState: Codable {
    var startDate: Date
    var members: [FamilyMember]
    var slots: [MealSlot]
    var selectedMemberID: String
    var eatenIDs: Set<String>
    var boughtNames: Set<String>
    var pantryNames: Set<String>
    var pantryItems: [PantryItem]? = nil
    var favorites: Set<String>
    var dislikes: Set<String>? = nil
    var avoidedRecipesBySlot: [String: Set<String>]? = nil
    var extraShopping: [String]
    var supplementsByMember: [String: [String]]
    var takenSupplements: Set<String>
    var skippedSlotIDs: Set<String>? = nil
    var activeCourseIDs: Set<String>? = nil
    var mealSchedule: MealSchedule? = nil
    var purchaseReceipts: [PurchaseReceipt]? = nil

    static func initial(selectAllAvailableCourses: Bool = false) -> DemoState {
        let family = [
            FamilyMember(id: "anna", name: "Анна", goal: "Баланс", portion: 1.0, allergies: []),
            FamilyMember(id: "igor", name: "Игорь", goal: "Поддержание", portion: 1.25, allergies: []),
            FamilyMember(id: "mila", name: "Мила", goal: "Без цели по весу", portion: 0.65, allergies: [])
        ]
        var slots: [MealSlot] = []
        for day in 0..<7 {
            for kind in 0..<3 {
                let breakfast = ["pancakes", "oats", "eggs"]
                let lunch = ["soup", "chicken-buckwheat", "vegetable-pasta"]
                let dinner = ["salmon", "turkey-rice", "lentil-stew"]
                let recipeID = kind == 0 ? breakfast[day % breakfast.count] : (kind == 1 ? lunch[day % lunch.count] : dinner[day % dinner.count])
                slots.append(MealSlot(id: "\(day)-\(kind)", day: day, kind: kind, recipeID: recipeID, memberIDs: family.map(\.id)))
            }
        }
        let initialCourses = selectAllAvailableCourses
            ? Set(CourseCatalogAccess.bundledCourses.map(\.id)) : Set(["lad-starter"])
        return DemoState(startDate: Calendar.current.startOfDay(for: .now), members: family, slots: slots, selectedMemberID: "anna", eatenIDs: [], boughtNames: [], pantryNames: [], favorites: ["anna|salmon"], extraShopping: [], supplementsByMember: [:], takenSupplements: [], activeCourseIDs: initialCourses)
    }

    static func nextWeek(after previous: DemoState, now: Date) -> DemoState {
        var fresh = DemoState.initial()
        fresh.startDate = Calendar.current.startOfDay(for: now)
        fresh.members = previous.members
        fresh.selectedMemberID = previous.selectedMemberID
        fresh.favorites = previous.favorites
        fresh.dislikes = previous.dislikes
        fresh.activeCourseIDs = previous.activeCourseIDs
        if fresh.activeCourseIDs?.contains("lad-starter") != true {
            for index in fresh.slots.indices { fresh.slots[index].recipeID = Recipe.unplanned.id }
        }
        fresh.pantryNames = previous.pantryNames
        fresh.pantryItems = previous.pantryItems
        fresh.extraShopping = previous.extraShopping
        fresh.supplementsByMember = previous.supplementsByMember
        fresh.mealSchedule = previous.mealSchedule
        fresh.purchaseReceipts = previous.purchaseReceipts
        for index in fresh.slots.indices {
            let kind = fresh.slots[index].kind
            let sameKind = previous.slots.filter { $0.kind == kind }
            let first = Set(sameKind.first?.memberIDs ?? [])
            fresh.slots[index].memberIDs = sameKind.count == 7 && sameKind.allSatisfy({ Set($0.memberIDs) == first })
                ? (sameKind.first?.memberIDs ?? []) : []
        }
        return fresh
    }
}

enum LocalWeekArchive {
    private static func folder() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = support.appendingPathComponent("lad-week-history", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        return folder
    }

    static func save(_ state: DemoState, accountID: String) throws {
        let file = try folder().appendingPathComponent("\(accountID)-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtection])
    }

    static func saveUnreadable(_ data: Data, accountID: String) throws {
        let file = try folder().appendingPathComponent("\(accountID)-unreadable-\(UUID().uuidString).bin")
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }

    static func count(accountID: String) -> Int {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return 0 }
        let folder = support.appendingPathComponent("lad-week-history", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(accountID + "-") && $0.pathExtension == "json" }.count ?? 0
    }
}

struct PlannedChange: Identifiable {
    let slotID: String
    let previousID: String
    let nextID: String
    var id: String { slotID }
}

struct ReplanPreview: Identifiable {
    let id = UUID().uuidString
    let title: String
    let explanation: String
    let changes: [PlannedChange]
    let shoppingDelta: [String]
    let pendingAvoid: AvoidedRecipe?
    let emptyMessage: String
    let expectedRevision: Int
    let expectedCatalogRevision: Int
    let lateCorrectionSlotID: String?
    let outsideCourseSlotID: String?
    let lateCorrectionSlotIDs: Set<String>
    let reviewRecipeIDs: Set<String>
}

struct AvoidedRecipe: Equatable {
    let slotID: String
    let memberID: String
    let recipeID: String
    var key: String { "\(slotID)|\(memberID)" }
}

@MainActor final class LadStore: ObservableObject {
    @Published var state: DemoState {
        didSet {
            stateRevision += 1
            if undoRevision != nil && undoRevision != stateRevision {
                undoRevision = nil
                canUndoReplan = false
                lastAppliedChanges = []
                lastAppliedAvoid = nil
            }
            save()
        }
    }
    @Published var selectedDay: Int = 0
    @Published private(set) var now: Date = .now
    @Published private(set) var privateRecipes: [Recipe] = []
    @Published private(set) var catalogueRecipes: [Recipe] = []
    @Published private(set) var courses: [LadCourse] = CourseCatalogAccess.bundledCourses
    @Published private(set) var courseCatalogStatus: String = "Демо-каталог офлайн"
    @Published private(set) var privateCatalogStatus: String = "Не подключён"
    @Published private(set) var familyCloudStatus: String = "Не подключено"
    @Published private(set) var storageWarning: String?
    @Published var replanPreview: ReplanPreview?
    @Published private(set) var canUndoReplan = false
    private var lastAppliedChanges: [PlannedChange] = []
    private var lastAppliedAvoid: AvoidedRecipe?
    private var stateRevision = 0
    private var catalogRevision = 0
    private var privateSessionRevision = 0
    private var undoRevision: Int?
    private var undoCatalogRevision: Int?
    let localAccountID: String
    var kinds: [String] { [L10n.text("Завтрак"), L10n.text("Обед"), L10n.text("Ужин")] }

    init() {
        if let savedID = UserDefaults.standard.string(forKey: "lad.localAccountID"), UUID(uuidString: savedID) != nil {
            localAccountID = savedID
        } else {
            let newID = UUID().uuidString
            localAccountID = newID
            UserDefaults.standard.set(newID, forKey: "lad.localAccountID")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshots") {
            state = .initial()
            if ProcessInfo.processInfo.arguments.contains("--empty-courses") {
                state.activeCourseIDs = []
            }
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: "lad-demo-v3"),
           let decoded = try? JSONDecoder().decode(DemoState.self, from: data) {
            let elapsed = Calendar.current.dateComponents([.day], from: decoded.startDate, to: .now).day ?? 0
            if elapsed > 6 {
                do {
                    try LocalWeekArchive.save(decoded, accountID: localAccountID)
                    state = DemoState.nextWeek(after: decoded, now: .now)
                } catch {
                    state = decoded
                    storageWarning = L10n.text("Не удалось сохранить прошлую неделю. Новый план не создан; данные оставлены без изменений.")
                }
            } else {
                state = decoded
                selectedDay = max(0, elapsed)
            }
        } else if let unreadable = UserDefaults.standard.data(forKey: "lad-demo-v3") {
            do {
                try LocalWeekArchive.saveUnreadable(unreadable, accountID: localAccountID)
            } catch {
                UserDefaults.standard.set(unreadable, forKey: "lad-unreadable-state-backup")
            }
            state = .initial()
            storageWarning = L10n.text("Старые данные не удалось прочитать. Они сохранены для восстановления; показан новый демо-план.")
        } else {
            state = .initial(selectAllAvailableCourses: true)
        }
        // Older installs had an implicit demo source. Record it explicitly so an empty
        // course selection is never confused with permission to use every recipe.
        if state.activeCourseIDs == nil { state.activeCourseIDs = ["lad-starter"] }
        if state.activeCourseIDs?.isEmpty == true {
            for index in state.slots.indices {
                let slot = state.slots[index]
                if !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                    state.slots[index].recipeID = Recipe.unplanned.id
                }
            }
        }
        let legacyFavorites = state.favorites.filter { !$0.contains("|") }
        for favorite in legacyFavorites {
            state.favorites.remove(favorite)
            state.favorites.insert("\(state.selectedMemberID)|\(favorite)")
        }
        if state.pantryItems == nil {
            state.pantryItems = state.pantryNames.map { name in
                let ingredient = Recipe.all.flatMap(\.ingredients).first { $0.name == name }
                return PantryItem(name: name, quantity: nil, unit: ingredient?.unit ?? "шт.", category: ingredient?.category ?? "Другое")
            }
            state.pantryNames = []
        }
        // Only replace the untouched three-dishes-every-day demo, never a person's edited plan.
        let oldPattern = state.slots.count == 21 && state.slots.allSatisfy { slot in
            slot.recipeID == (slot.kind == 0 ? "pancakes" : (slot.kind == 1 ? "soup" : "salmon"))
        }
        if oldPattern && state.activeCourseIDs?.contains("lad-starter") == true {
            let improved = DemoState.initial().slots
            for index in state.slots.indices {
                let slot = state.slots[index]
                if slot.day >= currentDay && !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                    state.slots[index].recipeID = improved[index].recipeID
                }
            }
        }
        #if DEBUG
        if let issue = PrivateRecipeAccess.importPilotProvisioning() {
            familyCloudStatus = issue
        }
        #endif
        if PrivateRecipeAccess.isConfigured {
            privateRecipes = PrivateRecipeAccess.cached()
            Task {
                await refreshPrivateRecipes()
                await refreshFamily()
            }
        }
        if CourseCatalogAccess.savedURL != nil {
            Task { await refreshCourseCatalog() }
        }
        save()
    }

    var currentMember: FamilyMember { state.members.first { $0.id == state.selectedMemberID } ?? state.members[0] }
    var archivedWeekCount: Int { LocalWeekArchive.count(accountID: localAccountID) }
    var allRecipes: [Recipe] {
        var seen = Set<String>()
        return (catalogueRecipes + Recipe.all + privateRecipes).filter { seen.insert($0.id).inserted }
    }
    var activeCourseIDs: Set<String> { state.activeCourseIDs ?? [] }
    var selectedCourses: [LadCourse] { courses.filter { activeCourseIDs.contains($0.id) } }
    var hasSelectedCourses: Bool { !selectedCourses.isEmpty }
    private var activeCourseRecipeIDs: Set<String> {
        let existing = Set(allRecipes.map(\.id))
        return Set(selectedCourses.flatMap(\.recipeIDs).map { id in
            existing.contains(id) ? id : "private:\(id)"
        })
    }
    func isOutsideSelectedCourses(_ recipeID: String) -> Bool {
        return !activeCourseRecipeIDs.contains(recipeID)
    }
    func isSelectedCourseRecipe(_ recipeID: String) -> Bool {
        activeCourseRecipeIDs.contains(recipeID)
    }
    func courseSourceLabel(for recipeID: String) -> String {
        let normalized = recipeID.hasPrefix("private:") ? String(recipeID.dropFirst("private:".count)) : recipeID
        let matches = courses.filter { $0.recipeIDs.contains(normalized) || $0.recipeIDs.contains(recipeID) }
        if matches.isEmpty { return L10n.text("Без курса") }
        return L10n.format("Курс: %@", matches.map(\.title).joined(separator: ", "))
    }
    func courseDraftIssue(_ recipe: Recipe, for requestedSlot: MealSlot) -> String? {
        guard let slot = state.slots.first(where: { $0.id == requestedSlot.id }) else {
            return L10n.text("Приём больше не найден в плане.")
        }
        guard isSelectedCourseRecipe(recipe.id), recipe.mealKinds.contains(slot.kind),
              !recipe.isUnavailable, !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else {
            return L10n.text("Блюдо не подходит для этого приёма выбранного курса.")
        }
        let people = participating(slot)
        guard !people.isEmpty else { return L10n.text("В этом приёме никто не участвует.") }
        if !recipe.allergensVerified && people.contains(where: { !$0.allergies.isEmpty }) {
            return L10n.text("Сведения об аллергенах блюда не проверены. Для участника с ограничениями его нельзя назначить.")
        }
        let incompatible = people.filter { AllergenMatching.conflicts(selected: $0.allergies, recipe: recipe.allergens) }
        if !incompatible.isEmpty {
            return L10n.text("Блюдо противоречит ограничениям участников.")
        }
        return nil
    }
    func chooserRecipes(for requestedSlot: MealSlot) -> [Recipe] {
        guard let slot = state.slots.first(where: { $0.id == requestedSlot.id }) else { return [] }
        return eligibleRecipes(for: slot)
    }
    #if DEBUG
    func replaceCatalogForTesting(recipes: [Recipe], courses: [LadCourse]) {
        catalogueRecipes = recipes
        self.courses = courses
        catalogRevision += 1
    }
    #endif
    func toggleCourse(_ id: String) {
        guard courses.contains(where: { $0.id == id }) else { return }
        var next = state
        var selected = next.activeCourseIDs ?? []
        let removing = !selected.insert(id).inserted
        if removing {
            selected.remove(id)
            clearUnselectedMeals(in: &next, selected: selected)
        }
        next.activeCourseIDs = selected
        state = next
    }
    func selectAllCourses() {
        var next = state
        next.activeCourseIDs = Set(courses.map(\.id))
        state = next
    }
    func deselectAllCourses() {
        var next = state
        next.activeCourseIDs = []
        clearUnselectedMeals(in: &next, selected: [])
        state = next
    }
    private func clearUnselectedMeals(in next: inout DemoState, selected: Set<String>) {
        let existing = Set(allRecipes.map(\.id))
        let allowed = Set(courses.filter { selected.contains($0.id) }.flatMap(\.recipeIDs).map { recipeID in
            existing.contains(recipeID) ? recipeID : "private:\(recipeID)"
        })
        for index in next.slots.indices {
            let slot = next.slots[index]
            guard !next.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }),
                  !allowed.contains(slot.recipeID) else { continue }
            next.slots[index].recipeID = Recipe.unplanned.id
        }
    }
    var outsideFutureSlotCount: Int {
        state.slots.filter { slot in
            slot.day >= currentDay && slot.recipeID != Recipe.unplanned.id &&
            !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) &&
            !activeCourseRecipeIDs.contains(slot.recipeID)
        }.count
    }
    func clearFutureDishesOutsideCourses() {
        var next = state
        for index in next.slots.indices {
            let slot = next.slots[index]
            guard slot.day >= currentDay, slot.recipeID != Recipe.unplanned.id,
                  !next.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }),
                  !activeCourseRecipeIDs.contains(slot.recipeID) else { continue }
            next.slots[index].recipeID = Recipe.unplanned.id
        }
        if next.slots.map(\.recipeID) != state.slots.map(\.recipeID) { state = next }
    }
    func setCourseCatalogURL(_ url: String) async {
        do {
            try CourseCatalogAccess.saveURL(url)
            await refreshCourseCatalog()
        } catch {
            courseCatalogStatus = error.localizedDescription
        }
    }
    func refreshCourseCatalog() async {
        let session = privateSessionRevision
        courseCatalogStatus = L10n.text("Загружаем…")
        do {
            let snapshot = try await CourseCatalogAccess.fetch()
            guard session == privateSessionRevision else { return }
            catalogueRecipes = snapshot.recipes
            courses = snapshot.courses
            let remaining = activeCourseIDs.intersection(Set(courses.map(\.id)))
            if remaining != activeCourseIDs {
                var next = state
                next.activeCourseIDs = remaining
                clearUnselectedMeals(in: &next, selected: remaining)
                state = next
            }
            catalogRevision += 1
            courseCatalogStatus = L10n.format("Загружено программ: %d", courses.count)
        } catch {
            guard session == privateSessionRevision else { return }
            if case PrivateCatalogError.unauthorized = error {
                catalogueRecipes = []
                courses = CourseCatalogAccess.bundledCourses
                privateRecipes = []
                privateCatalogStatus = error.localizedDescription
                catalogRevision += 1
            }
            courseCatalogStatus = error.localizedDescription
        }
    }
    var pantry: [PantryItem] { state.pantryItems ?? [] }
    var mealSchedule: MealSchedule { state.mealSchedule ?? .standard }
    var planRequirements: PlanRequirements {
        let effectiveSlots = hasSelectedCourses ? state.slots : state.slots.map { slot in
            var empty = slot
            empty.recipeID = Recipe.unplanned.id
            return empty
        }
        return PlanningCore.resolvePlan(slots: effectiveSlots, members: state.members, recipes: allRecipes,
                                 pantry: pantry, startDate: state.startDate, now: now,
                                 eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                 schedule: mealSchedule)
    }
    var shoppingNeeds: [ShoppingNeed] {
        planRequirements.shoppingNeeds
    }
    func requirements(for slot: MealSlot) -> SlotRequirements? { planRequirements.slots[slot.id] }
    func requirements(for recipe: Recipe, replacing slot: MealSlot) -> SlotRequirements? {
        var candidateSlots = state.slots
        guard let index = candidateSlots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        candidateSlots[index].recipeID = recipe.id
        return PlanningCore.resolvePlan(slots: candidateSlots, members: state.members, recipes: allRecipes,
                                        pantry: pantry, startDate: state.startDate, now: now,
                                        eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                        schedule: mealSchedule).slots[slot.id]
    }
    func availabilityTitle(for slot: MealSlot) -> String {
        if slot.recipeID == Recipe.unplanned.id { return L10n.text("Нет блюда · выберите курс и пересчитайте меню") }
        return availabilityTitle(requirements(for: slot), inventoryEmpty: planRequirements.inventoryEmpty)
    }
    func availabilityTitle(for recipe: Recipe, replacing slot: MealSlot) -> String {
        availabilityTitle(requirements(for: recipe, replacing: slot), inventoryEmpty: pantry.isEmpty)
    }
    private func availabilityTitle(_ result: SlotRequirements?, inventoryEmpty: Bool) -> String {
        guard let result else { return L10n.text("Наличие уточняется") }
        switch result.availability {
        case .past: return L10n.text("Время прошло · блюдо остаётся в плане до вашего решения")
        case .eaten: return L10n.text("Отмечено как съеденное")
        case .skipped: return L10n.text("Приём пропущен · продукты освобождены")
        case .noParticipants: return L10n.text("Никто не участвует")
        case .unavailable: return L10n.text("Рецепт недоступен — покупки неполные")
        case .needsReview: return L10n.text("Рецепт требует проверки · покупки предварительные")
        case .active: break
        }
        if inventoryEmpty { return L10n.text("Запасы не внесены — проверьте продукты") }
        if result.isReady { return L10n.text("Все продукты на этот приём есть дома") }
        let questions = result.ingredients.filter { $0.required == nil || $0.uncertain }.count
        let shortages = result.shortageCount
        if questions > 0 && shortages == 0 { return L10n.format("Нужно уточнить %d поз.", questions) }
        if questions > 0 { return L10n.format("Докупить %d поз. · уточнить %d", shortages, questions) }
        return L10n.format("Докупить %d поз.", shortages)
    }
    func availabilityDetails(for slot: MealSlot) -> [String] {
        guard let result = requirements(for: slot),
              result.availability == .active || result.availability == .needsReview ||
              result.availability == .past else { return [] }
        return result.ingredients.compactMap { ingredient in
            if ingredient.required == nil { return L10n.format("%@: уточнить количество", L10n.text(ingredient.name)) }
            if ingredient.uncertain { return L10n.format("%@: проверить остаток", L10n.text(ingredient.name)) }
            guard let shortage = ingredient.shortage, shortage > 0.001 else { return nil }
            let amount = shortage.formatted(.number.precision(.fractionLength(0...1)))
            return L10n.format("%@: докупить %@ %@", L10n.text(ingredient.name), amount, L10n.text(ingredient.unit))
        }
    }
    func ingredientAvailabilityText(_ ingredient: Ingredient, in slot: MealSlot?) -> String {
        if let slot {
            guard let line = requirements(for: slot)?.ingredients.first(where: {
                $0.id == PlanningCore.key(ingredient.name, ingredient.unit)
            }) else { return L10n.text("Наличие пока не рассчитано") }
            guard let required = line.required else { return L10n.text("Уточните количество для приготовления") }
            let allocated = line.allocated.formatted(.number.precision(.fractionLength(0...1)))
            let needed = required.formatted(.number.precision(.fractionLength(0...1)))
            if line.isReady { return L10n.format("Из запасов на этот день: %@ из %@ %@", allocated, needed, L10n.text(line.unit)) }
            if line.uncertain { return L10n.format("Подтверждено %@ из %@ %@ · остаток проверить", allocated, needed, L10n.text(line.unit)) }
            let missing = (line.shortage ?? 0).formatted(.number.precision(.fractionLength(0...1)))
            return L10n.format("Подтверждено %@ из %@ %@ · докупить %@ %@", allocated, needed, L10n.text(line.unit), missing, L10n.text(line.unit))
        }
        if pantry.isEmpty { return L10n.text("Запасы ещё не внесены") }
        guard let amount = ingredient.amount, amount > 0 else { return L10n.text("Уточните количество для приготовления") }
        let stock = PlanningCore.stock(for: ingredient, pantry: planRequirements.freePantry, now: now)
        if stock.known >= amount { return L10n.text("Есть в свободном остатке после плана") }
        return stock.uncertain ? L10n.text("Проверьте остаток") : L10n.text("Не записано достаточно продуктов дома")
    }
    func readiness(_ recipe: Recipe, portions: Double = 1) -> RecipeReadiness {
        PlanningCore.readiness(recipe, portions: portions, pantry: planRequirements.freePantry, now: now)
    }
    func pantryItem(named name: String, unit: String) -> PantryItem? {
        pantry.first { PlanningCore.key($0.name, $0.unit) == PlanningCore.key(name, unit) }
    }
    func savePantryItem(_ item: PantryItem) {
        var items = pantry
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
        state.pantryItems = items
    }
    func removePantryItem(_ id: String) {
        state.pantryItems = pantry.filter { $0.id != id }
    }
    func markOut(_ item: PantryItem) {
        var emptied = item
        emptied.quantity = 0
        savePantryItem(emptied)
        proposeReplan(affectedBy: item.name)
    }
    func addPurchasedToPantry(_ need: ShoppingNeed, quantity: Double, commandID: String) {
        guard quantity > 0, quantity.isFinite else { return }
        var next = state
        var receipts = next.purchaseReceipts ?? []
        guard !receipts.contains(where: { $0.id == commandID }) else { return }
        let item = PantryItem(name: need.name, quantity: quantity, unit: need.unit, category: need.category)
        var items = next.pantryItems ?? []
        items.append(item)
        next.pantryItems = items
        receipts.append(PurchaseReceipt(id: commandID, productName: need.name, quantity: quantity,
                                        unit: need.unit, purchasedAt: now))
        next.purchaseReceipts = receipts
        next.boughtNames.remove(need.name)
        state = next
    }
    var privateCatalogURL: String { PrivateRecipeAccess.savedURL ?? "" }
    var currentDay: Int { min(6, max(0, Calendar.current.dateComponents([.day], from: state.startDate, to: now).day ?? 0)) }
    func refreshClock(_ date: Date = .now) {
        let previousDay = currentDay
        now = date
        let elapsed = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: state.startDate),
                                                      to: Calendar.current.startOfDay(for: date)).day ?? 0
        if elapsed > 6 {
            do {
                try LocalWeekArchive.save(state, accountID: localAccountID)
                state = DemoState.nextWeek(after: state, now: date)
                selectedDay = 0
                storageWarning = nil
            } catch {
                storageWarning = L10n.text("Не удалось сохранить прошлую неделю. Новый план не создан; данные оставлены без изменений.")
            }
            return
        }
        if selectedDay == previousDay && currentDay != previousDay { selectedDay = currentDay }
    }
    func isPastWindow(_ slot: MealSlot) -> Bool {
        MealTiming.isPastWindow(day: slot.day, kind: slot.kind, currentDay: currentDay,
                                now: now, schedule: mealSchedule)
    }
    func suggestedSlot() -> MealSlot {
        if selectedDay != currentDay { return slot(selectedDay, 0) }
        let eatenKinds = Set((0..<3).filter { kind in
            let candidate = slot(currentDay, kind)
            let participants = participating(candidate)
            return !participants.isEmpty && participants.allSatisfy { state.eatenIDs.contains("\(candidate.id)-\($0.id)") }
        })
        if let kind = MealTiming.suggestedKind(on: currentDay, currentDay: currentDay, now: now,
                                                schedule: mealSchedule, eatenKinds: eatenKinds) {
            return slot(currentDay, kind)
        }
        if currentDay < 6 { return slot(currentDay + 1, 0) }
        return slot(currentDay, 2)
    }
    var supplementStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
    var dayLabels: [String] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: L10n.languageCode)
        return (0..<7).map { offset in
            fmt.dateFormat = "EE"
            return fmt.string(from: Calendar.current.date(byAdding: .day, value: offset, to: state.startDate)!).replacingOccurrences(of: ".", with: "").capitalized
        }
    }
    func dateLabel(_ offset: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: L10n.languageCode)
        fmt.dateFormat = "d MMMM"
        return fmt.string(from: Calendar.current.date(byAdding: .day, value: offset, to: state.startDate)!)
    }
    func dayNumber(_ offset: Int) -> String {
        String(Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: offset, to: state.startDate)!))
    }
    func slot(_ day: Int, _ kind: Int) -> MealSlot { state.slots.first { $0.day == day && $0.kind == kind }! }
    func recipe(_ slot: MealSlot) -> Recipe {
        if slot.recipeID == Recipe.unplanned.id { return .unplanned }
        return allRecipes.first { $0.id == slot.recipeID } ?? .unavailable
    }
    func participating(_ slot: MealSlot) -> [FamilyMember] { state.members.filter { slot.memberIDs.contains($0.id) } }
    func toggleEaten(_ slot: MealSlot) {
        guard slot.memberIDs.contains(state.selectedMemberID), slot.recipeID != Recipe.unplanned.id else { return }
        let key = "\(slot.id)-\(state.selectedMemberID)"
        var next = state
        if next.eatenIDs.contains(key) { next.eatenIDs.remove(key) }
        else {
            next.skippedSlotIDs?.remove(slot.id)
            next.eatenIDs.insert(key)
        }
        state = next
    }
    func isEaten(_ slot: MealSlot) -> Bool { state.eatenIDs.contains("\(slot.id)-\(state.selectedMemberID)") }
    func isSkipped(_ slot: MealSlot) -> Bool { state.skippedSlotIDs?.contains(slot.id) == true }
    func toggleSkipped(_ slot: MealSlot) {
        guard slot.day >= currentDay, !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else { return }
        var next = state
        var skipped = next.skippedSlotIDs ?? []
        if skipped.contains(slot.id) { skipped.remove(slot.id) } else { skipped.insert(slot.id) }
        next.skippedSlotIDs = skipped
        state = next
    }
    private func score(_ recipe: Recipe, slot: MealSlot, usedToday: Set<String>, plannedSlots: [MealSlot]) -> Double {
        var candidateSlots = plannedSlots
        guard let index = candidateSlots.firstIndex(where: { $0.id == slot.id }) else { return -.infinity }
        candidateSlots[index].recipeID = recipe.id
        let resolution = PlanningCore.resolvePlan(slots: candidateSlots, members: state.members, recipes: allRecipes,
                                                  pantry: pantry, startDate: state.startDate, now: now,
                                                  eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                                  schedule: mealSchedule)
        guard let match = resolution.slots[slot.id],
              match.availability == .active || match.availability == .needsReview ||
              (slot.day == currentDay && match.availability == .past) else { return -.infinity }
        var value = match.isReady ? (slot.day == currentDay ? 1_000.0 : 80.0) : 0
        if match.availability == .needsReview { value -= 100 }
        value += Double(match.ingredients.filter(\.isReady).count) * 5
        value -= Double(match.shortageCount) * 18
        value -= Double(match.ingredients.filter { $0.required == nil || $0.uncertain }.count) * 25
        if usedToday.contains(recipe.id) { value -= 35 }
        if plannedSlots.contains(where: { $0.day == slot.day - 1 && $0.recipeID == recipe.id }) { value -= 25 }
        value += Double(participating(slot).filter { state.favorites.contains("\($0.id)|\(recipe.id)") }.count * 5)
        if let kcal = recipe.kcal {
            for person in participating(slot) where (person.ageYears ?? 0) >= 18 {
                if let target = person.dailyEnergyTarget {
                    value -= abs(Double(kcal) * person.portion - Double(target) / 3) / 65
                }
            }
        }
        value -= Double(recipe.minutes) / 100
        return value
    }
    private func eligibleRecipes(for slot: MealSlot, limitingToCourses: Bool = true) -> [Recipe] {
        let people = participating(slot)
        let source = limitingToCourses ? activeCourseRecipeIDs : nil
        let excluded = Set(people.flatMap { person in
            state.avoidedRecipesBySlot?["\(slot.id)|\(person.id)"] ?? []
        })
        return allRecipes.filter { recipe in
            guard (source == nil || source?.contains(recipe.id) == true),
                  recipe.mealKinds.contains(slot.kind), !excluded.contains(recipe.id),
                  !people.contains(where: { state.dislikes?.contains("\($0.id)|\(recipe.id)") == true }) else { return false }
            if recipe.isPlanEligible { return incompatibility(slot, recipe: recipe) == nil }
            return limitingToCourses && source != nil && courseDraftIssue(recipe, for: slot) == nil
        }
    }
    private func rankedRecipes(_ recipes: [Recipe], slot: MealSlot, usedToday: Set<String>,
                               plannedSlots: [MealSlot]) -> [Recipe] {
        var ranked: [(recipe: Recipe, value: Double)] = []
        for recipe in recipes {
            let value = score(recipe, slot: slot, usedToday: usedToday, plannedSlots: plannedSlots)
            if value.isFinite { ranked.append((recipe, value)) }
        }
        ranked.sort { left, right in
            if left.value == right.value { return left.recipe.id < right.recipe.id }
            return left.value > right.value
        }
        return ranked.map(\.recipe)
    }
    private func makePreview(title: String, explanation: String, changes: [PlannedChange], pendingAvoid: AvoidedRecipe? = nil,
                             lateCorrectionSlotID: String? = nil,
                             outsideCourseSlotID: String? = nil,
                             lateCorrectionSlotIDs: Set<String> = [], reviewRecipeIDs: Set<String> = [],
                             emptyMessage: String = "Подходящей замены с меньшим числом недостающих продуктов не нашлось. Текущее меню остаётся, список покупок уже обновлён.") -> ReplanPreview {
        var proposedSlots = state.slots
        for change in changes {
            if let index = proposedSlots.firstIndex(where: { $0.id == change.slotID }) {
                proposedSlots[index].recipeID = change.nextID
            }
        }
        let before = Dictionary(uniqueKeysWithValues: shoppingNeeds.map { ($0.id, $0) })
        let afterNeeds = PlanningCore.resolvePlan(slots: proposedSlots, members: state.members, recipes: allRecipes,
                                                  pantry: pantry, startDate: state.startDate, now: now,
                                                  eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                                  schedule: mealSchedule).shoppingNeeds
        let after = Dictionary(uniqueKeysWithValues: afterNeeds.map { ($0.id, $0) })
        let delta = Set(before.keys).union(after.keys).sorted().compactMap { id -> String? in
            let oldAmount = before[id]?.missing ?? 0
            let newAmount = after[id]?.missing ?? 0
            let unknownChanged = (before[id]?.amountUnknown ?? false) != (after[id]?.amountUnknown ?? false)
            guard abs(newAmount - oldAmount) > 0.01 || unknownChanged else { return nil }
            let item = after[id] ?? before[id]!
            let old = oldAmount.formatted(.number.precision(.fractionLength(0...1)))
            let new = newAmount.formatted(.number.precision(.fractionLength(0...1)))
            return "\(L10n.text(item.name)): \(old) → \(new) \(L10n.text(item.unit))\(item.amountUnknown ? " · " + L10n.text("количество уточнить") : "")"
        }
        return ReplanPreview(title: title, explanation: explanation, changes: changes, shoppingDelta: delta,
                             pendingAvoid: pendingAvoid, emptyMessage: emptyMessage, expectedRevision: stateRevision,
                             expectedCatalogRevision: catalogRevision, lateCorrectionSlotID: lateCorrectionSlotID,
                             outsideCourseSlotID: outsideCourseSlotID, lateCorrectionSlotIDs: lateCorrectionSlotIDs,
                             reviewRecipeIDs: reviewRecipeIDs)
    }
    func proposeDayMenu(_ day: Int) {
        proposeMenu(days: [day], title: L10n.format("Подбор на %@", dateLabel(day)), preferDifferent: true)
    }
    func proposeWeekMenu() {
        proposeMenu(days: Array(currentDay..<7), title: L10n.text("Подбор недели"))
    }
    private func proposeMenu(days: [Int], title: String, preferDifferent: Bool = false) {
        guard hasSelectedCourses else {
            replanPreview = makePreview(title: title,
                                        explanation: L10n.text("Сначала выберите хотя бы один курс в каталоге. Пустой выбор не означает подбор из всех рецептов."),
                                        changes: [], emptyMessage: L10n.text("Курс не выбран. Меню не изменено."))
            return
        }
        var proposedSlots = state.slots
        var changes: [PlannedChange] = []
        var lateCorrectionIDs: Set<String> = []
        var reviewIDs: Set<String> = []
        var unmatched: [String] = []
        for day in days where (0..<7).contains(day) {
            var used: Set<String> = []
            for kind in 0..<3 {
                let slot = self.slot(day, kind)
                if (isPastWindow(slot) && day != currentDay) || isSkipped(slot) ||
                    state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                    used.insert(slot.recipeID)
                    continue
                }
                guard !slot.memberIDs.isEmpty else { continue }
                let ranked = rankedRecipes(eligibleRecipes(for: slot), slot: slot, usedToday: used,
                                           plannedSlots: proposedSlots)
                guard let choice = (preferDifferent ? ranked.first(where: { $0.id != slot.recipeID }) : nil) ?? ranked.first else {
                    if slot.recipeID != Recipe.unplanned.id {
                        unmatched.append("\(dateLabel(day)) · \(kinds[kind])")
                        changes.append(PlannedChange(slotID: slot.id, previousID: slot.recipeID,
                                                     nextID: Recipe.unplanned.id))
                        if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) {
                            proposedSlots[index].recipeID = Recipe.unplanned.id
                        }
                        if isPastWindow(slot) { lateCorrectionIDs.insert(slot.id) }
                    }
                    continue
                }
                used.insert(choice.id)
                if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) { proposedSlots[index].recipeID = choice.id }
                if choice.id != slot.recipeID {
                    changes.append(PlannedChange(slotID: slot.id, previousID: slot.recipeID, nextID: choice.id))
                    if isPastWindow(slot) { lateCorrectionIDs.insert(slot.id) }
                    if !choice.isPlanEligible { reviewIDs.insert(choice.id) }
                }
            }
        }
        var explanation = hasSelectedCourses
            ? L10n.text("Подбор использует только блюда выбранных курсов с подходящим тегом приёма пищи. Изменения появятся после подтверждения.")
            : L10n.text("Сопоставили продукты на всю неделю, даты готовки и ограничения участников. Если запасы не внесены, список покупок предварительный. Меню изменится только после подтверждения.")
        if !reviewIDs.isEmpty {
            explanation += " " + L10n.text("Часть блюд курса — черновики: количества, порции и калории оценены ИИ, а аллергены требуют проверки. Не считайте это подтверждённой программой снижения веса.")
        }
        if !lateCorrectionIDs.isEmpty {
            explanation += " " + L10n.text("Прошедшие сегодня, но не отмеченные съеденными приёмы меняются как план; факт еды не создаётся.")
        }
        if !unmatched.isEmpty {
            explanation += " " + L10n.format("Нет подходящего блюда с нужным тегом для: %@. После подтверждения эти приёмы останутся без блюда.", unmatched.joined(separator: ", "))
        }
        replanPreview = makePreview(title: title,
                                    explanation: explanation, changes: changes,
                                    lateCorrectionSlotIDs: lateCorrectionIDs, reviewRecipeIDs: reviewIDs,
                                    emptyMessage: hasSelectedCourses
                                        ? L10n.text("В выбранных курсах пока нет новых совместимых блюд с нужными тегами либо меню уже совпадает. Ничего не изменено.")
                                        : L10n.text("Подходящих изменений не нашлось. Меню остаётся прежним."))
    }
    func proposeNotToday(_ requestedSlot: MealSlot, includeOutsideCourses: Bool = false) {
        guard let slot = state.slots.first(where: { $0.id == requestedSlot.id }) else {
            replanPreview = makePreview(title: L10n.text("Другое блюдо"), explanation: L10n.text("Этот приём больше не найден в плане."), changes: [],
                                        emptyMessage: L10n.text("Откройте актуальный день и попробуйте снова."))
            return
        }
        guard hasSelectedCourses else {
            replanPreview = makePreview(title: L10n.text("Другое блюдо"),
                                        explanation: L10n.text("Сначала выберите курс в каталоге — пустой выбор не включает демо-блюда."),
                                        changes: [], emptyMessage: L10n.text("Курс не выбран. Блюдо не изменено."))
            return
        }
        guard !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else {
            replanPreview = makePreview(title: L10n.text("Другое блюдо"), explanation: L10n.text("Этот приём пищи уже отмечен съеденным."), changes: [],
                                        emptyMessage: L10n.text("Отмените отметку о съеденном, если хотите поменять блюдо."))
            return
        }
        guard !isSkipped(slot), !slot.memberIDs.isEmpty else {
            replanPreview = makePreview(title: L10n.text("Другое блюдо"), explanation: L10n.text("В этом приёме сейчас никто не участвует или он пропущен."), changes: [],
                                        emptyMessage: L10n.text("Верните приём в план и проверьте участников перед подбором."))
            return
        }
        guard !isPastWindow(slot) || slot.day == currentDay else {
            replanPreview = makePreview(title: L10n.text("Другое блюдо"), explanation: L10n.text("Этот день уже завершён."), changes: [],
                                        emptyMessage: L10n.text("Для прошедших дней сохраняйте факты отдельно; менять старый план нельзя."))
            return
        }
        let used = Set(state.slots.filter { $0.day == slot.day && $0.id != slot.id }.map(\.recipeID))
        let alternatives = eligibleRecipes(for: slot, limitingToCourses: !includeOutsideCourses).filter { $0.id != slot.recipeID }
        let choice = rankedRecipes(alternatives, slot: slot, usedToday: used, plannedSlots: state.slots).first
        let changes = choice.map { [PlannedChange(slotID: slot.id, previousID: slot.recipeID, nextID: $0.id)] } ?? []
        let selectedParticipates = slot.memberIDs.contains(state.selectedMemberID)
        let avoid = selectedParticipates ? choice.map { _ in AvoidedRecipe(slotID: slot.id, memberID: state.selectedMemberID, recipeID: slot.recipeID) } : nil
        let lateCorrection = isPastWindow(slot) ? slot.id : nil
        let normalExplanation = lateCorrection == nil
                                        ? (selectedParticipates
                                            ? L10n.format("Учтём, что %@ не хочет это блюдо в выбранный день. Замена учитывает продукты дома и ограничения всех за столом; предпочтение сохранится только для этого приёма пищи.", currentMember.name)
                                            : L10n.text("Выбранный человек не участвует в этом приёме. Подберём другое блюдо для участников, не записывая ему личный отказ."))
                                        : L10n.text("Обычное время прошло, но приём не отмечен съеденным. Можно явно заменить его сегодня; это не означает, что еда была съедена. Проверим продукты и ограничения всех участников.")
        let explanation = includeOutsideCourses && hasSelectedCourses
            ? L10n.text("Это предложение может быть вне выбранного курса. Оно не меняет сам курс и появится в меню только после подтверждения.") + " " + normalExplanation
            : normalExplanation
        let reviewIDs: Set<String> = choice.map { $0.isPlanEligible ? [] : [$0.id] } ?? []
        replanPreview = makePreview(title: L10n.format("Другое блюдо на %@", dateLabel(slot.day)),
                                    explanation: reviewIDs.isEmpty ? explanation : explanation + " " + L10n.text("Количества, порции и калории этого блюда оценочные; проверьте их и аллергены перед готовкой."),
                                    changes: changes, pendingAvoid: avoid, lateCorrectionSlotID: lateCorrection,
                                    outsideCourseSlotID: choice == nil && !includeOutsideCourses && hasSelectedCourses ? slot.id : nil,
                                    reviewRecipeIDs: reviewIDs,
                                    emptyMessage: includeOutsideCourses
                                        ? L10n.text("Подходящего проверенного блюда не нашлось и вне курса. Меню не меняется.")
                                        : (!hasSelectedCourses
                                            ? L10n.text("Пока нет другого совместимого блюда для этого приёма пищи. Меню не меняется.")
                                            : L10n.text("В выбранных курсах пока нет другого совместимого блюда с нужным тегом. Меню не меняется.")))
    }
    func proposeReplan(affectedBy ingredientName: String) {
        var changes: [PlannedChange] = []
        for slot in state.slots where slot.day >= currentDay {
            let original = recipe(slot)
            guard original.ingredients.contains(where: { ProductNames.canonical($0.name) == ProductNames.canonical(ingredientName) }) else { continue }
            if isPastWindow(slot) || state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) { continue }
            let originalMatch = planRequirements.slots[slot.id]
            let used = Set(state.slots.filter { $0.day == slot.day && $0.id != slot.id }.map(\.recipeID))
            let targetProduct = ProductNames.canonical(ingredientName)
            let alternatives = eligibleRecipes(for: slot).filter { candidate in
                candidate.id != original.id && !candidate.ingredients.contains { ProductNames.canonical($0.name) == targetProduct }
            }
            let candidates = rankedRecipes(alternatives, slot: slot, usedToday: used, plannedSlots: state.slots)
            if let choice = candidates.first(where: { candidate in
                var proposedSlots = state.slots
                if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) { proposedSlots[index].recipeID = candidate.id }
                let result = PlanningCore.resolvePlan(slots: proposedSlots, members: state.members, recipes: allRecipes,
                                                      pantry: pantry, startDate: state.startDate, now: now,
                                                      eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                                      schedule: mealSchedule).slots[slot.id]
                return (result?.shortageCount ?? .max) < (originalMatch?.shortageCount ?? .max)
            }) {
                changes.append(PlannedChange(slotID: slot.id, previousID: original.id, nextID: choice.id))
            }
        }
        replanPreview = makePreview(title: "\(ingredientName) закончился", explanation: "Запас обновлён, покупки пересчитаны. Ниже — только возможные изменения будущего меню. Уже отмеченные съеденными блюда не меняются.", changes: changes)
    }
    func applyReplan(_ preview: ReplanPreview) {
        guard preview.expectedRevision == stateRevision, preview.expectedCatalogRevision == catalogRevision else {
            replanPreview = makePreview(title: "План изменился", explanation: "Запасы, семья или каталог изменились после подбора.",
                                        changes: [], emptyMessage: "Обновите предложение, чтобы увидеть актуальный вариант.")
            return
        }
        var next = state
        for change in preview.changes {
            guard let index = next.slots.firstIndex(where: { $0.id == change.slotID && $0.recipeID == change.previousID }),
                  (!isPastWindow(next.slots[index]) ||
                   ((preview.lateCorrectionSlotID == change.slotID || preview.lateCorrectionSlotIDs.contains(change.slotID)) &&
                    next.slots[index].day == currentDay &&
                    !isSkipped(next.slots[index]))),
                  !state.eatenIDs.contains(where: { $0.hasPrefix("\(change.slotID)-") }),
                  let replacement = change.nextID == Recipe.unplanned.id ? Recipe.unplanned : allRecipes.first(where: { $0.id == change.nextID }),
                  (replacement.isUnplanned ||
                   (replacement.isPlanEligible
                    ? incompatibility(next.slots[index], recipe: replacement) == nil
                    : preview.reviewRecipeIDs.contains(replacement.id) &&
                      courseDraftIssue(replacement, for: next.slots[index]) == nil)) else {
                replanPreview = makePreview(title: "План изменился", explanation: "Предложение больше не подходит текущему плану.",
                                            changes: [], emptyMessage: "Подберите меню заново; ничего не было изменено.")
                return
            }
            next.slots[index].recipeID = change.nextID
        }
        guard !preview.changes.isEmpty else { replanPreview = nil; return }
        var appliedAvoid: AvoidedRecipe?
        if let avoid = preview.pendingAvoid {
            var all = next.avoidedRecipesBySlot ?? [:]
            if !all[avoid.key, default: []].contains(avoid.recipeID) {
                all[avoid.key, default: []].insert(avoid.recipeID)
                next.avoidedRecipesBySlot = all
                appliedAvoid = avoid
            }
        }
        state = next
        lastAppliedChanges = preview.changes
        lastAppliedAvoid = appliedAvoid
        undoRevision = stateRevision
        undoCatalogRevision = catalogRevision
        canUndoReplan = true
        replanPreview = nil
    }
    func undoReplan() {
        guard undoRevision == stateRevision, undoCatalogRevision == catalogRevision else {
            lastAppliedChanges = []
            lastAppliedAvoid = nil
            undoRevision = nil
            undoCatalogRevision = nil
            canUndoReplan = false
            return
        }
        var next = state
        for change in lastAppliedChanges {
            guard let index = next.slots.firstIndex(where: { $0.id == change.slotID && $0.recipeID == change.nextID }) else { return }
            next.slots[index].recipeID = change.previousID
        }
        if let avoid = lastAppliedAvoid {
            next.avoidedRecipesBySlot?[avoid.key]?.remove(avoid.recipeID)
        }
        state = next
        lastAppliedChanges = []
        lastAppliedAvoid = nil
        undoRevision = nil
        undoCatalogRevision = nil
        canUndoReplan = false
        replanPreview = nil
    }
    func assign(_ recipe: Recipe, to requestedSlot: MealSlot, allowUnverifiedCourseDraft: Bool = false) -> String? {
        guard let index = state.slots.firstIndex(where: { $0.id == requestedSlot.id }) else {
            return L10n.text("Приём больше не найден в плане.")
        }
        let slot = state.slots[index]
        guard hasSelectedCourses else { return L10n.text("Сначала выберите курс в каталоге.") }
        guard (!isPastWindow(slot) || slot.day == currentDay), !isSkipped(slot),
              !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else {
            return L10n.text("Нельзя заменить завершённый, пропущенный или отмеченный съеденным приём.")
        }
        if recipe.isUnavailable { return "Этот рецепт сейчас недоступен. Подключите закрытый каталог." }
        if hasSelectedCourses && !isSelectedCourseRecipe(recipe.id) {
            return L10n.text("Это блюдо вне выбранных курсов. Сначала измените выбор курса или используйте явное предложение вне курса.")
        }
        if recipe.isPlanEligible {
            if let issue = incompatibility(slot, recipe: recipe) { return issue }
        } else {
            guard allowUnverifiedCourseDraft else {
                return L10n.text("Этот рецепт требует проверки. Подтвердите выбор в карточке блюда.")
            }
            if let issue = courseDraftIssue(recipe, for: slot) { return issue }
        }
        state.slots[index].recipeID = recipe.id
        return nil
    }
    func incompatibility(_ slot: MealSlot, recipe: Recipe? = nil) -> String? {
        let recipe = recipe ?? self.recipe(slot)
        if recipe.isUnavailable { return "Рецепт недоступен до подключения закрытого каталога." }
        if !recipe.allergensVerified && participating(slot).contains(where: { !$0.allergies.isEmpty }) {
            return L10n.text("Сведения об аллергенах блюда не проверены. Для участника с ограничениями его нельзя назначить.")
        }
        let incompatible = participating(slot).filter { AllergenMatching.conflicts(selected: $0.allergies, recipe: recipe.allergens) }
        guard !incompatible.isEmpty else { return nil }
        return "Ограничение у \(incompatible.map(\.name).joined(separator: ", ")): \(recipe.allergens.joined(separator: ", ")). Выберите другое блюдо или измените участников."
    }
    func toggleParticipant(_ id: String, in slot: MealSlot) -> String? {
        guard let index = state.slots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        if recipe(slot).isUnavailable { return "Сначала подключите закрытый каталог: это блюдо сейчас недоступно." }
        if state.slots[index].memberIDs.contains(id) {
            guard !state.eatenIDs.contains("\(slot.id)-\(id)") else {
                return L10n.text("Приём уже отмечен съеденным. Сначала исправьте эту отметку.")
            }
            state.slots[index].memberIDs.removeAll { $0 == id }
        }
        else {
            let person = state.members.first { $0.id == id }
            if let person, !person.allergies.isEmpty, !recipe(slot).allergensVerified {
                return L10n.text("Сведения об аллергенах блюда не проверены. Для участника с ограничениями его нельзя назначить.")
            }
            if let person, AllergenMatching.conflicts(selected: person.allergies, recipe: recipe(slot).allergens) {
                return "Блюдо содержит \(recipe(slot).allergens.joined(separator: ", ")). Для \(person.name) выберите совместимый вариант."
            }
            state.slots[index].memberIDs.append(id)
        }
        return nil
    }
    func toggleFavorite(_ id: String) {
        let key = "\(state.selectedMemberID)|\(id)"
        if state.favorites.contains(key) { state.favorites.remove(key) }
        else {
            state.favorites.insert(key)
            state.dislikes?.remove(key)
        }
    }
    func isFavorite(_ id: String) -> Bool { state.favorites.contains("\(state.selectedMemberID)|\(id)") }
    func toggleDislike(_ id: String) {
        let key = "\(state.selectedMemberID)|\(id)"
        if state.dislikes?.contains(key) == true { state.dislikes?.remove(key) }
        else {
            state.dislikes = (state.dislikes ?? []).union([key])
            state.favorites.remove(key)
        }
    }
    func isDisliked(_ id: String) -> Bool { state.dislikes?.contains("\(state.selectedMemberID)|\(id)") == true }
    func updateMember(_ member: FamilyMember) {
        guard let index = state.members.firstIndex(where: { $0.id == member.id }) else { return }
        var checked = member
        if let age = checked.ageYears, age < 18 {
            checked.goal = "Без цели по весу"
            checked.dailyEnergyTarget = nil
        }
        state.members[index] = checked
    }
    func updateMealSchedule(_ schedule: MealSchedule) {
        guard schedule.isValid else { return }
        state.mealSchedule = schedule
    }
    func addMember(_ name: String) {
        let member = FamilyMember(id: UUID().uuidString, name: name, goal: "Без цели по весу", portion: 1.0, allergies: [])
        state.members.append(member)
    }
    func refreshFamily() async {
        let session = privateSessionRevision
        familyCloudStatus = L10n.text("Загружаем…")
        do {
            let remoteMembers = try await PrivateRecipeAccess.fetchFamily()
            guard session == privateSessionRevision, PrivateRecipeAccess.isConfigured else { return }
            let localMembers = Dictionary(uniqueKeysWithValues: state.members.map { ($0.id, $0) })
            let members = remoteMembers.map { remote in
                var merged = remote
                if let local = localMembers[remote.id] {
                    merged.goal = local.goal
                    merged.portion = local.portion
                    merged.allergies = local.allergies
                    merged.dailyEnergyTarget = local.dailyEnergyTarget
                    merged.heightCm = local.heightCm
                    merged.weightKg = local.weightKg
                    merged.measuredFatMassKg = local.measuredFatMassKg
                    merged.measuredMuscleMassKg = local.measuredMuscleMassKg
                }
                return merged
            }
            let wasDemo = Set(state.members.map(\.id)) == Set(["anna", "igor", "mila"])
            if wasDemo {
                for index in state.slots.indices {
                    state.slots[index].memberIDs = members.map(\.id)
                }
                state.selectedMemberID = members[0].id
                state.eatenIDs = []
                state.favorites = []
                state.dislikes = []
                state.avoidedRecipesBySlot = [:]
                state.supplementsByMember = [:]
                state.takenSupplements = []
                state.members = members
            } else {
                let remoteIDs = Set(members.map(\.id))
                let localOnly = state.members.filter { !remoteIDs.contains($0.id) && UUID(uuidString: $0.id) != nil }
                state.members = members + localOnly
            }
            let validIDs = Set(state.members.map(\.id))
            for index in state.slots.indices {
                state.slots[index].memberIDs.removeAll { !validIDs.contains($0) }
            }
            if !validIDs.contains(state.selectedMemberID) { state.selectedMemberID = members[0].id }
            familyCloudStatus = L10n.text("Имена и возраст обновлены с Hetzner · настройки остаются на этом iPhone")
        } catch {
            guard session == privateSessionRevision else { return }
            familyCloudStatus = L10n.format("Не удалось обновить: %@. Локальные данные сохранены.", error.localizedDescription)
        }
    }
    func refreshPrivateRecipes() async {
        let session = privateSessionRevision
        privateCatalogStatus = L10n.text("Загружаем…")
        do {
            let recipes = try await PrivateRecipeAccess.fetch()
            guard session == privateSessionRevision, PrivateRecipeAccess.isConfigured else { return }
            privateRecipes = recipes
            catalogRevision += 1
            privateCatalogStatus = L10n.format("Загружено закрытых рецептов: %d", privateRecipes.count)
        } catch {
            guard session == privateSessionRevision else { return }
            if case PrivateCatalogError.unauthorized = error {
                PrivateRecipeAccess.discardCached()
                privateRecipes = []
                catalogRevision += 1
            }
            privateCatalogStatus = privateRecipes.isEmpty
                ? error.localizedDescription
                : L10n.format("Нет связи: показаны %d сохранённых закрытых рецептов. %@",
                              privateRecipes.count, error.localizedDescription)
        }
    }
    func connectPrivateCatalog(url: String, token: String) async {
        do {
            try PrivateRecipeAccess.save(url: url, token: token)
            privateSessionRevision += 1
            privateRecipes = PrivateRecipeAccess.cached()
            catalogRevision += 1
            await refreshPrivateRecipes()
            await refreshFamily()
            await refreshCourseCatalog()
        } catch {
            privateCatalogStatus = error.localizedDescription
            familyCloudStatus = error.localizedDescription
        }
    }
    func disconnectPrivateCatalog() {
        privateSessionRevision += 1
        PrivateRecipeAccess.clear()
        privateRecipes = []
        catalogueRecipes = []
        courses = CourseCatalogAccess.bundledCourses
        catalogRevision += 1
        privateCatalogStatus = L10n.text("Не подключён")
        familyCloudStatus = L10n.text("Облако отключено · семья остаётся на этом iPhone")
        if CourseCatalogAccess.savedURL != nil { Task { await refreshCourseCatalog() } }
        else { courseCatalogStatus = L10n.text("Демо-каталог офлайн") }
    }
    func save() { if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "lad-demo-v3") } }
}
