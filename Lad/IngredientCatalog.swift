import Foundation

struct ProductCopy: Codable {
    let ru: String
    let en: String
    let uk: String
    var localized: String { L10n.languageCode == "en" ? en : (L10n.languageCode == "uk" ? uk : ru) }
}

struct IngredientProfile: Identifiable, Codable {
    let id: String
    let name: String
    let category: String
    let image: String
    let description: ProductCopy
    let storage: ProductCopy
    let cooking: ProductCopy
    var title: String { L10n.text(name) }
    var nutrients: [String: NutrientValue] { NutrientEstimator.ingredientComposition(name: name) }
    var compositionSource: URL? { NutrientEstimator.ingredientSource(name: name) }
}

enum IngredientCatalog {
    static let all: [IngredientProfile] = {
        guard let url = Bundle.main.url(forResource: "ingredient-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let products = try? JSONDecoder().decode([IngredientProfile].self, from: data),
              Set(products.map(\.id)).count == products.count,
              Set(products.map { ProductNames.canonical($0.name) }).count == products.count else { return [] }
        return products
    }()
    static func product(_ name: String) -> IngredientProfile? {
        all.first { ProductNames.canonical($0.name) == ProductNames.canonical(name) }
    }
    static let storageSource = URL(string: "https://www.foodsafety.gov/food-safety-charts/cold-food-storage-charts")!
    static let foodKeeperSource = URL(string: "https://www.foodsafety.gov/keep-food-safe/foodkeeper-app")!
}

// A personal observed purchase price, not a market-price prediction. A deletion
// is retained as a tombstone so an older iCloud snapshot cannot resurrect it.
struct IngredientPrice: Codable, Identifiable {
    var productName: String
    var packagePrice: Double
    var packageQuantity: Double
    var packageUnit: String
    var currency: String
    var updatedAt: Date = .now
    var deletedAt: Date? = nil
    var reference: PriceReference? = nil
    var id: String { ProductNames.canonical(productName) }
    var isValid: Bool {
        !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        packagePrice.isFinite && packagePrice >= 0 && packageQuantity.isFinite && packageQuantity > 0 &&
        ["г", "кг", "мл", "л", "шт."].contains(packageUnit) &&
        currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil
    }
}

struct IngredientCost {
    let amount: Double
    let maximum: Double
    let currency: String
    let approximate: Bool
}

struct RecipeCost {
    var totals: [String: Double] = [:]
    var maximums: [String: Double] = [:]
    var missingNames: [String] = []
    var approximate = false
    var isComplete: Bool { missingNames.isEmpty }
    var hasPrices: Bool { !totals.isEmpty }
}

enum FoodCost {
    private static func pricingMeasure(_ ingredient: Ingredient) -> Ingredient {
        // Preserve physical pack units. Pantry's old 1 g/ml convention must
        // not turn a 500 ml oil bottle into a 500 g bottle for pricing.
        let units: [String: (String, Double)] = [
            "г": ("г", 1), "гр": ("г", 1), "гр.": ("г", 1), "g": ("г", 1),
            "кг": ("г", 1000), "kg": ("г", 1000),
            "мл": ("мл", 1), "ml": ("мл", 1), "л": ("мл", 1000), "l": ("мл", 1000),
            "шт.": ("шт.", 1), "шт": ("шт.", 1), "pcs": ("шт.", 1)
        ]
        guard let (unit, factor) = units[ProductNames.normalized(ingredient.unit)] else {
            return IngredientMeasures.normalized(ingredient)
        }
        var result = ingredient
        result.unit = unit
        result.amount = ingredient.amount.map { $0 * factor }
        result.amountMax = ingredient.amountMax.map { $0 * factor }
        return result
    }
    // USDA SR Legacy household weights: 4.5 g per 5 ml teaspoon of
    // these oils. Dairy and other thin liquids use the same 1 g/ml proxy the
    // pantry already uses. Never apply a density to an unnamed powder.
    private static func gramsPerMilliliter(_ name: String) -> Double? {
        let key = ProductNames.canonical(name)
        let oils = ["Оливковое масло", "Растительное масло", "Кунжутное масло", "Ореховое масло"]
        if oils.contains(where: { ProductNames.canonical($0) == key }) { return 0.9 }
        let thin = ["Молоко", "Вода", "Йогурт натуральный", "Йогурт греческий", "Сметана", "Кефир",
                    "Ряженка", "Мясной бульон", "Томатный сок", "Лимонный сок", "Соевый соус",
                    "Красное сухое вино", "Белое сухое вино", "Винный уксус", "Яблочный уксус", "Майонез"]
        if thin.contains(where: { ProductNames.canonical($0) == key }) { return 1 }
        return nil
    }
    /// Grams for a priced measure. Millilitres convert only through a named density.
    /// A piece or spoon uses the food-specific household weight, never 1 g.
    private static func pricedGrams(_ item: Ingredient, name: String) -> Double? {
        guard let amount = item.amount, amount.isFinite, amount > 0 else { return nil }
        switch item.unit {
        case "г": return amount
        case "мл":
            guard let density = gramsPerMilliliter(name) else { return nil }
            return amount * density
        default:
            return EnergyEstimator.estimatedGrams(for: item)
        }
    }
    // Same shopping category when the recipe name is more specific than the price list.
    // Keys go through ProductNames.normalized: diacritic folding turns й into и.
    private static let priceAliases: [String: String] = {
        let pairs = [
            "свиная вырезка": "Свинина", "свиные ножки": "Свинина", "свинина": "Свинина",
            "бурый рис": "Рис", "пропаренный рис": "Рис", "рис вареный": "Рис",
            "чечевица красная": "Чечевица", "йогурт греческий": "Йогурт натуральный",
            "куриный окорочок": "Куриное филе", "моцарелла": "Сыр", "фета": "Сыр",
            "брынза": "Сыр", "творожный сыр": "Сыр", "сыр с белой плесенью": "Сыр",
            "ржаная мука": "Мука", "рисовая мука": "Мука"
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { (ProductNames.normalized($0.key), $0.value) })
    }()
    /// Grams of the cooked food one gram of the dry pack makes, for cooked
    /// products priced from their dry pack. Rice: USDA FoodData Central gives
    /// about 365 kcal per 100 g raw and 130 cooked, so 1 g dry makes about 2.8 g.
    /// Without it 280 g of cooked rice was billed as 280 g of dry rice.
    private static let cookedYield: [String: Double] = [ProductNames.normalized("рис вареный"): 2.8]

    static func price(for name: String, prices: [IngredientPrice]) -> IngredientPrice? {
        func match(_ name: String) -> IngredientPrice? {
            prices.filter { $0.id == ProductNames.canonical(name) }.max { $0.updatedAt < $1.updatedAt }
                .flatMap { $0.deletedAt == nil && $0.isValid ? $0 : nil }
        }
        if let direct = match(name) { return direct }
        let key = ProductNames.normalized(name)
        if let alias = priceAliases[key] { return match(alias) }
        return nil
    }
    static func ingredient(_ source: Ingredient, prices: [IngredientPrice], multiplier: Double = 1) -> IngredientCost? {
        guard multiplier.isFinite, multiplier > 0, let price = price(for: source.name, prices: prices) else { return nil }
        let food = pricingMeasure(source)
        let pack = pricingMeasure(Ingredient(name: source.name, amount: price.packageQuantity,
                                                            unit: price.packageUnit, category: source.category))
        guard let used = food.amount, used.isFinite, used > 0,
              let paid = pack.amount, paid.isFinite, paid > 0 else { return nil }
        var ratio: Double
        var approximate = food.aiEstimated == true || pack.aiEstimated == true || price.reference != nil ||
            ProductNames.canonical(price.productName) != ProductNames.canonical(source.name)
        if food.unit == pack.unit { ratio = used / paid }
        else if let usedGrams = pricedGrams(food, name: source.name),
                let paidGrams = pricedGrams(pack, name: source.name), paidGrams > 0 {
            ratio = usedGrams / paidGrams
            approximate = approximate || ProductNames.canonical(source.name) != ProductNames.canonical("Вода")
        }
        else { return nil }
        if ProductNames.canonical(price.productName) != ProductNames.canonical(source.name),
           let yield = cookedYield[ProductNames.normalized(source.name)] {
            ratio /= yield
        }
        let total = price.packagePrice * ratio * multiplier
        let maximum = total * max(1, (food.amountMax ?? used) / used)
        guard total.isFinite, maximum.isFinite else { return nil }
        return IngredientCost(amount: total, maximum: maximum, currency: price.currency, approximate: approximate)
    }
    static func recipe(_ recipe: Recipe, prices: [IngredientPrice], servings: Double = 1) -> RecipeCost {
        var result = RecipeCost()
        guard servings.isFinite, servings > 0, recipe.baseServings > 0 else { return result }
        for ingredient in recipe.ingredients {
            if let cost = self.ingredient(ingredient, prices: prices, multiplier: servings / recipe.baseServings) {
                result.totals[cost.currency, default: 0] += cost.amount
                result.maximums[cost.currency, default: 0] += cost.maximum
                result.approximate = result.approximate || cost.approximate
            } else { result.missingNames.append(ingredient.name) }
        }
        result.missingNames = Array(Set(result.missingNames)).sorted()
        return result
    }
    static func money(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency).locale(Locale(identifier: L10n.languageCode)))
    }
    static func merge(_ first: [IngredientPrice], _ second: [IngredientPrice]) -> [IngredientPrice] {
        var entries: [String: IngredientPrice] = [:]
        for price in first + second {
            if entries[price.id].map({ current in
                current.updatedAt < price.updatedAt ||
                    (current.updatedAt == price.updatedAt && (current.deletedAt == nil || price.deletedAt != nil))
            }) ?? true { entries[price.id] = price }
        }
        return entries.values.sorted { $0.id < $1.id }
    }
}

extension LadStore {
    var personalIngredientPrices: [IngredientPrice] { state.ingredientPrices ?? [] }
    var shelfPrices: [IngredientPrice] {
        guard referencePriceCountry == "IL" else { return [] }
        guard let snapshot = shelfFileSnapshot else { return ShelfPrices.records(country: "IL") }
        return ShelfPrices.applying(snapshot.quotes)
    }
    var ingredientPrices: [IngredientPrice] {
        referencePriceCatalog.effectivePrices(personal: personalIngredientPrices, country: referencePriceCountry, shelf: shelfPrices)
    }
    func setIngredientPrice(_ price: IngredientPrice) {
        guard price.isValid else { return }
        var next = state
        var updated = price
        updated.reference = nil
        updated.updatedAt = now
        next.ingredientPrices = FoodCost.merge(personalIngredientPrices, [updated])
        state = next
    }
    func removeIngredientPrice(_ name: String) {
        guard var price = FoodCost.price(for: name, prices: personalIngredientPrices) else { return }
        price.updatedAt = now
        price.deletedAt = now
        var next = state
        next.ingredientPrices = FoodCost.merge(personalIngredientPrices, [price])
        state = next
    }
}
