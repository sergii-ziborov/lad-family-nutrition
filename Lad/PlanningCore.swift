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

enum ProductNames {
    // Only interchangeable product names belong here. Related but different foods
    // (for example mushrooms and champignons, or lemon and lemon juice) stay separate.
    private static let equivalents: [[String]] = [
        ["томат", "томаты", "помидор", "помидоры"],
        ["кабачок", "кабачки", "цуккини"],
        ["картофель", "картошка", "картофелина", "картофелины"],
        ["морковь", "морковка", "морковки"],
        ["огурец", "огурцы"],
        ["яблоко", "яблоки"],
        ["яйцо", "яйца"],
        ["лук", "лук репчатый", "репчатый лук"],
        ["зеленый лук", "лук зеленый"],
        ["перец сладкий", "сладкий перец", "болгарский перец"],
        ["сушеный чеснок", "сухой чеснок", "чеснок сушеный", "чеснок сухой"],
        ["капуста белокочанная", "белокочанная капуста"],
        ["капуста цветная", "цветная капуста"],
        ["йогурт натуральный", "натуральный йогурт"],
        ["куриное филе", "филе курицы"],
        ["гречка", "гречневая крупа"]
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

    static func readiness(_ recipe: Recipe, portions: Double, pantry: [PantryItem]) -> RecipeReadiness {
        var covered = 0
        var missing: [String] = []
        var uncertain: [String] = []
        for ingredient in recipe.ingredients {
            guard let amount = ingredient.amount, amount > 0 else {
                uncertain.append(ingredient.name)
                continue
            }
            let stock = stock(for: ingredient, pantry: pantry)
            let required = amount * portions
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

    static func shoppingNeeds(slots: [MealSlot], members: [FamilyMember], recipes: [Recipe], pantry: [PantryItem]) -> [ShoppingNeed] {
        struct Aggregate {
            var ingredient: Ingredient
            var required: Double
            var sourceSlots: [String]
        }
        let membersByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        var totals: [String: Aggregate] = [:]
        for slot in slots {
            guard let recipe = recipesByID[slot.recipeID] else { continue }
            let portions = slot.memberIDs.compactMap { membersByID[$0]?.portion }.reduce(0, +)
            for ingredient in recipe.ingredients {
                guard let amount = ingredient.amount, amount > 0 else { continue }
                let id = key(ingredient.name, ingredient.unit)
                var entry = totals[id] ?? Aggregate(ingredient: ingredient, required: 0, sourceSlots: [])
                entry.required += amount * portions
                if !entry.sourceSlots.contains(slot.id) { entry.sourceSlots.append(slot.id) }
                totals[id] = entry
            }
        }
        return totals.map { id, aggregate in
            let stock = stock(for: aggregate.ingredient, pantry: pantry)
            return ShoppingNeed(id: id, name: aggregate.ingredient.name, unit: aggregate.ingredient.unit,
                                category: aggregate.ingredient.category, required: aggregate.required,
                                available: stock.known, amountUnknown: stock.uncertain,
                                sourceSlots: aggregate.sourceSlots)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum CatalogPaging {
    static func nextLimit(current: Int, total: Int, step: Int) -> Int {
        min(total, max(0, current) + max(1, step))
    }
}
