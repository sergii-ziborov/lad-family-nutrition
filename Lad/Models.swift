import Foundation
import SwiftUI

enum L10n {
    static func text(_ source: String) -> String {
        NSLocalizedString(source, tableName: "Localizable", bundle: .main, value: source, comment: "")
    }
    static func format(_ source: String, _ arguments: CVarArg...) -> String {
        String(format: text(source), locale: .current, arguments: arguments)
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

struct Ingredient: Identifiable, Codable {
    var name: String
    var amount: Double?
    var unit: String
    var category: String
    var alternatives: [String]? = nil
    var amountMax: Double? = nil
    var id: String { "\(name)|\(unit)" }
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
    var isPrivate: Bool { id.hasPrefix("private:") }
    var isUnavailable: Bool { id == "unavailable" }
    var isPlanEligible: Bool {
        !isUnavailable && !ingredients.isEmpty && ingredients.allSatisfy { ($0.amount ?? 0) > 0 } &&
        (!isPrivate || allergensVerified)
    }

    static let unavailable = Recipe(id: "unavailable", title: "Закрытый рецепт недоступен", caption: "Подключите каталог, чтобы снова открыть это блюдо.", image: "", cuisine: "Закрытая библиотека", minutes: 0, kcal: nil, protein: nil, allergens: [], ingredients: [], steps: [])

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
    var initials: String { String(name.prefix(1)) }
    var ageLabel: String? {
        guard let ageYears else { return nil }
        if Locale.current.language.languageCode?.identifier == "en" { return "\(ageYears) years" }
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

    static func nextWeek(after previous: DemoState, now: Date) -> DemoState {
        var fresh = DemoState.initial()
        fresh.startDate = Calendar.current.startOfDay(for: now)
        fresh.members = previous.members
        fresh.selectedMemberID = previous.selectedMemberID
        fresh.favorites = previous.favorites
        fresh.dislikes = previous.dislikes
        fresh.activeCourseIDs = previous.activeCourseIDs
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
    private var activeCourseRecipeIDs: Set<String>? {
        guard !activeCourseIDs.isEmpty else { return nil }
        let existing = Set(allRecipes.map(\.id))
        return Set(courses.filter { activeCourseIDs.contains($0.id) }.flatMap(\.recipeIDs).map { id in
            existing.contains(id) ? id : "private:\(id)"
        })
    }
    func toggleCourse(_ id: String) {
        guard courses.contains(where: { $0.id == id }) else { return }
        var next = state.activeCourseIDs ?? []
        if !next.insert(id).inserted { next.remove(id) }
        state.activeCourseIDs = next
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
        PlanningCore.resolvePlan(slots: state.slots, members: state.members, recipes: allRecipes,
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
        availabilityTitle(requirements(for: slot), inventoryEmpty: planRequirements.inventoryEmpty)
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
        fmt.locale = .current
        return (0..<7).map { offset in
            fmt.dateFormat = "EE"
            return fmt.string(from: Calendar.current.date(byAdding: .day, value: offset, to: state.startDate)!).replacingOccurrences(of: ".", with: "").capitalized
        }
    }
    func dateLabel(_ offset: Int) -> String {
        let fmt = DateFormatter()
        fmt.locale = .current
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
        guard slot.memberIDs.contains(state.selectedMemberID) else { return }
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
        guard isPastWindow(slot), !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else { return }
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
              match.availability == .active || (slot.day == currentDay && match.availability == .past) else { return -.infinity }
        var value = match.isReady ? (slot.day == currentDay ? 1_000.0 : 80.0) : 0
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
            (source == nil || source?.contains(recipe.id) == true) &&
            recipe.isPlanEligible && recipe.mealKinds.contains(slot.kind) && incompatibility(slot, recipe: recipe) == nil &&
            !excluded.contains(recipe.id) &&
            !people.contains { state.dislikes?.contains("\($0.id)|\(recipe.id)") == true }
        }
    }
    private func rankedRecipes(_ recipes: [Recipe], slot: MealSlot, usedToday: Set<String>,
                               plannedSlots: [MealSlot]) -> [Recipe] {
        var ranked: [(recipe: Recipe, value: Double)] = []
        for recipe in recipes {
            ranked.append((recipe, score(recipe, slot: slot, usedToday: usedToday, plannedSlots: plannedSlots)))
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
            return "\(item.name): \(old) → \(new) \(item.unit)\(item.amountUnknown ? " · количество уточнить" : "")"
        }
        return ReplanPreview(title: title, explanation: explanation, changes: changes, shoppingDelta: delta,
                             pendingAvoid: pendingAvoid, emptyMessage: emptyMessage, expectedRevision: stateRevision,
                             expectedCatalogRevision: catalogRevision, lateCorrectionSlotID: lateCorrectionSlotID,
                             outsideCourseSlotID: outsideCourseSlotID)
    }
    func proposeDayMenu(_ day: Int) {
        proposeMenu(days: [day], title: "Подбор на \(dateLabel(day))")
    }
    func proposeWeekMenu() {
        proposeMenu(days: Array(currentDay..<7), title: "Подбор недели")
    }
    private func proposeMenu(days: [Int], title: String) {
        var proposedSlots = state.slots
        var changes: [PlannedChange] = []
        for day in days where (0..<7).contains(day) {
            var used: Set<String> = []
            for kind in 0..<3 {
                let slot = self.slot(day, kind)
                if isPastWindow(slot) || state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                    used.insert(slot.recipeID)
                    continue
                }
                guard !slot.memberIDs.isEmpty else { continue }
                let ranked = rankedRecipes(eligibleRecipes(for: slot), slot: slot, usedToday: used,
                                           plannedSlots: proposedSlots)
                guard let choice = ranked.first else { continue }
                used.insert(choice.id)
                if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) { proposedSlots[index].recipeID = choice.id }
                if choice.id != slot.recipeID {
                    changes.append(PlannedChange(slotID: slot.id, previousID: slot.recipeID, nextID: choice.id))
                }
            }
        }
        replanPreview = makePreview(title: title,
                                    explanation: "Сопоставили продукты на всю неделю, даты готовки и ограничения участников. Если запасы не внесены, список покупок предварительный. Меню изменится только после подтверждения.",
                                    changes: changes)
    }
    func proposeNotToday(_ requestedSlot: MealSlot, includeOutsideCourses: Bool = false) {
        guard let slot = state.slots.first(where: { $0.id == requestedSlot.id }) else {
            replanPreview = makePreview(title: L10n.text("Другое блюдо"), explanation: L10n.text("Этот приём больше не найден в плане."), changes: [],
                                        emptyMessage: L10n.text("Откройте актуальный день и попробуйте снова."))
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
        let explanation = includeOutsideCourses && activeCourseRecipeIDs != nil
            ? L10n.text("Это предложение может быть вне выбранного курса. Оно не меняет сам курс и появится в меню только после подтверждения.") + " " + normalExplanation
            : normalExplanation
        replanPreview = makePreview(title: L10n.format("Другое блюдо на %@", dateLabel(slot.day)),
                                    explanation: explanation,
                                    changes: changes, pendingAvoid: avoid, lateCorrectionSlotID: lateCorrection,
                                    outsideCourseSlotID: choice == nil && !includeOutsideCourses && activeCourseRecipeIDs != nil ? slot.id : nil,
                                    emptyMessage: includeOutsideCourses
                                        ? L10n.text("Подходящего проверенного блюда не нашлось и вне курса. Меню не меняется.")
                                        : (activeCourseRecipeIDs == nil
                                            ? L10n.text("Пока нет другого совместимого блюда для этого приёма пищи. Меню не меняется.")
                                            : L10n.text("В выбранных курсах пока нет другого проверенного блюда для этого приёма. Меню не меняется; черновики с неизвестными количествами не подставляются автоматически.")))
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
                   (preview.lateCorrectionSlotID == change.slotID && next.slots[index].day == currentDay &&
                    !isSkipped(next.slots[index]))),
                  !state.eatenIDs.contains(where: { $0.hasPrefix("\(change.slotID)-") }),
                  let replacement = allRecipes.first(where: { $0.id == change.nextID }),
                  replacement.isPlanEligible,
                  incompatibility(next.slots[index], recipe: replacement) == nil else {
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
    func assign(_ recipe: Recipe, to slot: MealSlot) -> String? {
        guard !isPastWindow(slot), !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else {
            return "Нельзя заменить прошедшее или отмеченное съеденным блюдо."
        }
        if recipe.isUnavailable { return "Этот рецепт сейчас недоступен. Подключите закрытый каталог." }
        if recipe.isPrivate && !recipe.allergensVerified { return "Для этого закрытого рецепта ещё не проверены сведения об аллергенах. Его нельзя добавить в семейное меню." }
        if !recipe.isPlanEligible { return "Для семейного плана нужно уточнить количество каждого ингредиента." }
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
        if state.slots[index].memberIDs.contains(id) {
            guard !state.eatenIDs.contains("\(slot.id)-\(id)") else {
                return L10n.text("Приём уже отмечен съеденным. Сначала исправьте эту отметку.")
            }
            state.slots[index].memberIDs.removeAll { $0 == id }
        }
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
