import Foundation
import SwiftUI

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

struct Ingredient: Identifiable, Codable {
    var name: String
    var amount: Double
    var unit: String
    var category: String
    var id: String { name }
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
    var isPrivate: Bool { id.hasPrefix("private:") }
    var isUnavailable: Bool { id == "unavailable" }

    static let unavailable = Recipe(id: "unavailable", title: "Закрытый рецепт недоступен", caption: "Подключите каталог, чтобы снова открыть это блюдо.", image: "", cuisine: "Закрытая библиотека", minutes: 0, kcal: 0, protein: 0, allergens: [], ingredients: [], steps: [])

    static let all: [Recipe] = [
        Recipe(id: "salmon", title: "Лосось с картофелем", caption: "Ужин, который собирает всех", image: "Salmon", cuisine: "Домашняя", minutes: 35, kcal: 520, protein: 38, allergens: ["Рыба", "Молоко"], ingredients: [
            .init(name: "Лосось", amount: 160, unit: "г", category: "Рыба и мясо"),
            .init(name: "Картофель", amount: 180, unit: "г", category: "Овощи и зелень"),
            .init(name: "Брокколи", amount: 120, unit: "г", category: "Овощи и зелень"),
            .init(name: "Йогурт натуральный", amount: 40, unit: "г", category: "Молочные продукты"),
            .init(name: "Лимон", amount: 0.25, unit: "шт.", category: "Овощи и зелень")
        ], steps: ["Разогрейте духовку до 200 °C. Картофель нарежьте дольками и запекайте с маслом 20 минут.", "Добавьте рыбу и брокколи на противень. Запекайте ещё 12–15 минут до готовности рыбы.", "Смешайте йогурт с лимонным соком и зеленью. Подавайте соус отдельно — так каждый соберёт свою тарелку."], mealKinds: [1, 2]),
        Recipe(id: "pancakes", title: "Сырники с ягодами", caption: "Медленное и доброе утро", image: "Pancakes", cuisine: "Домашняя", minutes: 20, kcal: 340, protein: 22, allergens: ["Молоко", "Яйцо", "Пшеница"], ingredients: [
            .init(name: "Творог", amount: 150, unit: "г", category: "Молочные продукты"),
            .init(name: "Яйцо", amount: 0.5, unit: "шт.", category: "Молочные продукты"),
            .init(name: "Мука", amount: 20, unit: "г", category: "Бакалея"),
            .init(name: "Ягоды", amount: 70, unit: "г", category: "Овощи и зелень")
        ], steps: ["Разомните творог вилкой, добавьте яйцо и муку. Смешайте до однородности.", "Сформуйте небольшие сырники. Жарьте на умеренном огне по 3–4 минуты с каждой стороны.", "Подавайте с ягодами. Йогурт можно добавить по вкусу отдельно."], mealKinds: [0]),
        Recipe(id: "soup", title: "Томатный суп с чечевицей", caption: "Согревает и остаётся на завтра", image: "Soup", cuisine: "Средиземноморская", minutes: 30, kcal: 390, protein: 18, allergens: [], ingredients: [
            .init(name: "Чечевица красная", amount: 80, unit: "г", category: "Бакалея"),
            .init(name: "Томаты", amount: 220, unit: "г", category: "Овощи и зелень"),
            .init(name: "Лук", amount: 65, unit: "г", category: "Овощи и зелень"),
            .init(name: "Морковь", amount: 70, unit: "г", category: "Овощи и зелень")
        ], steps: ["Мелко нарежьте лук и морковь. Обжарьте до мягкости.", "Добавьте томаты, промытую чечевицу и воду. Варите около 20 минут.", "Приправьте по вкусу. Для более нежной текстуры частично измельчите блендером."], mealKinds: [1, 2]),
        Recipe(id: "oats", title: "Овсянка с бананом", caption: "Тёплый завтрак без спешки", image: "Oats", cuisine: "Домашняя", minutes: 12, kcal: 310, protein: 11, allergens: ["Молоко"], ingredients: [
            .init(name: "Овсяные хлопья", amount: 60, unit: "г", category: "Бакалея"),
            .init(name: "Молоко", amount: 180, unit: "мл", category: "Молочные продукты"),
            .init(name: "Банан", amount: 1, unit: "шт.", category: "Овощи и зелень")
        ], steps: ["Нагрейте молоко и всыпьте овсяные хлопья.", "Варите на слабом огне 5–7 минут, помешивая.", "Добавьте нарезанный банан перед подачей."], mealKinds: [0]),
        Recipe(id: "eggs", title: "Яйца с томатами и тостом", caption: "Простой завтрак на сковороде", image: "Eggs", cuisine: "Домашняя", minutes: 15, kcal: 330, protein: 17, allergens: ["Яйцо", "Пшеница"], ingredients: [
            .init(name: "Яйцо", amount: 2, unit: "шт.", category: "Молочные продукты"),
            .init(name: "Томаты", amount: 120, unit: "г", category: "Овощи и зелень"),
            .init(name: "Хлеб", amount: 50, unit: "г", category: "Бакалея")
        ], steps: ["Нарежьте томаты и прогрейте их на сковороде.", "Добавьте яйца и готовьте до желаемой степени прожарки.", "Подавайте с подсушенным хлебом."], mealKinds: [0]),
        Recipe(id: "chicken-buckwheat", title: "Курица с гречкой и огурцом", caption: "Сытный обед из простых продуктов", image: "ChickenBuckwheat", cuisine: "Домашняя", minutes: 30, kcal: 480, protein: 36, allergens: [], ingredients: [
            .init(name: "Куриное филе", amount: 160, unit: "г", category: "Рыба и мясо"),
            .init(name: "Гречка", amount: 70, unit: "г", category: "Бакалея"),
            .init(name: "Огурец", amount: 120, unit: "г", category: "Овощи и зелень")
        ], steps: ["Промойте гречку и сварите до готовности.", "Нарежьте куриное филе и полностью прожарьте его.", "Подавайте с нарезанным огурцом."], mealKinds: [1, 2]),
        Recipe(id: "vegetable-pasta", title: "Паста с томатами и кабачком", caption: "Овощной обед для общего стола", image: "VegetablePasta", cuisine: "Средиземноморская", minutes: 25, kcal: 450, protein: 15, allergens: ["Пшеница", "Молоко"], ingredients: [
            .init(name: "Макароны", amount: 90, unit: "г", category: "Бакалея"),
            .init(name: "Томаты", amount: 160, unit: "г", category: "Овощи и зелень"),
            .init(name: "Кабачок", amount: 120, unit: "г", category: "Овощи и зелень"),
            .init(name: "Сыр", amount: 25, unit: "г", category: "Молочные продукты")
        ], steps: ["Сварите макароны согласно упаковке.", "Нарежьте и потушите томаты с кабачком.", "Соедините с пастой, посыпьте сыром."], mealKinds: [1, 2]),
        Recipe(id: "turkey-rice", title: "Индейка с рисом и овощами", caption: "Спокойный семейный ужин", image: "TurkeyRice", cuisine: "Домашняя", minutes: 30, kcal: 470, protein: 34, allergens: [], ingredients: [
            .init(name: "Филе индейки", amount: 160, unit: "г", category: "Рыба и мясо"),
            .init(name: "Рис", amount: 70, unit: "г", category: "Бакалея"),
            .init(name: "Морковь", amount: 90, unit: "г", category: "Овощи и зелень"),
            .init(name: "Кабачок", amount: 100, unit: "г", category: "Овощи и зелень")
        ], steps: ["Сварите рис до готовности.", "Нарежьте индейку и овощи.", "Полностью приготовьте индейку с овощами на сковороде и подавайте с рисом."], mealKinds: [1, 2]),
        Recipe(id: "lentil-stew", title: "Чечевица с овощами", caption: "Ужин из одной кастрюли", image: "LentilStew", cuisine: "Средиземноморская", minutes: 28, kcal: 400, protein: 19, allergens: [], ingredients: [
            .init(name: "Чечевица красная", amount: 85, unit: "г", category: "Бакалея"),
            .init(name: "Томаты", amount: 170, unit: "г", category: "Овощи и зелень"),
            .init(name: "Перец сладкий", amount: 110, unit: "г", category: "Овощи и зелень"),
            .init(name: "Лук", amount: 60, unit: "г", category: "Овощи и зелень")
        ], steps: ["Нарежьте лук и перец, прогрейте в кастрюле.", "Добавьте томаты, чечевицу и воду.", "Тушите около 20 минут до мягкости чечевицы."], mealKinds: [1, 2])
    ]
}

struct FamilyMember: Identifiable, Codable {
    var id: String
    var name: String
    var goal: String
    var portion: Double
    var allergies: [String]
    var ageYears: Int? = nil
    var dailyEnergyTarget: Int? = nil
    var initials: String { String(name.prefix(1)) }
    var ageLabel: String? {
        guard let ageYears else { return nil }
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
    var extraShopping: [String]
    var supplementsByMember: [String: [String]]
    var takenSupplements: Set<String>

    static func initial() -> DemoState {
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
        return DemoState(startDate: Calendar.current.startOfDay(for: .now), members: family, slots: slots, selectedMemberID: "anna", eatenIDs: [], boughtNames: [], pantryNames: [], favorites: ["anna|salmon"], extraShopping: [], supplementsByMember: [:], takenSupplements: [])
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
}

@MainActor final class LadStore: ObservableObject {
    @Published var state: DemoState { didSet { save() } }
    @Published var selectedDay: Int = 0
    @Published private(set) var privateRecipes: [Recipe] = []
    @Published private(set) var privateCatalogStatus: String = "Не подключён"
    @Published private(set) var familyCloudStatus: String = "Не подключено"
    @Published var replanPreview: ReplanPreview?
    @Published private(set) var canUndoReplan = false
    private var lastAppliedChanges: [PlannedChange] = []
    let localAccountID: String
    let kinds = ["Завтрак", "Обед", "Ужин"]

    init() {
        if let savedID = UserDefaults.standard.string(forKey: "lad.localAccountID") {
            localAccountID = savedID
        } else {
            let newID = UUID().uuidString
            localAccountID = newID
            UserDefaults.standard.set(newID, forKey: "lad.localAccountID")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshots") {
            state = .initial()
            return
        }
        #endif
        if let data = UserDefaults.standard.data(forKey: "lad-demo-v3"),
           let decoded = try? JSONDecoder().decode(DemoState.self, from: data) {
            let elapsed = Calendar.current.dateComponents([.day], from: decoded.startDate, to: .now).day ?? 0
            if elapsed > 6 || elapsed < 0 {
                var fresh = DemoState.initial()
                fresh.members = decoded.members
                fresh.selectedMemberID = decoded.selectedMemberID
                fresh.favorites = decoded.favorites
                fresh.pantryNames = decoded.pantryNames
                fresh.pantryItems = decoded.pantryItems
                fresh.extraShopping = decoded.extraShopping
                fresh.supplementsByMember = decoded.supplementsByMember
                for index in fresh.slots.indices {
                    fresh.slots[index].memberIDs = decoded.members.map(\.id)
                }
                state = fresh
            } else {
                state = decoded
                selectedDay = elapsed
            }
        } else {
            state = .initial()
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
        if oldPattern {
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
            Task {
                await refreshPrivateRecipes()
                await refreshFamily()
            }
        }
    }

    var currentMember: FamilyMember { state.members.first { $0.id == state.selectedMemberID } ?? state.members[0] }
    var allRecipes: [Recipe] { Recipe.all + privateRecipes }
    var pantry: [PantryItem] { state.pantryItems ?? [] }
    var shoppingNeeds: [ShoppingNeed] {
        PlanningCore.shoppingNeeds(slots: state.slots, members: state.members, recipes: allRecipes, pantry: pantry)
    }
    func readiness(_ recipe: Recipe, portions: Double = 1) -> RecipeReadiness {
        PlanningCore.readiness(recipe, portions: portions, pantry: pantry)
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
    func addPurchasedToPantry(_ need: ShoppingNeed) {
        var item = pantryItem(named: need.name, unit: need.unit) ?? PantryItem(name: need.name, quantity: 0, unit: need.unit, category: need.category)
        item.quantity = (item.quantity ?? 0) + need.missing
        savePantryItem(item)
        state.boughtNames.remove(need.name)
    }
    var privateCatalogURL: String { PrivateRecipeAccess.savedURL ?? "" }
    var currentDay: Int { min(6, max(0, Calendar.current.dateComponents([.day], from: state.startDate, to: .now).day ?? 0)) }
    var supplementStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
    var dayLabels: [String] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        return (0..<7).map { offset in
            fmt.dateFormat = "EE"
            return fmt.string(from: Calendar.current.date(byAdding: .day, value: offset, to: state.startDate)!).replacingOccurrences(of: ".", with: "").capitalized
        }
    }
    func dateLabel(_ offset: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "d MMMM"
        return fmt.string(from: Calendar.current.date(byAdding: .day, value: offset, to: state.startDate)!)
    }
    func dayNumber(_ offset: Int) -> String {
        String(Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: offset, to: state.startDate)!))
    }
    func slot(_ day: Int, _ kind: Int) -> MealSlot { state.slots.first { $0.day == day && $0.kind == kind }! }
    func recipe(_ slot: MealSlot) -> Recipe { allRecipes.first { $0.id == slot.recipeID } ?? Recipe.unavailable }
    func participating(_ slot: MealSlot) -> [FamilyMember] { state.members.filter { slot.memberIDs.contains($0.id) } }
    func toggleEaten(_ slot: MealSlot) {
        let key = "\(slot.id)-\(state.selectedMemberID)"
        if state.eatenIDs.contains(key) { state.eatenIDs.remove(key) } else { state.eatenIDs.insert(key) }
    }
    func isEaten(_ slot: MealSlot) -> Bool { state.eatenIDs.contains("\(slot.id)-\(state.selectedMemberID)") }
    private func score(_ recipe: Recipe, slot: MealSlot, usedToday: Set<String>) -> Double {
        let portions = participating(slot).reduce(0) { $0 + $1.portion }
        let match = readiness(recipe, portions: portions)
        var value = Double(match.covered * 7 - match.missing.count * 10 - match.uncertain.count * 3)
        if usedToday.contains(recipe.id) { value -= 25 }
        if state.slots.contains(where: { $0.day == slot.day - 1 && $0.recipeID == recipe.id }) { value -= 14 }
        if isFavorite(recipe.id) { value += 5 }
        if let target = currentMember.dailyEnergyTarget, let kcal = recipe.kcal, (currentMember.ageYears ?? 0) >= 18 {
            value -= abs(Double(kcal) * currentMember.portion - Double(target) / 3) / 65
        }
        value -= Double(recipe.minutes) / 100
        return value
    }
    private func eligibleRecipes(for slot: MealSlot) -> [Recipe] {
        allRecipes.filter { $0.mealKinds.contains(slot.kind) && incompatibility(slot, recipe: $0) == nil }
    }
    private func makePreview(title: String, explanation: String, changes: [PlannedChange]) -> ReplanPreview {
        var proposedSlots = state.slots
        for change in changes {
            if let index = proposedSlots.firstIndex(where: { $0.id == change.slotID }) {
                proposedSlots[index].recipeID = change.nextID
            }
        }
        let before = Dictionary(uniqueKeysWithValues: shoppingNeeds.map { ($0.id, $0) })
        let after = Dictionary(uniqueKeysWithValues: PlanningCore.shoppingNeeds(slots: proposedSlots, members: state.members, recipes: allRecipes, pantry: pantry).map { ($0.id, $0) })
        let delta = Set(before.keys).union(after.keys).sorted().compactMap { id -> String? in
            let oldAmount = before[id]?.missing ?? 0
            let newAmount = after[id]?.missing ?? 0
            guard abs(newAmount - oldAmount) > 0.01 else { return nil }
            let item = after[id] ?? before[id]!
            let old = oldAmount.formatted(.number.precision(.fractionLength(0...1)))
            let new = newAmount.formatted(.number.precision(.fractionLength(0...1)))
            return "\(item.name): \(old) → \(new) \(item.unit)"
        }
        return ReplanPreview(title: title, explanation: explanation, changes: changes, shoppingDelta: delta)
    }
    func proposeDayMenu(_ day: Int) {
        var used: Set<String> = []
        var changes: [PlannedChange] = []
        for kind in 0..<3 {
            let slot = self.slot(day, kind)
            if state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) { used.insert(slot.recipeID); continue }
            let candidates = eligibleRecipes(for: slot).sorted { score($0, slot: slot, usedToday: used) > score($1, slot: slot, usedToday: used) }
            guard let choice = candidates.first else { continue }
            used.insert(choice.id)
            if choice.id != slot.recipeID { changes.append(PlannedChange(slotID: slot.id, previousID: slot.recipeID, nextID: choice.id)) }
        }
        replanPreview = makePreview(title: "Подбор на \(dateLabel(day))", explanation: "Учитываем запасы, известные аллергены, разнообразие и ваш ручной ориентир по калориям, если он задан. Пищевая ценность демо-блюд приблизительная; микроэлементы без исходных данных не рассчитываются.", changes: changes)
    }
    func proposeReplan(affectedBy ingredientName: String) {
        var changes: [PlannedChange] = []
        for slot in state.slots where slot.day >= currentDay {
            let original = recipe(slot)
            guard original.ingredients.contains(where: { $0.name.localizedCaseInsensitiveCompare(ingredientName) == .orderedSame }) else { continue }
            if state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) { continue }
            let originalMatch = readiness(original, portions: participating(slot).reduce(0) { $0 + $1.portion })
            let used = Set(state.slots.filter { $0.day == slot.day && $0.id != slot.id }.map(\.recipeID))
            let candidates = eligibleRecipes(for: slot).filter { candidate in
                candidate.id != original.id && !candidate.ingredients.contains { $0.name.localizedCaseInsensitiveCompare(ingredientName) == .orderedSame }
            }.sorted { score($0, slot: slot, usedToday: used) > score($1, slot: slot, usedToday: used) }
            if let choice = candidates.first {
                let candidateMatch = readiness(choice, portions: participating(slot).reduce(0) { $0 + $1.portion })
                if candidateMatch.missing.count + candidateMatch.uncertain.count < originalMatch.missing.count + originalMatch.uncertain.count {
                    changes.append(PlannedChange(slotID: slot.id, previousID: original.id, nextID: choice.id))
                }
            }
        }
        replanPreview = makePreview(title: "\(ingredientName) закончился", explanation: "Запас обновлён, покупки пересчитаны. Ниже — только возможные изменения будущего меню. Уже отмеченные съеденными блюда не меняются.", changes: changes)
    }
    func applyReplan(_ preview: ReplanPreview) {
        for change in preview.changes {
            if let index = state.slots.firstIndex(where: { $0.id == change.slotID && $0.recipeID == change.previousID }) {
                state.slots[index].recipeID = change.nextID
            }
        }
        lastAppliedChanges = preview.changes
        canUndoReplan = !preview.changes.isEmpty
        replanPreview = nil
    }
    func undoReplan() {
        for change in lastAppliedChanges {
            if let index = state.slots.firstIndex(where: { $0.id == change.slotID && $0.recipeID == change.nextID }) {
                state.slots[index].recipeID = change.previousID
            }
        }
        lastAppliedChanges = []
        canUndoReplan = false
    }
    func assign(_ recipe: Recipe, to slot: MealSlot) -> String? {
        if recipe.isUnavailable { return "Этот рецепт сейчас недоступен. Подключите закрытый каталог." }
        if recipe.isPrivate && !recipe.allergensVerified { return "Для этого закрытого рецепта ещё не проверены сведения об аллергенах. Его нельзя добавить в семейное меню." }
        let incompatible = participating(slot).filter { !Set($0.allergies).isDisjoint(with: recipe.allergens) }
        if !incompatible.isEmpty { return "У \(incompatible.map(\.name).joined(separator: ", ")) указано ограничение: \(recipe.allergens.joined(separator: ", ")). Для общей готовки выберите другое блюдо или измените участников." }
        guard let index = state.slots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        state.slots[index].recipeID = recipe.id
        return nil
    }
    func incompatibility(_ slot: MealSlot, recipe: Recipe? = nil) -> String? {
        let recipe = recipe ?? self.recipe(slot)
        if recipe.isUnavailable { return "Рецепт недоступен до подключения закрытого каталога." }
        if recipe.isPrivate && !recipe.allergensVerified { return "Сведения об аллергенах закрытого рецепта не проверены." }
        let incompatible = participating(slot).filter { !Set($0.allergies).isDisjoint(with: recipe.allergens) }
        guard !incompatible.isEmpty else { return nil }
        return "Ограничение у \(incompatible.map(\.name).joined(separator: ", ")): \(recipe.allergens.joined(separator: ", ")). Выберите другое блюдо или измените участников."
    }
    func toggleParticipant(_ id: String, in slot: MealSlot) -> String? {
        guard let index = state.slots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        if recipe(slot).isUnavailable { return "Сначала подключите закрытый каталог: это блюдо сейчас недоступно." }
        if state.slots[index].memberIDs.contains(id) { state.slots[index].memberIDs.removeAll { $0 == id } }
        else {
            let person = state.members.first { $0.id == id }
            if let person, !Set(person.allergies).isDisjoint(with: recipe(slot).allergens) {
                return "Блюдо содержит \(recipe(slot).allergens.joined(separator: ", ")). Для \(person.name) выберите совместимый вариант."
            }
            state.slots[index].memberIDs.append(id)
        }
        return nil
    }
    func toggleFavorite(_ id: String) {
        let key = "\(state.selectedMemberID)|\(id)"
        if state.favorites.contains(key) { state.favorites.remove(key) } else { state.favorites.insert(key) }
    }
    func isFavorite(_ id: String) -> Bool { state.favorites.contains("\(state.selectedMemberID)|\(id)") }
    func updateMember(_ member: FamilyMember) {
        guard let index = state.members.firstIndex(where: { $0.id == member.id }) else { return }
        state.members[index] = member
    }
    func addMember(_ name: String) {
        let member = FamilyMember(id: UUID().uuidString, name: name, goal: "Без цели по весу", portion: 1.0, allergies: [])
        state.members.append(member)
    }
    func refreshFamily() async {
        familyCloudStatus = "Загружаем…"
        do {
            let remoteMembers = try await PrivateRecipeAccess.fetchFamily()
            let localMembers = Dictionary(uniqueKeysWithValues: state.members.map { ($0.id, $0) })
            let members = remoteMembers.map { remote in
                var merged = remote
                if let local = localMembers[remote.id] {
                    merged.goal = local.goal
                    merged.portion = local.portion
                    merged.allergies = local.allergies
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
                if state.slots[index].memberIDs.isEmpty {
                    state.slots[index].memberIDs = members.map(\.id)
                }
            }
            if !validIDs.contains(state.selectedMemberID) { state.selectedMemberID = members[0].id }
            familyCloudStatus = "Имена и возраст обновлены с Hetzner · настройки остаются на этом iPhone"
        } catch {
            familyCloudStatus = "Не удалось обновить: \(error.localizedDescription). Локальные данные сохранены."
        }
    }
    func refreshPrivateRecipes() async {
        privateCatalogStatus = "Загружаем…"
        do {
            privateRecipes = try await PrivateRecipeAccess.fetch()
            privateCatalogStatus = "Загружено закрытых рецептов: \(privateRecipes.count)"
        } catch {
            privateRecipes = []
            privateCatalogStatus = error.localizedDescription
        }
    }
    func connectPrivateCatalog(url: String, token: String) async {
        do {
            try PrivateRecipeAccess.save(url: url, token: token)
            await refreshPrivateRecipes()
            await refreshFamily()
        } catch {
            privateCatalogStatus = error.localizedDescription
            familyCloudStatus = error.localizedDescription
        }
    }
    func disconnectPrivateCatalog() {
        PrivateRecipeAccess.clear()
        privateRecipes = []
        privateCatalogStatus = "Не подключён"
        familyCloudStatus = "Облако отключено · семья остаётся на этом iPhone"
    }
    func save() { if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "lad-demo-v3") } }
}
