import Foundation

struct ShoppingNeed: Identifiable {
    let id: String
    let name: String
    let unit: String
    let category: String
    let required: Double
    let available: Double
    let amountUnknown: Bool
    let sourceSlots: [String]

    var missing: Double { max(0, required - available) }
}

struct RecipeReadiness {
    let covered: Int
    let total: Int
    let missing: [String]
    let uncertain: [String]
}

enum SlotAvailability: Equatable {
    case active
    case past
    case eaten
    case noParticipants
    case unavailable
    case needsReview
    case skipped
}

struct ResolvedIngredient: Identifiable {
    let id: String
    let name: String
    let unit: String
    let category: String
    let required: Double?
    let allocated: Double
    let uncertain: Bool

    var shortage: Double? { required.map { max(0, $0 - allocated) } }
    var isReady: Bool { required != nil && (shortage ?? 0) < 0.001 && !uncertain }
}

struct SlotRequirements {
    let slotID: String
    let recipeID: String
    let availability: SlotAvailability
    let ingredients: [ResolvedIngredient]

    var isReady: Bool { availability == .active && ingredients.allSatisfy(\.isReady) }
    var hasUncertainty: Bool { ingredients.contains { $0.required == nil || $0.uncertain } }
    var shortageCount: Int { ingredients.filter { ($0.shortage ?? 0) > 0.001 }.count }
    var missingNames: [String] { ingredients.filter { ($0.shortage ?? 0) > 0.001 || $0.required == nil }.map(\.name) }
}

struct PlanRequirements {
    let slots: [String: SlotRequirements]
    let shoppingNeeds: [ShoppingNeed]
    let inventoryEmpty: Bool
    let freePantry: [PantryItem]
}

struct MealSchedule: Codable, Equatable {
    var breakfastEnds: Int = 11 * 60
    var lunchEnds: Int = 16 * 60
    var dinnerEnds: Int = 22 * 60

    static let standard = MealSchedule()

    func endMinute(for kind: Int) -> Int {
        switch kind {
        case 0: breakfastEnds
        case 1: lunchEnds
        default: dinnerEnds
        }
    }

    var isValid: Bool {
        (0..<24 * 60).contains(breakfastEnds) && breakfastEnds < lunchEnds &&
        lunchEnds < dinnerEnds && dinnerEnds <= 24 * 60
    }
}

enum MealTiming {
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func suggestedKind(on day: Int, currentDay: Int, now: Date, schedule: MealSchedule,
                              calendar: Calendar = .current, eatenKinds: Set<Int> = []) -> Int? {
        guard day >= currentDay else { return nil }
        if day > currentDay { return (0..<3).first { !eatenKinds.contains($0) } }
        let minute = minuteOfDay(now, calendar: calendar)
        return (0..<3).first { !eatenKinds.contains($0) && minute < schedule.endMinute(for: $0) }
    }

    static func isPastWindow(day: Int, kind: Int, currentDay: Int, now: Date,
                             schedule: MealSchedule, calendar: Calendar = .current) -> Bool {
        day < currentDay || (day == currentDay && minuteOfDay(now, calendar: calendar) >= schedule.endMinute(for: kind))
    }
}

enum ProductNames {
    // Only interchangeable product names belong here. Related but different foods
    // (for example mushrooms and champignons, or lemon and lemon juice) stay separate.
    private static let equivalents: [[String]] = [
        ["томат", "томаты", "помидор", "помидоры", "tomato", "tomatoes"],
        ["кабачок", "кабачки", "цуккини", "zucchini", "courgette"],
        ["картофель", "картошка", "картофелина", "картофелины", "potato", "potatoes"],
        ["морковь", "морковка", "морковки", "carrot", "carrots"],
        ["огурец", "огурцы", "cucumber", "cucumbers"],
        ["яблоко", "яблоки", "apple", "apples"],
        ["яйцо", "яйца", "egg", "eggs"],
        ["лук", "лук репчатый", "репчатый лук", "onion", "onions"],
        ["зеленый лук", "лук зеленый", "spring onion", "green onion"],
        ["перец сладкий", "сладкий перец", "болгарский перец"],
        ["сушеный чеснок", "сухой чеснок", "чеснок сушеный", "чеснок сухой"],
        ["капуста белокочанная", "белокочанная капуста"],
        ["капуста цветная", "цветная капуста"],
        ["йогурт натуральный", "натуральный йогурт"],
        ["куриное филе", "филе курицы"],
        ["гречка", "гречневая крупа", "buckwheat"]
    ].map { group in group.map { normalized($0) } }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func canonical(_ name: String) -> String {
        let value = normalized(name)
        if let known = equivalents.first(where: { $0.contains(value) })?.first { return known }
        return value.split(separator: " ").map { word in
            let token = String(word)
            return equivalents.first { $0.contains(token) }?.first ?? token
        }.joined(separator: " ")
    }

    static func matches(_ name: String, query: String) -> Bool {
        let label = normalized(name)
        let term = normalized(query)
        guard !term.isEmpty else { return true }
        if label.contains(term) { return true }
        let canonicalLabel = canonical(name)
        let canonicalTerm = canonical(query)
        if canonicalLabel == canonicalTerm || canonicalLabel.hasPrefix(canonicalTerm + " ") { return true }
        guard term.count >= 3 else { return false }
        return equivalents.contains { group in
            group.contains(where: { $0.contains(term) }) &&
            (group.contains(label) || label.split(separator: " ").contains { group.contains(String($0)) })
        }
    }
}

enum PlanningCore {
    static func key(_ name: String, _ unit: String) -> String {
        ProductNames.canonical(name) + "|" + ProductNames.normalized(unit)
    }

    static func ingredientSuggestions(recipes: [Recipe], pantry: [PantryItem], query: String) -> [Ingredient] {
        let stocked = Set(pantry.map { key($0.name, $0.unit) })
        var unique: [String: Ingredient] = [:]
        for ingredient in recipes.flatMap(\.ingredients) {
            let id = key(ingredient.name, ingredient.unit)
            if !stocked.contains(id) && ProductNames.matches(ingredient.name, query: query) && unique[id] == nil {
                unique[id] = ingredient
            }
        }
        return unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func stock(for ingredient: Ingredient, pantry: [PantryItem], now: Date = .now) -> (known: Double, uncertain: Bool) {
        let active = pantry.filter {
            ProductNames.canonical($0.name) == ProductNames.canonical(ingredient.name) &&
            ($0.expiresOn.map { Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: now) } ?? true)
        }
        let matching = active.filter { key($0.name, $0.unit) == key(ingredient.name, ingredient.unit) }
        let incomparable = active.contains {
            key($0.name, $0.unit) != key(ingredient.name, ingredient.unit) && ($0.quantity ?? 1) > 0
        }
        return (matching.compactMap(\.quantity).reduce(0, +), matching.contains { $0.quantity == nil } || incomparable)
    }

    static func readiness(_ recipe: Recipe, portions: Double, pantry: [PantryItem], now: Date = .now) -> RecipeReadiness {
        var covered = 0
        var missing: [String] = []
        var uncertain: [String] = []
        for ingredient in recipe.ingredients {
            guard let amount = ingredient.amount, amount > 0 else {
                uncertain.append(ingredient.name)
                continue
            }
            let stock = stock(for: ingredient, pantry: pantry, now: now)
            let required = amount * portions / max(1, recipe.baseServings)
            if stock.known >= required {
                covered += 1
            } else if stock.uncertain {
                uncertain.append(ingredient.name)
            } else {
                missing.append(ingredient.name)
            }
        }
        return RecipeReadiness(covered: covered, total: recipe.ingredients.count, missing: missing, uncertain: uncertain)
    }

    static func resolvePlan(slots: [MealSlot], members: [FamilyMember], recipes: [Recipe], pantry: [PantryItem],
                            startDate: Date, now: Date = .now, calendar: Calendar = .current,
                            eatenIDs: Set<String> = [], skippedIDs: Set<String> = [],
                            schedule: MealSchedule = .standard) -> PlanRequirements {
        struct Aggregate {
            var ingredient: Ingredient
            var required: Double
            var allocated: Double
            var uncertain: Bool
            var sourceSlots: [String]
        }
        struct Lot {
            let key: String
            let product: String
            let name: String
            let unit: String
            let category: String
            let expiresOn: Date?
            var remaining: Double?
        }
        let membersByID = members.reduce(into: [String: FamilyMember]()) { result, member in
            if result[member.id] == nil { result[member.id] = member }
        }
        let recipesByID = recipes.reduce(into: [String: Recipe]()) { result, recipe in
            if result[recipe.id] == nil { result[recipe.id] = recipe }
        }
        var lots = pantry.map { item in
            Lot(key: key(item.name, item.unit), product: ProductNames.canonical(item.name),
                name: item.name, unit: item.unit, category: item.category,
                expiresOn: item.expiresOn, remaining: item.quantity.map { max(0, $0) })
        }.sorted { left, right in
            switch (left.expiresOn, right.expiresOn) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.key < right.key
            }
        }
        var totals: [String: Aggregate] = [:]
        var resolvedSlots: [String: SlotRequirements] = [:]
        let firstDay = calendar.startOfDay(for: startDate)
        let currentDay = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: now)).day ?? 0
        for slot in slots.sorted(by: { ($0.day, $0.kind, $0.id) < ($1.day, $1.kind, $1.id) }) {
            let participants = slot.memberIDs.compactMap { membersByID[$0] }
            let status: SlotAvailability
            if skippedIDs.contains(slot.id) { status = .skipped }
            else if participants.isEmpty { status = .noParticipants }
            else if participants.allSatisfy({ eatenIDs.contains("\(slot.id)-\($0.id)") }) { status = .eaten }
            else if recipesByID[slot.recipeID] == nil || recipesByID[slot.recipeID]?.isUnavailable == true { status = .unavailable }
            else if recipesByID[slot.recipeID]?.isPlanEligible == false { status = .needsReview }
            else if MealTiming.isPastWindow(day: slot.day, kind: slot.kind, currentDay: currentDay,
                                            now: now, schedule: schedule, calendar: calendar) { status = .past }
            else { status = .active }
            guard status == .active || status == .needsReview || status == .past,
                  let recipe = recipesByID[slot.recipeID] else {
                resolvedSlots[slot.id] = SlotRequirements(slotID: slot.id, recipeID: slot.recipeID, availability: status, ingredients: [])
                continue
            }
            let portions = participants.filter { !eatenIDs.contains("\(slot.id)-\($0.id)") }
                .map(\.portion).reduce(0, +)
            let useDate = calendar.date(byAdding: .day, value: slot.day, to: firstDay) ?? firstDay
            var grouped: [String: (ingredient: Ingredient, amount: Double, unresolved: Bool)] = [:]
            for ingredient in recipe.ingredients {
                let id = key(ingredient.name, ingredient.unit)
                var entry = grouped[id] ?? (ingredient, 0, false)
                if let amount = ingredient.amount, amount > 0 {
                    entry.amount += amount * portions / max(1, recipe.baseServings)
                }
                else { entry.unresolved = true }
                if ingredient.aiEstimated == true { entry.unresolved = true }
                grouped[id] = entry
            }
            var lines: [ResolvedIngredient] = []
            for id in grouped.keys.sorted() {
                guard let group = grouped[id] else { continue }
                var toAllocate = group.amount
                var allocated = 0.0
                for index in lots.indices where toAllocate > 0.001 && lots[index].key == id {
                    if let expiry = lots[index].expiresOn,
                       calendar.startOfDay(for: expiry) < calendar.startOfDay(for: useDate) { continue }
                    let taken = min(toAllocate, lots[index].remaining ?? 0)
                    lots[index].remaining = (lots[index].remaining ?? 0) - taken
                    allocated += taken
                    toAllocate -= taken
                }
                let uncertainStock = lots.contains { lot in
                    guard lot.product == ProductNames.canonical(group.ingredient.name) else { return false }
                    if let expiry = lot.expiresOn,
                       calendar.startOfDay(for: expiry) < calendar.startOfDay(for: useDate) { return false }
                    return lot.remaining == nil || (lot.key != id && (lot.remaining ?? 0) > 0)
                }
                let uncertain = group.unresolved || (toAllocate > 0.001 && uncertainStock)
                lines.append(ResolvedIngredient(id: id, name: group.ingredient.name, unit: group.ingredient.unit,
                                                category: group.ingredient.category,
                                                required: group.amount > 0 ? group.amount : nil,
                                                allocated: allocated, uncertain: uncertain))
                var entry = totals[id] ?? Aggregate(ingredient: group.ingredient, required: 0, allocated: 0,
                                                    uncertain: false, sourceSlots: [])
                entry.required += group.amount
                entry.allocated += allocated
                entry.uncertain = entry.uncertain || uncertain
                if !entry.sourceSlots.contains(slot.id) { entry.sourceSlots.append(slot.id) }
                totals[id] = entry
            }
            resolvedSlots[slot.id] = SlotRequirements(slotID: slot.id, recipeID: slot.recipeID,
                                                      availability: status, ingredients: lines)
        }
        let needs = totals.map { id, aggregate in
            ShoppingNeed(id: id, name: aggregate.ingredient.name, unit: aggregate.ingredient.unit,
                                category: aggregate.ingredient.category, required: aggregate.required,
                                available: aggregate.allocated, amountUnknown: aggregate.uncertain,
                                sourceSlots: aggregate.sourceSlots)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let freePantry = lots.map {
            PantryItem(name: $0.name, quantity: $0.remaining, unit: $0.unit,
                       category: $0.category, expiresOn: $0.expiresOn)
        }
        return PlanRequirements(slots: resolvedSlots, shoppingNeeds: needs,
                                inventoryEmpty: pantry.isEmpty, freePantry: freePantry)
    }

    static func shoppingNeeds(slots: [MealSlot], members: [FamilyMember], recipes: [Recipe], pantry: [PantryItem],
                              startDate: Date = .now, now: Date = .now, calendar: Calendar = .current,
                              eatenIDs: Set<String> = [], skippedIDs: Set<String> = []) -> [ShoppingNeed] {
        resolvePlan(slots: slots, members: members, recipes: recipes, pantry: pantry,
                    startDate: startDate, now: now, calendar: calendar, eatenIDs: eatenIDs,
                    skippedIDs: skippedIDs).shoppingNeeds
    }
}

enum CatalogPaging {
    static func nextLimit(current: Int, total: Int, step: Int) -> Int {
        min(total, max(0, current) + max(1, step))
    }
}

enum QuantityInput {
    static func parse(_ input: String, locale: Locale = .current) -> Double? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        guard let number = formatter.number(from: value) else { return nil }
        let result = number.doubleValue
        return result.isFinite && result >= 0 ? result : nil
    }
}
