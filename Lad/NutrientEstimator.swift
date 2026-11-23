import Foundation

/// General physiological roles, not promises about the effect of one meal.
/// Keep the explanatory source separate from the source of a recipe's quantities.
enum NutrientGuide {
    struct Entry {
        let name: String
        let ru: String
        let en: String
        let uk: String
        let sourceURL: URL
        var role: String { role(language: L10n.languageCode) }
        func role(language: String) -> String {
            switch language { case "en": return en; case "uk": return uk; default: return ru }
        }
    }
    static let primaryKeys = ["protein", "fat", "carbohydrate", "fiber"]
    static let displayOrder = primaryKeys + NutrientEstimator.displayOrder + ["sodium"]
    static func visibleKeys(available: Set<String>, expanded: Bool) -> [String] {
        (expanded ? displayOrder : primaryKeys).filter { available.contains($0) }
    }
    private static func ods(_ sheet: String) -> URL {
        URL(string: "https://ods.od.nih.gov/factsheets/\(sheet)-Consumer/")!
    }
    private static func fda(_ sheet: String) -> URL {
        URL(string: "https://www.accessdata.fda.gov/scripts/interactivenutritionfactslabel/assets/InteractiveNFL_\(sheet)_October2021.pdf")!
    }
    static let entries: [String: Entry] = [
        "protein": Entry(name: "Белок", ru: "Нужен для роста и восстановления тканей, образования ферментов и антител.", en: "Helps build and repair tissues and form enzymes and antibodies.", uk: "Потрібен для росту й відновлення тканин, утворення ферментів та антитіл.", sourceURL: fda("Protein")),
        "fat": Entry(name: "Жиры", ru: "Даёт энергию, входит в состав клеточных мембран и помогает усваивать витамины A, D, E и K.", en: "Provides energy, forms part of cell membranes and helps absorb vitamins A, D, E and K.", uk: "Дає енергію, входить до складу клітинних мембран і допомагає засвоювати вітаміни A, D, E та K.", sourceURL: fda("TotalFat")),
        "carbohydrate": Entry(name: "Углеводы", ru: "Основной источник глюкозы — энергии для клеток, включая мозг и мышцы.", en: "A main source of glucose, which fuels cells, including the brain and muscles.", uk: "Основне джерело глюкози — енергії для клітин, зокрема мозку та м’язів.", sourceURL: fda("TotalCarbohydrate")),
        "fiber": Entry(name: "Клетчатка", ru: "Помогает работе кишечника и поддерживает чувство сытости.", en: "Supports bowel function and helps you feel full.", uk: "Допомагає роботі кишківника та підтримує відчуття ситості.", sourceURL: fda("DietaryFiber")),
        "vitamin_a": Entry(name: "Витамин A", ru: "Нужен для нормального зрения, работы иммунной системы и роста клеток.", en: "Supports normal vision, immune function and cell growth.", uk: "Потрібен для нормального зору, роботи імунної системи та росту клітин.", sourceURL: ods("VitaminA")),
        "vitamin_c": Entry(name: "Витамин C", ru: "Участвует в образовании коллагена, защищает клетки и улучшает усвоение железа из растительной пищи.", en: "Helps form collagen, protects cells and improves iron absorption from plant foods.", uk: "Бере участь в утворенні колагену, захищає клітини й покращує засвоєння заліза з рослинної їжі.", sourceURL: ods("VitaminC")),
        "vitamin_d": Entry(name: "Витамин D", ru: "Помогает усваивать кальций; нужен костям, мышцам и иммунной системе.", en: "Helps absorb calcium and supports bones, muscles and immune function.", uk: "Допомагає засвоювати кальцій; потрібен кісткам, м’язам та імунній системі.", sourceURL: ods("VitaminD")),
        "vitamin_e": Entry(name: "Витамин E", ru: "Защищает клетки от окислительного повреждения и участвует в работе иммунной системы.", en: "Protects cells from oxidative damage and supports immune function.", uk: "Захищає клітини від окисного пошкодження та бере участь у роботі імунної системи.", sourceURL: ods("VitaminE")),
        "vitamin_k": Entry(name: "Витамин K", ru: "Участвует в свёртывании крови и поддержании костной ткани.", en: "Helps blood clot and supports bone tissue.", uk: "Бере участь у згортанні крові та підтриманні кісткової тканини.", sourceURL: ods("VitaminK")),
        "vitamin_b1": Entry(name: "Витамин B1", ru: "Помогает превращать пищу в энергию и поддерживает рост и работу клеток.", en: "Helps turn food into energy and supports cell growth and function.", uk: "Допомагає перетворювати їжу на енергію та підтримує ріст і роботу клітин.", sourceURL: ods("Thiamin")),
        "vitamin_b2": Entry(name: "Витамин B2", ru: "Участвует в получении энергии из пищи, росте и развитии клеток.", en: "Helps release energy from food and supports cell growth and development.", uk: "Бере участь в отриманні енергії з їжі, рості й розвитку клітин.", sourceURL: ods("Riboflavin")),
        "vitamin_b3": Entry(name: "Витамин B3", ru: "Помогает получать энергию из пищи и поддерживает нормальную работу клеток.", en: "Helps release energy from food and supports normal cell function.", uk: "Допомагає отримувати енергію з їжі та підтримує нормальну роботу клітин.", sourceURL: ods("Niacin")),
        "vitamin_b6": Entry(name: "Витамин B6", ru: "Участвует в обмене питательных веществ и работе иммунной системы.", en: "Supports nutrient metabolism and immune function.", uk: "Бере участь в обміні поживних речовин і роботі імунної системи.", sourceURL: ods("VitaminB6")),
        "vitamin_b12": Entry(name: "Витамин B12", ru: "Нужен нервным клеткам, образованию клеток крови и синтезу ДНК.", en: "Supports nerve cells, blood cell formation and DNA synthesis.", uk: "Потрібен нервовим клітинам, утворенню клітин крові та синтезу ДНК.", sourceURL: ods("VitaminB12")),
        "folate": Entry(name: "Фолат", ru: "Нужен для синтеза ДНК и деления клеток.", en: "Needed to make DNA and for cell division.", uk: "Потрібен для синтезу ДНК та поділу клітин.", sourceURL: ods("Folate")),
        "choline": Entry(name: "Холин", ru: "Входит в состав клеточных мембран и участвует в передаче нервных сигналов и управлении мышцами.", en: "Forms part of cell membranes and supports nerve signalling and muscle control.", uk: "Входить до складу клітинних мембран і бере участь у передачі нервових сигналів та керуванні м’язами.", sourceURL: ods("Choline")),
        "calcium": Entry(name: "Кальций", ru: "Нужен костям и зубам, сокращению мышц и передаче нервных сигналов.", en: "Supports bones and teeth, muscle contraction and nerve signalling.", uk: "Потрібен кісткам і зубам, скороченню м’язів та передачі нервових сигналів.", sourceURL: ods("Calcium")),
        "iron": Entry(name: "Железо", ru: "Входит в состав гемоглобина и миоглобина, помогающих переносить кислород к тканям и мышцам.", en: "Forms part of haemoglobin and myoglobin, which carry oxygen to tissues and muscles.", uk: "Входить до складу гемоглобіну та міоглобіну, що переносять кисень до тканин і м’язів.", sourceURL: ods("Iron")),
        "magnesium": Entry(name: "Магний", ru: "Участвует в работе мышц и нервов, образовании белков и костной ткани.", en: "Supports muscle and nerve function and the formation of proteins and bone tissue.", uk: "Бере участь у роботі м’язів і нервів, утворенні білків та кісткової тканини.", sourceURL: ods("Magnesium")),
        "phosphorus": Entry(name: "Фосфор", ru: "Нужен костям и зубам и участвует в использовании энергии клетками.", en: "Supports bones and teeth and helps cells use energy.", uk: "Потрібен кісткам і зубам та бере участь у використанні енергії клітинами.", sourceURL: ods("Phosphorus")),
        "potassium": Entry(name: "Калий", ru: "Поддерживает водный баланс, работу мышц, сердца и нервной системы.", en: "Supports fluid balance and the function of muscles, the heart and the nervous system.", uk: "Підтримує водний баланс, роботу м’язів, серця та нервової системи.", sourceURL: fda("Vitamins%26MineralsChart")),
        "zinc": Entry(name: "Цинк", ru: "Нужен иммунной системе, синтезу белков и ДНК, заживлению ран.", en: "Supports immune function, protein and DNA synthesis and wound healing.", uk: "Потрібен імунній системі, синтезу білків і ДНК, загоєнню ран.", sourceURL: ods("Zinc")),
        "selenium": Entry(name: "Селен", ru: "Участвует в обмене гормонов щитовидной железы и защите клеток от повреждения.", en: "Supports thyroid hormone metabolism and helps protect cells from damage.", uk: "Бере участь в обміні гормонів щитоподібної залози та захисті клітин від пошкодження.", sourceURL: ods("Selenium")),
        "sodium": Entry(name: "Натрий", ru: "Участвует в поддержании водного баланса, работе мышц и передаче нервных сигналов.", en: "Supports fluid balance, muscle function and nerve signalling.", uk: "Бере участь у підтриманні водного балансу, роботі м’язів і передачі нервових сигналів.", sourceURL: fda("Vitamins%26MineralsChart"))
    ]
    static func name(_ key: String) -> String { L10n.text(entries[key]?.name ?? key) }
}

// Composition is from a reviewed subset of USDA FoodData Central SR Legacy.
// Cooking corrections are true-retention factors from USDA Release 6. A
// factor changes the nutrient in the whole batch, not its concentration per
// 100 g of cooked food; added/evaporated water must not change batch totals.
enum NutrientEstimator {
    private struct Food: Decodable {
        let fdc_id: Int
        let description: String
        let per_100g: [String: Double]
    }
    private struct Reference: Decodable {
        let units: [String: String]
        let foods: [String: Food]
        let retention: [String: [String: Double]]
    }

    private enum Preparation: String { case raw, baked, sauteed, simmered, boiledDrained, fried, heated, toasted, unknown }
    private static let reference: Reference? = {
        guard let url = Bundle.main.url(forResource: "nutrient-reference", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Reference.self, from: data)
    }()

    static let displayOrder = [
        "vitamin_a", "vitamin_c", "vitamin_d", "vitamin_e", "vitamin_k",
        "vitamin_b1", "vitamin_b2", "vitamin_b3", "vitamin_b6", "vitamin_b12",
        "folate", "choline", "calcium", "iron", "magnesium", "phosphorus",
        "potassium", "zinc", "selenium"
    ]
    static let calculationOrder = ["protein", "fat", "carbohydrate", "fiber"] + displayOrder + ["sodium"]
    static func ingredientComposition(name: String) -> [String: NutrientValue] {
        guard let reference,
              let food = reference.foods[name] ?? reference.foods.first(where: {
                  ProductNames.canonical($0.key) == ProductNames.canonical(name)
              })?.value else { return [:] }
        return food.per_100g.reduce(into: [:]) { result, entry in
            guard let unit = reference.units[entry.key] else { return }
            result[entry.key] = NutrientValue(amount: entry.value, unit: unit, source: "USDA FoodData Central", coverage: 1)
        }
    }
    static func ingredientSource(name: String) -> URL? {
        guard let reference,
              let food = reference.foods[name] ?? reference.foods.first(where: {
                  ProductNames.canonical($0.key) == ProductNames.canonical(name)
              })?.value else { return nil }
        return URL(string: "https://fdc.nal.usda.gov/food-details/\(food.fdc_id)/nutrients")
    }
    private static let proxyIngredients: Set<String> = [
        "Творог", "Ягоды", "Чечевица красная", "Хлеб", "Куриное филе",
        "Сыр", "Мясной фарш", "Растительное масло", "Говядина", "Хек", "Зелень",
        "Кефир", "Красное сухое вино", "Квашеная капуста", "Творожный сыр",
        "Нори", "Мясной бульон", "Говядина варёная", "Куриный фарш",
        "Гороховая крупа", "Яблочное пюре", "Чечевица", "Томаты черри",
        "Петрушка", "Базилик", "Орегано", "Кунжутное масло", "Ореховое масло",
        "Сыр с белой плесенью", "Свинина", "Брынза", "Белое сухое вино",
        "Куриный окорочок", "Говядина на кости", "Голень индейки",
        "Прованские травы", "Ряженка"
    ]

    static func estimate(_ recipe: Recipe, supplied: [String: NutrientValue] = [:]) -> [String: NutrientValue] {
        guard let reference, recipe.baseServings > 0, !recipe.ingredients.isEmpty else { return supplied }
        let weighed = recipe.ingredients.map { ingredient -> (Ingredient, Double?) in
            let amountRatio = ingredient.amountMax.flatMap { maximum -> Double? in
                guard let amount = ingredient.amount, amount > 0 else { return nil }
                return (amount + maximum) / (2 * amount)
            } ?? 1
            return (ingredient, EnergyEstimator.estimatedGrams(for: ingredient).map {
                $0 * amountRatio * (recipe.nutritionEdibleYield[ingredient.name] ?? 1)
            })
        }
        // Cooking/drinking water contributes no food micronutrients and must not
        // dilute the coverage percentage for the actual ingredients.
        let totalKnownGrams = weighed.filter { $0.0.name != "Вода" }.compactMap(\.1).reduce(0, +)
        guard totalKnownGrams > 0 else { return supplied }
        let hasProxy = recipe.ingredients.contains { proxyIngredients.contains($0.name) }
        var results = supplied
        for key in calculationOrder {
            // A catalog-provided value may be measured or independently verified;
            // do not silently replace it with this composition-based estimate.
            if supplied[key] != nil { continue }
            guard let unit = reference.units[key] else { continue }
            var batchAmount = 0.0
            var compositionCoveredGrams = 0.0
            var cookingCoveredGrams = 0.0
            var unadjustedCooked = false
            for (ingredient, gramsOptional) in weighed {
                if ingredient.name == "Вода" { continue }
                // Unsweetened packaged purée varies by brand and processing.
                // Raw apple composition is only a labelled proxy, never a measured value.
                let referenceName: String
                switch ingredient.name {
                case let name where reference.foods[name] != nil: referenceName = name
                case "Яблочное пюре": referenceName = "Яблоко"
                case "Чечевица": referenceName = "Чечевица красная"
                case "Томаты черри": referenceName = "Томаты"
                case "Петрушка", "Базилик": referenceName = "Зелень"
                case "Орегано": referenceName = "Майоран"
                case "Кунжутное масло", "Ореховое масло": referenceName = "Оливковое масло"
                case "Сыр с белой плесенью": referenceName = "Сыр"
                case "Прованские травы": referenceName = "Майоран"
                case "Ряженка": referenceName = "Кефир"
                default: referenceName = ingredient.name
                }
                guard let grams = gramsOptional, grams > 0,
                      let per100g = reference.foods[referenceName]?.per_100g[key] else { continue }
                compositionCoveredGrams += grams
                let preparation = preparation(for: recipe, ingredient: ingredient.name)
                if preparation == .raw {
                    cookingCoveredGrams += grams
                    batchAmount += per100g * grams / 100
                } else if let code = retentionCode(for: ingredient.name, preparation: preparation),
                          let factor = reference.retention[String(code)]?[key] {
                    cookingCoveredGrams += grams
                    batchAmount += per100g * grams / 100 * factor
                } else {
                    // Display a raw-composition baseline, clearly marked incomplete.
                    // It must not masquerade as a measured cooked nutrient total.
                    unadjustedCooked = true
                    batchAmount += per100g * grams / 100
                }
            }
            guard compositionCoveredGrams > 0 else { continue }
            let weighedCoverage = min(1, cookingCoveredGrams / totalKnownGrams)
            // This is coverage of ingredients whose mass is known. The UI
            // separately warns about unweighed ingredients and proxy foods.
            let coverage = weighedCoverage
            let source: String
            if unadjustedCooked {
                source = hasProxy
                    ? "USDA FDC · аналог продукта; часть без поправки на готовку"
                    : "USDA FDC SR Legacy · часть без поправки на приготовление"
            } else {
                source = hasProxy
                    ? "USDA FDC + USDA R6 · аналог продукта"
                    : "USDA FDC SR Legacy + коэффициенты сохранности USDA R6"
            }
            results[key] = NutrientValue(amount: batchAmount / recipe.baseServings,
                                          unit: unit, source: source, coverage: coverage)
        }
        return results
    }

    static func reheated(_ recipe: Recipe) -> [String: NutrientValue] {
        guard let reference, !recipe.isBeverage else { return recipe.nutrients }
        var contributions: [(name: String, values: [String: NutrientValue])] = []
        for ingredient in recipe.ingredients where ingredient.name != "Вода" {
            var single = Recipe(id: recipe.id, title: recipe.title, caption: "", image: "", cuisine: "", minutes: 0,
                                kcal: nil, protein: nil, allergens: [], ingredients: [ingredient], steps: [])
            single.baseServings = recipe.baseServings
            single.nutrientPreparationByIngredient = recipe.nutrientPreparationByIngredient
            single.nutritionEdibleYield = recipe.nutritionEdibleYield
            contributions.append((ingredient.name, estimate(single)))
        }
        var result = recipe.nutrients
        for (key, original) in recipe.nutrients where !NutrientGuide.primaryKeys.contains(key) {
            var baseline = 0.0, after = 0.0, covered = 0.0
            for contribution in contributions {
                guard let amount = contribution.values[key]?.amount else { continue }
                baseline += amount
                if let code = reheatingCode(contribution.name), let factor = reference.retention[String(code)]?[key] {
                    after += amount * factor
                    covered += amount
                } else { after += amount }
            }
            // No supported factor: retain the prior estimate, never invent losses.
            let fraction = baseline > 0 ? min(1, after / baseline) : 1
            result[key] = NutrientValue(amount: original.amount * fraction, unit: original.unit,
                                        source: "USDA R6 · повторный разогрев; общий коэффициент, не конкретный прибор",
                                        coverage: min(original.coverage, baseline > 0 ? covered / baseline : 0))
        }
        return result
    }
    private static func reheatingCode(_ name: String) -> Int? {
        switch name {
        case "Сыр", "Творог", "Брынза", "Моцарелла", "Фета", "Творожный сыр": return 7
        case "Яйцо": return 109
        case "Молоко": return 2154
        case "Куриное филе", "Куриный фарш", "Куриный окорочок": return 864
        case "Филе индейки", "Голень индейки": return 1860
        case "Говяжья печень", "Печень индейки": return 1154
        case "Свинина", "Свиная вырезка": return 1407
        case "Говядина", "Говядина варёная", "Говядина на кости": return 770
        case "Лосось", "Минтай", "Хек", "Скумбрия": return 2554
        case "Креветки": return 2771
        case "Яблоко", "Яблочное пюре", "Сливы", "Банан", "Ягоды": return 157
        case "Чернослив": return 257
        case "Картофель": return 3379
        case "Морковь", "Свёкла": return 3468
        case "Помидор", "Помидоры", "Томаты", "Томаты черри": return 3754
        case "Брокколи", "Цветная капуста", "Цукини", "Кабачок", "Лук", "Баклажан", "Перец", "Сладкий перец", "Перец сладкий", "Тыква", "Белокочанная капуста", "Капуста белокочанная", "Капуста", "Пекинская капуста", "Стручковая фасоль", "Сельдерей", "Шампиньоны", "Чеснок": return 3788
        case "Зелень", "Укроп", "Петрушка", "Листья салата", "Руккола", "Зелёный лук": return 3018
        case "Рис", "Бурый рис", "Пропаренный рис", "Рис варёный": return 434
        case "Макароны", "Рисовая лапша": return 385
        case "Мука", "Рисовая мука", "Гречневая мука", "Ржаная мука": return 304
        case "Чечевица", "Чечевица красная", "Гороховая крупа": return 550
        default: return nil
        }
    }

    private static func preparation(for recipe: Recipe, ingredient name: String) -> Preparation {
        if let declared = recipe.nutrientPreparationByIngredient[name],
           let preparation = Preparation(rawValue: declared) { return preparation }
        let id = recipe.id.replacingOccurrences(of: "private:", with: "")
        switch id {
        case "salmon":
            return ["Лосось", "Картофель", "Брокколи"].contains(name) ? .baked : .raw
        case "pancakes":
            return ["Творог", "Яйцо", "Мука"].contains(name) ? .fried : .raw
        case "soup":
            return ["Лук", "Морковь"].contains(name) ? .sauteed : .simmered
        case "oats":
            if name == "Банан" { return .raw }
            return name == "Молоко" ? .heated : .simmered
        case "eggs":
            if name == "Хлеб" { return .toasted }
            return name == "Яйцо" ? .fried : .sauteed
        case "chicken-buckwheat":
            if name == "Огурец" { return .raw }
            return name == "Гречка" ? .simmered : .fried
        case "vegetable-pasta":
            if name == "Сыр" { return .raw }
            return name == "Макароны" ? .boiledDrained : .simmered
        case "turkey-rice":
            return name == "Рис" ? .simmered : .sauteed
        case "lentil-stew":
            return ["Лук", "Перец сладкий"].contains(name) ? .sauteed : .simmered
        case "photo_meat_mushroom_nests":
            return ["Зелень", "Соль", "Чёрный перец"].contains(name) ? .raw : .baked
        case "photo_cottage_bake": return .baked
        case "photo_chicken_rice_noodle_soup":
            return ["Зелень", "Соль", "Чёрный перец"].contains(name) ? .raw : .simmered
        case "photo_vegetable_pilaf":
            if ["Зелень", "Соль"].contains(name) { return .raw }
            return ["Бурый рис", "Пропаренный рис", "Рис"].contains(name) ? .simmered : .sauteed
        case "photo_vegetable_cheese_cutlets": return .baked
        case "photo_cheese_cookies": return name == "Зелень" ? .raw : .baked
        case "photo_fish_vegetables": return .baked
        case "photo_buckwheat_cabbage_salad": return name == "Гречка" ? .simmered : .raw
        case "photo_cabbage_mushroom_cutlets": return .baked
        case "photo_zucchini_curd_fritters":
            return ["Томаты", "Йогурт натуральный", "Укроп"].contains(name) ? .raw : .baked
        case "photo_zucchini_meat_cheese": return .baked
        case "photo_beef_paprika_goulash": return .simmered
        case "photo_apple_vegetable_salad": return .raw
        default: return .unknown
        }
    }

    private static func retentionCode(for name: String, preparation: Preparation) -> Int? {
        if ["Соль", "Лимонный сок", "Растительное масло", "Оливковое масло", "Майонез"].contains(name) { return nil }
        if name == "Лосось" { return preparation == .baked ? 2452 : nil }
        if name == "Скумбрия" { return preparation == .baked ? 2452 : nil }
        if name == "Говяжья печень" { return preparation == .fried ? 1151 : nil }
        // No duck-specific R6 row: cooked poultry is an explicit approximation.
        if name == "Утка" { return preparation == .baked ? 805 : nil }
        if ["Минтай", "Хек"].contains(name) {
            return preparation == .baked ? 2302 : preparation == .simmered ? 2402 : preparation == .fried ? 2310 : nil
        }
        if name == "Куриное филе" {
            switch preparation {
            case .baked: return 805
            case .simmered: return 856
            case .fried, .sauteed: return 803
            default: return nil
            }
        }
        if name == "Филе индейки" { return preparation == .sauteed ? 1805 : nil }
        if name == "Говядина" || name == "Говядина на кости" {
            return preparation == .simmered ? 654 : preparation == .baked ? 601 : nil
        }
        if name == "Свиная вырезка" { return preparation == .baked ? 1254 : nil }
        if name == "Куриный фарш" { return preparation == .baked ? 805 : nil }
        if name == "Куриный окорочок" || name == "Голень индейки" {
            return preparation == .baked ? 805 : preparation == .simmered ? 856 : nil
        }
        if name == "Печень индейки" { return preparation == .simmered ? 856 : nil }
        if name == "Свинина" || name == "Свиные ножки" {
            return preparation == .simmered ? 1253 : nil
        }
        if name == "Креветки" { return preparation == .boiledDrained ? 2701 : nil }
        if name == "Мясной фарш" { return preparation == .baked ? 750 : nil }
        if name == "Яйцо" {
            if preparation == .baked { return 101 }
            if preparation == .fried { return 103 }
            if preparation == .boiledDrained { return 105 }
            return nil
        }
        if ["Сыр", "Творог"].contains(name) { return preparation == .baked ? 1 : nil }
        if name == "Молоко" { return preparation == .heated ? 2151 : nil }
        if name == "Пшено" {
            return preparation == .simmered || preparation == .boiledDrained ? 358 : nil
        }
        if name == "Овсяные хлопья" { return preparation == .simmered ? 352 : nil }
        if name == "Гречка" {
            return preparation == .simmered || preparation == .boiledDrained ? 358 : nil
        }
        if name == "Гороховая крупа" {
            return preparation == .boiledDrained ? 521 : preparation == .simmered ? 522 : nil
        }
        if ["Рис", "Бурый рис", "Пропаренный рис"].contains(name) {
            return preparation == .simmered ? 432 : preparation == .boiledDrained ? 431 : nil
        }
        if ["Макароны", "Рисовая лапша"].contains(name) {
            return preparation == .simmered ? 384 : preparation == .boiledDrained ? 381 : nil
        }
        if ["Чечевица", "Чечевица красная"].contains(name) {
            return preparation == .simmered ? 502 : preparation == .boiledDrained ? 501 : nil
        }
        if ["Мука", "Рисовая мука", "Гречневая мука", "Ржаная мука"].contains(name) {
            return preparation == .baked ? 301 : preparation == .fried ? 305 : nil
        }
        if name == "Картофель" { return preparation == .baked ? 3302 : nil }
        if name == "Томаты" {
            return preparation == .sauteed || preparation == .fried ? 3752 :
                preparation == .simmered || preparation == .baked ? 3751 : nil
        }
        if ["Морковь", "Свёкла"].contains(name) {
            switch preparation {
            case .baked: return 3451
            case .simmered: return 3456
            case .sauteed, .fried: return 3460
            default: return nil
            }
        }
        if name == "Яблоко" {
            return preparation == .baked ? 151 : preparation == .sauteed ? 153 :
                preparation == .heated || preparation == .simmered ? 155 : nil
        }
        if name == "Мандарин" { return preparation == .baked ? 270 : nil }
        if name == "Чернослив" { return preparation == .baked ? 251 : nil }
        if ["Брокколи", "Цветная капуста", "Капуста", "Капуста белокочанная", "Пекинская капуста", "Квашеная капуста", "Кабачок", "Цукини", "Лук", "Сладкий перец", "Перец сладкий", "Сельдерей", "Шампиньоны", "Чеснок", "Баклажан", "Имбирь", "Тыква", "Стручковая фасоль"].contains(name) {
            switch preparation {
            case .baked: return 3771
            case .simmered: return 3776
            case .boiledDrained: return 3775
            case .sauteed, .fried: return 3785
            default: return nil
            }
        }
        return nil
    }
}
