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

enum PlanningCore {
    static func key(_ name: String, _ unit: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
        + "|" + unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func stock(for ingredient: Ingredient, pantry: [PantryItem], now: Date = .now) -> (known: Double, uncertain: Bool) {
        let matching = pantry.filter {
            key($0.name, $0.unit) == key(ingredient.name, ingredient.unit) &&
            ($0.expiresOn.map { Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: now) } ?? true)
        }
        return (matching.compactMap(\.quantity).reduce(0, +), matching.contains { $0.quantity == nil })
    }

    static func readiness(_ recipe: Recipe, portions: Double, pantry: [PantryItem]) -> RecipeReadiness {
        var covered = 0
        var missing: [String] = []
        var uncertain: [String] = []
        for ingredient in recipe.ingredients {
            let stock = stock(for: ingredient, pantry: pantry)
            let required = ingredient.amount * portions
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
            for ingredient in recipe.ingredients where ingredient.amount > 0 {
                let id = key(ingredient.name, ingredient.unit)
                var entry = totals[id] ?? Aggregate(ingredient: ingredient, required: 0, sourceSlots: [])
                entry.required += ingredient.amount * portions
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
