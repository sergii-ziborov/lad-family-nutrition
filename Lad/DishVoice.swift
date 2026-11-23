import Foundation

// Spoken descriptions and cuisine labels for the one household course.
// Remote catalogues sometimes stored source notes instead of a dish description.
// The screen always shows this voice, so those notes never reach the reader.
enum DishVoice {
    static func cuisine(for recipe: Recipe) -> String {
        if recipe.isBeverage { return recipe.cuisine.isEmpty ? "Напитки" : recipe.cuisine }
        let id = recipe.id.replacingOccurrences(of: "private:", with: "")
        if let known = cuisines[id] { return known }
        return inferredCuisine(title: recipe.title, ingredients: recipe.ingredients.map(\.name))
    }

    static func story(for recipe: Recipe) -> String {
        if recipe.isUnavailable || recipe.isUnplanned { return L10n.text(recipe.caption) }
        switch L10n.languageCode {
        case "en": return english(recipe)
        case "uk": return ukrainian(recipe)
        default: return russian(recipe)
        }
    }

    private static let cuisines: [String: String] = [
        "pancakes": "Украинская",
        "oats": "Домашняя",
        "eggs": "Домашняя",
        "med-yogurt-walnuts": "Средиземноморская",
        "med-avocado-spinach-toast": "Средиземноморская",
        "med-bulgur-breakfast": "Средиземноморская",
        "med-vegetable-frittata": "Итальянская",
        "med-chickpea-spread-toast": "Левантийская",
        "bf-savory-oat-pancake": "Домашняя",
        "bf-buckwheat-egg-mushrooms": "Восточноевропейская",
        "bf-overnight-apple-oats": "Американская",
        "bf-baked-curd-oats": "Восточноевропейская",
        "bf-curd-herb-toast": "Восточноевропейская",
        "bf-chickpea-egg-skillet": "Левантийская",
        "bf-red-lentil-pancakes": "Средиземноморская",
        "bf-mozzarella-egg-toast": "Итальянская",
        "bf-millet-pumpkin-yogurt": "Восточноевропейская",
        "bf-salmon-avocado-toast": "Средиземноморская",
        "bf-spinach-mozzarella-oat-wrap": "Итальянская",
        "bf-banana-oat-pancakes": "Американская",
        "bf-buckwheat-apple-yogurt": "Восточноевропейская",
        "bf-savory-bulgur-egg": "Средиземноморская",
        "bf-millet-curd-plum-bake": "Восточноевропейская",
        "bf-zucchini-curd-frittata": "Итальянская",
        "bf-rye-yogurt-berry-pancakes": "Восточноевропейская",
        "bf-chickpea-feta-toast": "Греческая",
        "bf-lentil-carrot-egg-patties": "Средиземноморская",
        "photo_meat_mushroom_nests": "Восточноевропейская",
        "photo_chicken_rice_noodle_soup": "Восточноевропейская",
        "photo_vegetable_pilaf": "Среднеазиатская",
        "photo_vegetable_cheese_cutlets": "Домашняя",
        "photo_cheese_cookies": "Домашняя",
        "photo_fish_vegetables": "Восточноевропейская",
        "photo_buckwheat_cabbage_salad": "Восточноевропейская",
        "photo_cabbage_mushroom_cutlets": "Восточноевропейская",
        "photo_zucchini_curd_fritters": "Белорусская",
        "photo_zucchini_meat_cheese": "Восточноевропейская",
        "photo_beef_paprika_goulash": "Венгерская",
        "photo_apple_vegetable_salad": "Восточноевропейская",
        "photo2_meat_cauliflower_patties": "Восточноевропейская",
        "photo2_kefir_baked_chicken": "Восточноевропейская",
        "photo2_potato_dill_yogurt": "Восточноевропейская",
        "photo2_vegetable_soup": "Домашняя",
        "photo2_meat_in_cabbage": "Восточноевропейская",
        "photo2_plum_apple_salad": "Домашняя",
        "photo2_shakshuka": "Североафриканская",
        "photo2_boiled_shrimp": "Средиземноморская",
        "photo2_cabbage_stuffed_peppers": "Восточноевропейская",
        "photo2_cheese_crispbreads": "Восточноевропейская",
        "photo2_pork_chop_vegetables": "Восточноевропейская",
        "photo2_fruit_curd_minipizza": "Домашняя",
        "photo2_simple_goulash": "Венгерская",
        "photo2_boiled_eggs": "Домашняя",
        "photo3_fish_millet_soup": "Восточноевропейская",
        "photo3_apple_syrniki": "Украинская",
        "photo3_creamy_chicken_mushrooms": "Домашняя",
        "photo3_nori_cottage_rolls": "Японская",
        "photo3_cabbage_pie": "Русская",
        "photo3_kefir_chicken_fillet": "Восточноевропейская",
        "photo3_pumpkin_tomato_soup": "Домашняя",
        "photo3_apple_curd_souffle": "Французская",
        "photo3_country_potatoes": "Средиземноморская",
        "photo3_zucchini_caviar_rice": "Восточноевропейская",
        "photo3_pork_cheese_rolls": "Восточноевропейская",
        "photo3_baked_rice_vegetables": "Домашняя",
        "photo3_chicken_meatloaf": "Восточноевропейская",
        "photo3_cauliflower_puree": "Домашняя",
        "photo3_olivier_yogurt": "Русская",
        "photo3_oilless_goulash": "Венгерская",
        "photo4_cheese_chops_buckwheat": "Восточноевропейская",
        "photo4_cottage_apple_prune_bake": "Восточноевропейская",
        "photo4_fish_rice_soup": "Русская",
        "photo4_cabbage_carrot_buckwheat": "Восточноевропейская",
        "photo4_split_peas_onion": "Восточноевропейская",
        "photo4_brown_rice_fruit": "Домашняя",
        "photo4_baked_beef_millet": "Восточноевропейская",
        "photo4_apple_orange_kiwi_yogurt": "Домашняя",
        "photo5_meatball_tomato_soup": "Восточноевропейская",
        "photo5_cottage_dried_tomato_bake": "Восточноевропейская",
        "photo5_beef_pilaf": "Среднеазиатская",
        "photo5_beef_liver_chops": "Восточноевропейская",
        "photo5_cheese_chops": "Восточноевропейская",
        "photo5_baked_apple_mandarin_yogurt": "Домашняя",
        "photo5_eggplant_cheese_rolls": "Средиземноморская",
        "photo5_baked_mackerel": "Средиземноморская",
        "photo5_orange_cinnamon_duck": "Китайская",
        "photo5_buckwheat_tomatoes": "Восточноевропейская",
        "photo5_stovetop_stuffed_peppers": "Восточноевропейская",
        "photo5_crispbreads_cottage_cheese": "Восточноевропейская",
        "photo5_fish_batter": "Домашняя",
        "photo5_fish_patties": "Восточноевропейская",
        "photo5_stewed_cabbage_buckwheat": "Восточноевропейская",
        "photo6_buckwheat_meatball_soup": "Русская",
        "photo6_plain_buckwheat": "Восточноевропейская",
        "photo6_cottage_apple_puree": "Домашняя",
        "photo6_dry_pan_eggs": "Домашняя",
        "photo6_plain_lentils": "Средиземноморская",
        "photo7_avocado_boat_salad": "Итальянская",
        "photo7_radish_cucumber_salad": "Восточноевропейская",
        "photo7_lightly_salted_cucumbers": "Восточноевропейская",
        "photo7_asian_cabbage_salad": "Восточноазиатская",
        "photo7_avocado_tomato_salad": "Средиземноморская",
        "photo7_baked_vegetables": "Средиземноморская",
        "photo7_tomato_feta_salad": "Греческая",
        "photo7_mustard_garden_salad": "Средиземноморская",
        "photo7_zucchini_caviar": "Восточноевропейская",
        "photo7_tomato_beet_salad": "Восточноевропейская",
        "photo7_cabbage_cucumber_salad": "Восточноевропейская",
        "photo7_traffic_light_salad": "Домашняя",
        "photo7_eggplant_caviar": "Восточноевропейская",
        "photo7_plum_cheese_salad": "Домашняя",
        "photo7_pickled_cucumber_feta_beet": "Греческая",
        "photo8_beef_pork_eggplant": "Средиземноморская",
        "photo8_zucchini_mushroom_patties": "Восточноевропейская",
        "photo8_turkey_liver_apples": "Восточноевропейская",
        "photo8_tomato_grain_curd_salad": "Восточноевропейская",
        "photo8_pumpkin_broccoli_soup": "Домашняя",
        "photo8_dill_egg_pancakes": "Домашняя",
        "photo8_potato_zucchini_fritters": "Белорусская",
        "photo8_vegetable_brynza_roll": "Греческая",
        "photo8_lazy_rye_curd_dumplings": "Украинская",
        "photo8_mustard_wine_chicken_buckwheat": "Французская",
        "photo8_beef_turkey_aspic": "Русская",
        "photo9_cottage_plum_apple": "Домашняя",
        "photo9_rye_khachapuri": "Грузинская",
        "photo9_eggplant_chicken_plum_rolls": "Средиземноморская",
        "photo9_beet_caviar": "Восточноевропейская",
        "photo9_pork_pumpkin_chops": "Восточноевропейская",
        "photo9_broccoli_yogurt_salad": "Домашняя",
        "photo9_clear_meatball_soup": "Русская",
        "lunch-turkey-cauliflower-balls": "Восточноевропейская",
        "lunch-chicken-millet-soup": "Восточноевропейская",
        "lunch-pollock-broccoli-bake": "Восточноевропейская",
        "lunch-beef-zucchini-stew": "Средиземноморская",
        "lunch-lentil-pumpkin-soup": "Средиземноморская",
        "lunch-turkey-cabbage-rolls": "Восточноевропейская",
        "lunch-chicken-buckwheat-zucchini-boats": "Восточноевропейская",
        "lunch-beef-bulgur-pepper-pot": "Средиземноморская",
        "lunch-chicken-pumpkin-rice-bake": "Домашняя",
        "lunch-chicken-spinach-rolls": "Средиземноморская",
        "dinner-turkey-kefir-zucchini": "Восточноевропейская",
        "dinner-hake-spinach-lemon": "Средиземноморская",
        "dinner-curd-broccoli-bake": "Восточноевропейская",
        "dinner-buckwheat-mushroom-beans": "Восточноевропейская",
        "dinner-beet-curd-crispbreads": "Восточноевропейская",
        "dinner-curd-walnut-baked-apple": "Домашняя",
        "dinner-rice-zucchini-egg-bake": "Средиземноморская",
        "dinner-nori-egg-curd-rolls": "Японская",
        "dinner-lentil-zucchini-soup": "Средиземноморская",
        "dinner-fish-zucchini-steamed-patties": "Восточноевропейская",
        "salmon": "Средиземноморская",
        "soup": "Средиземноморская",
        "chicken-buckwheat": "Восточноевропейская",
        "vegetable-pasta": "Средиземноморская",
        "turkey-rice": "Домашняя",
        "lentil-stew": "Средиземноморская",
        "med-chickpea-spinach-stew": "Левантийская",
        "med-lemon-chicken-bulgur": "Средиземноморская",
        "med-salmon-lentil-salad": "Средиземноморская",
        "med-chickpea-greek-salad": "Греческая",
        "med-eggplant-lentil-bake": "Средиземноморская",
        "med-shrimp-spinach-pasta": "Средиземноморская",
        "med-bulgur-roasted-vegetables": "Греческая",
        "snack-yogurt-berries": "Домашняя",
        "snack-apple-walnuts": "Домашняя",
        "snack-curd-cucumber": "Восточноевропейская"
    ]

    private static func inferredCuisine(title: String, ingredients: [String]) -> String {
        let text = (title + " " + ingredients.joined(separator: " ")).lowercased()
        let rules: [(String, [String])] = [
            ("Грузинская", ["хачапури"]),
            ("Венгерская", ["гуляш", "паприк"]),
            ("Среднеазиатская", ["плов"]),
            ("Японская", ["нори", "ролл"]),
            ("Североафриканская", ["шакшук"]),
            ("Итальянская", ["фриттат", "моцарелл"]),
            ("Греческая", ["фета", "брынз"]),
            ("Левантийская", ["нут"]),
            ("Белорусская", ["драник"]),
            ("Украинская", ["сырник", "вареник"]),
            ("Русская", ["оливье", "холодец", "уха"]),
            ("Китайская", ["утк"]),
            ("Восточноазиатская", ["имбирь", "кунжут", "соевый соус"]),
            ("Восточноевропейская", ["гречк", "кефир", "пшен"])
        ]
        for (cuisine, keys) in rules where keys.contains(where: { text.contains($0) }) {
            return cuisine
        }
        return "Домашняя"
    }

    private static let neuterCuisine: [String: String] = [
        "Домашняя": "домашнее", "Украинская": "украинское", "Русская": "русское",
        "Белорусская": "белорусское", "Грузинская": "грузинское", "Венгерская": "венгерское",
        "Среднеазиатская": "среднеазиатское", "Греческая": "греческое", "Итальянская": "итальянское",
        "Левантийская": "левантийское", "Североафриканская": "североафриканское",
        "Японская": "японское", "Китайская": "китайское", "Восточноазиатская": "восточноазиатское",
        "Французская": "французское", "Американская": "американское",
        "Средиземноморская": "средиземноморское", "Восточноевропейская": "восточноевропейское",
        "Напитки": "напиток"
    ]

    private static func mealPhrase(_ recipe: Recipe) -> (ru: String, en: String, uk: String) {
        switch recipe.mealKinds.min() ?? 1 {
        case 0: return ("на завтрак", "breakfast", "на сніданок")
        case 2: return ("на ужин", "dinner", "на вечерю")
        case 3: return ("для перекуса", "snack", "для перекусу")
        default: return ("на обед", "lunch", "на обід")
        }
    }

    private static func russian(_ recipe: Recipe) -> String {
        let meal = mealPhrase(recipe)
        let kitchen = cuisine(for: recipe)
        let opening = recipe.isBeverage || kitchen == "Напитки"
            ? "\(recipe.title) — напиток \(meal.ru == "для перекуса" ? "к столу" : meal.ru)."
            : "\(recipe.title) — \(neuterCuisine[kitchen] ?? kitchen.lowercased()) блюдо \(meal.ru)."
        return opening + " " + way(recipe, language: "ru")
    }

    private static func english(_ recipe: Recipe) -> String {
        let meal = mealPhrase(recipe)
        let kitchen = L10n.text(cuisine(for: recipe)).lowercased()
        let opening = recipe.isBeverage
            ? "\(L10n.text(recipe.title)) is a drink for the table."
            : "\(L10n.text(recipe.title)) is a \(kitchen) \(meal.en)."
        return opening + " " + way(recipe, language: "en")
    }

    private static func ukrainian(_ recipe: Recipe) -> String {
        let meal = mealPhrase(recipe)
        let kitchen = L10n.text(cuisine(for: recipe)).lowercased()
        let opening = recipe.isBeverage
            ? "\(L10n.text(recipe.title)) — напій до столу."
            : "\(L10n.text(recipe.title)) — \(kitchen) страва \(meal.uk)."
        return opening + " " + way(recipe, language: "uk")
    }

    private static func way(_ recipe: Recipe, language: String) -> String {
        let text = (recipe.title + " " + recipe.steps.joined(separator: " ")).lowercased()
        let kind: String
        if text.contains("суп") || text.contains("бульон") { kind = "soup" }
        else if text.contains("салат") { kind = "salad" }
        else if text.contains("запек") || text.contains("духов") { kind = "oven" }
        else if text.contains("на пару") { kind = "steam" }
        else if text.contains("сковород") { kind = "pan" }
        else { kind = "pot" }
        switch (language, kind) {
        case ("en", "soup"): return "It simmers in one pot and is ladled out hot."
        case ("en", "salad"): return "Wash, cut and dress it just before it goes to the table."
        case ("en", "oven"): return "The oven finishes it in one dish."
        case ("en", "steam"): return "Steam keeps it soft, without a pool of oil."
        case ("en", "pan"): return "A short turn in the pan, then straight onto the plates."
        case ("en", _): return "It is cooked in one pot and shared across the plates."
        case ("uk", "soup"): return "Усе вариться в одній каструлі й розливається гарячим."
        case ("uk", "salad"): return "Продукти миють, ріжуть і з’єднують перед подачею."
        case ("uk", "oven"): return "Духовка доводить страву в одній формі."
        case ("uk", "steam"): return "Готують на парі, тож страва лишається м’якою."
        case ("uk", "pan"): return "Коротко прогрівають на сковорідці й одразу розкладають."
        case ("uk", _): return "Страву готують в одному посуді й розкладають по тарілках."
        case (_, "soup"): return "Всё варится в одной кастрюле и разливается горячим по тарелкам."
        case (_, "salad"): return "Продукты моют, режут и соединяют перед подачей."
        case (_, "oven"): return "Духовка доводит блюдо в одной форме."
        case (_, "steam"): return "Готовят на пару, поэтому блюдо остаётся мягким."
        case (_, "pan"): return "Коротко прогревают на сковороде и сразу раскладывают по тарелкам."
        default: return "Блюдо готовят в одной посуде и раскладывают по тарелкам."
        }
    }
}
