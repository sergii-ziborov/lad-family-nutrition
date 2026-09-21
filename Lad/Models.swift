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

struct Recipe: Identifiable {
    let id: String
    let title: String
    let caption: String
    let image: String
    let cuisine: String
    let minutes: Int
    let kcal: Int
    let protein: Int
    let allergens: [String]
    let ingredients: [Ingredient]
    let steps: [String]
    var allergensVerified: Bool = false
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
        ], steps: ["Разогрейте духовку до 200 °C. Картофель нарежьте дольками и запекайте с маслом 20 минут.", "Добавьте рыбу и брокколи на противень. Запекайте ещё 12–15 минут до готовности рыбы.", "Смешайте йогурт с лимонным соком и зеленью. Подавайте соус отдельно — так каждый соберёт свою тарелку."]),
        Recipe(id: "pancakes", title: "Сырники с ягодами", caption: "Медленное и доброе утро", image: "Pancakes", cuisine: "Домашняя", minutes: 20, kcal: 340, protein: 22, allergens: ["Молоко", "Яйцо", "Пшеница"], ingredients: [
            .init(name: "Творог", amount: 150, unit: "г", category: "Молочные продукты"),
            .init(name: "Яйцо", amount: 0.5, unit: "шт.", category: "Молочные продукты"),
            .init(name: "Мука", amount: 20, unit: "г", category: "Бакалея"),
            .init(name: "Ягоды", amount: 70, unit: "г", category: "Овощи и зелень")
        ], steps: ["Разомните творог вилкой, добавьте яйцо и муку. Смешайте до однородности.", "Сформуйте небольшие сырники. Жарьте на умеренном огне по 3–4 минуты с каждой стороны.", "Подавайте с ягодами. Йогурт можно добавить по вкусу отдельно."]),
        Recipe(id: "soup", title: "Томатный суп с чечевицей", caption: "Согревает и остаётся на завтра", image: "Soup", cuisine: "Средиземноморская", minutes: 30, kcal: 390, protein: 18, allergens: [], ingredients: [
            .init(name: "Чечевица красная", amount: 80, unit: "г", category: "Бакалея"),
            .init(name: "Томаты", amount: 220, unit: "г", category: "Овощи и зелень"),
            .init(name: "Лук", amount: 65, unit: "г", category: "Овощи и зелень"),
            .init(name: "Морковь", amount: 70, unit: "г", category: "Овощи и зелень")
        ], steps: ["Мелко нарежьте лук и морковь. Обжарьте до мягкости.", "Добавьте томаты, промытую чечевицу и воду. Варите около 20 минут.", "Приправьте по вкусу. Для более нежной текстуры частично измельчите блендером."])
    ]
}

struct FamilyMember: Identifiable, Codable {
    var id: String
    var name: String
    var goal: String
    var portion: Double
    var allergies: [String]
    var ageYears: Int? = nil
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
                let recipeID = kind == 0 ? "pancakes" : (kind == 1 ? "soup" : "salmon")
                slots.append(MealSlot(id: "\(day)-\(kind)", day: day, kind: kind, recipeID: recipeID, memberIDs: family.map(\.id)))
            }
        }
        return DemoState(startDate: Calendar.current.startOfDay(for: .now), members: family, slots: slots, selectedMemberID: "anna", eatenIDs: [], boughtNames: [], pantryNames: [], favorites: ["anna|salmon"], extraShopping: [], supplementsByMember: [:], takenSupplements: [])
    }
}

@MainActor final class LadStore: ObservableObject {
    @Published var state: DemoState { didSet { save() } }
    @Published var selectedDay: Int = 0
    @Published private(set) var privateRecipes: [Recipe] = []
    @Published private(set) var privateCatalogStatus: String = "Не подключён"
    @Published private(set) var familyCloudStatus: String = "Не подключено"
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
