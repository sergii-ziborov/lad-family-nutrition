import Foundation
import SwiftUI

enum L10n {
    static let languageKey = "lad.language"
    static var languageCode: String {
        let saved = UserDefaults.standard.string(forKey: languageKey) ?? "system"
        if ["en", "ru", "uk"].contains(saved) { return saved }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("uk") { return "uk" }
        return preferred.hasPrefix("ru") ? "ru" : "en"
    }
    static func text(_ source: String) -> String {
        guard languageCode != "ru", let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return source }
        return NSLocalizedString(source, tableName: "Localizable", bundle: bundle, value: source, comment: "")
    }
    static func format(_ source: String, _ arguments: CVarArg...) -> String {
        String(format: text(source), locale: Locale(identifier: languageCode), arguments: arguments)
    }
}

// This source recipe and the newer quantified version describe the same dish.
// Keep the older payload available for plans saved by earlier app versions, but
// do not offer it as a second choice in the catalogue or generator.
enum RecipeAliases {
    static let canonicalByLegacyID = ["photo_cottage_bake": "photo4_cottage_apple_prune_bake"]
    static func isLegacy(_ id: String) -> Bool {
        canonicalByLegacyID[id.hasPrefix("private:") ? String(id.dropFirst("private:".count)) : id] != nil
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

// Recipes may use household measures. Inventory and shopping use one metric
// measure per product; the source measure is still available as a cooking hint.
enum IngredientMeasures {
    private static let liquidNames: Set<String> = [
        "Вода", "Молоко", "Кефир", "Ряженка", "Мясной бульон", "Томатный сок",
        "Лимонный сок", "Соевый соус", "Красное сухое вино", "Белое сухое вино",
        "Винный уксус", "Яблочный уксус"
    ]
    private static let measuredInGrams: Set<String> = [
        "Йогурт натуральный", "Йогурт греческий", "Растительное масло", "Оливковое масло",
        "Кунжутное масло", "Ореховое масло", "Сметана", "Майонез"
    ]
    private static let canonicalLiquids = Set(liquidNames.map(ProductNames.canonical))
    private static let canonicalMassFoods = Set(measuredInGrams.map(ProductNames.canonical))
    private static func conversion(name: String, unit: String) -> (unit: String, factor: Double, estimated: Bool)? {
        let normalized = ProductNames.normalized(unit)
        let product = ProductNames.canonical(name)
        let liquid = canonicalLiquids.contains(product)
        switch normalized {
        case "г", "гр", "гр.", "g", "gram", "grams": return (liquid ? "мл" : "г", 1, liquid)
        case "кг", "kg": return (liquid ? "мл" : "г", 1000, liquid)
        case "мл", "ml":
            let solid = canonicalMassFoods.contains(product)
            // The existing food-composition reference uses a 1 g/ml proxy for
            // these foods. Keep that convention rather than inventing precision.
            return (solid ? "г" : "мл", 1, solid)
        case "л", "l", "liter", "litre":
            let solid = canonicalMassFoods.contains(product)
            return (solid ? "г" : "мл", 1000, solid)
        default:
            let aliases = ["шт": "шт.", "pcs": "шт.", "piece": "шт.", "pieces": "шт.",
                           "cup": "стакан", "cups": "стакан", "tbsp": "ст. л.", "tsp": "ч. л.",
                           "ст.л.": "ст. л.", "ч.л.": "ч. л."]
            let source = Ingredient(name: name, amount: 1, unit: aliases[normalized] ?? normalized, category: "")
            guard let grams = EnergyEstimator.estimatedGrams(for: source) else { return nil }
            return (liquid ? "мл" : "г", grams, true)
        }
    }
    static func normalized(_ ingredient: Ingredient) -> Ingredient {
        guard let measure = conversion(name: ingredient.name, unit: ingredient.unit) else { return ingredient }
        var result = ingredient
        result.amount = ingredient.amount.map { $0 * measure.factor }
        result.amountMax = ingredient.amountMax.map { $0 * measure.factor }
        result.unit = measure.unit
        if measure.estimated && (ingredient.unit != measure.unit || measure.factor != 1) { result.aiEstimated = true }
        return result
    }
    static func normalized(_ item: PantryItem) -> PantryItem {
        guard let measure = conversion(name: item.name, unit: item.unit) else { return item }
        var result = item
        result.quantity = item.quantity.map { $0 * measure.factor }
        result.unit = measure.unit
        if measure.estimated && (item.unit != measure.unit || measure.factor != 1) { result.quantityEstimated = true }
        return result
    }
}

enum IngredientAllergens {
    // Ingredient-derived tags supplement, never erase, catalogue declarations.
    // An unrecognised compound food is not silently declared allergen-free.
    private static let groups: [String: Set<String>] = [
        "Молоко": ["Молоко", "Творог", "Сыр", "Творожный сыр", "Сметана", "Йогурт натуральный", "Йогурт греческий", "Кефир", "Ряженка", "Моцарелла", "Фета", "Брынза", "Сыр с белой плесенью"],
        "Яйцо": ["Яйцо", "Майонез"],
        "Рыба": ["Лосось", "Минтай", "Хек", "Скумбрия"],
        "Ракообразные": ["Креветки"],
        "Пшеница": ["Мука", "Хлеб", "Макароны", "Соевый соус", "Булгур"],
        "Рожь": ["Ржаная мука", "Ржаные криспы"],
        "Овёс": ["Овсяные хлопья"],
        "Соя": ["Соевый соус"],
        "Горчица": ["Горчица"],
        "Сельдерей": ["Сельдерей"],
        "Кунжут": ["Кунжутное масло"],
        "Орехи": ["Ореховое масло", "Грецкие орехи"],
        "Диоксид серы и сульфиты": ["Красное сухое вино", "Белое сухое вино"]
    ]
    private static let plainFoods: Set<String> = [
        "Нут", "Оливки", "Шпинат",
        "Авокадо", "Аджика", "Апельсин", "Базилик", "Баклажан", "Банан", "Брокколи", "Бурый рис",
        "Ванилин", "Винный уксус", "Вода", "Вяленые томаты", "Гвоздика", "Говядина", "Говядина варёная",
        "Говядина на кости", "Говяжья печень", "Голень индейки", "Гороховая крупа", "Гречка", "Гречневая мука",
        "Душистый перец", "Желатин", "Зелень", "Зелёный лук", "Имбирь", "Кабачок", "Капуста",
        "Капуста белокочанная", "Картофель", "Квашеная капуста", "Киви", "Кориандр", "Корица", "Куриное филе",
        "Куриный окорочок", "Куриный фарш", "Лавровый лист", "Лимон", "Лимонный сок", "Листья салата", "Лук",
        "Любисток", "Майоран", "Мандарин", "Морковь", "Мясной фарш", "Нори", "Огурец", "Оливковое масло", "Орегано",
        "Паприка", "Пекинская капуста", "Перец сладкий", "Петрушка", "Печень индейки", "Пропаренный рис",
        "Пшено", "Разрыхлитель", "Растительное масло", "Редис", "Рис", "Рис варёный", "Рисовая лапша",
        "Рисовая мука", "Рисовые хлебцы", "Гречневые хлебцы", "Руккола", "Свиная вырезка", "Свинина",
        "Свиные ножки", "Свёкла", "Сладкий перец", "Сливы", "Соль", "Солёные огурцы", "Стручковая фасоль",
        "Сушёный чеснок", "Томатная паста", "Томатный сок", "Томаты", "Томаты черри", "Тыква", "Укроп", "Утка",
        "Филе индейки", "Цветная капуста", "Цукини", "Чернослив", "Чеснок", "Чечевица", "Чечевица красная",
        "Чёрный перец", "Шампиньоны", "Яблоко", "Яблочное пюре", "Яблочный уксус", "Ягоды", "Чай", "Кофе"
    ]
    private static let canonicalGroups = groups.mapValues { Set($0.map(ProductNames.canonical)) }
    private static let recognisedFoods = Set(plainFoods.map(ProductNames.canonical))
        .union(canonicalGroups.values.reduce(into: Set<String>()) { $0.formUnion($1) })
    static func inferred(from ingredients: [Ingredient]) -> [String] {
        let names = Set(ingredients.flatMap { [$0.name] + ($0.alternatives ?? []) }.map(ProductNames.canonical))
        return canonicalGroups.keys.filter { !names.isDisjoint(with: canonicalGroups[$0] ?? []) }.sorted()
    }
    static func containsUnspecifiedComposition(_ ingredients: [Ingredient]) -> Bool {
        ingredients.flatMap { [$0.name] + ($0.alternatives ?? []) }.contains { name in
            !recognisedFoods.contains(ProductNames.canonical(name))
        }
    }
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
    static func energyDensity(for name: String) -> Double? {
        guard !["Кофе", "Чай"].contains(name) else { return nil }
        return NutrientEstimator.ingredientComposition(name: name)["energy"]?.amount ??
            kcalPer100g[name] ?? kcalPer100g.first { ProductNames.canonical($0.key) == ProductNames.canonical(name) }?.value
    }
    private static let kcalPer100g: [String: Double] = [
        "Лосось": 208, "Картофель": 77, "Брокколи": 34, "Йогурт натуральный": 60,
        "Лимон": 29, "Творог": 121, "Яйцо": 143, "Мука": 364, "Ягоды": 50,
        "Чечевица красная": 352, "Чечевица": 352, "Томаты": 18, "Лук": 40, "Морковь": 41,
        "Овсяные хлопья": 389, "Молоко": 50, "Банан": 89, "Хлеб": 265,
        "Куриное филе": 120, "Гречка": 343, "Огурец": 15, "Макароны": 350,
        "Кабачок": 17, "Цукини": 17, "Сыр": 350, "Филе индейки": 114,
        "Рис": 365, "Бурый рис": 370, "Пропаренный рис": 374,
        "Перец сладкий": 26, "Сладкий перец": 26,
        "Минтай": 72, "Хек": 82, "Сметана": 200, "Цветная капуста": 25,
        "Шампиньоны": 22, "Рисовая мука": 366, "Ржаная мука": 335,
        "Сельдерей": 16, "Мясной фарш": 250, "Растительное масло": 884,
        "Капуста": 25, "Свёкла": 43, "Яблоко": 52, "Яблочное пюре": 48, "Чеснок": 149,
        "Чернослив": 240, "Говядина": 200, "Ванилин": 288, "Майоран": 271,
        "Любисток": 42, "Сушёный чеснок": 331, "Соль": 0, "Чёрный перец": 251,
        "Кориандр": 298, "Укроп": 43, "Аджика": 60, "Зелень": 30,
        "Специи": 300, "Лимонный сок": 22, "Рисовая лапша": 364,
        "Лавровый лист": 313, "Душистый перец": 263, "Специи для плова": 300,
        "Зелёный лук": 32, "Паприка": 282, "Майонез": 680,
        "Разрыхлитель": 53, "Кефир": 41, "Пекинская капуста": 16,
        "Красное сухое вино": 85, "Квашеная капуста": 19, "Горчица": 66,
        "Имбирь": 80, "Сливы": 46, "Томатная паста": 82, "Креветки": 85,
        "Рис варёный": 123, "Томатный сок": 17, "Ржаные криспы": 366,
        "Творожный сыр": 201, "Свиная вырезка": 120, "Баклажан": 25,
        "Соевый соус": 53, "Мандарин": 53,
        "Пшено": 378, "Нори": 259, "Корица": 247, "Тыква": 26,
        "Гороховая крупа": 352, "Апельсин": 47, "Киви": 61,
        "Мясной бульон": 13, "Желатин": 335, "Йогурт греческий": 73,
        "Оливковое масло": 884, "Куриный фарш": 143,
        "Стручковая фасоль": 31, "Солёные огурцы": 11,
        "Говядина варёная": 247, "Говяжья печень": 135,
        "Утка": 135, "Скумбрия": 205, "Вяленые томаты": 258,
        "Авокадо": 160, "Редис": 16, "Листья салата": 15,
        "Моцарелла": 280, "Фета": 264, "Руккола": 25,
        "Томаты черри": 18, "Петрушка": 36, "Кунжутное масло": 884,
        "Ореховое масло": 884, "Винный уксус": 19, "Яблочный уксус": 21,
        "Орегано": 265, "Базилик": 23, "Сыр с белой плесенью": 334,
        "Свинина": 230, "Печень индейки": 126, "Прованские травы": 270,
        "Брынза": 264, "Белое сухое вино": 82, "Ряженка": 67,
        "Куриный окорочок": 178, "Свиные ножки": 212,
        "Говядина на кости": 200, "Голень индейки": 144, "Гвоздика": 274,
        "Рисовые хлебцы": 380, "Гречневые хлебцы": 360,
        "Вода": 0, "Чай": 0, "Кофе": 0,
        "Нут": 378, "Булгур": 342, "Оливки": 145, "Грецкие орехи": 654, "Шпинат": 23
    ]
    private static let pieceGrams: [String: Double] = [
        "Лимон": 58, "Яйцо": 50, "Банан": 118, "Лук": 110,
        "Морковь": 75, "Цукини": 200, "Кабачок": 200, "Томаты": 120,
        "Куриное филе": 200,
        "Сладкий перец": 120, "Перец сладкий": 120, "Шампиньоны": 18,
        "Яблоко": 150, "Чернослив": 10, "Огурец": 150,
        "Апельсин": 130, "Киви": 75, "Мандарин": 85, "Картофель": 150,
        "Баклажан": 250, "Сливы": 40
    ]
    private static func householdWeight(_ table: [String: Double], name: String) -> Double? {
        table[name] ?? table.first { ProductNames.canonical($0.key) == ProductNames.canonical(name) }?.value
    }
    static func estimatedGrams(for ingredient: Ingredient) -> Double? {
        guard let amount = ingredient.amount, amount > 0 else { return nil }
        switch ingredient.unit {
        case "г", "мл": return amount
        case "шт.": return householdWeight(pieceGrams, name: ingredient.name).map { amount * $0 }
        case "зуб.": return ingredient.name == "Чеснок" ? amount * 3 : nil
        case "головка": return ingredient.name == "Чеснок" ? amount * 40 : nil
        case "филе": return ["Куриное филе": 200, "Минтай": 150, "Хек": 150][ingredient.name].map { amount * $0 }
        case "ст. л.": return householdWeight(["Йогурт натуральный": 15, "Рисовая мука": 10,
                                 "Ржаная мука": 10], name: ingredient.name).map { amount * $0 }
        case "ч. л.": return householdWeight(["Растительное масло": 5, "Сметана": 5,
                                "Сельдерей": 3, "Майонез": 5], name: ingredient.name).map { amount * $0 }
        case "стакан": return householdWeight(["Бурый рис": 180, "Рис": 180], name: ingredient.name).map { amount * $0 }
        case "ломтик": return ingredient.name == "Сельдерей" ? amount * 10 : nil
        case "щепотка": return amount * 0.5
        default: return nil
        }
    }
    static func evaluate(_ ingredients: [Ingredient], edibleYield: [String: Double] = [:]) -> EnergyEstimate {
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
            known += grams * averageAmount * (edibleYield[ingredient.name] ?? 1) * density / 100
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
    var isCourseSide: Bool = false
    var nutrients: [String: NutrientValue] = [:]
    var nutrientPreparationByIngredient: [String: String] = [:]
    // Raw shopping weight may include bone/skin discarded before serving.
    var nutritionEdibleYield: [String: Double] = [:]
    var remoteImage: Bool = false
    var stepImageIDs: [String?] = []
    var stepMinutes: [Int] = []
    var difficulty: CookingDifficulty? = nil
    var energyEstimate: EnergyEstimate? = nil
    var baseServings: Double = 1
    var servingsEstimated: Bool = false
    var kcalEstimated: Bool = false
    var isPrivate: Bool { id.hasPrefix("private:") }
    var isBeverage: Bool { CourseBeverages.isBeverage(self) }
    var containsAlcoholIngredient: Bool {
        ingredients.contains { ["Красное сухое вино", "Белое сухое вино"].contains($0.name) }
    }
    var isUnavailable: Bool { id == "unavailable" || id == "unplanned" }
    var isUnplanned: Bool { id == "unplanned" }
    var knownAllergens: [String] { Array(Set(allergens + IngredientAllergens.inferred(from: ingredients))).sorted() }
    var hasUnspecifiedAllergenComposition: Bool {
        !allergensVerified && IngredientAllergens.containsUnspecifiedComposition(ingredients)
    }
    var isPlanEligible: Bool {
        !isUnavailable && !ingredients.isEmpty && ingredients.allSatisfy { ($0.amount ?? 0) > 0 }
    }

    static let unavailable = Recipe(id: "unavailable", title: "Закрытый рецепт недоступен", caption: "Подключите каталог, чтобы снова открыть это блюдо.", image: "", cuisine: "Закрытая библиотека", minutes: 0, kcal: nil, protein: nil, allergens: [], ingredients: [], steps: [])
    static let unplanned = Recipe(id: "unplanned", title: "Блюдо не выбрано", caption: "Выберите курс и составьте меню.", image: "", cuisine: "", minutes: 0, kcal: nil, protein: nil, allergens: [], ingredients: [], steps: [])

    private struct PublicDemoBundle: Decodable { let recipes: [PrivateRecipePayload] }

    private static func bundled(_ name: String) -> [Recipe] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(PublicDemoBundle.self, from: data) else { return [] }
        let recipes = bundle.recipes.compactMap { $0.recipe(privateAccess: false, remoteImage: false) }
        guard recipes.count == bundle.recipes.count, Set(recipes.map(\.id)).count == recipes.count else { return [] }
        return recipes
    }
    static let launchRecipes = bundled("public-recipes")
    static let all: [Recipe] = {
        guard !ReleasePolicy.isStoreRelease else { return launchRecipes }
        var seen = Set<String>()
        return (launchRecipes + bundled("legacy-recipes")).filter { seen.insert($0.id).inserted }
    }()
}

// Beverages are optional course companions, not replacements for breakfast, lunch or dinner.
// Dry tea/coffee are shopping ingredients; their unconsumed grounds are not counted as food energy.
enum CourseBeverages {
    static let prefix = "course-drink-"
    static let waterID = "course-drink-water"
    static func isBeverage(_ id: String) -> Bool { id.hasPrefix(prefix) }
    static func isBeverage(_ recipe: Recipe) -> Bool {
        if isBeverage(recipe.id) { return true }
        // Imported water/tea/coffee must not become a main meal just because
        // they have another ID or valid quantities. Soup and milk-based food
        // still contain other ingredients, so remain food.
        let drinkIngredients: Set<String> = ["вода", "чай", "кофе", "молоко", "кефир", "томатный сок",
                                              "красное сухое вино", "белое сухое вино"]
        let names = Set(recipe.ingredients.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return !names.isEmpty && names.isSubset(of: drinkIngredients)
    }
    static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
    static func sourceRecommendations(for recipe: Recipe) -> Set<String>? {
        let id = recipe.id.replacingOccurrences(of: "private:", with: "")
        let plain: Set<String> = [waterID, "course-drink-tea", "course-drink-coffee"]
        // Drink lists printed next to these source dishes. The list is a pool
        // of alternatives, not an instruction to consume every listed drink.
        let dairy: Set<String> = ["photo4_cottage_apple_prune_bake", "photo4_apple_orange_kiwi_yogurt",
                                 "photo6_cottage_apple_puree", "photo8_lazy_rye_curd_dumplings",
                                 "photo9_cottage_plum_apple", "photo9_rye_khachapuri"]
        let vegetable: Set<String> = ["photo8_tomato_grain_curd_salad", "photo9_beet_caviar",
                                     "photo9_broccoli_yogurt_salad", "photo_vegetable_pilaf"]
        let plainOnly: Set<String> = ["photo8_dill_egg_pancakes", "photo8_beef_turkey_aspic",
                                     "photo9_clear_meatball_soup"]
        if plainOnly.contains(id) { return plain }
        if dairy.contains(id) || vegetable.contains(id) {
            let withDairy = plain.union(["course-drink-kefir", "course-drink-milk"])
            return vegetable.contains(id) ? withDairy.union(["course-drink-tomato-juice"]) : withDairy
        }
        return nil
    }
    static let all: [Recipe] = {
        var recipes: [Recipe] = [
        Recipe(id: waterID, title: "Вода", caption: "Стакан воды; объём ориентировочный.", image: "", cuisine: "Напитки", minutes: 1, kcal: 0, protein: 0, allergens: [], ingredients: [Ingredient(name: "Вода", amount: 200, unit: "мл", category: "Напитки", aiEstimated: true)], steps: ["Налейте питьевую воду в стакан."], allergensVerified: true),
        Recipe(id: "course-drink-tea", title: "Чай", caption: "Без сахара; количество сухого чая и воды ориентировочное.", image: "", cuisine: "Напитки", minutes: 5, kcal: 0, protein: 0, allergens: [], ingredients: [Ingredient(name: "Чай", amount: 2, unit: "г", category: "Напитки", aiEstimated: true), Ingredient(name: "Вода", amount: 200, unit: "мл", category: "Напитки", aiEstimated: true)], steps: ["Заварите чай питьевой водой; добавки учитывайте отдельно."], allergensVerified: true),
        Recipe(id: "course-drink-coffee", title: "Кофе", caption: "Без сахара и молока; сухой кофе расходуется из запасов, но не съедается целиком.", image: "", cuisine: "Напитки", minutes: 5, kcal: 0, protein: 0, allergens: [], ingredients: [Ingredient(name: "Кофе", amount: 8, unit: "г", category: "Напитки", aiEstimated: true), Ingredient(name: "Вода", amount: 200, unit: "мл", category: "Напитки", aiEstimated: true)], steps: ["Приготовьте кофе с питьевой водой; молоко и сахар, если добавите, внесите отдельно."], allergensVerified: true),
        Recipe(id: "course-drink-kefir", title: "Кефир", caption: "Порция 200 мл — ориентир; проверяйте состав и индивидуальную переносимость.", image: "", cuisine: "Напитки", minutes: 1, kcal: 82, protein: 6, allergens: ["Молоко"], ingredients: [Ingredient(name: "Кефир", amount: 200, unit: "мл", category: "Молочные продукты", aiEstimated: true)], steps: ["Налейте кефир в стакан."], allergensVerified: true),
        Recipe(id: "course-drink-milk", title: "Молоко", caption: "Стакан молока 200 мл; пищевая ценность зависит от жирности.", image: "", cuisine: "Напитки", minutes: 1, kcal: 100, protein: 7, allergens: ["Молоко"], ingredients: [Ingredient(name: "Молоко", amount: 200, unit: "мл", category: "Молочные продукты", aiEstimated: true)], steps: ["Налейте молоко в стакан."], allergensVerified: true),
        Recipe(id: "course-drink-tomato-juice", title: "Томатный сок", caption: "Стакан 200 мл без добавленного сахара; проверьте соль на упаковке.", image: "", cuisine: "Напитки", minutes: 1, kcal: 34, protein: 2, allergens: [], ingredients: [Ingredient(name: "Томатный сок", amount: 200, unit: "мл", category: "Напитки", aiEstimated: true)], steps: ["Налейте томатный сок в стакан."], allergensVerified: true),
        Recipe(id: "course-drink-red-wine", title: "Красное сухое вино (алкоголь)", caption: "Только по явному выбору взрослого. 100 мл и калории — приблизительная оценка; алкоголь не предлагается автоматически и противопоказан при беременности.", image: "", cuisine: "Напитки", minutes: 1, kcal: 85, protein: 0, allergens: [], ingredients: [Ingredient(name: "Красное сухое вино", amount: 100, unit: "мл", category: "Напитки", aiEstimated: true)], steps: ["Отмерьте выбранную порцию; употребление алкоголя не обязательно."], allergensVerified: true)
        ]
        for index in recipes.indices {
            recipes[index].nutrientPreparationByIngredient = Dictionary(uniqueKeysWithValues:
                recipes[index].ingredients.map { ($0.name, "raw") })
            recipes[index].nutrients = NutrientEstimator.estimate(recipes[index])
        }
        return recipes
    }()
}

struct WeightEntry: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var memberID: String
    var measuredAt: Date
    var kilograms: Double
    var note = ""
    var isValid: Bool { !memberID.isEmpty && kilograms.isFinite && (10...500).contains(kilograms) && measuredAt.timeIntervalSince1970.isFinite }
}

enum WeightJournal {
    static func entries(_ state: DemoState, memberID: String) -> [WeightEntry] {
        (state.weightEntries ?? []).filter { $0.memberID == memberID && $0.isValid }
            .sorted { $0.measuredAt == $1.measuredAt ? $0.id < $1.id : $0.measuredAt < $1.measuredAt }
    }
    static func csv(_ entries: [WeightEntry], name: String) -> String {
        func cell(_ value: String) -> String {
            let safe = ["=", "+", "-", "@", "\t", "\r", "\n"].contains(where: { value.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = entries.map { [cell($0.id), cell(name), cell(ISO8601DateFormatter().string(from: $0.measuredAt)),
                                String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0.kilograms), cell($0.note)].joined(separator: ",") }
        return (["entry_id,person,measured_at,weight_kg,note"] + rows).joined(separator: "\r\n")
    }
}

extension LadStore {
    func saveWeightEntry(_ entry: WeightEntry) -> Bool {
        guard !protectedStateReadFailed, entry.isValid, entry.measuredAt <= Date.now.addingTimeInterval(60), entry.note.count <= 1000,
              let index = state.members.firstIndex(where: { $0.id == entry.memberID }) else { return false }
        var next = state
        next.weightEntries = (next.weightEntries ?? []).filter { $0.id != entry.id } + [entry]
        if let latest = WeightJournal.entries(next, memberID: entry.memberID).last { next.members[index].weightKg = latest.kilograms }
        state = next
        if maintainsDayMenu { fillTodayMenu() }
        return true
    }
    func removeWeightEntry(_ entry: WeightEntry) {
        state.weightEntries = (state.weightEntries ?? []).filter { $0.id != entry.id }
    }
}

/// Health notes that change what a person should eat. They only add warnings
/// to the menu: the app does not diagnose, ban dishes or replace a doctor.
enum DietCondition: String, Codable, CaseIterable, Identifiable {
    case pregnancy, noSugar, stomach, lowSalt, gout, eatingDisorder
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pregnancy: return "Беременность или кормление грудью"
        case .noSugar: return "Диабет или без сахара"
        case .stomach: return "Язва или гастрит"
        case .lowSalt: return "Давление или почки: меньше соли"
        case .gout: return "Подагра"
        case .eatingDisorder: return "Расстройство пищевого поведения"
        }
    }
    var hint: String {
        switch self {
        case .pregnancy: return "Предупредит о вине, сыре с плесенью и печени."
        case .noSugar: return "Предупредит о сахаре, мёде, варенье, шоколаде и сухофруктах."
        case .stomach: return "Предупредит об уксусе, горчице, аджике, остром перце и вине."
        case .lowSalt: return "Предупредит о соевом соусе, фете, брынзе, оливках и солениях."
        case .gout: return "Предупредит о печени, мясном бульоне, скумбрии и вине."
        case .eatingDisorder: return "Анорексия, булимия и другие. Калории этого человека не показываются, цель «Снижение» отключается."
        }
    }
    /// Short reason printed after the names in a menu warning.
    var reason: String {
        switch self {
        case .pregnancy: return "беременность или кормление"
        case .noSugar: return "без сахара"
        case .stomach: return "язва или гастрит"
        case .lowSalt: return "меньше соли"
        case .gout: return "подагра"
        case .eatingDisorder: return "РПП"
        }
    }
}

struct FamilyMember: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var goal: String
    var portion: Double
    var allergies: [String]
    var ageYears: Int? = nil
    var dailyEnergyTarget: Int? = nil
    var preferredVitaminKeys: Set<String>? = nil
    var heightCm: Double? = nil
    var weightKg: Double? = nil
    var automaticPortions: Bool? = nil
    var energySex: EnergySex? = nil
    var energyActivity: EnergyActivity? = nil
    var energyContext: EnergyContext? = nil
    var measuredFatMassKg: Double? = nil
    var measuredMuscleMassKg: Double? = nil
    /// Long-term conditions that change what this person should eat.
    var dietConditions: Set<DietCondition>? = nil
    /// Marked conditions, with pregnancy also read from the energy calculation type.
    var conditions: Set<DietCondition> {
        var marked = dietConditions ?? []
        if energyContext == .pregnancyOrLactation { marked.insert(.pregnancy) }
        return marked
    }
    /// With an eating disorder the app keeps calories and weight-loss goals
    /// out of this person's views; the plan stays a family menu.
    var hidesEnergyNumbers: Bool { conditions.contains(.eatingDisorder) }
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
        if L10n.languageCode == "uk" {
            let suffix: String
            if (11...14).contains(ageYears % 100) { suffix = "років" }
            else if ageYears % 10 == 1 { suffix = "рік" }
            else if (2...4).contains(ageYears % 10) { suffix = "роки" }
            else { suffix = "років" }
            return "\(ageYears) \(suffix)"
        }
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
    var quantityEstimated: Bool? = nil
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
    var extraRecipeIDs: [String]? = nil
    // Keep decoding old single-drink plans. New edits use beverageIDs, including
    // an explicit [] (no drinks), so generation does not overwrite that choice.
    var beverageID: String? = nil
    var beverageIDs: [String]? = nil
    var beveragesSelectedManually: Bool? = nil
    /// True when a person chose this dish. Automatic fill leaves it false and
    /// will not replace a true value. Nil means an older plan that stays put
    /// until the day's inputs change.
    var recipeChosenManually: Bool? = nil
    var preparedDishIDs: [String: String]? = nil
    var chronologicalOrder: Int { CourseSnacks.mealOrder.firstIndex(of: kind) ?? 4 }

    var selectedBeverageIDs: [String] {
        CourseBeverages.unique(beverageIDs ?? beverageID.map { [$0] } ?? [])
    }
    var hasManualBeverages: Bool {
        beveragesSelectedManually ?? (beverageIDs != nil || (beverageID != nil && beverageID != CourseBeverages.waterID))
    }
    mutating func setBeverages(_ ids: [String], manuallySelected: Bool = false) {
        beverageIDs = CourseBeverages.unique(ids)
        beverageID = nil
        beveragesSelectedManually = manuallySelected
    }

    var allRecipeIDs: [String] {
        recipeID == Recipe.unplanned.id ? [recipeID] :
            CourseBeverages.unique([recipeID] + (extraRecipeIDs ?? []) + selectedBeverageIDs)
    }
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
    var diaryEntries: [DiaryEntry]? = nil
    var diaryDeletedAt: [String: Date]? = nil
    var preparedDishes: [PreparedDish]? = nil
    var ingredientPrices: [IngredientPrice]? = nil
    var weightEntries: [WeightEntry]? = nil
    var launchMenuVersion: Int? = nil
    /// Inputs that last produced today's automatic dishes. A matching stamp
    /// keeps those dishes until a preference, the weight, or earlier meals change.
    var autoDayMenuStamp: String? = nil
    /// 1 after the one-time release of child portions that were locked at 100%.
    var portionRulesVersion: Int? = nil

    mutating func migratePortionRules() {
        guard portionRulesVersion == nil else { return }
        for index in members.indices {
            var member = members[index]
            if (member.ageYears ?? 19) < 19, member.automaticPortions == false, abs(member.portion - 1) < 0.001 {
                member.automaticPortions = nil
            }
            members[index] = member
        }
        portionRulesVersion = 1
    }

    mutating func migrateLaunchMenu(currentDay: Int) {
        guard launchMenuVersion == nil else { return }
        launchMenuVersion = 1
        var selected = CourseAliases.canonical(activeCourseIDs ?? [])
        if selected.remove("weight-week-pilot") != nil { selected.insert(CourseAliases.mediterranean) }
        activeCourseIDs = selected
        guard selected.contains(CourseAliases.mediterranean) else { return }
        let available = Dictionary(uniqueKeysWithValues: Recipe.launchRecipes.map { ($0.id, $0) })
        func canonical(_ id: String) -> String {
            let raw = id.replacingOccurrences(of: "private:", with: "")
            return RecipeAliases.canonicalByLegacyID[raw] ?? raw
        }
        for index in slots.indices {
            let slot = slots[index]
            guard slot.day >= currentDay, !eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else { continue }
            let id = canonical(slot.recipeID)
            guard let recipe = available[id], recipe.mealKinds.contains(slot.kind) else {
                slots[index].recipeID = Recipe.unplanned.id
                slots[index].extraRecipeIDs = []
                slots[index].setBeverages([])
                continue
            }
            slots[index].recipeID = id
            slots[index].extraRecipeIDs = (slot.extraRecipeIDs ?? []).map(canonical).filter {
                available[$0]?.mealKinds.contains(slot.kind) == true
            }
        }
    }

    static func initial(selectAllAvailableCourses: Bool = false) -> DemoState {
        let family = [
            FamilyMember(id: "anna", name: "Анна", goal: "Баланс", portion: 1.0, allergies: []),
            FamilyMember(id: "igor", name: "Игорь", goal: "Поддержание", portion: 1.25, allergies: []),
            FamilyMember(id: "mila", name: "Мила", goal: "Без цели по весу", portion: 0.65, allergies: [])
        ]
        var slots: [MealSlot] = []
        for day in 0..<7 {
            for kind in 0..<3 {
                let mains = Recipe.launchRecipes.filter { !$0.isCourseSide }
                let breakfast = mains.filter { $0.mealKinds.contains(0) }.map(\.id)
                let lunch = mains.filter { $0.mealKinds.contains(1) }.map(\.id)
                let dinner = mains.filter { $0.mealKinds.contains(2) }.map(\.id)
                let pairs = (CourseCatalogAccess.bundledCourses.first?.suggestedPairs ?? []).filter {
                    lunch.contains($0.lunchRecipeID) && $0.dinnerRecipeID.map(dinner.contains) == true
                }
                let pair = pairs.isEmpty ? nil : pairs[day % pairs.count]
                let options = kind == 0 ? breakfast : kind == 1 ? lunch : dinner
                let fallback = options.isEmpty ? Recipe.unplanned.id : options[day % options.count]
                let recipeID = kind == 1 ? pair?.lunchRecipeID ?? fallback :
                    kind == 2 ? pair?.dinnerRecipeID ?? fallback : fallback
                slots.append(MealSlot(id: "\(day)-\(kind)", day: day, kind: kind, recipeID: recipeID, memberIDs: family.map(\.id)))
            }
        }
        let initialCourses = selectAllAvailableCourses
            ? Set(CourseCatalogAccess.bundledCourses.map(\.id)) : Set([CourseAliases.mediterranean])
        return DemoState(startDate: Calendar.current.startOfDay(for: .now), members: family, slots: slots, selectedMemberID: "anna", eatenIDs: [], boughtNames: [], pantryNames: [], favorites: ["anna|salmon"], extraShopping: [], supplementsByMember: [:], takenSupplements: [], activeCourseIDs: initialCourses, launchMenuVersion: 1)
    }

    static func nextWeek(after previous: DemoState, now: Date) -> DemoState {
        var fresh = DemoState.initial()
        fresh.startDate = Calendar.current.startOfDay(for: now)
        fresh.members = previous.members
        fresh.selectedMemberID = previous.selectedMemberID
        fresh.favorites = previous.favorites
        fresh.dislikes = previous.dislikes
        fresh.activeCourseIDs = CourseAliases.canonical(previous.activeCourseIDs ?? [])
        if previous.launchMenuVersion == nil, fresh.activeCourseIDs?.remove("weight-week-pilot") != nil {
            fresh.activeCourseIDs?.insert(CourseAliases.mediterranean)
        }
        if fresh.activeCourseIDs?.contains(CourseAliases.mediterranean) != true {
            for index in fresh.slots.indices { fresh.slots[index].recipeID = Recipe.unplanned.id }
        }
        fresh.pantryNames = previous.pantryNames
        fresh.pantryItems = previous.pantryItems
        fresh.extraShopping = previous.extraShopping
        fresh.supplementsByMember = previous.supplementsByMember
        fresh.mealSchedule = previous.mealSchedule
        fresh.purchaseReceipts = previous.purchaseReceipts
        fresh.diaryEntries = previous.diaryEntries
        fresh.diaryDeletedAt = previous.diaryDeletedAt
        fresh.preparedDishes = previous.preparedDishes
        fresh.ingredientPrices = previous.ingredientPrices
        fresh.weightEntries = previous.weightEntries
        fresh.portionRulesVersion = previous.portionRulesVersion
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
        var folder = support.appendingPathComponent("lad-week-history", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        if ReleasePolicy.isStoreRelease {
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try folder.setResourceValues(resources)
        }
        return folder
    }

    static func save(_ state: DemoState, accountID: String) throws {
        let file = try folder().appendingPathComponent("\(accountID)-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtection])
    }

    static func protectExistingArchives() throws { _ = try folder() }

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
    static func states(accountID: String) -> [DemoState] {
        guard let folder = try? folder(),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.lastPathComponent.hasPrefix(accountID + "-") && $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(DemoState.self, from: data)
        }
    }
}

struct PlannedChange: Identifiable {
    let slotID: String
    let previousID: String
    let nextID: String
    var previousBeverageIDs: [String]? = nil
    var nextBeverageIDs: [String]? = nil
    var beverageChanged: Bool = false
    var previousBeveragesManual: Bool = false
    var nextBeveragesManual: Bool = false
    var previousExtraRecipeIDs: [String]? = nil
    var nextExtraRecipeIDs: [String]? = nil
    var extrasChanged: Bool = false
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
    let ruleWarnings: [CourseRuleWarning]
}

struct AvoidedRecipe: Equatable {
    let slotID: String
    let memberID: String
    let recipeID: String
    var key: String { "\(slotID)|\(memberID)" }
}

@MainActor final class LadStore: ObservableObject {
    @Published var referencePriceCatalog = ReferencePriceCatalog.current
    @Published var shelfFileSnapshot = ShelfFileSync.load()
    @Published var referencePriceCountrySource = LadStore.storedPriceCountrySource()
    @Published var referencePriceCountry = LadStore.storedReferencePriceCountry()
    @Published var referencePriceStatus: String?
    @Published var isUpdatingReferencePrices = false
    @Published var state: DemoState {
        didSet {
            stateRevision += 1
            if undoRevision != nil && undoRevision != stateRevision {
                undoRevision = nil
                canUndoReplan = false
                lastAppliedChanges = []
                lastAppliedAvoid = nil
            }
            save(markChanged: true)
        }
    }
    @Published var selectedDay: Int = 0
    @Published private(set) var now: Date = .now
    @Published private(set) var privateRecipes: [Recipe] = [] { didSet { recipeSourceRevision &+= 1 } }
    @Published private(set) var catalogueRecipes: [Recipe] = [] { didSet { recipeSourceRevision &+= 1 } }
    @Published private(set) var courses: [LadCourse] = CourseCatalogAccess.bundledCourses { didSet { recipeSourceRevision &+= 1 } }
    @Published private(set) var courseCatalogStatus: String = "Бесплатный каталог офлайн"
    @Published private(set) var privateCatalogStatus: String = "Не подключён"
    @Published private(set) var familyCloudStatus: String = "Не подключено"
    @Published private(set) var storageWarning: String?
    @Published var notificationStatus = "Уведомления выключены"
    @Published var cloudSyncStatus = "iCloud выключен"
    @Published var cloudLastSync: Date?
    var personalStateModifiedAt = UserDefaults.standard.object(forKey: "lad.personalModifiedAt") as? Date ?? .distantPast
    var isApplyingCloudSnapshot = false
    var cloudSyncTask: Task<Void, Never>?
    var notificationTask: Task<Void, Never>?
    @Published var isCloudSyncing = false
    var cloudResyncRequested = false
    var servicesStarted = false
    var maintainsDayMenu = false
    private var isFillingDayMenu = false
    @Published var replanPreview: ReplanPreview?
    @Published private(set) var canUndoReplan = false
    private var lastAppliedChanges: [PlannedChange] = []
    private var lastAppliedAvoid: AvoidedRecipe?
    private var stateRevision = 0
    /// Changes whenever the merged recipe list may change. Views read
    /// `allRecipes`, the plan and portions many times per frame; those are
    /// cached per revision instead of being rebuilt on every access.
    private var recipeSourceRevision = 0
    private var recipeCache: (revision: Int, recipes: [Recipe], visible: [Recipe], byID: [String: Recipe])?
    private var planCache: (key: String, value: PlanRequirements)?
    private var portionCache: (key: String, shares: [String: Double])?
    private var courseRecipeCache: (key: String, ids: Set<String>)?
    private var catalogRevision = 0
    private var privateSessionRevision = 0
    var protectedStateReadFailed = false
    private var undoRevision: Int?
    private var undoCatalogRevision: Int?
    let localAccountID: String
    var kinds: [String] { [L10n.text("Завтрак"), L10n.text("Обед"), L10n.text("Ужин"), L10n.text("Перекус")] }

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
            if ProcessInfo.processInfo.arguments.contains("--screenshot-snack") {
                state.slots.append(MealSlot(id: "0-3", day: 0, kind: 3,
                                           recipeID: CourseSnacks.all[0].id, memberIDs: [state.selectedMemberID]))
            }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-prices") {
                state.ingredientPrices = [
                    IngredientPrice(productName: "Йогурт греческий", packagePrice: 14, packageQuantity: 500, packageUnit: "г", currency: "ILS"),
                    IngredientPrice(productName: "Ягоды", packagePrice: 20, packageQuantity: 250, packageUnit: "г", currency: "ILS"),
                    IngredientPrice(productName: "Грецкие орехи", packagePrice: 32, packageQuantity: 250, packageUnit: "г", currency: "ILS"),
                    IngredientPrice(productName: "Корица", packagePrice: 5, packageQuantity: 50, packageUnit: "г", currency: "ILS")
                ]
            }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-courses"),
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let data = try? Data(contentsOf: directory.appendingPathComponent("course-qa.json")),
               let fixtures = try? JSONDecoder().decode([LadCourse].self, from: data), !fixtures.isEmpty {
                courses = fixtures
                state.activeCourseIDs = Set(fixtures.map(\.id))
            }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-drinks") {
                state.slots[0].setBeverages([CourseBeverages.waterID, "course-drink-tea"], manuallySelected: true)
            }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-family") {
                func person(_ id: String, _ name: String, age: Int, goal: String) -> FamilyMember {
                    FamilyMember(id: id, name: name, goal: goal, portion: 1, allergies: [], ageYears: age)
                }
                let names = L10n.languageCode == "en" ? ["Maria", "Sergey", "Ester", "Beatrice"] :
                    L10n.languageCode == "uk" ? ["Марія", "Сергій", "Естер", "Беатріс"] : ["Мария", "Сергей", "Естер", "Беатрис"]
                state.members = [person("maria", names[0], age: 35, goal: "Снижение"),
                                 person("sergey", names[1], age: 39, goal: "Без цели по весу"),
                                 person("ester", names[2], age: 10, goal: "Без цели по весу"),
                                 person("bea", names[3], age: 5, goal: "Без цели по весу")]
                state.selectedMemberID = "maria"
                for index in state.slots.indices { state.slots[index].memberIDs = state.members.map(\.id) }
            }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-profile") {
                state.members[0].ageYears = 30
                state.members[0].heightCm = 165
                state.members[0].weightKg = 60
                state.members[0].allergies = ["Молоко", "Орехи"]
                state.members[0].preferredVitaminKeys = ["vitamin_c", "vitamin_d"]
                state.members[0].automaticPortions = true
                state.members[0].energySex = .female
                state.members[0].energyActivity = .inactive
                state.members[0].energyContext = .standard
            }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-diary") ||
               ProcessInfo.processInfo.arguments.contains("--screenshot-entry") ||
               ProcessInfo.processInfo.arguments.contains("--screenshot-ready") {
                let recipe = Recipe.all.first { $0.id == "pancakes" } ?? Recipe.all[0]
                let prepared = Date.now.addingTimeInterval(-86400)
                var food = DiaryFood(recipe: recipe, servings: 1.25)
                let batch = PreparedDish(id: "qa-batch", food: DiaryFood(recipe: recipe, servings: 1), totalServings: 3,
                                         preparedAt: prepared, useBy: Date.now.addingTimeInterval(86400))
                food.preparedDishID = batch.id; food.preparation = .microwave; food.actualWeightGrams = 180
                state.preparedDishes = [batch]
                state.diaryEntries = [DiaryEntry(memberID: state.members[0].id, memberName: state.members[0].name,
                                                eatenAt: Date.now.addingTimeInterval(-3600), mealKind: 1, foods: [food])]
                state.selectedMemberID = state.members[0].id
            }
            if ProcessInfo.processInfo.arguments.contains("--empty-courses") {
                state.activeCourseIDs = []
            }
            if ProcessInfo.processInfo.arguments.contains("--screenshot-weight") {
                state.weightEntries = (0..<24).map { index in
                    WeightEntry(id: "demo-weight-\(index)", memberID: state.members[0].id,
                                measuredAt: Date().addingTimeInterval(Double(index - 23) * 86400),
                                kilograms: 64.2 - Double(index) * 0.055 + [0.0, 0.18, -0.12, 0.06][index % 4])
                }
            }
            return
        }
        #endif
        let persisted: Data?
        if ReleasePolicy.isStoreRelease {
            do {
                try LocalWeekArchive.protectExistingArchives()
                if let legacyBackup = UserDefaults.standard.data(forKey: "lad-unreadable-state-backup") {
                    try LocalWeekArchive.saveUnreadable(legacyBackup, accountID: localAccountID)
                    UserDefaults.standard.removeObject(forKey: "lad-unreadable-state-backup")
                }
                persisted = try LocalPersonalFile.read() ?? UserDefaults.standard.data(forKey: "lad-demo-v3")
            }
            catch { persisted = nil; protectedStateReadFailed = true }
        } else { persisted = UserDefaults.standard.data(forKey: "lad-demo-v3") }
        if let data = persisted,
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
        } else if let unreadable = persisted {
            do {
                try LocalWeekArchive.saveUnreadable(unreadable, accountID: localAccountID)
            } catch {
                if ReleasePolicy.isStoreRelease { protectedStateReadFailed = true }
                else { UserDefaults.standard.set(unreadable, forKey: "lad-unreadable-state-backup") }
            }
            state = .initial()
            storageWarning = L10n.text("Старые данные не удалось прочитать. Они сохранены для восстановления; показан новый демо-план.")
        } else {
            state = .initial(selectAllAvailableCourses: true)
        }
        if protectedStateReadFailed {
            storageWarning = L10n.text("Личные данные сейчас недоступны. Разблокируйте iPhone и заново откройте приложение. Сохранённый файл не изменён.")
        }
        // Older installs had an implicit demo source. Record it explicitly so an empty
        // course selection is never confused with permission to use every recipe.
        state.activeCourseIDs = CourseAliases.canonical(state.activeCourseIDs ?? [CourseAliases.mediterranean])
        if let saved = state.mealSchedule,
           saved.breakfastEnds == 11 * 60, saved.lunchEnds == 16 * 60, saved.dinnerEnds == 22 * 60,
           saved.snackMinute == nil {
            state.mealSchedule = .standard
        }
        state.migrateLaunchMenu(currentDay: currentDay)
        state.migratePortionRules()
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
        // Keep existing lot IDs, quantities and expiry dates while migrating
        // household units. This is idempotent across subsequent app launches.
        state.pantryItems = state.pantryItems?.map(IngredientMeasures.normalized)
        // Only replace the untouched three-dishes-every-day demo, never a person's edited plan.
        let oldPattern = state.slots.count == 21 && state.slots.allSatisfy { slot in
            slot.recipeID == (slot.kind == 0 ? "pancakes" : (slot.kind == 1 ? "soup" : "salmon"))
        }
        if oldPattern && state.activeCourseIDs?.contains(CourseAliases.mediterranean) == true {
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
    var allRecipes: [Recipe] { recipeIndex.recipes }
    var recipesByID: [String: Recipe] { recipeIndex.byID }
    private var recipeIndex: (recipes: [Recipe], visible: [Recipe], byID: [String: Recipe]) {
        if let recipeCache, recipeCache.revision == recipeSourceRevision {
            return (recipeCache.recipes, recipeCache.visible, recipeCache.byID)
        }
        let recipes = mergedRecipes()
        let visible = recipes.filter { !RecipeAliases.isLegacy($0.id) }
        let byID = PersonalPortions.recipeIndex(recipes)
        recipeCache = (recipeSourceRevision, recipes, visible, byID)
        return (recipes, visible, byID)
    }
    private func mergedRecipes() -> [Recipe] {
        var seen = Set<String>()
        let sourceCourses = courses.filter(\.usesWeightMenuRules)
        let sourceMeals = Set(sourceCourses.flatMap(\.recipeIDs))
        var sourceKinds: [String: Set<Int>] = [:]
        for course in sourceCourses {
            for id in course.breakfastRecipeIDs ?? [] { sourceKinds[id, default: []].insert(0) }
            for pair in course.suggestedPairs ?? [] {
                sourceKinds[pair.lunchRecipeID, default: []].insert(1)
                if let id = pair.dinnerRecipeID { sourceKinds[id, default: []].insert(2) }
                for id in pair.lunchExtraRecipeIDs ?? [] { sourceKinds[id, default: []].insert(1) }
                for id in pair.dinnerExtraRecipeIDs ?? [] { sourceKinds[id, default: []].insert(2) }
            }
        }
        return (catalogueRecipes + Recipe.all + privateRecipes + CourseBeverages.all + CourseSnacks.all)
            .filter { seen.insert($0.id).inserted }
            .map { recipe in
                let rawID = recipe.id.replacingOccurrences(of: "private:", with: "")
                if let kinds = sourceKinds[rawID] ?? sourceKinds[recipe.id] {
                    var corrected = recipe
                    corrected.mealKinds = kinds.sorted()
                    return corrected
                }
                // The source leaves breakfast open. Earlier imports added a
                // breakfast tag to some of its dinner recipes without a source recipe.
                guard (sourceMeals.contains(rawID) || sourceMeals.contains(recipe.id)),
                      recipe.mealKinds.contains(0), recipe.mealKinds.contains(where: { [1, 2].contains($0) }) else { return recipe }
                var corrected = recipe
                corrected.mealKinds.removeAll { $0 == 0 }
                return corrected
            }
    }
    var visibleRecipes: [Recipe] { recipeIndex.visible }
    var activeCourseIDs: Set<String> { CourseAliases.canonical(state.activeCourseIDs ?? []) }
    var selectedCourses: [LadCourse] { courses.filter { activeCourseIDs.contains($0.id) } }
    var courseRuleWarnings: [CourseRuleWarning] {
        CourseRuleEngine.visibleWarnings(courses: selectedCourses, slots: state.slots, recipes: allRecipes,
                                         schedule: mealSchedule, skippedIDs: state.skippedSlotIDs ?? [])
    }
    var hasSelectedCourses: Bool { !selectedCourses.isEmpty }
    private var weightPlanningCourse: LadCourse? { selectedCourses.first(where: \.usesWeightMenuRules) }
    private var activeCourseRecipeIDs: Set<String> {
        let key = "\(recipeSourceRevision)|\(activeCourseIDs.sorted().joined(separator: ","))"
        if let courseRecipeCache, courseRecipeCache.key == key { return courseRecipeCache.ids }
        let existing = recipesByID
        var ids = Set(selectedCourses.flatMap(\.recipeIDs).map { id in
            existing[id] != nil ? id : "private:\(id)"
        })
        if !selectedCourses.isEmpty { ids.formUnion(CourseBeverages.all.map(\.id)) }
        if selectedCourses.contains(where: \.isCombinedDefaultMenu) { ids.formUnion(CourseSnacks.all.map(\.id)) }
        courseRecipeCache = (key, ids)
        return ids
    }
    private func allowsMealKind(_ recipe: Recipe, for slot: MealSlot) -> Bool {
        if isFreeChoiceBreakfast(slot), weightPlanningCourse?.isCombinedDefaultMenu != true { return true }
        return (recipesByID[recipe.id] ?? recipe).mealKinds.contains(slot.kind)
    }
    func isFreeChoiceBreakfast(_ slot: MealSlot) -> Bool {
        slot.kind == 0 && weightPlanningCourse != nil
    }
    private func isAllowedBySelectedCourses(_ recipeID: String, for slot: MealSlot) -> Bool {
        isSelectedCourseRecipe(recipeID) ||
            (isFreeChoiceBreakfast(slot) && visibleRecipes.contains { $0.id == recipeID })
    }
    func isOutsideSelectedCourses(_ recipeID: String, for slot: MealSlot? = nil) -> Bool {
        if let slot { return !isAllowedBySelectedCourses(recipeID, for: slot) }
        return !isSelectedCourseRecipe(recipeID)
    }
    func isSelectedCourseRecipe(_ recipeID: String) -> Bool {
        activeCourseRecipeIDs.contains(recipeID)
    }
    func courseSourceLabel(for recipeID: String) -> String {
        if CourseSnacks.all.contains(where: { $0.id == recipeID }) { return L10n.text("Перекус по желанию") }
        let normalized = recipeID.hasPrefix("private:") ? String(recipeID.dropFirst("private:".count)) : recipeID
        let matches = courses.filter { $0.recipeIDs.contains(normalized) || $0.recipeIDs.contains(recipeID) }
        if matches.isEmpty { return L10n.text("Без курса") }
        return L10n.format("Курс: %@", matches.map(\.title).joined(separator: ", "))
    }
    func courseDraftIssue(_ recipe: Recipe, for requestedSlot: MealSlot) -> String? {
        guard let slot = state.slots.first(where: { $0.id == requestedSlot.id }) else {
            return L10n.text("Приём больше не найден в плане.")
        }
        guard isAllowedBySelectedCourses(recipe.id, for: slot), allowsMealKind(recipe, for: slot),
              !recipe.isUnavailable, !recipe.ingredients.isEmpty, !recipe.steps.isEmpty else {
            return L10n.text("Блюдо не подходит для этого приёма выбранного курса.")
        }
        let people = participating(slot)
        guard !people.isEmpty else { return L10n.text("В этом приёме никто не участвует.") }
        let incompatible = people.filter { AllergenMatching.conflicts(selected: $0.allergies, recipe: recipe.knownAllergens) }
        if !incompatible.isEmpty {
            return L10n.text("Блюдо противоречит ограничениям участников.")
        }
        if recipe.hasUnspecifiedAllergenComposition && people.contains(where: { !$0.allergies.isEmpty }) {
            return L10n.text("Для этих ограничений выберите блюдо с полным составом.")
        }
        return nil
    }
    func chooserRecipes(for requestedSlot: MealSlot, adding: Bool = false) -> [Recipe] {
        guard let slot = state.slots.first(where: { $0.id == requestedSlot.id }) else { return [] }
        return eligibleRecipes(for: slot, includeSides: adding, automaticSelection: false)
    }
    #if DEBUG || LAD_TESTING
    func replaceCatalogForTesting(recipes: [Recipe], courses: [LadCourse]) {
        catalogueRecipes = recipes
        self.courses = courses
        catalogRevision += 1
    }
    #endif
    func toggleCourse(_ id: String) {
        let id = CourseAliases.canonical([id]).first ?? id
        guard courses.contains(where: { $0.id == id }) else { return }
        var next = state
        var selected = CourseAliases.canonical(next.activeCourseIDs ?? [])
        let removing = !selected.insert(id).inserted
        if removing {
            selected.remove(id)
            clearUnselectedMeals(in: &next, selected: selected)
        }
        next.activeCourseIDs = selected
        state = next
        if maintainsDayMenu { fillTodayMenu() }
    }
    func selectAllCourses() {
        var next = state
        next.activeCourseIDs = Set(courses.map(\.id))
        state = next
        if maintainsDayMenu { fillTodayMenu() }
    }
    func deselectAllCourses() {
        var next = state
        next.activeCourseIDs = []
        clearUnselectedMeals(in: &next, selected: [])
        state = next
        if maintainsDayMenu { fillTodayMenu() }
    }
    private func clearUnselectedMeals(in next: inout DemoState, selected: Set<String>) {
        let existing = Set(allRecipes.map(\.id))
        var allowed = Set(courses.filter { selected.contains($0.id) }.flatMap(\.recipeIDs).map { recipeID in
            existing.contains(recipeID) ? recipeID : "private:\(recipeID)"
        })
        if !selected.isEmpty { allowed.formUnion(CourseBeverages.all.map(\.id)) }
        let freeBreakfast = selected.contains("weight-week-pilot") && courses.contains { $0.id == "weight-week-pilot" }
        for index in next.slots.indices {
            let slot = next.slots[index]
            guard !next.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else { continue }
            let slotAllowed = freeBreakfast && slot.kind == 0 ? existing : allowed
            if !slotAllowed.contains(slot.recipeID) {
                next.slots[index].recipeID = Recipe.unplanned.id
                next.slots[index].recipeChosenManually = false
            }
            next.slots[index].extraRecipeIDs = (slot.extraRecipeIDs ?? []).filter { slotAllowed.contains($0) }
            if selected.isEmpty || next.slots[index].recipeID == Recipe.unplanned.id {
                next.slots[index].extraRecipeIDs = []
                next.slots[index].setBeverages([])
            }
        }
    }
    var outsideFutureSlotCount: Int {
        state.slots.filter { slot in
            slot.day >= currentDay && slot.recipeID != Recipe.unplanned.id &&
            !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) &&
            slot.allRecipeIDs.contains(where: { isOutsideSelectedCourses($0, for: slot) })
        }.count
    }
    func clearFutureDishesOutsideCourses() {
        var next = state
        for index in next.slots.indices {
            let slot = next.slots[index]
            guard slot.day >= currentDay, slot.recipeID != Recipe.unplanned.id,
                  !next.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) else { continue }
            if isOutsideSelectedCourses(slot.recipeID, for: slot) {
                next.slots[index].recipeID = Recipe.unplanned.id
                next.slots[index].recipeChosenManually = false
            }
            next.slots[index].extraRecipeIDs = (slot.extraRecipeIDs ?? []).filter { !isOutsideSelectedCourses($0, for: slot) }
            if !hasSelectedCourses || next.slots[index].recipeID == Recipe.unplanned.id {
                next.slots[index].extraRecipeIDs = []
                next.slots[index].setBeverages([])
            }
        }
        if next.slots.map(\.recipeID) != state.slots.map(\.recipeID) ||
           next.slots.map(\.extraRecipeIDs) != state.slots.map(\.extraRecipeIDs) ||
           next.slots.map(\.selectedBeverageIDs) != state.slots.map(\.selectedBeverageIDs) { state = next }
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
        let purchaseProof = AppPurchases.shared.catalogProof
        courseCatalogStatus = L10n.text("Загружаем…")
        do {
            let snapshot = try await LaunchCatalogAccess.fetch()
            guard session == privateSessionRevision, purchaseProof == AppPurchases.shared.catalogProof else { return }
            catalogueRecipes = snapshot.recipes
            courses = snapshot.courses.filter { $0.id != "lad-starter" }
            var selected = activeCourseIDs
            if courses.contains(where: \.isCombinedDefaultMenu), selected.remove("weight-week-pilot") != nil {
                selected.insert(CourseAliases.mediterranean)
            }
            let available = Set(snapshot.recipes.map(\.id))
            var migrated = state
            for index in migrated.slots.indices {
                func migratedID(_ id: String) -> String {
                    let raw = id.replacingOccurrences(of: "private:", with: "")
                    return available.contains(raw) ? raw : id
                }
                migrated.slots[index].recipeID = migratedID(migrated.slots[index].recipeID)
                migrated.slots[index].extraRecipeIDs = migrated.slots[index].extraRecipeIDs?.map(migratedID)
            }
            if migrated.slots.map(\.allRecipeIDs) != state.slots.map(\.allRecipeIDs) { state = migrated }
            let remaining = selected.intersection(Set(courses.map(\.id)))
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
    func returnToFreeCatalog() {
        catalogueRecipes = Recipe.launchRecipes
        courses = CourseCatalogAccess.bundledCourses
        catalogRevision += 1
    }
    var pantry: [PantryItem] { (state.pantryItems ?? []).map(IngredientMeasures.normalized) }
    var mealSchedule: MealSchedule { state.planningSchedule }
    func mealCutoffText(for kind: Int) -> String {
        let minute = mealSchedule.endMinute(for: kind)
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }
    var planRequirements: PlanRequirements {
        let key = "\(stateRevision)|\(recipeSourceRevision)|\(now.timeIntervalSinceReferenceDate)"
        if let planCache, planCache.key == key { return planCache.value }
        let value = resolveCurrentPlan()
        planCache = (key, value)
        return value
    }
    private func resolveCurrentPlan() -> PlanRequirements {
        let effectiveSlots = hasSelectedCourses ? state.slots : state.slots.map { slot in
            var empty = slot
            empty.recipeID = Recipe.unplanned.id
            empty.extraRecipeIDs = []
            empty.setBeverages([])
            return empty
        }
        return PlanningCore.resolvePlan(slots: effectiveSlots, members: state.members, recipes: allRecipes,
                                 pantry: pantry, startDate: state.startDate, now: now,
                                 eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                 schedule: mealSchedule, preparedDishes: state.preparedDishes ?? [], diary: diary,
                                 recipesByID: recipesByID)
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
                                        schedule: mealSchedule, preparedDishes: state.preparedDishes ?? [], diary: diary).slots[slot.id]
    }
    func requirements(for recipe: Recipe, addingTo slot: MealSlot) -> SlotRequirements? {
        var candidateSlots = state.slots
        guard let index = candidateSlots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        candidateSlots[index].extraRecipeIDs = (candidateSlots[index].extraRecipeIDs ?? []) + [recipe.id]
        return PlanningCore.resolvePlan(slots: candidateSlots, members: state.members, recipes: allRecipes,
                                        pantry: pantry, startDate: state.startDate, now: now,
                                        eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                        schedule: mealSchedule, preparedDishes: state.preparedDishes ?? [], diary: diary).slots[slot.id]
    }
    func availabilityTitle(for slot: MealSlot) -> String {
        if slot.recipeID == Recipe.unplanned.id { return L10n.text("Нет блюда · выберите курс в каталоге") }
        return availabilityTitle(requirements(for: slot), inventoryEmpty: planRequirements.inventoryEmpty)
    }
    func availabilityTitle(for recipe: Recipe, replacing slot: MealSlot) -> String {
        availabilityTitle(requirements(for: recipe, replacing: slot), inventoryEmpty: pantry.isEmpty)
    }
    func availabilityTitle(for recipe: Recipe, addingTo slot: MealSlot) -> String {
        availabilityTitle(requirements(for: recipe, addingTo: slot), inventoryEmpty: pantry.isEmpty)
    }
    private func availabilityTitle(_ result: SlotRequirements?, inventoryEmpty: Bool) -> String {
        guard let result else { return L10n.text("Наличие уточняется") }
        switch result.availability {
        case .past: return L10n.text("Время приёма прошло")
        case .eaten: return L10n.text("Отмечено как съеденное")
        case .skipped: return L10n.text("Приём пропущен · продукты освобождены")
        case .noParticipants: return L10n.text("Никто не участвует")
        case .unavailable: return L10n.text("Рецепт недоступен — покупки неполные")
        case .needsReview: return L10n.text("Уточните количества ингредиентов")
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
    /// Shortage or a blocked meal, for the dish card.
    func mealCardNotice(for slot: MealSlot) -> String? {
        guard slot.recipeID != Recipe.unplanned.id else { return nil }
        return mealCardNotice(requirements(for: slot), inventoryEmpty: planRequirements.inventoryEmpty)
    }
    func mealCardNotice(for recipe: Recipe, replacing slot: MealSlot) -> String? {
        mealCardNotice(requirements(for: recipe, replacing: slot), inventoryEmpty: pantry.isEmpty)
    }
    func mealCardNotice(for recipe: Recipe, addingTo slot: MealSlot) -> String? {
        mealCardNotice(requirements(for: recipe, addingTo: slot), inventoryEmpty: pantry.isEmpty)
    }
    private func mealCardNotice(_ result: SlotRequirements?, inventoryEmpty: Bool) -> String? {
        guard let result else { return nil }
        switch result.availability {
        case .past, .eaten, .active:
            break
        case .skipped:
            return L10n.text("Приём пропущен · продукты освобождены")
        case .noParticipants:
            return L10n.text("Никто не участвует")
        case .unavailable:
            return L10n.text("Рецепт недоступен — покупки неполные")
        case .needsReview:
            return L10n.text("Уточните количества ингредиентов")
        }
        guard result.availability == .active, !inventoryEmpty, !result.isReady else { return nil }
        let questions = result.ingredients.filter { $0.required == nil || $0.uncertain }.count
        let shortages = result.shortageCount
        if questions > 0 && shortages == 0 { return L10n.format("Нужно уточнить %d поз.", questions) }
        if questions > 0 { return L10n.format("Докупить %d поз. · уточнить %d", shortages, questions) }
        if shortages > 0 { return L10n.format("Докупить %d поз.", shortages) }
        return nil
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
        let ingredient = IngredientMeasures.normalized(ingredient)
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
        let ingredient = IngredientMeasures.normalized(Ingredient(name: name, amount: 1, unit: unit, category: ""))
        return pantry.first { PlanningCore.key($0.name, $0.unit) == PlanningCore.key(ingredient.name, ingredient.unit) }
    }
    func savePantryItem(_ item: PantryItem) {
        let item = IngredientMeasures.normalized(item)
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
    func suggestedSlot() -> MealSlot { suggestedSlot(on: selectedDay) }
    func suggestedSlot(on day: Int) -> MealSlot {
        if day != currentDay { return slot(day, 0) }
        let eatenKinds = Set((0..<3).filter { kind in
            let candidate = slot(currentDay, kind)
            let participants = participating(candidate)
            return !participants.isEmpty && participants.allSatisfy { state.eatenIDs.contains("\(candidate.id)-\($0.id)") }
        })
        if let kind = mealKinds(on: currentDay, forMember: currentMember.id).first(where: { kind in
            let candidate = slot(currentDay, kind)
            return !eatenKinds.contains(kind) && !isSkipped(candidate) &&
                !isEaten(candidate) && MealTiming.minuteOfDay(now) < mealSchedule.endMinute(for: kind)
        }) {
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
        let dish = recipesByID[slot.recipeID] ?? .unavailable
        return dish.isBeverage ? .unplanned : dish
    }
    func recipes(_ slot: MealSlot) -> [Recipe] {
        guard !recipe(slot).isUnplanned else { return [] }
        return slot.allRecipeIDs.compactMap { id in
            guard id != Recipe.unplanned.id else { return nil }
            return recipesByID[id] ?? .unavailable
        }
    }
    func participating(_ slot: MealSlot) -> [FamilyMember] { state.members.filter { slot.memberIDs.contains($0.id) } }
    func toggleEaten(_ slot: MealSlot) {
        guard slot.memberIDs.contains(state.selectedMemberID), !recipe(slot).isUnplanned else { return }
        let key = "\(slot.id)-\(state.selectedMemberID)"
        if state.eatenIDs.contains(key) {
            if let entry = diaryEntry(for: slot) { removeDiaryEntry(entry) }
            else { state.eatenIDs.remove(key) }
        } else { saveDiaryEntry(diaryDraft(for: slot)) }
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
    /// Inputs that stay the same while one slot's candidates are ranked.
    private struct RankingContext {
        /// Stock left after every meal before this one.
        let pantryBefore: [PantryItem]
        let diary: [DiaryEntry]
        let schedule: MealSchedule
        let skipped: Set<String>
        let byID: [String: Recipe]
        let people: [FamilyMember]
        let ruleWarningsBefore: [String: Int]?
    }
    private func rankingContext(slot: MealSlot, plannedSlots: [MealSlot]) -> RankingContext {
        let rules: [String: Int]? = selectedCourses.contains(where: { !($0.rules ?? []).isEmpty })
            ? Dictionary(CourseRuleEngine.warnings(courses: selectedCourses, slots: plannedSlots, recipes: allRecipes,
                                                   schedule: mealSchedule, skippedIDs: state.skippedSlotIDs ?? [])
                .filter { !$0.isConflict }.map { ($0.id, $0.excess) }, uniquingKeysWith: { first, _ in first })
            : nil
        return RankingContext(pantryBefore: pantryBefore(slot, plannedSlots: plannedSlots), diary: diary,
                              schedule: mealSchedule, skipped: state.skippedSlotIDs ?? [],
                              byID: recipesByID, people: participating(slot), ruleWarningsBefore: rules)
    }
    private func pantryBefore(_ slot: MealSlot, plannedSlots: [MealSlot]) -> [PantryItem] {
        let stock = pantry
        guard !stock.isEmpty else { return [] }
        return PlanningCore.resolvePlan(slots: plannedSlots, members: state.members, recipes: allRecipes,
                                        pantry: stock, startDate: state.startDate, now: now,
                                        eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                        schedule: mealSchedule, preparedDishes: state.preparedDishes ?? [], diary: diary,
                                        recipesByID: recipesByID, stopBeforeSlotID: slot.id).freePantry
    }
    private func score(_ recipe: Recipe, slot: MealSlot, usedToday: Set<String>, plannedSlots: [MealSlot],
                       context: RankingContext) -> Double {
        var candidateSlots = plannedSlots
        guard let index = candidateSlots.firstIndex(where: { $0.id == slot.id }) else { return -.infinity }
        candidateSlots[index].recipeID = recipe.id
        let resolution = PlanningCore.resolvePlan(slots: candidateSlots, members: state.members, recipes: allRecipes,
                                                  pantry: context.pantryBefore, startDate: state.startDate, now: now,
                                                  eatenIDs: state.eatenIDs, skippedIDs: context.skipped,
                                                  schedule: context.schedule, preparedDishes: state.preparedDishes ?? [],
                                                  diary: context.diary, recipesByID: context.byID, onlySlotID: slot.id)
        guard let match = resolution.slots[slot.id],
              match.availability == .active || match.availability == .needsReview ||
              (slot.day == currentDay && match.availability == .past) else { return -.infinity }
        var value = match.isReady ? (slot.day == currentDay ? 1_000.0 : 80.0) : 0
        if match.availability == .needsReview { value -= 100 }
        value += Double(match.ingredients.filter(\.isReady).count) * 5
        value -= Double(match.shortageCount) * 18
        value -= Double(match.ingredients.filter { $0.required == nil || $0.uncertain }.count) * 25
        if usedToday.contains(recipe.id) { value -= 35 }
        // Dishes that would warn someone at this meal go last, but stay possible.
        value -= Double(DietCautions.cautions(for: [recipe], people: participating(slot)).count) * 2_000
        if weightPlanningCourse != nil {
            value -= CourseWeekPreferences.recentRepeatPenalty(recipeID: recipe.id, day: slot.day, slots: plannedSlots)
        }
        value += Double(context.people.filter { state.favorites.contains("\($0.id)|\(recipe.id)") }.count * 5)
        // Source-specific lunch guidance is a small preference, never a hard
        // dietary constraint or an extra ingredient silently added to a dish.
        if let course = weightPlanningCourse, slot.kind == 1,
           course.recipeIDs.contains(recipe.id.replacingOccurrences(of: "private:", with: "")) {
            let names = recipe.ingredients.map { ProductNames.canonical($0.name) }
            if names.contains(where: { $0.contains("гречк") || $0.contains("рис") }) { value += 12 }
            if names.contains(where: { $0.contains("томат") || $0.contains("огур") || $0.contains("перец") }) { value += 3 }
        }
        if slot.kind == 2, let lunch = candidateSlots.first(where: { $0.day == slot.day && $0.kind == 1 }) {
            value += CourseWeekPreferences.pairingBonus(
                course: weightPlanningCourse,
                lunchID: lunch.recipeID, dinnerID: recipe.id)
        }
        if let before = context.ruleWarningsBefore {
            let after = Dictionary(uniqueKeysWithValues: CourseRuleEngine.warnings(
                courses: selectedCourses, slots: candidateSlots, recipes: allRecipes, schedule: mealSchedule,
                skippedIDs: state.skippedSlotIDs ?? []).filter { !$0.isConflict }.map { ($0.id, $0.excess) })
            for id in Set(before.keys).union(after.keys) {
                let delta = (after[id] ?? 0) - (before[id] ?? 0)
                if delta > 0 { value -= Double(delta) * 75 }
                if delta < 0 { value += Double(-delta) * 20 }
            }
        }
        if slot.kind != CourseSnacks.kind, let kcal = recipe.kcal {
            for person in context.people where (person.ageYears ?? 0) >= 18 {
                if let target = PersonalPortions.energyTarget(person) {
                    value -= abs(Double(kcal) * person.portion - target / 3) / 65
                }
            }
        }
        // A user's vitamin focus is a ranking preference across the union of
        // selected courses, not a clinical intake target or a hard rule.
        for person in context.people where (person.ageYears ?? 0) >= 18 {
            for key in person.preferredVitaminKeys ?? [] where key.hasPrefix("vitamin_") {
                guard let nutrient = recipe.nutrients[key], nutrient.amount > 0,
                      nutrient.coverage >= 0.75 else { continue }
                let alreadyCovered = plannedSlots.contains { other in
                    other.day == slot.day && other.id != slot.id &&
                    other.allRecipeIDs.contains { id in
                        context.byID[id]?.nutrients[key].map {
                            $0.amount > 0 && $0.coverage >= 0.75
                        } == true
                    }
                }
                value += alreadyCovered ? 1.5 : 5
            }
        }
        value -= Double(recipe.minutes) / 100
        value += weightGapScore(recipe, slot: slot, plannedSlots: plannedSlots)
        return value
    }
    /// Prefer the dish that covers more of what this person's weight still leaves short.
    /// Likes, dislikes and recent meals are handled around this term. It does not
    /// replace a dish the person chose.
    private func weightGapScore(_ recipe: Recipe, slot: MealSlot, plannedSlots: [MealSlot]) -> Double {
        var total = 0.0
        for person in participating(slot) {
            guard let targets = WeightGap.targets(for: person) else { continue }
            let taken = nutrientIntake(for: person, day: slot.day, slots: plannedSlots, excluding: slot.id)
            let offered = servingIntake(of: recipe, portion: person.portion)
            total += WeightGap.closure(offered: offered, remaining: taken.gap(against: targets), targets: targets) * 120
        }
        return total
    }
    private func nutrientIntake(for person: FamilyMember, day: Int, slots: [MealSlot], excluding slotID: String) -> WeightGap.Intake {
        var total = WeightGap.Intake()
        for meal in slots where meal.day == day && meal.id != slotID && meal.memberIDs.contains(person.id) {
            if state.skippedSlotIDs?.contains(meal.id) == true { continue }
            for id in meal.allRecipeIDs where id != Recipe.unplanned.id {
                guard let dish = recipesByID[id], !dish.isUnplanned, !dish.isUnavailable else { continue }
                total = total.adding(servingIntake(of: dish, portion: person.portion))
            }
        }
        return total
    }
    private func servingIntake(of recipe: Recipe, portion: Double) -> WeightGap.Intake {
        func amount(_ key: String, fallback: Double = 0) -> Double {
            (recipe.nutrients[key]?.amount ?? fallback) * portion
        }
        return WeightGap.Intake(energy: Double(recipe.kcal ?? 0) * portion,
                                protein: amount("protein", fallback: Double(recipe.protein ?? 0)),
                                fat: amount("fat"),
                                carbohydrate: amount("carbohydrate"),
                                fiber: amount("fiber"))
    }
    private func eligibleRecipes(for slot: MealSlot, limitingToCourses: Bool = true,
                                 includeSides: Bool = false, automaticSelection: Bool = true) -> [Recipe] {
        let people = participating(slot)
        let source = limitingToCourses && !isFreeChoiceBreakfast(slot) ? activeCourseRecipeIDs : nil
        let excluded = Set(people.flatMap { person in
            state.avoidedRecipesBySlot?["\(slot.id)|\(person.id)"] ?? []
        })
        return visibleRecipes.filter { recipe in
            guard (source == nil || source?.contains(recipe.id) == true),
                  !recipe.isBeverage, (includeSides || (!automaticSelection && isFreeChoiceBreakfast(slot)) || !recipe.isCourseSide),
                  allowsMealKind(recipe, for: slot), !excluded.contains(recipe.id),
                  (!automaticSelection || !isFreeChoiceBreakfast(slot) || recipe.mealKinds.contains(0)),
                  !people.contains(where: { state.dislikes?.contains("\($0.id)|\(recipe.id)") == true }) else { return false }
            if recipe.isPlanEligible { return incompatibility(slot, recipe: recipe) == nil }
            return limitingToCourses && courseDraftIssue(recipe, for: slot) == nil
        }
    }
    private func rankedRecipes(_ recipes: [Recipe], slot: MealSlot, usedToday: Set<String>,
                               plannedSlots: [MealSlot]) -> [Recipe] {
        var ranked: [(recipe: Recipe, value: Double)] = []
        let context = rankingContext(slot: slot, plannedSlots: plannedSlots)
        for recipe in recipes {
            let value = score(recipe, slot: slot, usedToday: usedToday, plannedSlots: plannedSlots, context: context)
            if value.isFinite { ranked.append((recipe, value)) }
        }
        ranked.sort { left, right in
            if left.value == right.value { return left.recipe.id < right.recipe.id }
            return left.value > right.value
        }
        return ranked.map(\.recipe)
    }
    private func beverageIssue(_ id: String, for slot: MealSlot) -> String? {
        guard let drink = CourseBeverages.all.first(where: { $0.id == id }) else {
            return L10n.text("Напиток недоступен.")
        }
        if drink.containsAlcoholIngredient, participating(slot).contains(where: { ($0.ageYears ?? 0) < 18 }) {
            return L10n.text("Алкогольный напиток нельзя назначить несовершеннолетнему или участнику без подтверждённого возраста.")
        }
        return incompatibility(slot, recipe: drink)
    }
    private func suggestedBeverages(for slot: MealSlot, foods: [Recipe], plannedSlots: [MealSlot]) -> [String] {
        guard !foods.isEmpty, foods.allSatisfy({ !$0.isUnavailable && !$0.isBeverage }) else { return [] }
        if slot.hasManualBeverages {
            return slot.selectedBeverageIDs.filter { beverageIssue($0, for: slot) == nil }
        }
        let names = Set(foods.flatMap(\.ingredients).map { $0.name.lowercased() })
        let animalOrEgg = names.contains { name in
            ["мяс", "фарш", "говя", "свин", "курин", "индей", "печень", "рыб", "кревет", "хек", "минтай", "скумбр", "яйц"].contains { name.contains($0) }
        }
        let hasDairy = foods.contains { $0.knownAllergens.contains("Молоко") }
        let hasFruit = names.contains { name in
            ["яблок", "апельсин", "киви", "слив", "чернослив", "мандари"].contains { name.contains($0) }
        }
        var recommended: Set<String> = [CourseBeverages.waterID, "course-drink-tea", "course-drink-coffee"]
        // Match the leaflet's drink groups to food, not the printed week/day.
        // Meat/fish/egg dinners stay with plain drinks; curd/fruit and vegetable
        // meals may have dairy or vegetable juice. This affects suggestions,
        // not a user's explicit choices or personal meal times.
        if slot.kind == 0 || !animalOrEgg {
            if hasDairy || hasFruit || slot.kind == 0 {
                recommended.formUnion(["course-drink-kefir", "course-drink-milk"])
            }
            if !hasFruit { recommended.insert("course-drink-tomato-juice") }
        }
        if let source = CourseBeverages.sourceRecommendations(for: foods[0]) {
            recommended = source
        }
        let people = participating(slot)
        let candidates = CourseBeverages.all.filter { drink in
            recommended.contains(drink.id) && drink.id != CourseBeverages.waterID &&
            !drink.containsAlcoholIngredient && beverageIssue(drink.id, for: slot) == nil &&
            (drink.id != "course-drink-coffee" || people.allSatisfy { ($0.ageYears ?? 0) >= 18 }) &&
            !people.contains { state.dislikes?.contains("\($0.id)|\(drink.id)") == true }
        }
        let preferred: [String] = slot.kind == 0
            ? ["course-drink-coffee", "course-drink-tea", "course-drink-kefir", "course-drink-milk", "course-drink-tomato-juice"]
            : slot.kind == 1
                ? ["course-drink-tomato-juice", "course-drink-tea", "course-drink-kefir", "course-drink-milk", "course-drink-coffee"]
                : ["course-drink-kefir", "course-drink-tea", "course-drink-tomato-juice", "course-drink-milk", "course-drink-coffee"]
        let stockBefore = candidates.isEmpty ? [] : pantryBefore(slot, plannedSlots: plannedSlots)
        func drinkScore(_ drink: Recipe) -> Double {
            var value = Double(5 - (preferred.firstIndex(of: drink.id) ?? 5)) * 8
            let repeats = plannedSlots.filter { other in
                other.id != slot.id && other.day == slot.day && other.kind < slot.kind &&
                other.selectedBeverageIDs.contains(drink.id)
            }.count
            value -= Double(repeats) * 18
            var candidateSlots = plannedSlots
            if let index = candidateSlots.firstIndex(where: { $0.id == slot.id }) {
                candidateSlots[index].recipeID = foods[0].id
                candidateSlots[index].extraRecipeIDs = foods.dropFirst().map(\.id)
                candidateSlots[index].setBeverages([CourseBeverages.waterID, drink.id])
            }
            let resolution = PlanningCore.resolvePlan(slots: candidateSlots, members: state.members, recipes: allRecipes,
                                                      pantry: stockBefore, startDate: state.startDate, now: now,
                                                      eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                                      schedule: mealSchedule, preparedDishes: state.preparedDishes ?? [], diary: diary,
                                                      recipesByID: recipesByID, onlySlotID: slot.id)
            let keys = Set(drink.ingredients.map(IngredientMeasures.normalized).map { PlanningCore.key($0.name, $0.unit) })
            let stocked = resolution.slots[slot.id]?.ingredients.filter { keys.contains($0.id) && $0.isReady }.count ?? 0
            value += Double(stocked) * 12
            value += Double(people.filter { state.favorites.contains("\($0.id)|\(drink.id)") }.count) * 10
            let mealKcal = foods.compactMap(\.kcal).reduce(0, +) + (drink.kcal ?? 0)
            for person in people where (person.ageYears ?? 0) >= 18 {
                if let target = PersonalPortions.energyTarget(person) {
                    value -= max(0, Double(mealKcal) * person.portion - target / 3) / 15
                }
                for key in person.preferredVitaminKeys ?? [] {
                    if let nutrient = drink.nutrients[key], nutrient.amount > 0, nutrient.coverage >= 0.75 { value += 5 }
                }
            }
            return value
        }
        let scores = Dictionary(candidates.map { ($0.id, drinkScore($0)) }, uniquingKeysWith: { first, _ in first })
        let companion = candidates.sorted {
            let a = scores[$0.id] ?? 0, b = scores[$1.id] ?? 0
            return a == b ? $0.id < $1.id : a > b
        }.first
        return [CourseBeverages.waterID] + (companion.map { [$0.id] } ?? [])
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
                if change.beverageChanged {
                    proposedSlots[index].setBeverages(change.nextBeverageIDs ?? [], manuallySelected: change.nextBeveragesManual)
                }
                if change.extrasChanged { proposedSlots[index].extraRecipeIDs = change.nextExtraRecipeIDs }
            }
        }
        let before = Dictionary(uniqueKeysWithValues: shoppingNeeds.map { ($0.id, $0) })
        let afterNeeds = PlanningCore.resolvePlan(slots: proposedSlots, members: state.members, recipes: allRecipes,
                                                  pantry: pantry, startDate: state.startDate, now: now,
                                                  eatenIDs: state.eatenIDs, skippedIDs: state.skippedSlotIDs ?? [],
                                                  schedule: mealSchedule, preparedDishes: state.preparedDishes ?? [], diary: diary).shoppingNeeds
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
        let ruleWarnings = CourseRuleEngine.visibleWarnings(courses: selectedCourses, slots: proposedSlots,
                                                            recipes: allRecipes, schedule: mealSchedule,
                                                            skippedIDs: state.skippedSlotIDs ?? [])
        return ReplanPreview(title: L10n.text(title), explanation: L10n.text(explanation), changes: changes, shoppingDelta: delta,
                             pendingAvoid: pendingAvoid, emptyMessage: L10n.text(emptyMessage), expectedRevision: stateRevision,
                             expectedCatalogRevision: catalogRevision, lateCorrectionSlotID: lateCorrectionSlotID,
                             outsideCourseSlotID: outsideCourseSlotID, lateCorrectionSlotIDs: lateCorrectionSlotIDs,
                             reviewRecipeIDs: reviewRecipeIDs, ruleWarnings: ruleWarnings)
    }
    /// Fill still-open meals for today and the rest of the week from likes,
    /// dislikes, earlier meals and the weight gap. A dish the person chose stays.
    /// This writes the plan directly.
    func fillTodayMenu(replacing forced: Set<String> = []) {
        guard hasSelectedCourses, state.hasValidMealSlots, !isFillingDayMenu else { return }
        isFillingDayMenu = true
        defer { isFillingDayMenu = false }
        let stamp = dayMenuStamp()
        var planned = state.slots
        var changed = false
        for day in currentDay..<7 {
        var used = Set<String>()
        for kind in mealKinds(on: day) {
            guard let index = planned.firstIndex(where: { $0.day == day && $0.kind == kind }) else { continue }
            let slot = planned[index]
            let eaten = state.eatenIDs.contains { $0.hasPrefix("\(slot.id)-") }
            let locked = slot.recipeChosenManually == true || eaten || isSkipped(slot) ||
                slot.memberIDs.isEmpty || isPastWindow(slot)
            if locked || (slot.recipeID != Recipe.unplanned.id && state.autoDayMenuStamp == stamp && !forced.contains(slot.id)) {
                if slot.recipeID != Recipe.unplanned.id {
                    used.insert(slot.recipeID)
                    used.formUnion(slot.extraRecipeIDs ?? [])
                }
                continue
            }
            let ranked = rankedRecipes(eligibleRecipes(for: slot).filter(\.isPlanEligible),
                                       slot: slot, usedToday: used, plannedSlots: planned)
            guard let choice = ranked.first else {
                if slot.recipeID != Recipe.unplanned.id { used.insert(slot.recipeID) }
                continue
            }
            used.insert(choice.id)
            planned[index].recipeID = choice.id
            planned[index].recipeChosenManually = false
            var extras: [String] = []
            if [1, 2].contains(kind), let course = weightPlanningCourse {
                let rawID = choice.id.replacingOccurrences(of: "private:", with: "")
                let lunchID = planned.first { $0.day == day && $0.kind == 1 }?
                    .recipeID.replacingOccurrences(of: "private:", with: "")
                let proposedIDs = (course.suggestedPairs ?? []).flatMap { pair -> [String] in
                    if kind == 1, pair.lunchRecipeID == rawID { return pair.lunchExtraRecipeIDs ?? [] }
                    if kind == 2, pair.dinnerRecipeID == rawID, pair.lunchRecipeID == lunchID {
                        return pair.dinnerExtraRecipeIDs ?? []
                    }
                    return []
                }
                if let extra = proposedIDs.compactMap({ id in
                    allRecipes.first { $0.id == id || $0.id == "private:\(id)" }
                }).first(where: { candidate in
                    !candidate.isBeverage && candidate.isPlanEligible && candidate.id != choice.id &&
                    !used.contains(candidate.id) && isSelectedCourseRecipe(candidate.id) &&
                    allowsMealKind(candidate, for: slot) && incompatibility(slot, recipe: candidate) == nil
                }) {
                    extras = [extra.id]
                    used.insert(extra.id)
                }
            }
            planned[index].extraRecipeIDs = extras
            let foods = [choice] + extras.compactMap { id in allRecipes.first { $0.id == id } }
            let drinks = suggestedBeverages(for: planned[index], foods: foods, plannedSlots: planned)
            planned[index].setBeverages(drinks, manuallySelected: slot.hasManualBeverages)
            changed = true
        }
        }
        var next = state
        next.slots = planned
        if next.autoDayMenuStamp != stamp {
            next.autoDayMenuStamp = stamp
            changed = true
        }
        if changed { state = next }
    }
    private func dayMenuStamp() -> String {
        let day = currentDay
        let people = state.members.map { member in
            [
                member.id,
                String(format: "%.1f", member.weightKg ?? -1),
                String(member.ageYears ?? -1),
                String(format: "%.0f", member.heightCm ?? -1),
                member.energySex?.rawValue ?? "",
                member.energyActivity?.rawValue ?? "",
                member.energyContext?.rawValue ?? "",
                String(member.dailyEnergyTarget ?? -1),
                member.automaticPortions == true ? "1" : "0",
                String(format: "%.2f", member.portion),
                (member.preferredVitaminKeys ?? []).sorted().joined(separator: "+")
            ].joined(separator: ":")
        }.sorted().joined(separator: "|")
        let history = state.slots.filter { $0.day < day }.map { "\($0.day)-\($0.kind):\($0.recipeID)" }.sorted().joined(separator: ",")
        return [
            String(Int(state.startDate.timeIntervalSince1970)),
            String(day),
            people,
            // Likes and dislikes are left out on purpose: a like must not
            // reshuffle the week, a dislike replaces only its own dish.
            (state.activeCourseIDs ?? []).sorted().joined(separator: ","),
            history
        ].joined(separator: "#")
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
            for kind in mealKinds(on: day) {
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
                    if slot.recipeID != Recipe.unplanned.id || !slot.selectedBeverageIDs.isEmpty || !(slot.extraRecipeIDs ?? []).isEmpty {
                        unmatched.append("\(dateLabel(day)) · \(kinds[kind])")
                        changes.append(PlannedChange(slotID: slot.id, previousID: slot.recipeID,
                                                     nextID: Recipe.unplanned.id,
                                                     previousBeverageIDs: slot.selectedBeverageIDs, nextBeverageIDs: [],
                                                     beverageChanged: !slot.selectedBeverageIDs.isEmpty,
                                                     previousBeveragesManual: slot.hasManualBeverages,
                                                     previousExtraRecipeIDs: slot.extraRecipeIDs, nextExtraRecipeIDs: [],
                                                     extrasChanged: !(slot.extraRecipeIDs ?? []).isEmpty))
                        if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) {
                            proposedSlots[index].recipeID = Recipe.unplanned.id
                            proposedSlots[index].setBeverages([])
                            proposedSlots[index].extraRecipeIDs = []
                        }
                        if isPastWindow(slot) { lateCorrectionIDs.insert(slot.id) }
                    }
                    continue
                }
                used.insert(choice.id)
                if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) { proposedSlots[index].recipeID = choice.id }
                var suggestedExtras = choice.id == slot.recipeID ? (slot.extraRecipeIDs ?? []) : []
                if suggestedExtras.isEmpty, [1, 2].contains(kind), let course = weightPlanningCourse {
                    let rawID = choice.id.hasPrefix("private:") ? String(choice.id.dropFirst("private:".count)) : choice.id
                    let lunchID = proposedSlots.first(where: { $0.day == day && $0.kind == 1 })
                        .map { $0.recipeID.replacingOccurrences(of: "private:", with: "") }
                    let proposedIDs = (course.suggestedPairs ?? []).flatMap { pair -> [String] in
                        if kind == 1, pair.lunchRecipeID == rawID { return pair.lunchExtraRecipeIDs ?? [] }
                        if kind == 2, pair.dinnerRecipeID == rawID, pair.lunchRecipeID == lunchID {
                            return pair.dinnerExtraRecipeIDs ?? []
                        }
                        return []
                    }
                    if let extra = proposedIDs.compactMap({ id in
                        allRecipes.first { $0.id == id || $0.id == "private:\(id)" }
                    }).first(where: { candidate in
                        !candidate.isBeverage && candidate.id != choice.id && !used.contains(candidate.id) &&
                        isSelectedCourseRecipe(candidate.id) && allowsMealKind(candidate, for: slot) &&
                        (candidate.isPlanEligible ? incompatibility(slot, recipe: candidate) == nil
                                                  : courseDraftIssue(candidate, for: slot) == nil)
                    }) {
                        suggestedExtras = [extra.id]
                        used.insert(extra.id)
                        if !extra.isPlanEligible { reviewIDs.insert(extra.id) }
                    }
                }
                if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) {
                    proposedSlots[index].extraRecipeIDs = suggestedExtras
                }
                let foods = [choice] + suggestedExtras.compactMap { id in allRecipes.first { $0.id == id } }
                let suggestedDrinks = suggestedBeverages(for: slot, foods: foods, plannedSlots: proposedSlots)
                if let index = proposedSlots.firstIndex(where: { $0.id == slot.id }) {
                    proposedSlots[index].setBeverages(suggestedDrinks, manuallySelected: slot.hasManualBeverages)
                }
                if choice.id != slot.recipeID || suggestedDrinks != slot.selectedBeverageIDs || suggestedExtras != (slot.extraRecipeIDs ?? []) {
                    changes.append(PlannedChange(slotID: slot.id, previousID: slot.recipeID, nextID: choice.id,
                                                 previousBeverageIDs: slot.selectedBeverageIDs, nextBeverageIDs: suggestedDrinks,
                                                 beverageChanged: suggestedDrinks != slot.selectedBeverageIDs,
                                                 previousBeveragesManual: slot.hasManualBeverages,
                                                 nextBeveragesManual: slot.hasManualBeverages,
                                                 previousExtraRecipeIDs: slot.extraRecipeIDs, nextExtraRecipeIDs: suggestedExtras,
                                                 extrasChanged: suggestedExtras != (slot.extraRecipeIDs ?? [])))
                    if isPastWindow(slot) { lateCorrectionIDs.insert(slot.id) }
                    if !choice.isPlanEligible { reviewIDs.insert(choice.id) }
                }
            }
        }
        var explanation = hasSelectedCourses
            ? L10n.text("Подбор использует только блюда выбранных курсов с подходящим тегом приёма пищи. Изменения появятся после подтверждения.")
            : L10n.text("Сопоставили продукты на всю неделю, даты готовки и ограничения участников. Если запасы не внесены, список покупок предварительный. Меню изменится только после подтверждения.")
        if weightPlanningCourse?.isCombinedDefaultMenu == true {
            explanation = L10n.text("Меню возьмётся из курса «Здоровое питание». Изменения появятся после подтверждения.")
        } else if weightPlanningCourse != nil {
            explanation = L10n.text("Завтрак — свободный выбор из доступного каталога. Автоматически предлагаем блюда с тегом завтрака; обед и ужин подбираем из выбранных курсов. Изменения появятся после подтверждения.")
        }
        if !reviewIDs.isEmpty {
            explanation += " " + L10n.text("Для расчёта покупок укажите недостающие количества ингредиентов.")
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
        let changes = choice.map { dish -> [PlannedChange] in
            let foods = [dish] + (slot.extraRecipeIDs ?? []).compactMap { id in allRecipes.first { $0.id == id } }
            let drinks = suggestedBeverages(for: slot, foods: foods, plannedSlots: state.slots)
            return [PlannedChange(slotID: slot.id, previousID: slot.recipeID, nextID: dish.id,
                                  previousBeverageIDs: slot.selectedBeverageIDs, nextBeverageIDs: drinks,
                                  beverageChanged: drinks != slot.selectedBeverageIDs,
                                  previousBeveragesManual: slot.hasManualBeverages, nextBeveragesManual: slot.hasManualBeverages)]
        } ?? []
        let selectedParticipates = slot.memberIDs.contains(state.selectedMemberID)
        let avoid = selectedParticipates ? choice.map { _ in AvoidedRecipe(slotID: slot.id, memberID: state.selectedMemberID, recipeID: slot.recipeID) } : nil
        let lateCorrection = isPastWindow(slot) ? slot.id : nil
        var explanation = lateCorrection == nil
            ? L10n.text("Замена только на этот приём.")
            : L10n.text("Можно заменить сегодня. Отметка о еде не появится.")
        if includeOutsideCourses && hasSelectedCourses {
            explanation = L10n.text("Блюдо может быть вне курса.") + " " + explanation
        }
        let reviewIDs: Set<String> = choice.map { $0.isPlanEligible ? [] : [$0.id] } ?? []
        if !reviewIDs.isEmpty {
            explanation += " " + L10n.text("Для расчёта покупок укажите недостающие количества ингредиентов.")
        }
        replanPreview = makePreview(title: L10n.format("Другое блюдо на %@", dateLabel(slot.day)),
                                    explanation: explanation,
                                    changes: changes, pendingAvoid: avoid, lateCorrectionSlotID: lateCorrection,
                                    outsideCourseSlotID: choice == nil && !includeOutsideCourses && hasSelectedCourses ? slot.id : nil,
                                    reviewRecipeIDs: reviewIDs,
                                    emptyMessage: includeOutsideCourses
                                        ? L10n.text("Подходящего блюда не нашлось и вне курса. Меню не меняется.")
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
                                                      schedule: mealSchedule, preparedDishes: state.preparedDishes ?? [], diary: diary).slots[slot.id]
                return (result?.shortageCount ?? .max) < (originalMatch?.shortageCount ?? .max)
            }) {
                changes.append(PlannedChange(slotID: slot.id, previousID: original.id, nextID: choice.id))
            }
        }
        replanPreview = makePreview(title: L10n.format("%@ закончился", L10n.text(ingredientName)), explanation: "Запас обновлён, покупки пересчитаны. Ниже — только возможные изменения будущего меню. Уже отмеченные съеденными блюда не меняются.", changes: changes)
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
                  (replacement.isUnplanned || (!replacement.isBeverage &&
                   allowsMealKind(replacement, for: next.slots[index]) &&
                   (replacement.isPlanEligible
                    ? incompatibility(next.slots[index], recipe: replacement) == nil
                    : preview.reviewRecipeIDs.contains(replacement.id) &&
                      courseDraftIssue(replacement, for: next.slots[index]) == nil))) else {
                replanPreview = makePreview(title: "План изменился", explanation: "Предложение больше не подходит текущему плану.",
                                            changes: [], emptyMessage: "Подберите меню заново; ничего не было изменено.")
                return
            }
            if change.extrasChanged {
                guard let extras = change.nextExtraRecipeIDs, extras.count <= 4, extras.allSatisfy({ id in
                    guard let extra = allRecipes.first(where: { $0.id == id }),
                          !extra.isBeverage, isAllowedBySelectedCourses(id, for: next.slots[index]), allowsMealKind(extra, for: next.slots[index]) else { return false }
                    return extra.isPlanEligible ? incompatibility(next.slots[index], recipe: extra) == nil
                                                : preview.reviewRecipeIDs.contains(id) && courseDraftIssue(extra, for: next.slots[index]) == nil
                }) else {
                    replanPreview = makePreview(title: "План изменился", explanation: "Дополнительное блюдо больше не подходит участникам.",
                                                changes: [], emptyMessage: "Подберите меню заново; ничего не было изменено.")
                    return
                }
            }
            if change.beverageChanged {
                guard (change.nextBeverageIDs ?? []).allSatisfy({ beverageIssue($0, for: next.slots[index]) == nil }),
                      !replacement.isUnplanned || (change.nextBeverageIDs ?? []).isEmpty else {
                    replanPreview = makePreview(title: "План изменился", explanation: "Предложение больше не подходит текущему плану.",
                                                changes: [], emptyMessage: "Подберите меню заново; ничего не было изменено.")
                    return
                }
            }
            next.slots[index].recipeID = change.nextID
            next.slots[index].recipeChosenManually = true
            if change.beverageChanged {
                next.slots[index].setBeverages(change.nextBeverageIDs ?? [], manuallySelected: change.nextBeveragesManual)
            }
            if replacement.isUnplanned { next.slots[index].setBeverages([]) }
            if change.extrasChanged { next.slots[index].extraRecipeIDs = change.nextExtraRecipeIDs }
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
            next.slots[index].recipeChosenManually = nil
            if change.beverageChanged {
                next.slots[index].setBeverages(change.previousBeverageIDs ?? [], manuallySelected: change.previousBeveragesManual)
            }
            if change.extrasChanged { next.slots[index].extraRecipeIDs = change.previousExtraRecipeIDs }
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
        guard !recipe.isBeverage else { return L10n.text("Напиток добавляется к еде и не заменяет основное блюдо.") }
        guard allowsMealKind(recipe, for: slot) else { return L10n.text("Блюдо не подходит для этого приёма пищи.") }
        if hasSelectedCourses && !isAllowedBySelectedCourses(recipe.id, for: slot) {
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
        state.slots[index].recipeChosenManually = true
        if slot.recipeID == Recipe.unplanned.id { state.slots[index].extraRecipeIDs = [] }
        let foods = [recipe] + (state.slots[index].extraRecipeIDs ?? []).compactMap { id in allRecipes.first { $0.id == id } }
        state.slots[index].setBeverages(suggestedBeverages(for: slot, foods: foods, plannedSlots: state.slots),
                                       manuallySelected: slot.hasManualBeverages)
        return nil
    }
    func addDish(_ recipe: Recipe, to requestedSlot: MealSlot, allowUnverifiedCourseDraft: Bool = false) -> String? {
        guard let index = state.slots.firstIndex(where: { $0.id == requestedSlot.id }) else {
            return L10n.text("Приём больше не найден в плане.")
        }
        let slot = state.slots[index]
        guard hasSelectedCourses, (!isPastWindow(slot) || slot.day == currentDay), !isSkipped(slot),
              !state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }),
              !self.recipe(slot).isUnplanned else {
            return L10n.text("Добавить блюдо можно только к будущему, не завершённому приёму.")
        }
        guard !recipe.isBeverage else { return L10n.text("Напиток добавляется к еде и не заменяет основное блюдо.") }
        guard 1 + (slot.extraRecipeIDs ?? []).count < 5 else { return L10n.text("На один приём можно добавить не больше пяти блюд.") }
        guard !slot.allRecipeIDs.contains(recipe.id) else { return L10n.text("Это блюдо уже есть в приёме.") }
        guard isAllowedBySelectedCourses(recipe.id, for: slot), allowsMealKind(recipe, for: slot), !recipe.isUnavailable else {
            return L10n.text("Выберите блюдо с нужным тегом из выбранного курса.")
        }
        if recipe.isPlanEligible {
            if let issue = incompatibility(slot, recipe: recipe) { return issue }
        } else {
            guard allowUnverifiedCourseDraft else { return L10n.text("Сначала подтвердите черновик блюда.") }
            if let issue = courseDraftIssue(recipe, for: slot) { return issue }
        }
        state.slots[index].extraRecipeIDs = (slot.extraRecipeIDs ?? []) + [recipe.id]
        return nil
    }
    func removeExtraDish(_ recipeID: String, from requestedSlot: MealSlot) {
        guard let index = state.slots.firstIndex(where: { $0.id == requestedSlot.id }),
              (!isPastWindow(state.slots[index]) || state.slots[index].day == currentDay), !isSkipped(state.slots[index]),
              !state.eatenIDs.contains(where: { $0.hasPrefix("\(requestedSlot.id)-") }) else { return }
        state.slots[index].extraRecipeIDs?.removeAll { $0 == recipeID }
    }
    func setBeverage(_ beverageID: String?, for requestedSlot: MealSlot) -> String? {
        setBeverages(beverageID.map { [$0] } ?? [], for: requestedSlot)
    }
    func toggleBeverage(_ beverageID: String, for requestedSlot: MealSlot) -> String? {
        guard let slot = state.slots.first(where: { $0.id == requestedSlot.id }) else {
            return L10n.text("Приём больше не найден в плане.")
        }
        var ids = slot.selectedBeverageIDs
        if ids.contains(beverageID) { ids.removeAll { $0 == beverageID } }
        else { ids.append(beverageID) }
        return setBeverages(ids, for: slot)
    }
    func setBeverages(_ beverageIDs: [String], for requestedSlot: MealSlot) -> String? {
        guard hasSelectedCourses,
              let index = state.slots.firstIndex(where: { $0.id == requestedSlot.id }),
              !state.slots[index].memberIDs.isEmpty,
              !recipe(state.slots[index]).isUnavailable, !recipe(state.slots[index]).isBeverage,
              !isSkipped(state.slots[index]),
              (!isPastWindow(state.slots[index]) || state.slots[index].day == currentDay),
              !state.eatenIDs.contains(where: { $0.hasPrefix("\(requestedSlot.id)-") }) else {
            return L10n.text("Напиток можно выбрать только для активного приёма выбранного курса.")
        }
        for id in CourseBeverages.unique(beverageIDs) {
            if let issue = beverageIssue(id, for: state.slots[index]) { return issue }
        }
        state.slots[index].setBeverages(beverageIDs, manuallySelected: true)
        return nil
    }
    /// Warnings for the people at this meal: wine with children, sugar with
    /// "no sugar", and so on. They never block a dish.
    func dietCautions(_ slot: MealSlot, recipe: Recipe? = nil) -> [DietCaution] {
        DietCautions.cautions(for: recipe.map { [$0] } ?? recipes(slot), people: participating(slot))
    }
        func incompatibility(_ slot: MealSlot, recipe: Recipe? = nil) -> String? {
        for dish in recipe.map({ [$0] }) ?? recipes(slot) {
            if dish.isUnavailable { return "Рецепт недоступен до подключения закрытого каталога." }
            let incompatible = participating(slot).filter { AllergenMatching.conflicts(selected: $0.allergies, recipe: dish.knownAllergens) }
            if !incompatible.isEmpty {
                return L10n.format("Блюдо содержит %@. Ограничение у %@: выберите другое блюдо или измените участников.",
                                   dish.knownAllergens.map(L10n.text).joined(separator: ", "), incompatible.map(\.name).joined(separator: ", "))
            }
            if dish.hasUnspecifiedAllergenComposition && participating(slot).contains(where: { !$0.allergies.isEmpty }) {
                return L10n.text("Для этих ограничений выберите блюдо с полным составом.")
            }
        }
        return nil
    }
    func toggleParticipant(_ id: String, in slot: MealSlot) -> String? {
        guard let index = state.slots.firstIndex(where: { $0.id == slot.id }) else { return nil }
        if recipes(slot).contains(where: \.isUnavailable) { return "Сначала подключите закрытый каталог: это блюдо сейчас недоступно." }
        if state.slots[index].memberIDs.contains(id) {
            guard !state.eatenIDs.contains("\(slot.id)-\(id)") else {
                return L10n.text("Приём уже отмечен съеденным. Сначала исправьте эту отметку.")
            }
            state.slots[index].memberIDs.removeAll { $0 == id }
        }
        else {
            let person = state.members.first { $0.id == id }
            if let person, let dish = recipes(slot).first(where: { AllergenMatching.conflicts(selected: person.allergies, recipe: $0.knownAllergens) }) {
                return L10n.format("Блюдо содержит %@. Ограничение у %@: выберите другое блюдо или измените участников.",
                                   dish.knownAllergens.map(L10n.text).joined(separator: ", "), person.name)
            }
            if let person, !person.allergies.isEmpty, recipes(slot).contains(where: { $0.hasUnspecifiedAllergenComposition }) {
                return L10n.text("Для этих ограничений выберите блюдо с полным составом.")
            }
            state.slots[index].memberIDs.append(id)
        }
        return nil
    }
    /// A like only changes future ranking. It does not reshuffle the plan
    /// the person is looking at, so the tap answers immediately.
    func toggleFavorite(_ id: String) {
        let key = "\(state.selectedMemberID)|\(id)"
        var next = state
        if next.favorites.contains(key) { next.favorites.remove(key) }
        else {
            next.favorites.insert(key)
            next.dislikes?.remove(key)
        }
        state = next
    }
    func isFavorite(_ id: String) -> Bool { state.favorites.contains("\(state.selectedMemberID)|\(id)") }
    /// A dislike replaces this dish only in the person's open automatic meals
    /// from today on. Other days and dishes chosen by hand stay as they are.
    func toggleDislike(_ id: String) {
        let member = state.selectedMemberID
        let key = "\(member)|\(id)"
        var next = state
        let adding = next.dislikes?.contains(key) != true
        if adding {
            next.dislikes = (next.dislikes ?? []).union([key])
            next.favorites.remove(key)
        } else {
            next.dislikes?.remove(key)
        }
        state = next
        guard adding, maintainsDayMenu else { return }
        let affected = Set(state.slots.filter { slot in
            slot.day >= currentDay && slot.memberIDs.contains(member) &&
                (slot.recipeID == id || (slot.extraRecipeIDs ?? []).contains(id))
        }.map(\.id))
        if !affected.isEmpty { scheduleDayMenuFill(replacing: affected) }
    }
    private var pendingDayMenuFill: Set<String>?
    /// Run the automatic fill after the current frame is on screen, so a tap
    /// or a tab switch is drawn first. Requests in the same moment merge.
    func scheduleDayMenuFill(replacing slotIDs: Set<String> = []) {
        if pendingDayMenuFill != nil {
            pendingDayMenuFill?.formUnion(slotIDs)
            return
        }
        pendingDayMenuFill = slotIDs
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, let ids = self.pendingDayMenuFill else { return }
            self.pendingDayMenuFill = nil
            self.fillTodayMenu(replacing: ids)
        }
    }
    func isDisliked(_ id: String) -> Bool { state.dislikes?.contains("\(state.selectedMemberID)|\(id)") == true }
    func updateMember(_ member: FamilyMember) {
        guard let index = state.members.firstIndex(where: { $0.id == member.id }) else { return }
        var checked = member
        if let age = checked.ageYears, age < 18 {
            checked.goal = "Без цели по весу"
            checked.dailyEnergyTarget = nil
            checked.preferredVitaminKeys = nil
        }
        if (checked.ageYears ?? 0) < 19, checked.automaticPortions == true { checked.automaticPortions = nil }
        let oldWeight = state.members[index].weightKg
        var next = state
        next.members[index] = checked
        if let weight = checked.weightKg, weight != oldWeight, weight.isFinite, (10...500).contains(weight) {
            next.weightEntries = (next.weightEntries ?? []) + [WeightEntry(memberID: checked.id, measuredAt: .now, kilograms: weight)]
        }
        state = next
        if maintainsDayMenu { fillTodayMenu() }
    }
    func portion(for member: FamilyMember, recipe: Recipe, slot: MealSlot) -> Double {
        guard !recipe.isBeverage, !recipe.mealKinds.contains(3) else { return member.portion }
        // Only cache the stored person; an edited copy is computed fresh.
        guard state.members.first(where: { $0.id == member.id }) == member else {
            return PersonalPortions.foodShare(member: member, day: slot.day, slots: state.slots,
                                              byID: recipesByID, skippedIDs: state.skippedSlotIDs ?? [])
        }
        let key = "\(stateRevision)|\(recipeSourceRevision)"
        if portionCache?.key != key { portionCache = (key, [:]) }
        let shareKey = "\(member.id)|\(slot.day)"
        if let share = portionCache?.shares[shareKey] { return share }
        let share = PersonalPortions.foodShare(member: member, day: slot.day, slots: state.slots,
                                               byID: recipesByID, skippedIDs: state.skippedSlotIDs ?? [])
        portionCache?.shares[shareKey] = share
        return share
    }
    func dayRecipes(for member: FamilyMember, day: Int) -> [(recipe: Recipe, portion: Double)] {
        state.slots.filter { $0.day == day }.flatMap { meal -> [(recipe: Recipe, portion: Double)] in
            guard meal.memberIDs.contains(member.id), !isSkipped(meal) else { return [] }
            return recipes(meal).filter { !$0.isUnplanned && !$0.isUnavailable }
                .map { ($0, portion(for: member, recipe: $0, slot: meal)) }
        }
    }
    func updateMealSchedule(_ schedule: MealSchedule) {
        guard schedule.isValid else { return }
        var personal = schedule
        personal.snackMinute = nil
        state.mealSchedule = personal
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
            // A background server refresh is not a new personal edit. Otherwise
            // opening an older device would give its unchanged preferences a new
            // timestamp and overwrite newer preferences already stored in iCloud.
            let wasApplyingSnapshot = isApplyingCloudSnapshot
            isApplyingCloudSnapshot = true
            defer {
                isApplyingCloudSnapshot = wasApplyingSnapshot
                if servicesStarted && !wasApplyingSnapshot { personalDataChanged() }
            }
            let localMembers = Dictionary(uniqueKeysWithValues: state.members.map { ($0.id, $0) })
            let members = remoteMembers.map { remote in
                var merged = remote
                if let local = localMembers[remote.id] {
                    merged.goal = local.goal
                    merged.portion = local.portion
                    merged.ageYears = local.ageYears ?? remote.ageYears
                    merged.allergies = local.allergies
                    merged.dailyEnergyTarget = local.dailyEnergyTarget
                    merged.preferredVitaminKeys = local.preferredVitaminKeys
                    merged.heightCm = local.heightCm
                    merged.weightKg = local.weightKg
                    merged.automaticPortions = local.automaticPortions
                    merged.energySex = local.energySex
                    merged.energyActivity = local.energyActivity
                    merged.energyContext = local.energyContext
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
    func save(markChanged: Bool = false) {
        // A locked/protected file must never be replaced by a fresh plan.
        guard !protectedStateReadFailed else { return }
        do {
            if ReleasePolicy.isStoreRelease {
                try LocalPersonalFile.save(state)
                UserDefaults.standard.removeObject(forKey: "lad-demo-v3")
            } else {
                UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: "lad-demo-v3")
            }
            if markChanged && !isApplyingCloudSnapshot {
                personalStateModifiedAt = .now
                UserDefaults.standard.set(personalStateModifiedAt, forKey: "lad.personalModifiedAt")
            }
            if servicesStarted && !isApplyingCloudSnapshot { personalDataChanged() }
        } catch { storageWarning = L10n.text("Не удалось сохранить изменения. Не закрывайте приложение и попробуйте ещё раз.") }
    }
}
