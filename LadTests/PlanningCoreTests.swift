import XCTest
import UIKit
import SwiftUI
@testable import Lad

final class PlanningCoreTests: XCTestCase {
    @MainActor func testWeightHistoryRecordsProfileChangesWithoutInventingOldDates() {
        let store = LadStore()
        store.state = .initial(); store.state.members = [portionProfile()]
        XCTAssertTrue(WeightJournal.entries(store.state, memberID: "adult").isEmpty)
        store.updateMember(store.state.members[0])
        XCTAssertTrue(WeightJournal.entries(store.state, memberID: "adult").isEmpty)
        var changed = store.state.members[0]; changed.weightKg = 61.5
        store.updateMember(changed)
        XCTAssertEqual(WeightJournal.entries(store.state, memberID: "adult").count, 1)
        XCTAssertEqual(WeightJournal.entries(store.state, memberID: "adult").last?.kilograms, 61.5)
        store.updateMember(changed)
        XCTAssertEqual(WeightJournal.entries(store.state, memberID: "adult").count, 1)
    }

    @MainActor func testWeightHistoryBackdatingEditingAndDeletionPreserveCurrentProfile() {
        let store = LadStore()
        store.state = .initial(); store.state.members = [portionProfile()]
        let latest = WeightEntry(id: "latest", memberID: "adult", measuredAt: store.now, kilograms: 62)
        var older = WeightEntry(id: "older", memberID: "adult", measuredAt: store.now.addingTimeInterval(-86400), kilograms: 65)
        XCTAssertTrue(store.saveWeightEntry(latest))
        XCTAssertTrue(store.saveWeightEntry(older))
        XCTAssertEqual(store.state.members[0].weightKg, 62)
        older.kilograms = 64
        XCTAssertTrue(store.saveWeightEntry(older))
        XCTAssertEqual(WeightJournal.entries(store.state, memberID: "adult").map(\.id), ["older", "latest"])
        XCTAssertEqual(WeightJournal.entries(store.state, memberID: "adult").first?.kilograms, 64)
        store.removeWeightEntry(latest)
        XCTAssertEqual(store.state.members[0].weightKg, 62)
        XCTAssertEqual(store.state.weightEntries?.count, 1)
    }

    @MainActor func testWeightHistoryRejectsInvalidAndFutureMeasurements() {
        let store = LadStore()
        store.state = .initial(); store.state.members = [portionProfile()]
        for weight in [Double.nan, .infinity, -1, 0, 501] {
            XCTAssertFalse(store.saveWeightEntry(WeightEntry(memberID: "adult", measuredAt: store.now, kilograms: weight)))
        }
        XCTAssertFalse(store.saveWeightEntry(WeightEntry(memberID: "unknown", measuredAt: store.now, kilograms: 60)))
        XCTAssertFalse(store.saveWeightEntry(WeightEntry(memberID: "adult", measuredAt: store.now.addingTimeInterval(3600), kilograms: 60)))
        XCTAssertFalse(store.saveWeightEntry(WeightEntry(memberID: "adult", measuredAt: store.now, kilograms: 60, note: String(repeating: "x", count: 1001))))
        store.protectedStateReadFailed = true
        XCTAssertFalse(store.saveWeightEntry(WeightEntry(memberID: "adult", measuredAt: store.now, kilograms: 60)))
        XCTAssertTrue((store.state.weightEntries ?? []).isEmpty)
    }

    func testWeightHistorySurvivesWeekRolloverAndStaysLocalDuringCloudMerge() {
        var localState = DemoState.initial()
        let entry = WeightEntry(memberID: localState.members[0].id, measuredAt: .now, kilograms: 60)
        localState.weightEntries = [entry]
        XCTAssertEqual(DemoState.nextWeek(after: localState, now: .now).weightEntries, [entry])
        var remoteState = localState
        remoteState.weightEntries = [WeightEntry(memberID: entry.memberID, measuredAt: .now, kilograms: 90)]
        let local = PersonalCloudSnapshot(state: localState, modifiedAt: Date(timeIntervalSince1970: 1), deviceID: "a")
        let remote = PersonalCloudSnapshot(state: remoteState, modifiedAt: Date(timeIntervalSince1970: 2), deviceID: "b")
        XCTAssertEqual(PersonalCloudSnapshot.merge(local, remote).state.weightEntries, [entry])
    }

    func testOldStateDecodesWithoutWeightHistoryAndCSVIsEscaped() throws {
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(DemoState.initial())) as? [String: Any])
        old.removeValue(forKey: "weightEntries")
        let restored = try JSONDecoder().decode(DemoState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(restored.weightEntries)
        let csv = WeightJournal.csv([WeightEntry(id: "id", memberID: "adult", measuredAt: Date(timeIntervalSince1970: 0), kilograms: 60.25, note: "=1+1")], name: "Name, \"quoted\"")
        XCTAssertTrue(csv.contains("1970-01-01T00:00:00Z"))
        XCTAssertTrue(csv.contains("60.25"))
        XCTAssertTrue(csv.contains("\"Name, \"\"quoted\"\"\""))
        XCTAssertTrue(csv.contains("\"'=1+1\""))
        XCTAssertTrue(csv.contains("\r\n"))
    }

    func testLegalDocumentsAreBundledInAllThreeLanguages() {
        for language in ["en", "ru", "uk"] {
            for page in LegalPage.allCases {
                XCTAssertGreaterThan(page.text(language: language).count, 500, "\(language)/\(page.rawValue)")
            }
        }
        XCTAssertTrue(LegalPage.privacy.text(language: "en").contains("iCloud"))
        XCTAssertTrue(LegalPage.authors.text(language: "ru").contains("вознагражд"))
    }

    @MainActor func testSettingsCountryPricesFitSmallPhoneInEveryLanguage() {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        let originalCountry = UserDefaults.standard.string(forKey: LadStore.referencePriceCountryKey)
        defer {
            UserDefaults.standard.set(original, forKey: L10n.languageKey)
            if let originalCountry {
                UserDefaults.standard.set(originalCountry, forKey: LadStore.referencePriceCountryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: LadStore.referencePriceCountryKey)
            }
        }
        let store = LadStore()
        store.state = .initial()
        store.setReferencePriceCountry("IL")
        XCTAssertGreaterThan(store.referencePriceCatalog.records(country: "IL").count, 8)
        XCTAssertGreaterThan(store.ingredientPrices.count, 8)
        let shelf = store.ingredientPrices.filter { $0.reference?.method == ShelfPrices.method }
        XCTAssertGreaterThan(shelf.count, 20)
        XCTAssertNotNil(shelf.first { $0.productName == "Гречка" })
        for language in ["ru", "en", "uk"] {
            UserDefaults.standard.set(language, forKey: L10n.languageKey)
            let controller = UIHostingController(rootView: LanguageSettingsSheet().environmentObject(store)
                .environment(\.locale, Locale(identifier: language)))
            controller.loadViewIfNeeded()
            let size = controller.sizeThatFits(in: CGSize(width: 320, height: 700))
            XCTAssertLessThanOrEqual(size.width, 321, language)
            XCTAssertGreaterThan(size.height, 0, language)
        }
    }

    @MainActor func testWeightAndLegalViewsFitSmallPhoneInEveryLanguage() {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let store = LadStore()
        store.state = .initial(); store.state.members = [portionProfile()]
        for language in ["ru", "en", "uk"] {
            UserDefaults.standard.set(language, forKey: L10n.languageKey)
            for count in [0, 1, 24] {
                store.state.weightEntries = (0..<count).map {
                    WeightEntry(memberID: "adult", measuredAt: store.now.addingTimeInterval(Double(-$0) * 86400), kilograms: 60 + Double($0) * 0.1)
                }
                let controller = UIHostingController(rootView: WeightHistoryView().environmentObject(store)
                    .environment(\.locale, Locale(identifier: language)))
                controller.loadViewIfNeeded()
                XCTAssertLessThanOrEqual(controller.sizeThatFits(in: CGSize(width: 320, height: 700)).width, 321, language)
            }
            for page in LegalPage.allCases {
                let controller = UIHostingController(rootView: LegalDocumentView(page: page).environmentObject(store))
                controller.loadViewIfNeeded()
                XCTAssertLessThanOrEqual(controller.sizeThatFits(in: CGSize(width: 320, height: 700)).width, 321, language)
            }
        }
    }

    @MainActor func testPersonalCloudSnapshotOmitsWeightHistory() {
        let store = LadStore()
        store.state = .initial()
        store.state.weightEntries = [WeightEntry(memberID: store.currentMember.id, measuredAt: store.now, kilograms: 60)]
        XCTAssertNil(store.cloudSnapshot().state.weightEntries)
        XCTAssertEqual(store.state.weightEntries?.count, 1)
    }

    func testStoreReleasePolicyDisablesPilotAccessAndPersonalCloud() {
        #if DEBUG
        XCTAssertFalse(ReleasePolicy.isStoreRelease)
        #else
        XCTAssertTrue(ReleasePolicy.isStoreRelease)
        XCTAssertFalse(PrivateRecipeAccess.isConfigured)
        XCTAssertNil(PrivateRecipeAccess.catalogToken)
        XCTAssertFalse(PersonalSettings.cloudAvailable)
        XCTAssertTrue(PrivateRecipeAccess.cached().isEmpty)
        #endif
    }

    func testOilBottlePriceConvertsRecipeGramsWithoutInventingPowderDensity() throws {
        let price = IngredientPrice(productName: "Оливковое масло", packagePrice: 45,
                                    packageQuantity: 500, packageUnit: "мл", currency: "ILS")
        let oil = Ingredient(name: "Оливковое масло", amount: 9, unit: "г", category: "Бакалея")
        let cost = try XCTUnwrap(FoodCost.ingredient(oil, prices: [price]))
        XCTAssertEqual(cost.amount, 0.9, accuracy: 0.0001)
        XCTAssertTrue(cost.approximate)
        let oilByVolume = Ingredient(name: "Оливковое масло", amount: 10, unit: "мл", category: "Бакалея")
        XCTAssertEqual(try XCTUnwrap(FoodCost.ingredient(oilByVolume, prices: [price])).amount, 0.9, accuracy: 0.0001)
        let flour = Ingredient(name: "Рисовая мука", amount: 10, unit: "г", category: "Бакалея")
        let flourPrice = IngredientPrice(productName: "Рисовая мука", packagePrice: 20,
                                         packageQuantity: 100, packageUnit: "мл", currency: "ILS")
        XCTAssertNil(FoodCost.ingredient(flour, prices: [flourPrice]))
    }

    func testNewExactCompositionTakesPriorityOverOldFoodAnalogue() throws {
        for name in ["Кунжутное масло", "Ореховое масло", "Петрушка", "Базилик"] {
            let recipe = Recipe(id: "raw", title: "Test", caption: "", image: "", cuisine: "", minutes: 0,
                                kcal: nil, protein: nil, allergens: [], ingredients: [
                                    Ingredient(name: name, amount: 100, unit: "г", category: "Бакалея")], steps: [])
            let reference = try XCTUnwrap(NutrientEstimator.ingredientComposition(name: name)["vitamin_e"])
            let estimated = try XCTUnwrap(NutrientEstimator.estimate(recipe)["vitamin_e"])
            XCTAssertEqual(estimated.amount, reference.amount, accuracy: 0.0001, name)
        }
    }

    func testCookedDishWritesSaltPepperAndTimedSteps() throws {
        let dish = try XCTUnwrap(Recipe.all.first { $0.id == "chicken-buckwheat" })
        XCTAssertEqual(CookingGuide.unmeasuredTaste(dish), ["Соль", "Чёрный перец"])
        let minutes = CookingGuide.stepMinutes(dish)
        XCTAssertEqual(minutes.count, dish.steps.count)
        XCTAssertEqual(minutes.reduce(0, +), dish.minutes)
        XCTAssertTrue(minutes.allSatisfy { $0 >= 1 })
        let salted = try XCTUnwrap(Recipe.all.first { $0.ingredients.contains { $0.name == "Соль" } && !$0.isBeverage })
        XCTAssertFalse(CookingGuide.unmeasuredTaste(salted).contains("Соль"))
    }

    func testSpokenStepsUseGlassesOfGrainAndWater() throws {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let dish = try XCTUnwrap(Recipe.all.first { $0.id == "chicken-buckwheat" })
        let names = dish.ingredients.map(\.name)
        UserDefaults.standard.set("ru", forKey: L10n.languageKey)
        let one = CookingGuide.spokenStep(recipe: dish, index: 0, portions: 1)
        XCTAssertTrue(one.contains("Промойте"), one)
        XCTAssertTrue(one.contains("треть стакана"), one)
        XCTAssertTrue(one.contains("гречк"), one)
        XCTAssertTrue(one.contains("вод"), one)
        XCTAssertTrue(one.contains("70"), one)
        XCTAssertTrue(one.contains("до закипания"), one)
        XCTAssertTrue(one.contains("ложк"), one)
        XCTAssertTrue(one.contains("\(CookingGuide.stepMinutes(dish)[0])"), one)
        XCTAssertEqual(dish.ingredients.map(\.name), names)
        let family = CookingGuide.spokenStep(recipe: dish, index: 0, portions: 3)
        XCTAssertTrue(family.contains("стакан гречки"), family)
        XCTAssertTrue(family.contains("два стакана воды"), family)
        XCTAssertTrue(family.contains("210"), family)
        let larger = CookingGuide.spokenStep(recipe: dish, index: 0, portions: 4)
        XCTAssertTrue(larger.contains("280"), larger)
        let fry = CookingGuide.spokenStep(recipe: dish, index: 1, portions: 1)
        XCTAssertTrue(fry.contains("Нарежьте куриное"), fry)
        XCTAssertTrue(fry.contains("160"), fry)
        XCTAssertTrue(fry.contains("ложк"), fry)
        let plate = CookingGuide.spokenStep(recipe: dish, index: 2, portions: 1)
        XCTAssertTrue(plate.contains("огурец"), plate)
        XCTAssertTrue(plate.contains("120"), plate)
        let pasta = try XCTUnwrap(Recipe.all.first { $0.id == "vegetable-pasta" })
        let boiled = CookingGuide.spokenStep(recipe: pasta, index: 0, portions: 1)
        XCTAssertTrue(boiled.contains("макарон"), boiled)
        XCTAssertTrue(boiled.contains("кастрюлю"), boiled)
        XCTAssertTrue(boiled.contains("вод"), boiled)
        let salmon = try XCTUnwrap(Recipe.all.first { $0.id == "salmon" })
        let oven = CookingGuide.spokenStep(recipe: salmon, index: 0, portions: 1)
        XCTAssertTrue(oven.contains("200"), oven)
        XCTAssertTrue(oven.contains("духовку"), oven)
        XCTAssertTrue(oven.contains("180"), oven)
        let cheese = Recipe(id: "cheese-speech", title: "Сыр", caption: "", image: "", cuisine: "", minutes: 5,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Сыр", amount: 25, unit: "г", category: "Молочные продукты")
                            ], steps: ["Пока внутри не останется сырого.", "Посыпьте сыром."])
        XCTAssertFalse(CookingGuide.spokenStep(recipe: cheese, index: 0, portions: 1).contains("25"))
        XCTAssertTrue(CookingGuide.spokenStep(recipe: cheese, index: 1, portions: 1).contains("25"))
        UserDefaults.standard.set("en", forKey: L10n.languageKey)
        let english = CookingGuide.spokenStep(recipe: dish, index: 0, portions: 1)
        XCTAssertTrue(english.contains("Rinse the buckwheat"), english)
        XCTAssertTrue(english.contains("glass"), english)
        XCTAssertTrue(english.contains("buckwheat"), english)
        XCTAssertTrue(english.contains("water"), english)
        XCTAssertTrue(english.contains("before it boils"), english)
        XCTAssertNil(english.range(of: "[А-Яа-яЁёІіЇїЄєҐґ]", options: .regularExpression), english)
        UserDefaults.standard.set("uk", forKey: L10n.languageKey)
        let ukrainian = CookingGuide.spokenStep(recipe: dish, index: 0, portions: 1)
        XCTAssertTrue(ukrainian.contains("Промийте"), ukrainian)
        XCTAssertTrue(ukrainian.contains("склян"), ukrainian)
        XCTAssertTrue(ukrainian.contains("вод"), ukrainian)
        XCTAssertTrue(ukrainian.contains("до закипання"), ukrainian)
        UserDefaults.standard.set("ru", forKey: L10n.languageKey)
        let sweet = Recipe(id: "sweet-speech", title: "Каша", caption: "", image: "", cuisine: "", minutes: 10,
                           kcal: nil, protein: nil, allergens: [], ingredients: [
                            Ingredient(name: "Гречка", amount: 70, unit: "г", category: "Бакалея"),
                            Ingredient(name: "Сахар", amount: 10, unit: "г", category: "Бакалея")
                           ], steps: ["Промойте гречку и сварите до готовности."])
        XCTAssertFalse(CookingGuide.spokenStep(recipe: sweet, index: 0, portions: 1).contains("до закипания"))
        let alreadySalted = Recipe(id: "salt-speech", title: "Каша", caption: "", image: "", cuisine: "", minutes: 15,
                                   kcal: nil, protein: nil, allergens: [], ingredients: [
                                    Ingredient(name: "Гречка", amount: 70, unit: "г", category: "Бакалея"),
                                    Ingredient(name: "Вода", amount: 200, unit: "мл", category: "Напитки"),
                                    Ingredient(name: "Соль", amount: 2, unit: "г", category: "Бакалея")
                                   ], steps: ["Промойте гречку, залейте водой и добавьте соль. Варите под крышкой 15 минут."])
        let timed = CookingGuide.spokenStep(recipe: alreadySalted, index: 0, portions: 1)
        XCTAssertTrue(timed.contains("до закипания"), timed)
        XCTAssertTrue(timed.contains("Эту соль всыпьте"), timed)
        XCTAssertTrue(timed.contains("половина чайной ложки"), timed)
        XCTAssertFalse(timed.contains("Соль всыпьте в холодную воду до закипания:"), timed)
        let salmonBake = CookingGuide.spokenStep(recipe: salmon, index: 0, portions: 1)
        XCTAssertTrue(salmonBake.contains("до духовки"), salmonBake)
    }

    func testEveryShortStepGainsAHouseholdLine() {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        UserDefaults.standard.set("ru", forKey: L10n.languageKey)
        let recipes = Recipe.launchRecipes
        XCTAssertEqual(recipes.count, 200)
        var thin: [String] = []
        for recipe in recipes {
            for index in recipe.steps.indices {
                let step = recipe.steps[index]
                let spoken = CookingGuide.spokenStep(recipe: recipe, index: index, portions: 1)
                let alreadyMeasured = step.contains("°")
                if step.count < 100, !alreadyMeasured, spoken.count < step.count + 40 {
                    thin.append("\(recipe.title) #\(index) \(spoken)")
                }
                if step.lowercased().contains("сковород"), spoken.contains("Духовку разогрейте") {
                    thin.append("oven on pan: \(recipe.title) #\(index)")
                }
            }
        }
        XCTAssertTrue(thin.isEmpty, thin.joined(separator: "\n"))
    }

    func testIngredientPricesUsePackSizeAndRecipeYield() throws {
        var recipe = Recipe(id: "cost", title: "Cost", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [],
                            ingredients: [Ingredient(name: "Бурый рис", amount: 200, unit: "г", category: "Бакалея")], steps: ["Cook"])
        recipe.baseServings = 4
        let prices = [IngredientPrice(productName: "brown rice", packagePrice: 10, packageQuantity: 1,
                                      packageUnit: "кг", currency: "ILS")]
        let one = FoodCost.recipe(recipe, prices: prices)
        XCTAssertEqual(try XCTUnwrap(one.totals["ILS"]), 0.5, accuracy: 0.00001)
        XCTAssertTrue(one.isComplete)
        XCTAssertEqual(try XCTUnwrap(FoodCost.recipe(recipe, prices: prices, servings: 3).totals["ILS"]), 1.5, accuracy: 0.00001)
    }

    func testFoodCostDoesNotHideMissingPricesOrMixCurrencies() throws {
        let recipe = Recipe(id: "cost", title: "Cost", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Яблоко", amount: 100, unit: "г", category: "Фрукты"),
                                Ingredient(name: "Йогурт натуральный", amount: 100, unit: "г", category: "Молочные продукты"),
                                Ingredient(name: "Вода", amount: 100, unit: "мл", category: "Напитки")], steps: ["Mix"])
        let prices = [IngredientPrice(productName: "Яблоко", packagePrice: 8, packageQuantity: 1, packageUnit: "кг", currency: "ILS"),
                      IngredientPrice(productName: "Йогурт натуральный", packagePrice: 2, packageQuantity: 200, packageUnit: "г", currency: "EUR")]
        let cost = FoodCost.recipe(recipe, prices: prices)
        XCTAssertEqual(cost.missingNames, ["Вода"])
        XCTAssertFalse(cost.isComplete)
        XCTAssertEqual(try XCTUnwrap(cost.totals["ILS"]), 0.8, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(cost.totals["EUR"]), 1, accuracy: 0.00001)
        let water = IngredientPrice(productName: "Вода", packagePrice: 0, packageQuantity: 1, packageUnit: "л", currency: "ILS")
        XCTAssertTrue(FoodCost.recipe(recipe, prices: prices + [water]).isComplete)
    }

    func testPricingKeepsRawAndCookedProductsDistinctAndRejectsInvalidPack() {
        let dryPrice = IngredientPrice(productName: "Рис", packagePrice: 10, packageQuantity: 1, packageUnit: "кг", currency: "UAH")
        XCTAssertNil(FoodCost.price(for: "Рис варёный", prices: [dryPrice]))
        let broken = IngredientPrice(productName: "Рис", packagePrice: 10, packageQuantity: 0, packageUnit: "кг", currency: "UAH")
        XCTAssertFalse(broken.isValid)
        XCTAssertNil(FoodCost.price(for: "Рис", prices: [broken]))
        var deleted = dryPrice
        deleted.updatedAt = dryPrice.updatedAt.addingTimeInterval(1)
        deleted.deletedAt = deleted.updatedAt
        XCTAssertNil(FoodCost.price(for: "Рис", prices: FoodCost.merge([deleted], [dryPrice])))
    }

    func testCostRangesAndHouseholdMeasuresAreMarkedApproximate() throws {
        let ingredient = Ingredient(name: "Бурый рис", amount: 0.5, unit: "стакан", category: "Бакалея", amountMax: 1)
        let price = IngredientPrice(productName: "Бурый рис", packagePrice: 20, packageQuantity: 1, packageUnit: "кг", currency: "USD")
        let cost = try XCTUnwrap(FoodCost.ingredient(ingredient, prices: [price]))
        XCTAssertEqual(cost.amount, 1.8, accuracy: 0.00001)
        XCTAssertEqual(cost.maximum, 3.6, accuracy: 0.00001)
        XCTAssertTrue(cost.approximate)
    }

    func testCloudMergeKeepsPricesPerProductIncludingDeletions() {
        let at = Date(timeIntervalSince1970: 100)
        let apple = IngredientPrice(productName: "Яблоко", packagePrice: 3, packageQuantity: 1,
                                    packageUnit: "кг", currency: "EUR", updatedAt: at)
        var newer = apple
        newer.packagePrice = 4; newer.updatedAt = at.addingTimeInterval(5)
        let rice = IngredientPrice(productName: "Бурый рис", packagePrice: 2, packageQuantity: 1,
                                   packageUnit: "кг", currency: "EUR", updatedAt: at)
        var first = DemoState.initial(); first.activeCourseIDs = ["lad-starter"]; first.ingredientPrices = [newer]
        var second = DemoState.initial(); second.activeCourseIDs = ["lad-starter"]; second.ingredientPrices = [apple, rice]
        let local = PersonalCloudSnapshot(state: first, modifiedAt: at, deviceID: "a")
        let remote = PersonalCloudSnapshot(state: second, modifiedAt: at.addingTimeInterval(10), deviceID: "b")
        let merged = PersonalCloudSnapshot.merge(local, remote)
        XCTAssertEqual(merged.state.activeCourseIDs, [CourseAliases.mediterranean])
        XCTAssertEqual(merged.state.ingredientPrices?.count, 2)
        XCTAssertEqual(FoodCost.price(for: "Яблоко", prices: merged.state.ingredientPrices ?? [])?.packagePrice, 4)
        var deleted = newer; deleted.deletedAt = newer.updatedAt
        XCTAssertNil(FoodCost.price(for: "Яблоко", prices: FoodCost.merge([deleted], [newer])))
    }

    func testDefaultCourseCombinesMediterraneanBreakfastsAndSourceMeals() throws {
        let course = try XCTUnwrap(CourseCatalogAccess.bundledCourses.first { $0.id == CourseAliases.mediterranean })
        XCTAssertEqual(CourseCatalogAccess.bundledCourses.count, 1)
        XCTAssertFalse(CourseCatalogAccess.bundledCourses.contains { $0.id == "lad-starter" })
        XCTAssertEqual(course.recipeIDs.count, 200)
        XCTAssertEqual(Set(course.recipeIDs).count, 200)
        XCTAssertEqual(course.totalRecipeCount, 200)
        XCTAssertTrue(course.isCombinedDefaultMenu)
        XCTAssertEqual(course.breakfastRecipeIDs?.count, 36)
        XCTAssertEqual(Recipe.launchRecipes.count, 200)
        XCTAssertEqual(course.generalTimingRules.map(\.mealKind), [0, 1, 2])
        XCTAssertNil(course.days)
        for recipe in Recipe.launchRecipes {
            XCTAssertFalse(recipe.mealKinds.isEmpty, recipe.id)
            XCTAssertTrue(recipe.mealKinds.allSatisfy { (0...2).contains($0) }, recipe.id)
            XCTAssertEqual(course.breakfastRecipeIDs?.contains(recipe.id), recipe.mealKinds == [0])
        }
        for pair in course.suggestedPairs ?? [] {
            XCTAssertEqual(Recipe.launchRecipes.first { $0.id == pair.lunchRecipeID }?.mealKinds, [1])
            if let id = pair.dinnerRecipeID { XCTAssertEqual(Recipe.launchRecipes.first { $0.id == id }?.mealKinds, [2]) }
        }
        XCTAssertEqual(CourseAliases.canonical(["lad-starter", "mediterranean-ideas"]), [CourseAliases.mediterranean])
        var previous = DemoState.initial()
        previous.activeCourseIDs = ["lad-starter"]
        previous.ingredientPrices = [IngredientPrice(productName: "Яблоко", packagePrice: 10, packageQuantity: 1, packageUnit: "кг", currency: "ILS")]
        let next = DemoState.nextWeek(after: previous, now: .now)
        XCTAssertEqual(next.activeCourseIDs, [CourseAliases.mediterranean])
        XCTAssertEqual(next.ingredientPrices?.count, 1)
        XCTAssertFalse(next.slots.contains { $0.recipeID == Recipe.unplanned.id })
    }

    func testIngredientCatalogueHasOneCardPerProductAndCompletePhotos() throws {
        XCTAssertEqual(IngredientCatalog.all.count, 135)
        XCTAssertEqual(IngredientCatalog.product("Цукини")?.id, IngredientCatalog.product("Кабачок")?.id)
        XCTAssertEqual(IngredientCatalog.product("Сладкий перец")?.id, IngredientCatalog.product("Перец сладкий")?.id)
        for product in IngredientCatalog.all {
            XCTAssertNotNil(UIImage(named: product.image), product.name)
            XCTAssertFalse(product.description.ru.isEmpty)
            XCTAssertFalse(product.description.en.isEmpty)
            XCTAssertFalse(product.description.uk.isEmpty)
            XCTAssertFalse(product.storage.ru.isEmpty)
        }
        for recipe in Recipe.all {
            for ingredient in recipe.ingredients { XCTAssertNotNil(IngredientCatalog.product(ingredient.name), ingredient.name) }
        }
        for recipe in Recipe.all where recipe.id.hasPrefix("med-") {
            XCTAssertEqual(recipe.steps.count, recipe.stepImageIDs.count)
            for image in recipe.stepImageIDs { XCTAssertNotNil(image.flatMap { UIImage(named: $0) }) }
        }
        XCTAssertGreaterThan(NutrientEstimator.ingredientComposition(name: "Нут")["folate"]?.amount ?? 0, 0)
        XCTAssertGreaterThan(NutrientEstimator.ingredientComposition(name: "Шпинат")["vitamin_k"]?.amount ?? 0, 0)
        XCTAssertEqual(IngredientAllergens.inferred(from: [Ingredient(name: "Булгур", amount: 50, unit: "г", category: "Бакалея")]), ["Пшеница"])
    }

    private func diaryEntry(_ foods: [DiaryFood], id: String = "entry", at date: Date = .now) -> DiaryEntry {
        DiaryEntry(id: id, memberID: "adult", memberName: "Test", eatenAt: date, mealKind: 1, foods: foods)
    }

    func testDiaryCapturesImmutableNutritionAndScalesActualServing() throws {
        var recipe = portionMeal()
        recipe.nutrients = ["vitamin_c": NutrientValue(amount: 20, unit: "мг", source: "fixture", coverage: 1)]
        let food = DiaryFood(recipe: recipe, servings: 1.5)
        recipe = portionMeal(kcal: 100)
        recipe.nutrients = ["vitamin_c": NutrientValue(amount: 100, unit: "мг", source: "fixture", coverage: 1)]
        recipe.nutrients["vitamin_c"]?.amount = 100
        XCTAssertEqual(food.kcal, 750)
        XCTAssertEqual(food.nutrients["vitamin_c"]?.amount, 30)
        XCTAssertEqual(food.nutrients["protein"]?.amount, 30)
        XCTAssertEqual(try JSONDecoder().decode(DiaryFood.self, from: JSONEncoder().encode(food)).kcal, 750)
    }

    func testDiaryUnknownNutritionIsNotReportedAsZero() {
        let known = DiaryFood(title: "known", kcal: 100, nutrients: ["protein": NutrientValue(amount: 10, unit: "г", source: "", coverage: 1)])
        let unknown = DiaryFood(title: "unknown")
        let entry = diaryEntry([known, unknown])
        XCTAssertNil(entry.kcal)
        XCTAssertEqual(DiaryCore.total([entry], key: "protein").amount, 10)
        XCTAssertEqual(DiaryCore.total([entry], key: "protein").unknown, 1)
        XCTAssertEqual(DiaryCore.total([entry], key: "vitamin_c").unknown, 2)
    }

    func testDiaryRejectsInvalidPortionsAndManualAmounts() {
        for amount in [-1.0, 0, .nan, .infinity, 21] {
            XCTAssertFalse(DiaryFood(title: "food", servings: amount).isValid)
        }
        XCTAssertFalse(DiaryFood(title: " ").isValid)
        XCTAssertFalse(DiaryFood(title: "food", kcal: -10).isValid)
        var food = DiaryFood(title: "food")
        food.actualWeightGrams = -10
        XCTAssertFalse(food.isValid)
    }

    func testPreparedBatchIsFiniteAndEditingOrDeletingRestoresRemainder() {
        let batch = PreparedDish(id: "batch", food: DiaryFood(recipe: portionMeal(), servings: 1), totalServings: 3, preparedAt: .now, useBy: .now)
        var food = batch.food; food.preparedDishID = batch.id; food.servings = 1.5
        let first = diaryEntry([food])
        XCTAssertEqual(batch.remaining(in: [first]), 1.5)
        food.servings = 1
        XCTAssertEqual(batch.remaining(in: [diaryEntry([food])]), 2)
        XCTAssertEqual(batch.remaining(in: []), 3)
        XCTAssertEqual(batch.remaining(in: [first, diaryEntry([food], id: "another")]), 0.5)
        var discarded = batch; discarded.discardedAt = .now
        XCTAssertEqual(discarded.remaining(in: []), 0)
    }

    func testReadyFoodDoesNotBuyRawIngredientsTwiceAndCannotCoverUnlimitedMeals() throws {
        var member = portionProfile(); member.automaticPortions = false
        let recipe = portionMeal()
        let start = Calendar.current.startOfDay(for: .now)
        let batch = PreparedDish(id: "batch", food: DiaryFood(recipe: recipe, servings: 1), totalServings: 1.5, preparedAt: start, useBy: start)
        var slots = portionDay(recipe)
        for index in slots.indices { slots[index].preparedDishIDs = [recipe.id: batch.id] }
        let plan = PlanningCore.resolvePlan(slots: slots, members: [member], recipes: [recipe], pantry: [], startDate: start, now: start, preparedDishes: [batch])
        XCTAssertEqual(plan.slots["0-0"]?.preparedServings, 1)
        XCTAssertEqual(plan.slots["0-1"]?.preparedServings, 0.5)
        XCTAssertEqual(plan.slots["0-2"]?.preparedServings, 0)
        XCTAssertEqual(try XCTUnwrap(plan.shoppingNeeds.first).required, 150, accuracy: 0.001)
    }

    func testExpiredOrNotYetPreparedBatchNeverCoversPlanning() throws {
        var member = portionProfile(); member.automaticPortions = false
        let recipe = portionMeal(), start = Calendar.current.startOfDay(for: .now)
        var slot = portionDay(recipe)[0]; slot.preparedDishIDs = [recipe.id: "batch"]
        for invalidDate in [-1, 1] {
            let date = Calendar.current.date(byAdding: .day, value: invalidDate, to: start)!
            let batch = PreparedDish(id: "batch", food: DiaryFood(recipe: recipe, servings: 1), totalServings: 5,
                                     preparedAt: invalidDate > 0 ? date : date.addingTimeInterval(-86400), useBy: date)
            let plan = PlanningCore.resolvePlan(slots: [slot], members: [member], recipes: [recipe], pantry: [], startDate: start, now: start, preparedDishes: [batch])
            XCTAssertEqual(plan.slots[slot.id]?.preparedServings, 0)
            XCTAssertEqual(plan.shoppingNeeds.first?.required, 100)
        }
    }

    func testCSVQuotesCommasNewlinesAndNeutralizesSpreadsheetFormulas() {
        var entry = diaryEntry([DiaryFood(title: "=SUM(A1),\"fruit\"\nsecond line", kcal: nil)])
        entry.memberName = "+cmd"; entry.note = "@note"
        let csv = DiaryCore.csv([entry])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}\"entry_id\""))
        XCTAssertTrue(csv.contains("\"'+cmd\""))
        XCTAssertTrue(csv.contains("\"'=SUM(A1),\"\"fruit\"\"\nsecond line\""))
        XCTAssertTrue(csv.contains("\"'@note\""))
        XCTAssertTrue(csv.contains("\"\",\"false\""), "Unknown kcal must be an empty cell")
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testCSVUsesActualScaledAndReheatedSnapshotNotCurrentCatalogue() {
        var food = DiaryFood(title: "fixture", servings: 2, kcal: 50, nutrients: ["vitamin_c": NutrientValue(amount: 10, unit: "мг", source: "", coverage: 1)])
        food.preparation = .microwave
        food.reheatedNutrientsPerServing = ["vitamin_c": NutrientValue(amount: 8, unit: "мг", source: "", coverage: 1)]
        let csv = DiaryCore.csv([diaryEntry([food])])
        XCTAssertTrue(csv.contains("\"100.000\""))
        XCTAssertTrue(csv.contains("\"16.000\",\"mg\""))
    }

    func testCloudMergePreservesIndependentDiaryAddsAndLatestEdits() {
        var left = DemoState.initial(), right = left
        var edit = diaryEntry([DiaryFood(title: "old")], id: "shared")
        edit.updatedAt = Date(timeIntervalSince1970: 1)
        left.diaryEntries = [edit, diaryEntry([DiaryFood(title: "left")], id: "left")]
        edit.foods = [DiaryFood(title: "new")]; edit.updatedAt = Date(timeIntervalSince1970: 2)
        right.diaryEntries = [edit, diaryEntry([DiaryFood(title: "right")], id: "right")]
        let a = PersonalCloudSnapshot(state: left, modifiedAt: Date(timeIntervalSince1970: 5), deviceID: "a")
        let b = PersonalCloudSnapshot(state: right, modifiedAt: Date(timeIntervalSince1970: 4), deviceID: "b")
        let result = PersonalCloudSnapshot.merge(a, b)
        XCTAssertEqual(DiaryCore.visible(result.state).count, 3)
        XCTAssertEqual(result.state.diaryEntries?.first { $0.id == "shared" }?.foods.first?.title, "new")
        XCTAssertEqual(result.deviceID, "a")
    }

    func testCloudTombstonePreventsDeletedEntryComingBackAndReconcilesMealMarks() {
        var left = DemoState.initial(), right = left
        let slot = left.slots[0], member = left.members[0]
        var entry = DiaryEntry(id: "deleted", memberID: member.id, memberName: member.name, eatenAt: .now, mealKind: slot.kind,
                              planKey: DiaryCore.planKey(startDate: left.startDate, slotID: slot.id, memberID: member.id), foods: [DiaryFood(title: "meal")])
        entry.updatedAt = Date(timeIntervalSince1970: 1)
        left.diaryEntries = [entry]; left.eatenIDs.insert("\(slot.id)-\(member.id)")
        right.diaryDeletedAt = [entry.id: Date(timeIntervalSince1970: 2)]
        let result = PersonalCloudSnapshot.merge(PersonalCloudSnapshot(state: left, modifiedAt: .now, deviceID: "a"), PersonalCloudSnapshot(state: right, modifiedAt: .distantPast, deviceID: "b"))
        XCTAssertTrue(DiaryCore.visible(result.state).isEmpty)
        XCTAssertFalse(result.state.eatenIDs.contains("\(slot.id)-\(member.id)"))
    }

    func testWeekRolloverKeepsDiaryAndReadyBatchesButNeverReusesOldPlanKeys() {
        var state = DemoState.initial()
        state.diaryEntries = [diaryEntry([DiaryFood(title: "history")])]
        state.preparedDishes = [PreparedDish(food: DiaryFood(title: "leftover"), totalServings: 2, preparedAt: .now, useBy: .now)]
        state.diaryDeletedAt = ["deleted": .now]
        let next = DemoState.nextWeek(after: state, now: state.startDate.addingTimeInterval(7 * 86400))
        XCTAssertEqual(next.diaryEntries?.count, 1)
        XCTAssertEqual(next.preparedDishes?.count, 1)
        XCTAssertNotNil(next.diaryDeletedAt?["deleted"])
        XCTAssertNotEqual(DiaryCore.planKey(startDate: state.startDate, slotID: "0-0", memberID: "a"), DiaryCore.planKey(startDate: next.startDate, slotID: "0-0", memberID: "a"))
    }

    func testNotificationScheduleExcludesEatenSkippedUnplannedAndOtherPeople() {
        var state = DemoState.initial()
        let start = Calendar.current.startOfDay(for: state.startDate)
        state.selectedMemberID = state.members[0].id
        state.slots[0].memberIDs = [state.selectedMemberID]
        state.slots[1].recipeID = Recipe.unplanned.id
        state.slots[2].memberIDs = []
        state.skippedSlotIDs = [state.slots[3].id]
        state.eatenIDs.insert("\(state.slots[4].id)-\(state.selectedMemberID)")
        let reminders = MealReminder.future(state: state, now: start)
        XCTAssertTrue(reminders.contains { $0.id.contains(".0-0.") })
        for index in 1...4 { XCTAssertFalse(reminders.contains { $0.id.contains(".\(state.slots[index].id).") }) }
        XCTAssertTrue(reminders.allSatisfy { $0.date > start })
        XCTAssertLessThanOrEqual(reminders.count, 21)
        let late = start.addingTimeInterval(23 * 3600)
        XCTAssertFalse(MealReminder.future(state: state, now: late).contains { $0.id.contains(".0-0.") })
    }

    func testReheatingKeepsMacrosAndUsesSupportedVitaminFactorsWithoutInventingApplianceDifferences() throws {
        var recipe = Recipe(id: "reheat", title: "Carrots", caption: "", image: "", cuisine: "", minutes: 10, kcal: 100, protein: 2, allergens: [],
                            ingredients: [Ingredient(name: "Морковь", amount: 100, unit: "г", category: "Овощи")], steps: ["Cook"])
        recipe.nutrientPreparationByIngredient = ["Морковь": "simmered"]
        recipe.nutrients = NutrientEstimator.estimate(recipe)
        let reheated = NutrientEstimator.reheated(recipe)
        let before = try XCTUnwrap(recipe.nutrients["vitamin_c"]), after = try XCTUnwrap(reheated["vitamin_c"])
        XCTAssertLessThan(after.amount, before.amount)
        XCTAssertGreaterThan(after.coverage, 0)
        XCTAssertEqual(reheated["calcium"]?.amount, recipe.nutrients["calcium"]?.amount)
        XCTAssertEqual(reheated["protein"]?.amount, recipe.nutrients["protein"]?.amount)
        var microwave = DiaryFood(recipe: recipe, servings: 1), stove = microwave
        microwave.preparation = .microwave; stove.preparation = .stove
        XCTAssertEqual(microwave.nutrients["vitamin_c"]?.amount, stove.nutrients["vitamin_c"]?.amount)
    }

    @MainActor func testDiaryEditsDoNotRewritePlanAndDeletionRestoresMark() {
        let store = LadStore(); store.state = .initial(); store.refreshClock()
        let slot = store.slot(store.currentDay, 0), oldRecipe = slot.recipeID
        var entry = store.diaryDraft(for: slot)
        entry.foods = [DiaryFood(title: "Something else", kcal: 150)]
        XCTAssertTrue(store.saveDiaryEntry(entry))
        XCTAssertEqual(store.slot(slot.day, slot.kind).recipeID, oldRecipe)
        XCTAssertTrue(store.isEaten(slot))
        entry.foods[0].servings = 2
        XCTAssertTrue(store.saveDiaryEntry(entry))
        XCTAssertEqual(store.diary.count, 1)
        XCTAssertEqual(store.diary.first?.kcal, 300)
        store.removeDiaryEntry(entry)
        XCTAssertFalse(store.isEaten(slot)); XCTAssertTrue(store.diary.isEmpty)
    }

    @MainActor func testPreparedFoodCannotBeOverconsumedAndCookingStockDeductionIsIdempotent() {
        let store = LadStore(); store.state = .initial(); store.refreshClock()
        let recipe = portionMeal()
        store.state.pantryItems = [PantryItem(name: "Яйцо", quantity: 400, unit: "г", category: "Яйца"), PantryItem(name: "Соль", quantity: nil, unit: "г", category: "Другое")]
        let batch = PreparedDish(id: "batch", food: DiaryFood(recipe: recipe, servings: 1), totalServings: 2, preparedAt: Date.now.addingTimeInterval(-60), useBy: Date.now.addingTimeInterval(86400))
        store.savePreparedDish(batch, cookedRecipe: recipe, consumePantry: true)
        store.savePreparedDish(batch, cookedRecipe: recipe, consumePantry: true)
        XCTAssertEqual(store.pantry.first { $0.name == "Яйцо" }?.quantity, 200)
        XCTAssertNil(store.pantry.first { $0.name == "Соль" }?.quantity)
        var food = batch.food; food.preparedDishID = batch.id; food.servings = 1.5
        XCTAssertTrue(store.saveDiaryEntry(diaryEntry([food], id: "first", at: store.now)))
        XCTAssertFalse(store.saveDiaryEntry(diaryEntry([food], id: "second", at: store.now)))
        XCTAssertEqual(store.diary.count, 1)
        store.removeDiaryEntry(store.diary[0])
        XCTAssertTrue(store.saveDiaryEntry(diaryEntry([food], id: "second", at: store.now)))
    }

    @MainActor func testPlannedDiaryDraftHasStableIDAndActualTimestamp() {
        let store = LadStore(); store.state = .initial(); store.refreshClock()
        let slot = store.slot(store.currentDay, 0)
        let first = store.diaryDraft(for: slot), second = store.diaryDraft(for: slot)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.eatenAt, store.now)
        XCTAssertTrue(store.saveDiaryEntry(first))
        XCTAssertTrue(store.saveDiaryEntry(second))
        XCTAssertEqual(store.diary.count, 1)
    }

    @MainActor func testDiscardedLeftoversKeepHistoricalEditsButRejectNewConsumption() {
        let store = LadStore(); store.state = .initial(); store.refreshClock()
        let batch = PreparedDish(id: "discard-test", food: DiaryFood(recipe: portionMeal(), servings: 1), totalServings: 3,
                                 preparedAt: store.now.addingTimeInterval(-60), useBy: store.now.addingTimeInterval(86400))
        store.savePreparedDish(batch)
        var food = batch.food; food.preparedDishID = batch.id
        var entry = diaryEntry([food], id: "consumed", at: store.now)
        XCTAssertTrue(store.saveDiaryEntry(entry))
        store.discardPreparedDish(batch)
        XCTAssertTrue(store.preparedDishes.isEmpty)
        entry.note = "Corrected note"
        XCTAssertTrue(store.saveDiaryEntry(entry))
        entry.foods[0].servings = 2
        XCTAssertFalse(store.saveDiaryEntry(entry))
        XCTAssertFalse(store.saveDiaryEntry(diaryEntry([food], id: "new", at: store.now)))
        XCTAssertEqual(store.diary.count, 1)
    }

    private func portionProfile() -> FamilyMember {
        FamilyMember(id: "adult", name: "Test", goal: "Баланс", portion: 1, allergies: [],
                     ageYears: 30, heightCm: 165, weightKg: 60, automaticPortions: true,
                     energySex: .female, energyActivity: .inactive, energyContext: .standard)
    }

    private func portionMeal(kcal: Int? = 500) -> Recipe {
        Recipe(id: "portion-food", title: "Test", caption: "", image: "", cuisine: "", minutes: 10,
               kcal: kcal, protein: 20, allergens: [],
               ingredients: [Ingredient(name: "Яйцо", amount: 100, unit: "г", category: "Яйца")], steps: ["Cook"])
    }

    private func portionDay(_ recipe: Recipe) -> [MealSlot] {
        (0..<3).map { MealSlot(id: "0-\($0)", day: 0, kind: $0, recipeID: recipe.id, memberIDs: ["adult"]) }
    }


    func testHouseholdPortionsStayRealisticOnALightMenuAndKeepTheirRatio() throws {
        func person(_ id: String, age: Int, goal: String) -> FamilyMember {
            FamilyMember(id: id, name: id, goal: goal, portion: 1, allergies: [], ageYears: age)
        }
        let maria = person("maria", age: 35, goal: "Снижение")
        let sergey = person("sergey", age: 39, goal: "Без цели по весу")
        let ester = person("ester", age: 10, goal: "Без цели по весу")
        let beatrice = person("bea", age: 5, goal: "Без цели по весу")
        let people = [maria, sergey, ester, beatrice]
        let food = portionMeal(kcal: 300)
        // Breakfast, lunch and dinner at one authored serving: 900 kcal, like the
        // light default course. Fitting a whole day to it doubled every plate.
        var slots = (0..<3).map { MealSlot(id: "0-\($0)", day: 0, kind: $0, recipeID: food.id, memberIDs: people.map(\.id)) }
        let byID = PersonalPortions.recipeIndex([food])
        func share(_ member: FamilyMember, day: Int = 0, in day0: [MealSlot]? = nil, recipes: [String: Recipe]? = nil) -> Double {
            PersonalPortions.multiplier(member: member, recipe: food, day: day, slots: day0 ?? slots,
                                        byID: recipes ?? byID, skippedIDs: [])
        }
        XCTAssertEqual(share(maria), 0.85 * 1.25, accuracy: 0.0001)
        XCTAssertEqual(share(sergey), 1.25, accuracy: 0.0001)
        XCTAssertEqual(share(ester), 1.0, accuracy: 0.0001)
        XCTAssertEqual(share(beatrice), 0.65 * 1.25, accuracy: 0.0001)
        XCTAssertEqual(people.map { share($0) }.reduce(0, +), 4.125, accuracy: 0.0001, "about four servings for the family, not eight")
        XCTAssertEqual(share(beatrice) / share(sergey), 0.65, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.profileDailyEnergy(beatrice) ?? 0, 1300, accuracy: 0.001)
        // A hearty menu still shrinks the plate to the day's energy.
        let hearty = portionMeal(kcal: 800)
        let heartyDay = (0..<3).map { MealSlot(id: "0-\($0)", day: 0, kind: $0, recipeID: hearty.id, memberIDs: people.map(\.id)) }
        XCTAssertEqual(share(sergey, in: heartyDay, recipes: PersonalPortions.recipeIndex([hearty])), 2000.0 / 2400, accuracy: 0.0001)
        // A missed school lunch does not inflate the other meals.
        slots[1].memberIDs = [maria.id, sergey.id]
        XCTAssertEqual(share(ester), 1.0, accuracy: 0.0001)
        // A day without a planned dinner borrows the average of complete days.
        slots += (0..<2).map { MealSlot(id: "1-\($0)", day: 1, kind: $0, recipeID: food.id, memberIDs: people.map(\.id)) }
        XCTAssertEqual(share(sergey, day: 1), 1.25, accuracy: 0.0001)
        // Without any planned day the stored age share stays as it was.
        XCTAssertEqual(PersonalPortions.multiplier(member: beatrice, recipe: food, day: 0, slots: [], byID: byID, skippedIDs: []), 0.65, accuracy: 0.0001)
        var manual = beatrice
        manual.automaticPortions = false
        manual.portion = 0.8
        XCTAssertEqual(share(manual), 0.8, accuracy: 0.0001)
        var infant = beatrice
        infant.ageYears = 1
        XCTAssertNil(PersonalPortions.menuFittedShare(member: infant, day: 0, slots: slots, byID: byID, skippedIDs: []))
    }

    @MainActor func testLikeKeepsThePlanAndDislikeReplacesOnlyThatDish() async throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        store.maintainsDayMenu = true
        store.fillTodayMenu()
        let before = store.state.slots.map { "\($0.id):\($0.recipeID)" }
        let dinner = store.slot(0, 2).recipeID
        let started = Date()
        store.toggleFavorite(dinner)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.25)
        XCTAssertTrue(store.isFavorite(dinner))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.state.slots.map { "\($0.id):\($0.recipeID)" }, before)
        store.toggleDislike(dinner)
        XCTAssertTrue(store.isDisliked(dinner))
        XCTAssertFalse(store.isFavorite(dinner))
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertNotEqual(store.slot(0, 2).recipeID, dinner)
        for slot in store.state.slots where slot.recipeID != dinner && slot.id != "0-2" {
            let old = before.first { $0.hasPrefix("\(slot.id):") }
            if old?.hasSuffix(":\(dinner)") == false { XCTAssertEqual(old, "\(slot.id):\(slot.recipeID)") }
        }
    }

    @MainActor func testPlainStaplesAreOnlyServedBesideAComposedMain() throws {
        let course = try XCTUnwrap(CourseCatalogAccess.bundledCourses.first)
        let byID = Dictionary(uniqueKeysWithValues: Recipe.launchRecipes.map { ($0.id, $0) })
        for id in ["photo6_plain_buckwheat", "photo6_plain_lentils", "photo4_split_peas_onion",
                   "photo3_cauliflower_puree", "photo6_dry_pan_eggs", "photo2_boiled_eggs"] {
            XCTAssertEqual(byID[id]?.isCourseSide, true, id)
        }
        for pair in course.suggestedPairs ?? [] {
            XCTAssertEqual(byID[pair.lunchRecipeID]?.isCourseSide, false, "pair \(pair.number)")
            XCTAssertEqual(pair.dinnerRecipeID.flatMap { byID[$0] }?.isCourseSide, false, "pair \(pair.number)")
        }
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        store.maintainsDayMenu = true
        store.fillTodayMenu()
        let planned = store.state.slots.filter { $0.recipeID != Recipe.unplanned.id }
        XCTAssertEqual(planned.count, 21)
        for slot in planned {
            XCTAssertFalse(store.recipe(slot).isCourseSide, "\(slot.id): \(slot.recipeID)")
        }
    }

    func testNewCourseDishesAreCompleteAndTranslated() throws {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let course = try XCTUnwrap(CourseCatalogAccess.bundledCourses.first)
        let added = Recipe.launchRecipes.filter { $0.image.hasPrefix("Menu200-") }
        XCTAssertEqual(added.count, 37)
        XCTAssertEqual(added.filter { $0.mealKinds == [0] }.count, 9)
        XCTAssertFalse(added.contains { recipe in recipe.ingredients.contains { $0.name == "Гречка" } },
                       "The menu already has plenty of buckwheat")
        for recipe in added {
            XCTAssertTrue(course.recipeIDs.contains(recipe.id), recipe.id)
            XCTAssertTrue(recipe.isPlanEligible, recipe.id)
            XCTAssertFalse(recipe.isCourseSide, recipe.id)
            XCTAssertNotNil(UIImage(named: recipe.image), recipe.id)
            XCTAssertTrue(try XCTUnwrap(recipe.energyEstimate).unresolvedNames.isEmpty, recipe.id)
            let energy = try XCTUnwrap(recipe.kcal, recipe.id)
            XCTAssertTrue((170...700).contains(energy), "\(recipe.id): \(energy)")
            if recipe.mealKinds == [0] {
                XCTAssertGreaterThanOrEqual(energy, 280, recipe.id)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(recipe.nutrients["protein"]).amount, 15, recipe.id)
            }
            XCTAssertEqual(Set(recipe.nutrientPreparationByIngredient.keys), Set(recipe.ingredients.map(\.name)), recipe.id)
            for allergen in IngredientAllergens.inferred(from: recipe.ingredients) {
                XCTAssertTrue(recipe.allergens.contains(allergen), "\(recipe.id): \(allergen)")
            }
        }
        for language in ["en", "uk"] {
            let folder = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let table = try XCTUnwrap(try PropertyListSerialization.propertyList(
                from: Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("Localizable.strings")),
                options: [], format: nil) as? [String: String])
            for recipe in added {
                for text in [recipe.title, recipe.caption] + recipe.steps {
                    let value = try XCTUnwrap(table[text], "\(language): \(recipe.id): \(text)")
                    if language == "en" {
                        XCTAssertNil(value.range(of: "[А-Яа-яЁёІіЇїЄєҐґ]", options: .regularExpression), recipe.id)
                    }
                }
            }
        }
    }

    func testAdultEnergyUsesAgeHeightWeightSexAndActivity() throws {
        var member = portionProfile()
        XCTAssertEqual(try XCTUnwrap(PersonalPortions.estimatedEnergy(member)), 2021, accuracy: 0.01)
        member.ageYears = 40
        XCTAssertEqual(try XCTUnwrap(PersonalPortions.estimatedEnergy(member)), 1950.9, accuracy: 0.01)
        member.heightCm = 175
        XCTAssertEqual(try XCTUnwrap(PersonalPortions.estimatedEnergy(member)), 2008.1, accuracy: 0.01)
        member.weightKg = 70
        XCTAssertEqual(try XCTUnwrap(PersonalPortions.estimatedEnergy(member)), 2125.2, accuracy: 0.01)
        member.energySex = .male
        member.heightCm = 180
        member.weightKg = 80
        XCTAssertEqual(try XCTUnwrap(PersonalPortions.estimatedEnergy(member)), 2617.87, accuracy: 0.01)
        member.energyActivity = .active
        XCTAssertGreaterThan(try XCTUnwrap(PersonalPortions.estimatedEnergy(member)), 2617.87)
    }

    func testAdultEnergyNeverGuessesMissingFieldsOrSpecialLifeStages() {
        for field in 0..<8 {
            var member = portionProfile()
            switch field {
            case 0: member.ageYears = nil
            case 1: member.ageYears = 18
            case 2: member.heightCm = nil
            case 3: member.weightKg = .nan
            case 4: member.energySex = nil
            case 5: member.energyActivity = nil
            case 6: member.energyContext = .pregnancyOrLactation
            default: member.energyContext = .specialDiet
            }
            XCTAssertNil(PersonalPortions.estimatedEnergy(member), "field \(field)")
            XCTAssertNil(PersonalPortions.foodMultiplier(member: member, day: 0, slots: portionDay(portionMeal()),
                                                        recipes: [portionMeal()], skippedIDs: []))
        }
    }

    func testPersonalFoodPortionsMatchEnergyAndNeverIncreaseDrinks() throws {
        let member = portionProfile()
        let food = portionMeal(kcal: 600)
        let wine = try XCTUnwrap(CourseBeverages.all.first { $0.id == "course-drink-red-wine" })
        var slots = portionDay(food)
        slots[1].setBeverages([wine.id])
        let recipes = [food, wine]
        let factor = try XCTUnwrap(PersonalPortions.foodMultiplier(member: member, day: 0, slots: slots,
                                                                  recipes: recipes, skippedIDs: []))
        XCTAssertEqual(factor, (2021 - 85) / 1800, accuracy: 0.0001)
        let total = slots.reduce(0.0) { result, slot in
            result + slot.allRecipeIDs.compactMap { id in recipes.first { $0.id == id } }.reduce(0) {
                $0 + Double($1.kcal ?? 0) * PersonalPortions.multiplier(member: member, recipe: $1, day: 0,
                                                                      slots: slots, recipes: recipes, skippedIDs: [])
            }
        }
        XCTAssertEqual(total, 2021, accuracy: 0.001)
        XCTAssertEqual(PersonalPortions.multiplier(member: member, recipe: wine, day: 0, slots: slots,
                                                   recipes: recipes, skippedIDs: []), 1)
        let future = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        let stock = PlanningCore.resolvePlan(slots: slots, members: [member], recipes: recipes, pantry: [], startDate: future)
        XCTAssertEqual(try XCTUnwrap(stock.shoppingNeeds.first { $0.name == "Яйцо" }).required, 300 * factor, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stock.shoppingNeeds.first { $0.name == "Красное сухое вино" }).required, 100)
        // A light menu is not stretched past a quarter over the profile plate.
        let light = portionMeal(kcal: 300)
        XCTAssertEqual(PersonalPortions.multiplier(member: member, recipe: light, day: 0, slots: portionDay(light),
                                                   recipes: [light], skippedIDs: []),
                       PersonalPortions.profileShare(member) * 1.25, accuracy: 0.0001)
    }

    func testIncompleteMenuAndUnknownCaloriesKeepManualPortions() {
        let member = portionProfile()
        let food = portionMeal()
        let slots = portionDay(food)
        XCTAssertNil(PersonalPortions.foodMultiplier(member: member, day: 0, slots: Array(slots.prefix(2)),
                                                     recipes: [food], skippedIDs: []))
        XCTAssertNil(PersonalPortions.foodMultiplier(member: member, day: 0, slots: slots,
                                                     recipes: [food], skippedIDs: [slots[0].id]))
        XCTAssertNil(PersonalPortions.foodMultiplier(member: member, day: 0, slots: slots,
                                                     recipes: [portionMeal(kcal: nil)], skippedIDs: []))
        var excluded = slots
        excluded[2].memberIDs = []
        XCTAssertNil(PersonalPortions.foodMultiplier(member: member, day: 0, slots: excluded,
                                                     recipes: [food], skippedIDs: []))
        XCTAssertEqual(PersonalPortions.multiplier(member: member, recipe: food, day: 0,
                                                   slots: Array(slots.prefix(2)), recipes: [food], skippedIDs: []), member.portion)
    }

    func testAutomaticPortionsOptInPreservesManualTargetAndLegacyData() throws {
        var member = portionProfile()
        member.measuredFatMassKg = 12
        member.dailyEnergyTarget = 1800
        XCTAssertEqual(PersonalPortions.energyTarget(member), 1800)
        XCTAssertEqual(PersonalPortions.foodMultiplier(member: member, day: 0, slots: portionDay(portionMeal()),
                                                       recipes: [portionMeal()], skippedIDs: []), 1.2)
        member.automaticPortions = false
        XCTAssertNil(PersonalPortions.foodMultiplier(member: member, day: 0, slots: portionDay(portionMeal()),
                                                     recipes: [portionMeal()], skippedIDs: []))
        let restored = try JSONDecoder().decode(FamilyMember.self, from: JSONEncoder().encode(member))
        XCTAssertEqual(restored.energySex, .female)
        XCTAssertEqual(restored.energyActivity, .inactive)
        XCTAssertEqual(restored.energyContext, .standard)
        XCTAssertEqual(restored.measuredFatMassKg, 12)
        let legacy = #"{"id":"old","name":"Test","goal":"Баланс","portion":1.25,"allergies":[]}"#.data(using: .utf8)!
        let old = try JSONDecoder().decode(FamilyMember.self, from: legacy)
        XCTAssertNil(old.automaticPortions)
        XCTAssertNil(PersonalPortions.energyTarget(old))
        XCTAssertEqual(PersonalPortions.multiplier(member: old, recipe: portionMeal(), day: 0, slots: [], recipes: [], skippedIDs: []), 1.25)
    }

    func testNutrientPreviewShowsFourMainValuesAndMoreRevealsAll() {
        let all = Set(NutrientGuide.displayOrder)
        XCTAssertEqual(NutrientGuide.visibleKeys(available: all, expanded: false), ["protein", "fat", "carbohydrate", "fiber"])
        XCTAssertEqual(NutrientGuide.visibleKeys(available: all, expanded: true), NutrientGuide.displayOrder)
        XCTAssertEqual(NutrientGuide.visibleKeys(available: ["protein", "vitamin_c"], expanded: false), ["protein"])
        XCTAssertEqual(NutrientGuide.visibleKeys(available: ["protein", "vitamin_c"], expanded: true), ["protein", "vitamin_c"])
    }

    @MainActor
    func testPersonalPortionsAreSharedByDayRecipeCookingAndStock() throws {
        let store = LadStore()
        store.state = .initial()
        let member = portionProfile()
        store.state.members = [member]
        store.state.selectedMemberID = member.id
        let recipes = store.allRecipes.filter { !$0.isBeverage && $0.kcal != nil && !$0.isUnavailable && !$0.isUnplanned }
        let chosen = Array(recipes.prefix(3))
        XCTAssertEqual(chosen.count, 3)
        store.state.slots = chosen.enumerated().map { MealSlot(id: "0-\($0.offset)", day: 0, kind: $0.offset,
                                                             recipeID: $0.element.id, memberIDs: [member.id]) }
        let day = store.dayRecipes(for: member, day: 0)
        let total = day.reduce(0.0) { $0 + Double($1.recipe.kcal!) * $1.portion }
        let menu = chosen.reduce(0.0) { $0 + Double($1.kcal!) }
        let fitted = try XCTUnwrap(PersonalPortions.foodMultiplier(member: member, day: 0, slots: store.state.slots,
                                                                  byID: store.recipesByID, skippedIDs: []))
        XCTAssertEqual(fitted * menu, try XCTUnwrap(PersonalPortions.energyTarget(member)), accuracy: 0.001)
        // The plate follows the energy target, up to a quarter over the profile plate.
        XCTAssertEqual(total, menu * min(fitted, PersonalPortions.menuCeiling(member)), accuracy: 0.001)
        XCTAssertEqual(day[0].portion, store.portion(for: member, recipe: chosen[0], slot: store.state.slots[0]))
        var child = member
        child.ageYears = 12
        store.updateMember(child)
        XCTAssertNil(store.state.members[0].automaticPortions)
        XCTAssertNil(store.state.members[0].dailyEnergyTarget)
    }

    @MainActor
    func testCompactNutrientsAndProfileFitSmallPhoneInEveryLanguage() {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let store = LadStore()
        store.state = .initial()
        for language in ["ru", "en", "uk"] {
            UserDefaults.standard.set(language, forKey: L10n.languageKey)
            let views = [AnyView(TodayView()),
                         AnyView(WeekView()),
                         AnyView(FamilyView()),
                         AnyView(CoursesView()),
                         AnyView(MemberEditor(member: portionProfile())),
                         AnyView(RecipeDetailView(recipe: Recipe.all[0])),
                         AnyView(IngredientDetailView(name: "Йогурт греческий")),
                         AnyView(IngredientPriceEditor(name: "Йогурт греческий")),
                         AnyView(PantryEditor(item: PantryItem(name: "Йогурт греческий", quantity: 500, unit: "г", category: "Молочные продукты"))),
                         AnyView(ShoppingView()),
                         AnyView(RecipeCostSummary(recipe: Recipe.all[0], servings: 3)),
                         AnyView(DayNutrientSummary(day: 0))]
            for view in views {
                let controller = UIHostingController(rootView: view.environmentObject(store)
                    .environment(\.locale, Locale(identifier: language)))
                controller.loadViewIfNeeded()
                let size = controller.sizeThatFits(in: CGSize(width: 320, height: 700))
                XCTAssertLessThanOrEqual(size.width, 321, language)
                XCTAssertGreaterThan(size.height, 0, language)
            }
            let savedMembers = store.state.members
            var weighed = portionProfile()
            weighed.id = savedMembers[0].id
            weighed.name = savedMembers[0].name
            store.state.members[0] = weighed
            let gap = UIHostingController(rootView: DayNutrientSummary(day: 0).environmentObject(store)
                .environment(\.locale, Locale(identifier: language)))
            gap.loadViewIfNeeded()
            XCTAssertLessThanOrEqual(gap.sizeThatFits(in: CGSize(width: 320, height: 900)).width, 321, language)
            store.state.members = savedMembers
        }
    }

    func testMetricMeasuresPreserveRangesAndSourceRecipe() throws {
        let source = Ingredient(name: "Бурый рис", amount: 0.5, unit: "стакан", category: "Крупы", amountMax: 1)
        let converted = IngredientMeasures.normalized(source)
        XCTAssertEqual(converted.amount, 90)
        XCTAssertEqual(converted.amountMax, 180)
        XCTAssertEqual(converted.unit, "г")
        XCTAssertEqual(converted.aiEstimated, true)
        XCTAssertEqual(source.unit, "стакан")
        XCTAssertEqual(EnergyEstimator.estimatedGrams(for: source), EnergyEstimator.estimatedGrams(for: converted))
        XCTAssertEqual(IngredientMeasures.normalized(converted).amount, 90)
        let milk = IngredientMeasures.normalized(Ingredient(name: "Молоко", amount: 1, unit: "л", category: "Молочные продукты"))
        XCTAssertEqual(milk.amount, 1000)
        XCTAssertEqual(milk.unit, "мл")
    }

    func testRiceAndYogurtSuggestionsHaveOneMetricUnitPerProduct() {
        let recipe = Recipe(id: "measures", title: "Test", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Бурый рис", amount: 0.5, unit: "стакан", category: "Крупы"),
                                Ingredient(name: "Бурый рис", amount: 100, unit: "г", category: "Крупы"),
                                Ingredient(name: "Йогурт натуральный", amount: 3, unit: "ст. л.", category: "Молочные продукты"),
                                Ingredient(name: "Йогурт натуральный", amount: 100, unit: "мл", category: "Молочные продукты")
                            ], steps: ["Cook"])
        let options = PlanningCore.ingredientSuggestions(recipes: [recipe], pantry: [], query: "")
        XCTAssertEqual(options.count, 2)
        XCTAssertTrue(options.allSatisfy { $0.unit == "г" })
        XCTAssertTrue(PlanningCore.ingredientSuggestions(recipes: [recipe], pantry: [
            PantryItem(name: "Brown rice", quantity: 1, unit: "kg", category: "Крупы")
        ], query: "рис").isEmpty)
    }

    func testAllHouseholdMeasuresUsedByCatalogueBecomeMetric() {
        let measures = [("Банан", "шт."), ("Бурый рис", "стакан"), ("Йогурт натуральный", "ст. л."),
                        ("Куриное филе", "шт."), ("Лимон", "шт."), ("Лук", "шт."), ("Майонез", "ч. л."),
                        ("Минтай", "филе"), ("Морковь", "шт."), ("Огурец", "шт."), ("Разрыхлитель", "щепотка"),
                        ("Растительное масло", "ч. л."), ("Рисовая мука", "ст. л."), ("Сельдерей", "ломтик"),
                        ("Сельдерей", "ч. л."), ("Сладкий перец", "шт."), ("Сметана", "ч. л."),
                        ("Томаты", "шт."), ("Цукини", "шт."), ("Чернослив", "шт."), ("Чеснок", "головка"),
                        ("Чеснок", "зуб."), ("Шампиньоны", "шт."), ("Яблоко", "шт."), ("Яйцо", "шт.")]
        for (name, unit) in measures {
            let item = IngredientMeasures.normalized(Ingredient(name: name, amount: 1, unit: unit, category: ""))
            XCTAssertEqual(item.unit, "г", "\(name) \(unit)")
            XCTAssertGreaterThan(item.amount ?? 0, 0, name)
        }
    }

    func testPantryMetricMigrationIsIdempotentAndPreservesLotIdentity() throws {
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let source = PantryItem(name: "Бурый рис", quantity: 2, unit: "стакан", category: "Крупы", expiresOn: expiry)
        let first = IngredientMeasures.normalized(source)
        let second = IngredientMeasures.normalized(first)
        XCTAssertEqual(first.id, source.id)
        XCTAssertEqual(first.expiresOn, expiry)
        XCTAssertEqual(second.quantity, 360)
        XCTAssertEqual(second.unit, "г")
        XCTAssertEqual(second.quantityEstimated, true)
        let oldJSON = #"{"id":"A62E8EDB-25DC-4B9D-9DBC-AD974C29C230","name":"Рис","quantity":100,"unit":"г","category":"Крупы"}"#
        XCTAssertNil(try JSONDecoder().decode(PantryItem.self, from: Data(oldJSON.utf8)).quantityEstimated)
    }

    func testMixedRiceMeasuresAllocateSameInventoryAndOneShoppingRow() throws {
        let recipe = Recipe(id: "rice", title: "Rice", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Бурый рис", amount: 0.5, unit: "стакан", category: "Крупы"),
                                Ingredient(name: "Бурый рис", amount: 100, unit: "г", category: "Крупы")
                            ], steps: ["Cook"])
        let day = Calendar.current.startOfDay(for: .now)
        let slot = MealSlot(id: "rice", day: 0, kind: 1, recipeID: recipe.id, memberIDs: ["a"])
        let pantry = [PantryItem(name: "Бурый рис", quantity: 0.5, unit: "стакан", category: "Крупы"),
                      PantryItem(name: "Бурый рис", quantity: 100, unit: "г", category: "Крупы")]
        let result = PlanningCore.resolvePlan(slots: [slot], members: [
            FamilyMember(id: "a", name: "A", goal: "", portion: 1, allergies: [])
        ], recipes: [recipe], pantry: pantry, startDate: day, now: day)
        let need = try XCTUnwrap(result.shoppingNeeds.first)
        XCTAssertEqual(result.shoppingNeeds.count, 1)
        XCTAssertEqual(need.unit, "г")
        XCTAssertEqual(need.required, 190)
        XCTAssertEqual(need.available, 190)
        XCTAssertEqual(need.missing, 0)
        XCTAssertTrue(try XCTUnwrap(result.slots[slot.id]).isReady)
    }

    @MainActor
    func testFruitSaladInfersMilkWithoutBlanketVerificationBlock() throws {
        let recipe = Recipe(id: "private:fruit-salad", title: "Salad", caption: "", image: "", cuisine: "",
                            minutes: 10, kcal: 200, protein: 5, allergens: [], ingredients: [
                                Ingredient(name: "Яблоко", amount: 100, unit: "г", category: "Фрукты"),
                                Ingredient(name: "Апельсин", amount: 100, unit: "г", category: "Фрукты"),
                                Ingredient(name: "Киви", amount: 100, unit: "г", category: "Фрукты"),
                                Ingredient(name: "Чернослив", amount: 50, unit: "г", category: "Фрукты"),
                                Ingredient(name: "Йогурт натуральный", amount: 100, unit: "г", category: "Молочные продукты")
                            ], steps: ["Mix"], allergensVerified: false)
        XCTAssertEqual(recipe.knownAllergens, ["Молоко"])
        XCTAssertFalse(recipe.hasUnspecifiedAllergenComposition)
        XCTAssertTrue(recipe.isPlanEligible)
        let store = LadStore()
        store.state = .initial()
        store.replaceCatalogForTesting(recipes: [recipe], courses: [])
        store.state.slots[1].recipeID = recipe.id
        store.state.slots[1].memberIDs = [store.state.members[0].id]
        XCTAssertNil(store.incompatibility(store.slot(0, 1)))
        store.state.members[0].allergies = ["Яйцо"]
        XCTAssertNil(store.incompatibility(store.slot(0, 1)))
        store.state.members[0].allergies = ["Молоко"]
        XCTAssertNotNil(store.incompatibility(store.slot(0, 1)))
    }

    func testEveryDisplayedNutrientHasRolesInAllLanguagesAndAuthoritativeSource() throws {
        for key in NutrientGuide.displayOrder {
            let entry = try XCTUnwrap(NutrientGuide.entries[key], key)
            for language in ["ru", "en", "uk"] { XCTAssertFalse(entry.role(language: language).isEmpty, "\(key) \(language)") }
            XCTAssertTrue(["ods.od.nih.gov", "www.accessdata.fda.gov"].contains(entry.sourceURL.host ?? ""))
            XCTAssertFalse(entry.role(language: "en").unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) })
        }
    }

    func testDynamicRecipeAndAllergenLabelsAreTranslatedInEnglishAndUkrainian() throws {
        let labels = ["Молоко", "Яйцо", "Рыба", "Злаки с глютеном", "Пшеница", "Рожь", "Ячмень", "Овёс",
                      "Ракообразные", "Арахис", "Соя", "Орехи", "Сельдерей", "Горчица", "Кунжут",
                      "Диоксид серы и сульфиты", "Люпин", "Моллюски", "Легко", "Средняя", "Много действий",
                      "Не оценена", "Нравится", "Не нравится", "Все", "Курс снижения веса", "Остальное",
                      "Есть дома", "Не хватает", "Нравится", "Закрытые", "Следующий шаг"] + NutrientGuide.entries.values.map(\.name)
        for language in ["en", "uk"] {
            let bundle = try XCTUnwrap(Bundle(path: XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))))
            for source in labels {
                let value = bundle.localizedString(forKey: source, value: "__missing__", table: "Localizable")
                XCTAssertNotEqual(value, "__missing__", "\(language): \(source)")
                if language == "en" { XCTAssertFalse(value.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, source) }
            }
        }
    }

    func testVerifiedRecipeAliasIsNotOfferedAsAnotherDish() {
        XCTAssertTrue(RecipeAliases.isLegacy("private:photo_cottage_bake"))
        XCTAssertTrue(RecipeAliases.isLegacy("photo_cottage_bake"))
        XCTAssertFalse(RecipeAliases.isLegacy("private:photo4_cottage_apple_prune_bake"))
    }
    func testCourseSuggestedPairsAreOptionalMetadata() throws {
        let encoded = """
        {"id":"course","titleRu":"Курс","titleEn":"Course","summaryRu":"Подборка","summaryEn":"Collection",
         "category":"home","access":"members","status":"published","recipeIDs":["lunch","dinner"],
         "suggestedPairs":[{"number":1,"lunchRecipeID":"lunch","dinnerRecipeID":"dinner"}]}
        """
        let course = try JSONDecoder().decode(LadCourse.self, from: Data(encoded.utf8))
        XCTAssertEqual(course.suggestedPairs?.count, 1)
        XCTAssertEqual(course.suggestedPairs?.first?.lunchRecipeID, "lunch")
        XCTAssertNil(course.days)
    }

    func testCourseRulesWarnAcrossWeekAndNeverBlockChoice() throws {
        let rare = Recipe(id: "rare-dish", title: "Картофель", caption: "", image: "", cuisine: "Домашняя",
                          minutes: 10, kcal: 100, protein: 1, allergens: [],
                          ingredients: [Ingredient(name: "Картофель", amount: 200, unit: "г", category: "Овощи")],
                          steps: ["Приготовить"], allergensVerified: true, mealKinds: [1])
        var course = LadCourse(id: "course-a", titleRu: "Курс А", titleEn: "Course A", summaryRu: "", summaryEn: "",
                               category: "home", access: "members", status: "published", recipeIDs: [rare.id],
                               days: nil, suggestedPairs: nil)
        course.rules = [CourseRule(id: "rare-week", scope: "week", kind: "maxRecipeOccurrences",
                                   titleRu: "Не чаще раза в неделю", titleEn: "At most once weekly",
                                   titleUk: "Не частіше разу на тиждень", recipeIDs: [rare.id], limit: 1)]
        let slots = [0, 1].map { MealSlot(id: "\($0)-1", day: $0, kind: 1, recipeID: rare.id, memberIDs: ["adult"]) }
        let warnings = CourseRuleEngine.warnings(courses: [course], slots: slots, recipes: [rare], schedule: .standard)
        XCTAssertEqual(warnings.filter { !$0.isConflict }.count, 1)
        XCTAssertEqual(warnings.first?.scope, "week")
        XCTAssertEqual(warnings.first?.excess, 1)
        XCTAssertEqual(slots.count, 2)  // A warning never mutates or rejects the chosen plan.
    }

    @MainActor
    func testSelectedCuisineCoursesMixWhileWeightAdviceStaysAdvisory() {
        let store = LadStore()
        store.state = .initial()
        let home = Recipe(id: "home-lunch", title: "Home", caption: "", image: "", cuisine: "Home",
                          minutes: 10, kcal: 300, protein: 12, allergens: [],
                          ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")],
                          steps: ["Cook"], allergensVerified: true, mealKinds: [1])
        let other = Recipe(id: "other-lunch", title: "Other", caption: "", image: "", cuisine: "Other",
                           minutes: 10, kcal: 300, protein: 12, allergens: [],
                           ingredients: [Ingredient(name: "Картофель", amount: 100, unit: "г", category: "Овощи"),
                                         Ingredient(name: "Говядина", amount: 100, unit: "г", category: "Мясо")],
                           steps: ["Cook"], allergensVerified: true, mealKinds: [1])
        var weight = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "weight-management", access: "members", status: "published",
                               recipeIDs: [home.id], days: nil, suggestedPairs: nil)
        weight.rules = [CourseRule(id: "pair", scope: "meal", kind: "avoidIngredientPair",
                                   titleRu: "Совет", titleEn: "Advice", titleUk: "Порада",
                                   ingredientNames: ["Говядина"], pairedIngredientNames: ["Картофель"], mealKind: 1)]
        let cuisine = LadCourse(id: "another-cuisine", titleRu: "Другая кухня", titleEn: "Other cuisine",
                                summaryRu: "", summaryEn: "", category: "cuisine", access: "members",
                                status: "published", recipeIDs: [other.id], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [home, other], courses: [weight, cuisine])
        store.state.activeCourseIDs = [weight.id, cuisine.id]
        XCTAssertEqual(Set(store.chooserRecipes(for: store.slot(0, 1)).map(\.id)), [home.id, other.id])
        let mixedSlot = MealSlot(id: "mixed", day: 0, kind: 1, recipeID: other.id, memberIDs: ["adult"])
        XCTAssertEqual(CourseRuleEngine.warnings(courses: [weight, cuisine], slots: [mixedSlot],
                                                 recipes: [home, other], schedule: .standard).count, 1)
        XCTAssertTrue(CourseRuleEngine.warnings(courses: [cuisine], slots: [mixedSlot],
                                                recipes: [home, other], schedule: .standard).isEmpty)
    }

    func testWeeklyIngredientRuleCountsOnlySpecifiedMealAndTracksExcess() throws {
        let potato = Recipe(id: "potato", title: "Картофель", caption: "", image: "", cuisine: "Домашняя",
                            minutes: 15, kcal: nil, protein: nil, allergens: [],
                            ingredients: [Ingredient(name: "Картофель", amount: 150, unit: "г", category: "Овощи")],
                            steps: ["Приготовить"])
        var course = LadCourse(id: "a", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "members", status: "published", recipeIDs: ["potato"],
                               days: nil, suggestedPairs: nil)
        course.rules = [CourseRule(id: "rare", scope: "week", kind: "maxIngredientOccurrences",
                                   titleRu: "Редко", titleEn: "Rarely", titleUk: "Рідко",
                                   ingredientNames: ["Картофель"], mealKind: 1, limit: 1)]
        let slots = [
            MealSlot(id: "0-1", day: 0, kind: 1, recipeID: potato.id, memberIDs: ["adult"]),
            MealSlot(id: "1-1", day: 1, kind: 1, recipeID: potato.id, memberIDs: ["adult"]),
            MealSlot(id: "2-1", day: 2, kind: 1, recipeID: potato.id, memberIDs: ["adult"]),
            MealSlot(id: "3-2", day: 3, kind: 2, recipeID: potato.id, memberIDs: ["adult"])
        ]
        let warning = try XCTUnwrap(CourseRuleEngine.warnings(courses: [course], slots: slots,
                                                               recipes: [potato], schedule: .standard).first)
        XCTAssertEqual(warning.excess, 2)
    }

    func testApplePureeHasEstimatedEnergyAndAnalogueMicronutrients() throws {
        let puree = Ingredient(name: "Яблочное пюре", amount: 100, unit: "г", category: "Фрукты", aiEstimated: true)
        XCTAssertEqual(EnergyEstimator.evaluate([puree]).knownBatchKcal, 48)
        let dish = Recipe(id: "test-puree", title: "Пюре", caption: "", image: "", cuisine: "Домашняя",
                          minutes: 1, kcal: nil, protein: nil, allergens: [], ingredients: [puree],
                          steps: ["Подать"])
        let vitamin = try XCTUnwrap(NutrientEstimator.estimate(dish)["vitamin_c"])
        XCTAssertTrue(vitamin.source.contains("аналог"))
    }

    func testUnspecifiedLentilVarietyUsesLabelledProxy() throws {
        let lentil = Ingredient(name: "Чечевица", amount: 75, unit: "г", category: "Бакалея", aiEstimated: true)
        XCTAssertTrue(EnergyEstimator.evaluate([lentil]).unresolvedNames.isEmpty)
        var dish = Recipe(id: "test-lentils", title: "Чечевица", caption: "", image: "", cuisine: "Домашняя",
                          minutes: 30, kcal: nil, protein: nil, allergens: [], ingredients: [lentil],
                          steps: ["Сварить"])
        dish.nutrientPreparationByIngredient = ["Чечевица": "boiledDrained"]
        let iron = try XCTUnwrap(NutrientEstimator.estimate(dish)["iron"])
        XCTAssertGreaterThan(iron.amount, 0)
        XCTAssertTrue(iron.source.contains("аналог"))
    }

    func testOptionalWineHasTrackedStockAndIsNotDefaultDrink() throws {
        let wine = try XCTUnwrap(CourseBeverages.all.first { $0.id == "course-drink-red-wine" })
        XCTAssertEqual(wine.ingredients.first?.name, "Красное сухое вино")
        XCTAssertEqual(wine.ingredients.first?.amount, 100)
        XCTAssertNotEqual(CourseBeverages.waterID, wine.id)
    }

    func testCourseRulesDetectDayAndWeekConflictsBetweenCourses() throws {
        var first = LadCourse(id: "a", titleRu: "А", titleEn: "A", summaryRu: "", summaryEn: "",
                              category: "home", access: "members", status: "published", recipeIDs: ["dish"],
                              days: nil, suggestedPairs: nil)
        var second = LadCourse(id: "b", titleRu: "Б", titleEn: "B", summaryRu: "", summaryEn: "",
                               category: "home", access: "members", status: "published", recipeIDs: ["dish"],
                               days: nil, suggestedPairs: nil)
        first.rules = [CourseRule(id: "lunch", scope: "day", kind: "allowedMealKinds", titleRu: "Только обед",
                                  titleEn: "Lunch only", titleUk: "Лише обід", recipeIDs: ["dish"],
                                  allowedMealKinds: [1]),
                       CourseRule(id: "max", scope: "week", kind: "maxRecipeOccurrences", titleRu: "Не более одного",
                                  titleEn: "At most one", titleUk: "Не більше одного", recipeIDs: ["dish"], limit: 1)]
        second.rules = [CourseRule(id: "dinner", scope: "day", kind: "allowedMealKinds", titleRu: "Только ужин",
                                   titleEn: "Dinner only", titleUk: "Лише вечеря", recipeIDs: ["dish"],
                                   allowedMealKinds: [2]),
                        CourseRule(id: "min", scope: "week", kind: "minRecipeOccurrences", titleRu: "Не менее двух",
                                   titleEn: "At least two", titleUk: "Не менше двох", recipeIDs: ["dish"], limit: 2)]
        let warnings = CourseRuleEngine.warnings(courses: [first, second], slots: [], recipes: [], schedule: .standard)
        XCTAssertEqual(warnings.filter(\.isConflict).count, 2)
        XCTAssertEqual(Set(warnings.filter(\.isConflict).map(\.scope)), ["day", "week"])
    }

    func testSuggestedCombinationCanIncludeSidesAndDrinks() throws {
        let encoded = """
        {"id":"course","titleRu":"Курс","titleEn":"Course","summaryRu":"Подборка","summaryEn":"Collection",
         "category":"home","access":"members","status":"published","recipeIDs":["breakfast","soup","salad","dinner"],
         "suggestedPairs":[{"number":33,"lunchRecipeID":"soup","dinnerRecipeID":"dinner",
         "breakfastRecipeIDs":["breakfast"],"lunchExtraRecipeIDs":["salad"],"drinkOptions":["чай","кофе"]}]}
        """
        let course = try JSONDecoder().decode(LadCourse.self, from: Data(encoded.utf8))
        let combination = try XCTUnwrap(course.suggestedPairs?.first)
        XCTAssertEqual(combination.breakfastRecipeIDs, ["breakfast"])
        XCTAssertEqual(combination.lunchExtraRecipeIDs, ["salad"])
        XCTAssertEqual(combination.drinkOptions, ["чай", "кофе"])
    }

    func testNewLiverAndMackerelMicronutrientsAreCovered() throws {
        let ingredients = [
            Ingredient(name: "Говяжья печень", amount: 100, unit: "г", category: "Рыба и мясо"),
            Ingredient(name: "Скумбрия", amount: 100, unit: "г", category: "Рыба и мясо")
        ]
        XCTAssertTrue(EnergyEstimator.evaluate(ingredients).unresolvedNames.isEmpty)
        var liver = Recipe(id: "liver-test", title: "Печень", caption: "", image: "", cuisine: "Домашняя",
                           minutes: 15, kcal: nil, protein: nil, allergens: [], ingredients: [ingredients[0]],
                           steps: ["Приготовить"], allergensVerified: false, mealKinds: [2])
        liver.nutrientPreparationByIngredient = ["Говяжья печень": "fried"]
        XCTAssertGreaterThan(try XCTUnwrap(NutrientEstimator.estimate(liver)["vitamin_a"]).amount, 0)
    }

    func testCookingWaterIsTrackedWithoutDilutingMicronutrientCoverage() throws {
        let tomato = Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")
        let water = Ingredient(name: "Вода", amount: 500, unit: "мл", category: "Напитки", aiEstimated: true)
        let plain = Recipe(id: "soup", title: "Томаты", caption: "", image: "", cuisine: "Домашняя",
                           minutes: 5, kcal: nil, protein: nil, allergens: [], ingredients: [tomato], steps: ["Подать"])
        let diluted = Recipe(id: "soup", title: "Суп", caption: "", image: "", cuisine: "Домашняя",
                             minutes: 5, kcal: nil, protein: nil, allergens: [], ingredients: [tomato, water], steps: ["Сварить"])
        XCTAssertEqual(EnergyEstimator.evaluate(diluted.ingredients).knownBatchKcal,
                       EnergyEstimator.evaluate(plain.ingredients).knownBatchKcal)
        XCTAssertEqual(try XCTUnwrap(NutrientEstimator.estimate(diluted)["vitamin_c"]).coverage,
                       try XCTUnwrap(NutrientEstimator.estimate(plain)["vitamin_c"]).coverage)
    }

    func testBoneInShoppingWeightUsesEdibleYieldOnlyForNutrition() throws {
        let turkey = Ingredient(name: "Голень индейки", amount: 1000, unit: "г",
                                category: "Рыба и мясо", aiEstimated: false)
        let whole = EnergyEstimator.evaluate([turkey]).knownBatchKcal
        let edible = EnergyEstimator.evaluate([turkey], edibleYield: ["Голень индейки": 0.6]).knownBatchKcal
        XCTAssertEqual(edible, Int((Double(whole) * 0.6).rounded()))

        var recipe = Recipe(id: "private:test-aspic-yield", title: "Холодец", caption: "", image: "",
                            cuisine: "Домашняя", minutes: 360, kcal: nil, protein: nil,
                            allergens: [], ingredients: [turkey], steps: ["Сварить"])
        recipe.baseServings = 4
        recipe.nutritionEdibleYield = ["Голень индейки": 0.6]
        recipe.nutrientPreparationByIngredient = ["Голень индейки": "simmered"]
        let withYield = try XCTUnwrap(NutrientEstimator.estimate(recipe)["vitamin_b12"]?.amount)
        recipe.nutritionEdibleYield = [:]
        let withoutYield = try XCTUnwrap(NutrientEstimator.estimate(recipe)["vitamin_b12"]?.amount)
        XCTAssertEqual(withYield, withoutYield * 0.6, accuracy: 0.0001)
    }

    func testWineInMarinadeIsRecognizedAsAlcoholIngredient() {
        let wine = Ingredient(name: "Белое сухое вино", amount: 30, unit: "мл", category: "Напитки")
        let chicken = Ingredient(name: "Куриный окорочок", amount: 500, unit: "г", category: "Рыба и мясо")
        let dish = Recipe(id: "test-wine-marinade", title: "Курица", caption: "", image: "",
                          cuisine: "Домашняя", minutes: 40, kcal: nil, protein: nil,
                          allergens: [], ingredients: [chicken, wine], steps: ["Запечь"])
        XCTAssertTrue(dish.containsAlcoholIngredient)
    }

    func testBoiledEggNutrientsUseCookingFactorWithoutAIBadge() throws {
        var dish = Recipe(id: "private:test-boiled-egg", title: "Яйца", caption: "", image: "", cuisine: "Домашняя",
                          minutes: 12, kcal: nil, protein: nil, allergens: ["Яйцо"],
                          ingredients: [Ingredient(name: "Яйцо", amount: 150, unit: "г", category: "Молочные продукты")],
                          steps: ["Отварить"], allergensVerified: false, mealKinds: [2])
        dish.baseServings = 1
        dish.nutrientPreparationByIngredient = ["Яйцо": "boiledDrained"]
        let nutrients = NutrientEstimator.estimate(dish)
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["vitamin_b12"]).amount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["selenium"]).amount, 0)
        XCTAssertTrue(EnergyEstimator.evaluate(dish.ingredients).aiEstimatedNames.isEmpty)
    }

    func testNewCourseFoodsHaveEnergyAndMethodSpecificNutrients() throws {
        let ingredients = [
            Ingredient(name: "Минтай", amount: 400, unit: "г", category: "Рыба и мясо"),
            Ingredient(name: "Пшено", amount: 40, unit: "г", category: "Бакалея", aiEstimated: true),
            Ingredient(name: "Морковь", amount: 75, unit: "г", category: "Овощи и зелень", aiEstimated: true)
        ]
        let energy = EnergyEstimator.evaluate(ingredients)
        XCTAssertTrue(energy.unresolvedNames.isEmpty)
        XCTAssertEqual(Set(energy.aiEstimatedNames), ["Пшено", "Морковь"])
        XCTAssertTrue(EnergyEstimator.evaluate([
            Ingredient(name: "Пропаренный рис", amount: 100, unit: "г", category: "Бакалея")
        ]).unresolvedNames.isEmpty)
        var soup = Recipe(id: "private:test-fish-soup", title: "Рыбный суп", caption: "", image: "",
                          cuisine: "Домашняя", minutes: 35, kcal: nil, protein: nil,
                          allergens: ["Рыба"], ingredients: ingredients, steps: ["Сварить"])
        soup.baseServings = 4
        soup.nutrientPreparationByIngredient = ["Минтай": "simmered", "Пшено": "simmered", "Морковь": "simmered"]
        let nutrients = NutrientEstimator.estimate(soup)
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["vitamin_a"]).amount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["selenium"]).amount, 0)
        // Fish and millet have no measured vitamin A entry in this reference;
        // coverage correctly reflects the carrot's share of the known mass.
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["vitamin_a"]?.coverage), 0)
        XCTAssertLessThan(try XCTUnwrap(nutrients["vitamin_a"]?.coverage), 1)
    }

    func testSaladFoodsUseReviewedNutrientProfiles() throws {
        let ingredients = [
            Ingredient(name: "Авокадо", amount: 75, unit: "г", category: "Овощи"),
            Ingredient(name: "Редис", amount: 60, unit: "г", category: "Овощи"),
            Ingredient(name: "Фета", amount: 50, unit: "г", category: "Молочные продукты"),
        ]
        XCTAssertTrue(EnergyEstimator.evaluate(ingredients).unresolvedNames.isEmpty)
        var salad = Recipe(id: "private:test-salad-nutrients", title: "Салат", caption: "", image: "",
                           cuisine: "Домашняя", minutes: 5, kcal: nil, protein: nil,
                           allergens: ["Молоко"], ingredients: ingredients, steps: ["Смешать"])
        salad.baseServings = 2
        salad.nutrientPreparationByIngredient = ["Авокадо": "raw", "Редис": "raw", "Фета": "raw"]
        let nutrients = NutrientEstimator.estimate(salad)
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["vitamin_c"]).amount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["folate"]).amount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(nutrients["calcium"]).amount, 0)
        XCTAssertEqual(try XCTUnwrap(nutrients["calcium"]).coverage, 1)
    }

    @MainActor
    func testSelectingWeightCourseNeverChangesPersonalSchedule() {
        let store = LadStore()
        store.state = .initial()
        var pilot = LadCourse(id: "weight-week-pilot", titleRu: "Лёгкая домашняя кухня", titleEn: "Lighter home cooking",
                              summaryRu: "", summaryEn: "", category: "weight-management", access: "members",
                              status: "published", recipeIDs: [], days: nil, suggestedPairs: nil)
        let other = LadCourse(id: "other-weight-course", titleRu: "Другой", titleEn: "Other",
                              summaryRu: "", summaryEn: "", category: "weight-management", access: "members",
                              status: "published", recipeIDs: [], days: nil, suggestedPairs: nil)
        pilot.rules = [CourseRule(id: "hour", scope: "day", kind: "latestMealMinute", titleRu: "До 19",
                                 titleEn: "By 19", titleUk: "До 19", mealKind: 2, minute: 1140)]
        store.replaceCatalogForTesting(recipes: [], courses: [pilot, other])
        let personal = MealSchedule(breakfastEnds: 12 * 60, lunchEnds: 16 * 60, dinnerEnds: 22 * 60)
        store.updateMealSchedule(personal)
        store.toggleCourse(other.id)
        store.toggleCourse(pilot.id)
        XCTAssertEqual(store.mealCutoffText(for: 0), "12:00")
        XCTAssertEqual(store.mealCutoffText(for: 1), "16:00")
        XCTAssertEqual(store.mealCutoffText(for: 2), "22:00")
        store.proposeWeekMenu()
        XCTAssertEqual(store.mealSchedule.breakfastEnds, personal.breakfastEnds)
        XCTAssertEqual(store.mealSchedule.lunchEnds, personal.lunchEnds)
        XCTAssertEqual(store.mealSchedule.dinnerEnds, personal.dinnerEnds)
    }

    @MainActor
    func testMealCardNoticeSkipsStatusEssays() {
        let store = LadStore()
        store.state = .initial()
        let noon = Calendar.current.date(byAdding: .hour, value: 12, to: store.state.startDate)!
        store.refreshClock(noon)
        let breakfast = store.slot(0, 0)
        XCTAssertEqual(store.availabilityTitle(for: breakfast), L10n.text("Время приёма прошло"))
        XCTAssertNil(store.mealCardNotice(for: breakfast))
        let lunch = store.slot(0, 1)
        XCTAssertEqual(store.availabilityTitle(for: lunch), L10n.text("Запасы не внесены — проверьте продукты"))
        XCTAssertNil(store.mealCardNotice(for: lunch))

        let recipe = Recipe(id: "card-soup", title: "Суп", caption: "", image: "", cuisine: "Домашняя",
                            minutes: 20, kcal: 100, protein: 4, allergens: [],
                            ingredients: [Ingredient(name: "Картофель", amount: 100, unit: "г", category: "Овощи")],
                            steps: ["Сварить"], allergensVerified: true, mealKinds: [1])
        store.replaceCatalogForTesting(recipes: [recipe], courses: store.courses)
        store.state.pantryItems = [PantryItem(name: "Картофель", quantity: 20, unit: "г", category: "Овощи")]
        store.state.slots[1].recipeID = recipe.id
        let notice = store.mealCardNotice(for: store.slot(0, 1))
        XCTAssertEqual(notice, L10n.format("Докупить %d поз.", 1))
        store.state.pantryItems = [PantryItem(name: "Картофель", quantity: 2000, unit: "г", category: "Овощи")]
        XCTAssertNil(store.mealCardNotice(for: store.slot(0, 1)))
    }

    func testSourcePairingsRankWeekWithoutFixingPrintedDay() {
        let pairs = (1...49).map {
            CourseSuggestion(number: $0, lunchRecipeID: "lunch", dinnerRecipeID: "dinner")
        }
        let course = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course",
                               summaryRu: "", summaryEn: "", category: "weight-management",
                               access: "members", status: "published", recipeIDs: ["lunch", "dinner"],
                               days: nil, suggestedPairs: pairs)
        XCTAssertTrue(CourseCatalogAccess.suggestionsAreValid(course))
        XCTAssertEqual(CourseWeekPreferences.pairingBonus(course: course, lunchID: "private:lunch",
                                                        dinnerID: "private:dinner"), 18)
        XCTAssertEqual(CourseWeekPreferences.pairingBonus(course: course, lunchID: "other",
                                                        dinnerID: "private:dinner"), 0)
        let previous = [MealSlot(id: "0-1", day: 0, kind: 1, recipeID: "private:lunch", memberIDs: ["adult"])]
        XCTAssertEqual(CourseWeekPreferences.recentRepeatPenalty(recipeID: "private:lunch", day: 3,
                                                                  slots: previous), 22)
        XCTAssertEqual(CourseWeekPreferences.recentRepeatPenalty(recipeID: "private:lunch", day: 0,
                                                                  slots: previous), 0)
    }

    func testTimingAdviceHasSeparateDisplayFromConflictWarnings() {
        let dish = Recipe(id: "dish", title: "Dish", caption: "", image: "", cuisine: "Home",
                          minutes: 10, kcal: 100, protein: 1, allergens: [], ingredients: [],
                          steps: ["Cook"], mealKinds: [0])
        var course = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course",
                               summaryRu: "", summaryEn: "", category: "weight-management",
                               access: "members", status: "published", recipeIDs: ["dish"],
                               days: nil, suggestedPairs: nil)
        course.rules = [CourseRule(id: "source-hour", scope: "day", kind: "latestMealMinute",
                                   titleRu: "До 10:00", titleEn: "Before 10", titleUk: "До 10",
                                   mealKind: 0, minute: 600),
                        CourseRule(id: "wrong-slot", scope: "day", kind: "allowedMealKinds",
                                   titleRu: "Только ужин", titleEn: "Dinner only", titleUk: "Лише вечеря",
                                   recipeIDs: ["dish"], allowedMealKinds: [2])]
        let slots = [MealSlot(id: "0-0", day: 0, kind: 0, recipeID: "dish", memberIDs: ["adult"])]
        let lateBreakfast = MealSchedule(breakfastEnds: 11 * 60, lunchEnds: 16 * 60, dinnerEnds: 22 * 60)
        XCTAssertEqual(CourseRuleEngine.warnings(courses: [course], slots: slots, recipes: [dish],
                                                 schedule: lateBreakfast).count, 2)
        XCTAssertEqual(CourseRuleEngine.visibleWarnings(courses: [course], slots: slots, recipes: [dish],
                                                        schedule: lateBreakfast).count, 1)
        XCTAssertEqual(course.generalTimingRules.map(\.id), ["source-hour"])
    }

    func testCourseTimesExcludeRecipeSpecificAndInvalidHours() {
        var course = LadCourse(id: "course", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "members", status: "published", recipeIDs: ["salad"],
                               days: nil, suggestedPairs: nil)
        func hour(_ id: String, _ kind: Int, _ minute: Int, recipes: [String]? = nil) -> CourseRule {
            CourseRule(id: id, scope: "day", kind: "latestMealMinute", titleRu: "", titleEn: "", titleUk: "",
                       recipeIDs: recipes, mealKind: kind, minute: minute)
        }
        course.rules = [hour("lunch", 1, 930), hour("breakfast", 0, 660), hour("dinner", 2, 1140),
                        hour("salad", 1, 840, recipes: ["salad"]), hour("bad-kind", 4, 600),
                        hour("bad-minute", 2, -10)]
        XCTAssertEqual(course.generalTimingRules.map(\.id), ["breakfast", "lunch", "dinner"])
        course.rules = [hour("salad", 1, 840, recipes: ["salad"])]
        XCTAssertTrue(course.generalTimingRules.isEmpty, "A salad-specific cutoff must not apply to the whole course")
    }

    func testCourseTimingMetadataAndLabelsInAllLanguages() throws {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let legacy = #"{"id":"legacy","scope":"day","kind":"latestMealMinute","titleRu":"","titleEn":"","titleUk":"","mealKind":1,"minute":930}"#
        var rule = try JSONDecoder().decode(CourseRule.self, from: Data(legacy.utf8))
        XCTAssertNil(rule.preferredMinute)
        XCTAssertNil(rule.minutesAfterWaking)
        XCTAssertNil(rule.windowStartMinute)
        rule.minute = 660
        rule.preferredMinute = 600
        rule.minutesAfterWaking = 60
        let restored = try JSONDecoder().decode(CourseRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(restored.preferredMinute, 600)
        XCTAssertEqual(restored.minutesAfterWaking, 60)
        for (language, label, details) in [
            ("ru", "до 11:00", "желательно до 10:00 · в течение 60 мин после пробуждения"),
            ("en", "by 11:00", "ideally by 10:00 · within 60 min of waking"),
            ("uk", "до 11:00", "бажано до 10:00 · протягом 60 хв після пробудження")
        ] {
            UserDefaults.standard.set(language, forKey: L10n.languageKey)
            XCTAssertEqual(rule.timingLabel, label)
            XCTAssertEqual(rule.timingDetails, details)
        }
        rule.minute = 1140
        rule.windowStartMinute = 1080
        rule.preferredMinute = nil
        rule.minutesAfterWaking = nil
        UserDefaults.standard.set("en", forKey: L10n.languageKey)
        XCTAssertEqual(rule.timingDetails, "suggested window 18:00–19:00")
        rule.minute = -1
        XCTAssertNil(rule.timingLabel)
        XCTAssertNil(rule.timingDetails)
    }

    func testDeliveredCourseShowsAvailabilityNotAccessJargon() {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let members = LadCourse(id: "course", titleRu: "", titleEn: "", summaryRu: "", summaryEn: "",
                                category: "home", access: "members", status: "published", recipeIDs: [],
                                days: nil, suggestedPairs: nil)
        let free = LadCourse(id: "course2", titleRu: "", titleEn: "", summaryRu: "", summaryEn: "",
                             category: "home", access: "free", status: "published", recipeIDs: [],
                             days: nil, suggestedPairs: nil)
        for (language, available, freeLabel) in [("ru", "Доступен", "Бесплатный"),
                                                ("en", "Available", "Free"), ("uk", "Доступний", "Безкоштовний")] {
            UserDefaults.standard.set(language, forKey: L10n.languageKey)
            XCTAssertEqual(members.availabilityLabel, available)
            XCTAssertEqual(free.availabilityLabel, freeLabel)
        }
    }

    func testMeasuredBodyPercentagesAndOlderProfiles() throws {
        let legacy = #"{"id":"one","name":"Test","goal":"Баланс","portion":1,"allergies":[]}"#.data(using: .utf8)!
        var member = try JSONDecoder().decode(FamilyMember.self, from: legacy)
        XCTAssertNil(member.preferredVitaminKeys)
        member.preferredVitaminKeys = ["vitamin_c", "vitamin_d"]
        let restored = try JSONDecoder().decode(FamilyMember.self, from: JSONEncoder().encode(member))
        XCTAssertEqual(restored.preferredVitaminKeys, ["vitamin_c", "vitamin_d"])
        XCTAssertNil(member.heightCm)
        XCTAssertNil(member.fatPercent)
        member.heightCm = 175
        member.weightKg = 80
        member.measuredFatMassKg = 20
        member.measuredMuscleMassKg = 32
        XCTAssertEqual(member.fatPercent, 25)
        XCTAssertEqual(member.musclePercent, 40)
        member.measuredFatMassKg = 90
        XCTAssertNil(member.fatPercent)
    }

    func testGlutenGroupMatchesSpecificCerealAllergens() {
        XCTAssertTrue(AllergenMatching.conflicts(selected: ["Злаки с глютеном"], recipe: ["Пшеница"]))
        XCTAssertTrue(AllergenMatching.conflicts(selected: ["Овёс"], recipe: ["Злаки с глютеном"]))
        XCTAssertFalse(AllergenMatching.conflicts(selected: ["Рыба"], recipe: ["Молоко"]))
    }

    func testAppLanguageChangesCourseTitlesAndInterfaceStrings() throws {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let starter = try XCTUnwrap(CourseCatalogAccess.bundledCourses.first { $0.id == CourseAliases.mediterranean })
        UserDefaults.standard.set("en", forKey: L10n.languageKey)
        XCTAssertEqual(L10n.text("Настройки"), "Settings")
        XCTAssertEqual(starter.title, "Healthy eating")
        UserDefaults.standard.set("ru", forKey: L10n.languageKey)
        XCTAssertEqual(L10n.text("Настройки"), "Настройки")
        XCTAssertEqual(starter.title, "Здоровое питание")
        UserDefaults.standard.set("uk", forKey: L10n.languageKey)
        XCTAssertEqual(L10n.text("Настройки"), "Налаштування")
        XCTAssertEqual(L10n.text("Кофе"), "Кава")
        var translated = starter
        translated.summaryUk = "Український опис"
        XCTAssertEqual(translated.summary, "Український опис")
    }

    @MainActor
    func testRevocationDropsDownloadedPaidRecipesWithoutWaitingForNetwork() throws {
        let store = LadStore()
        store.state = .initial()
        let paid = Recipe(id: "paid-only", title: "Paid", caption: "", image: "", cuisine: "",
                          minutes: 10, kcal: 100, protein: 5, allergens: [],
                          ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")],
                          steps: ["Cook"], allergensVerified: true, mealKinds: [1])
        var full = try XCTUnwrap(CourseCatalogAccess.bundledCourses.first)
        full = LadCourse(id: full.id, titleRu: full.titleRu, titleEn: full.titleEn,
                         summaryRu: full.summaryRu, summaryEn: full.summaryEn, category: full.category,
                         access: full.access, status: full.status, recipeIDs: full.recipeIDs + [paid.id],
                         days: nil, suggestedPairs: full.suggestedPairs, planningStyle: full.planningStyle,
                         breakfastRecipeIDs: full.breakfastRecipeIDs, totalRecipeCount: 51)
        store.replaceCatalogForTesting(recipes: [paid], courses: [full])
        store.state.slots[4].recipeID = paid.id
        XCTAssertTrue(store.allRecipes.contains { $0.id == paid.id })
        store.returnToFreeCatalog()
        XCTAssertFalse(store.allRecipes.contains { $0.id == paid.id })
        XCTAssertEqual(store.courses.first?.recipeIDs.count, 200)
        XCTAssertEqual(store.state.slots[4].recipeID, paid.id, "A purchase change must not erase personal records")
        XCTAssertTrue(store.recipe(store.state.slots[4]).isUnavailable)
    }

    @MainActor
    func testLaunchMigrationWorksOfflineAndPreservesEatenAndPastMeals() throws {
        var state = DemoState.initial()
        state.launchMenuVersion = nil
        state.activeCourseIDs = ["weight-week-pilot"]
        let lunch = try XCTUnwrap(Recipe.launchRecipes.first { $0.mealKinds == [1] && !$0.isCourseSide })
        state.slots[0].recipeID = "private:old-dessert"
        state.slots[3].recipeID = "private:already-eaten"
        state.eatenIDs.insert("\(state.slots[3].id)-anna")
        state.slots[6].recipeID = "private:wrong-breakfast"
        state.slots[7].recipeID = "private:\(lunch.id)"
        state.migrateLaunchMenu(currentDay: 1)
        XCTAssertEqual(state.activeCourseIDs, [CourseAliases.mediterranean])
        XCTAssertEqual(state.slots[0].recipeID, "private:old-dessert")
        XCTAssertEqual(state.slots[3].recipeID, "private:already-eaten")
        XCTAssertEqual(state.slots[6].recipeID, Recipe.unplanned.id)
        XCTAssertEqual(state.slots[7].recipeID, lunch.id)
        let ids = state.slots.map(\.recipeID)
        state.migrateLaunchMenu(currentDay: 1)
        XCTAssertEqual(state.slots.map(\.recipeID), ids)
    }

    func testLaunchMigrationKeepsAnExplicitEmptySelectionAndMigratesRollover() {
        var state = DemoState.initial()
        state.launchMenuVersion = nil
        state.activeCourseIDs = []
        state.migrateLaunchMenu(currentDay: 0)
        XCTAssertEqual(state.activeCourseIDs, [])
        state.launchMenuVersion = nil
        state.activeCourseIDs = ["weight-week-pilot"]
        let next = DemoState.nextWeek(after: state, now: .now)
        XCTAssertEqual(next.activeCourseIDs, [CourseAliases.mediterranean])
        XCTAssertTrue(next.slots.allSatisfy { $0.recipeID != Recipe.unplanned.id })
    }

    @MainActor
    func testCombinedMenuRejectsDinnerAtLunchEvenWithStaleMealTags() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let dinner = try XCTUnwrap(Recipe.launchRecipes.first { $0.mealKinds == [2] && !$0.isCourseSide })
        let lunch = store.slot(1, 1)
        XCTAssertNotNil(store.assign(dinner, to: lunch))
        var stale = dinner
        stale.mealKinds = [1, 2]
        XCTAssertNotNil(store.assign(stale, to: lunch))
        XCTAssertNotNil(store.addDish(stale, to: lunch))
        XCTAssertFalse(store.chooserRecipes(for: lunch).contains { $0.id == dinner.id })
        let breakfastIDs = Set(store.selectedCourses.flatMap { $0.breakfastRecipeIDs ?? [] })
        XCTAssertEqual(Set(store.chooserRecipes(for: store.slot(1, 0)).map(\.id)), breakfastIDs)
        store.proposeDayMenu(1)
        for change in try XCTUnwrap(store.replanPreview).changes where change.nextID != Recipe.unplanned.id {
            let slot = try XCTUnwrap(store.state.slots.first { $0.id == change.slotID })
            // Mediterranean dishes tagged for lunch and dinner may take either slot; a dinner-only dish may not.
            XCTAssertEqual(store.allRecipes.first { $0.id == change.nextID }?.mealKinds.contains(slot.kind), true, change.nextID)
        }
    }

    func testLaunchMenuPreservesServingCaloriesAndRecommendedHours() throws {
        let course = try XCTUnwrap(CourseCatalogAccess.bundledCourses.first)
        XCTAssertEqual(course.generalTimingRules.map(\.preferredMinute), [600, 840, nil])
        XCTAssertEqual(course.generalTimingRules.last?.windowStartMinute, 1080)
        XCTAssertEqual(course.generalTimingRules.last?.minute, 1140)
        XCTAssertEqual(course.generalTimingRules.first?.recommendedTimingLabel, L10n.format("до %@", "10:00"))
        XCTAssertEqual(course.generalTimingRules.last?.recommendedTimingLabel, "18:00–19:00")
        XCTAssertTrue(Recipe.launchRecipes.contains { $0.baseServings > 1 })
        for recipe in Recipe.launchRecipes {
            let energy = try XCTUnwrap(recipe.energyEstimate)
            XCTAssertEqual(recipe.kcal, Int((Double(energy.knownBatchKcal) / recipe.baseServings).rounded()), recipe.id)
            XCTAssertNotNil(UIImage(named: recipe.image), recipe.id)
        }
    }

    @MainActor
    func testFreeBreakfastUsesBreakfastSuggestionsAndAllowsExplicitDinnerChoice() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let dessert = Recipe(id: "private:source-dessert", title: "Source dinner", caption: "", image: "", cuisine: "",
                             minutes: 10, kcal: 200, protein: 5, allergens: [],
                             ingredients: [Ingredient(name: "Яблоко", amount: 100, unit: "г", category: "Фрукты")],
                             steps: ["Serve"], allergensVerified: true, mealKinds: [0, 2])
        let course = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "members", status: "published",
                               recipeIDs: ["source-dessert"], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [dessert], courses: [course])
        store.state.activeCourseIDs = [course.id]
        let correctedDessert = try XCTUnwrap(store.allRecipes.first { $0.id == dessert.id })
        XCTAssertEqual(correctedDessert.mealKinds, [2])
        let breakfast = store.slot(0, 0)
        XCTAssertTrue(store.chooserRecipes(for: breakfast).contains { $0.id == "oats" })
        XCTAssertTrue(store.chooserRecipes(for: breakfast).contains { $0.id == dessert.id })
        XCTAssertFalse(store.chooserRecipes(for: store.slot(0, 1)).contains { $0.id == "oats" })
        XCTAssertNil(store.assign(correctedDessert, to: breakfast), "A person can explicitly choose a dinner for a free breakfast")
        store.proposeWeekMenu()
        let preview = try XCTUnwrap(store.replanPreview)
        let breakfastChanges = preview.changes.filter { $0.slotID.hasSuffix("-0") }
        XCTAssertFalse(breakfastChanges.isEmpty)
        for change in breakfastChanges {
            XCTAssertNotEqual(change.nextID, dessert.id)
            XCTAssertTrue(store.allRecipes.first { $0.id == change.nextID }?.mealKinds.contains(0) == true)
        }
        store.applyReplan(preview)
        XCTAssertNotEqual(store.slot(0, 0).recipeID, dessert.id)
        store.proposeNotToday(store.slot(0, 0))
        XCTAssertNotEqual(try XCTUnwrap(store.replanPreview?.changes.first).nextID, dessert.id)
        XCTAssertEqual(store.activeCourseIDs, [course.id])
    }

    @MainActor
    func testFreeBreakfastPreservesOutsideDishesUntilTheCourseIsRemoved() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let course = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "members", status: "published",
                               recipeIDs: ["soup"], days: nil, suggestedPairs: nil)
        let other = LadCourse(id: "other-course", titleRu: "Другой", titleEn: "Other", summaryRu: "", summaryEn: "",
                              category: "home", access: "free", status: "published",
                              recipeIDs: ["oats"], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [], courses: [course, other])
        store.state.activeCourseIDs = [course.id, other.id]
        let oats = try XCTUnwrap(Recipe.all.first { $0.id == "oats" })
        let eggs = try XCTUnwrap(Recipe.all.first { $0.id == "eggs" })
        XCTAssertNil(store.assign(oats, to: store.slot(1, 0)))
        XCTAssertNil(store.addDish(eggs, to: store.slot(1, 0)))
        let breakfast = store.slot(1, 0)
        XCTAssertFalse(store.isOutsideSelectedCourses(oats.id, for: breakfast))
        store.toggleCourse(other.id)
        XCTAssertEqual(store.slot(1, 0).recipeID, oats.id)
        XCTAssertEqual(store.slot(1, 0).extraRecipeIDs, [eggs.id])
        store.clearFutureDishesOutsideCourses()
        XCTAssertEqual(store.slot(1, 0).allRecipeIDs, breakfast.allRecipeIDs)
        XCTAssertEqual(store.outsideFutureSlotCount, 0)
        XCTAssertNotNil(store.assign(oats, to: store.slot(1, 1)), "Free breakfast must not open lunch to outside dishes")
        store.toggleCourse(course.id)
        XCTAssertEqual(store.slot(1, 0).recipeID, Recipe.unplanned.id)
        XCTAssertTrue(store.chooserRecipes(for: store.slot(1, 0)).isEmpty)
    }

    @MainActor
    func testFreeBreakfastStillFiltersAllergiesDislikesAndBeverages() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let course = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "members", status: "published",
                               recipeIDs: [], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [], courses: [course])
        store.state.activeCourseIDs = [course.id]
        store.state.members[0].allergies = ["Яйцо"]
        let eggs = try XCTUnwrap(Recipe.all.first { $0.id == "eggs" })
        XCTAssertFalse(store.chooserRecipes(for: store.slot(0, 0)).contains { $0.id == eggs.id })
        XCTAssertNotNil(store.assign(eggs, to: store.slot(0, 0)))
        store.state.dislikes = ["anna|oats"]
        let choices = store.chooserRecipes(for: store.slot(0, 0))
        XCTAssertFalse(choices.contains { $0.id == "oats" })
        XCTAssertFalse(choices.contains { $0.isBeverage })
        XCTAssertTrue(choices.allSatisfy { !$0.containsAlcoholIngredient })
    }

    @MainActor
    func testCourseLunchDinnerRolesStaySeparateAndBeverageInventory() throws {
        let store = LadStore()
        store.state = .initial()
        let dinner = Recipe(id: "course-dinner", title: "Ужин", caption: "", image: "", cuisine: "Домашняя",
                            minutes: 10, kcal: 100, protein: 5, allergens: [],
                            ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")],
                            steps: ["Приготовить"], allergensVerified: true, mealKinds: [2])
        let pilot = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                              category: "weight-management", access: "members", status: "published",
                              recipeIDs: [dinner.id], days: nil, suggestedPairs: nil)
        let other = LadCourse(id: "other-course", titleRu: "Другой", titleEn: "Other", summaryRu: "", summaryEn: "",
                              category: "home", access: "members", status: "published",
                              recipeIDs: [dinner.id], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [dinner], courses: [pilot, other])
        store.state.activeCourseIDs = [other.id]
        XCTAssertFalse(store.chooserRecipes(for: store.slot(0, 1)).contains { $0.id == dinner.id })
        store.state.activeCourseIDs = [pilot.id]
        XCTAssertFalse(store.chooserRecipes(for: store.slot(0, 1)).contains { $0.id == dinner.id })
        store.proposeDayMenu(1)
        let drinks = try XCTUnwrap(store.replanPreview?.changes.first(where: { $0.slotID == store.slot(1, 2).id })?.nextBeverageIDs)
        XCTAssertEqual(drinks.count, 2)
        XCTAssertTrue(drinks.contains(CourseBeverages.waterID))
        XCTAssertTrue(drinks.contains { $0 != CourseBeverages.waterID })

        var slot = MealSlot(id: "drink-test", day: 0, kind: 1, recipeID: dinner.id, memberIDs: ["adult"])
        slot.beverageID = "course-drink-coffee"
        let person = FamilyMember(id: "adult", name: "Test", goal: "", portion: 1, allergies: [])
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1,
                                                           to: Calendar.current.startOfDay(for: .now)))
        let result = PlanningCore.resolvePlan(slots: [slot], members: [person], recipes: [dinner] + CourseBeverages.all,
                                               pantry: [], startDate: tomorrow)
        XCTAssertTrue(result.shoppingNeeds.contains { $0.name == "Кофе" && $0.required == 8 })
        XCTAssertTrue(result.shoppingNeeds.contains { $0.name == "Вода" && $0.required == 200 })
        XCTAssertEqual(slot.allRecipeIDs.count, 2)
    }

    func testCoffeeStockDepletesAcrossPlannedMeals() throws {
        let dish = Recipe(id: "dish", title: "Блюдо", caption: "", image: "", cuisine: "Домашняя",
                          minutes: 5, kcal: 100, protein: 5, allergens: [],
                          ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")],
                          steps: ["Подать"])
        let person = FamilyMember(id: "adult", name: "Test", goal: "", portion: 1, allergies: [])
        let slots = [0, 1].map { day -> MealSlot in
            var slot = MealSlot(id: "\(day)-1", day: day, kind: 1, recipeID: dish.id, memberIDs: [person.id])
            slot.beverageID = "course-drink-coffee"
            return slot
        }
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1,
                                                           to: Calendar.current.startOfDay(for: .now)))
        let pantry = [PantryItem(name: "Кофе", quantity: 10, unit: "г", category: "Напитки")]
        let result = PlanningCore.resolvePlan(slots: slots, members: [person], recipes: [dish] + CourseBeverages.all,
                                               pantry: pantry, startDate: tomorrow)
        let coffee = try XCTUnwrap(result.shoppingNeeds.first { $0.name == "Кофе" })
        XCTAssertEqual(coffee.required, 16)
        XCTAssertEqual(coffee.available, 10)
        XCTAssertEqual(coffee.missing, 6)
        let milk = try XCTUnwrap(CourseBeverages.all.first { $0.id == "course-drink-milk" })
        XCTAssertGreaterThan(try XCTUnwrap(milk.nutrients["calcium"]).amount, 0)
        XCTAssertEqual(milk.nutrients["calcium"]?.coverage, 1)
    }

    func testBeverageArrayDecodesLegacyPlansAndDeduplicatesRecipes() throws {
        let legacy = Data(#"{"id":"1-1","day":1,"kind":1,"recipeID":"food","memberIDs":["adult"],"beverageID":"course-drink-coffee"}"#.utf8)
        var slot = try JSONDecoder().decode(MealSlot.self, from: legacy)
        XCTAssertEqual(slot.selectedBeverageIDs, ["course-drink-coffee"])
        XCTAssertTrue(slot.hasManualBeverages)
        slot.extraRecipeIDs = ["food", "side", "side"]
        slot.setBeverages([CourseBeverages.waterID, "course-drink-coffee", "course-drink-coffee"], manuallySelected: true)
        let restored = try JSONDecoder().decode(MealSlot.self, from: JSONEncoder().encode(slot))
        XCTAssertEqual(restored.allRecipeIDs, ["food", "side", CourseBeverages.waterID, "course-drink-coffee"])
        XCTAssertNil(restored.beverageID)
        slot.setBeverages([], manuallySelected: true)
        XCTAssertTrue(slot.hasManualBeverages)
        XCTAssertTrue(slot.selectedBeverageIDs.isEmpty)
    }

    func testSourceDrinkListsAreAlternativesAndDoNotAddMilkToEggDinner() throws {
        func sourceDish(_ id: String) -> Recipe {
            Recipe(id: id, title: "Source", caption: "", image: "", cuisine: "", minutes: 5, kcal: 100, protein: 5,
                   allergens: [], ingredients: [], steps: ["Serve"])
        }
        let eggDrinks = try XCTUnwrap(CourseBeverages.sourceRecommendations(for: sourceDish("private:photo8_dill_egg_pancakes")))
        XCTAssertEqual(eggDrinks, [CourseBeverages.waterID, "course-drink-tea", "course-drink-coffee"])
        let curdDrinks = try XCTUnwrap(CourseBeverages.sourceRecommendations(for: sourceDish("photo4_cottage_apple_prune_bake")))
        XCTAssertTrue(curdDrinks.contains("course-drink-kefir"))
        XCTAssertFalse(curdDrinks.contains("course-drink-tomato-juice"))
        XCTAssertFalse(curdDrinks.contains("course-drink-red-wine"))
        let vegetableDrinks = try XCTUnwrap(CourseBeverages.sourceRecommendations(for: sourceDish("photo9_broccoli_yogurt_salad")))
        XCTAssertTrue(vegetableDrinks.contains("course-drink-tomato-juice"))
    }

    func testMultipleDrinksShareWaterStockAndOnlySelectedIngredientsAreCounted() throws {
        let food = Recipe(id: "food", title: "Food", caption: "", image: "", cuisine: "", minutes: 5,
                          kcal: 100, protein: 5, allergens: [],
                          ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")], steps: ["Serve"])
        let adult = FamilyMember(id: "adult", name: "Test", goal: "", portion: 1, allergies: [])
        var slot = MealSlot(id: "1-1", day: 1, kind: 1, recipeID: food.id, memberIDs: [adult.id])
        slot.setBeverages([CourseBeverages.waterID, "course-drink-coffee", "course-drink-milk", "course-drink-coffee"])
        let result = PlanningCore.resolvePlan(slots: [slot], members: [adult], recipes: [food] + CourseBeverages.all,
                                              pantry: [PantryItem(name: "Вода", quantity: 300, unit: "мл", category: "Напитки")],
                                              startDate: Calendar.current.startOfDay(for: .now))
        let water = try XCTUnwrap(result.shoppingNeeds.first { $0.name == "Вода" })
        XCTAssertEqual(water.required, 400)
        XCTAssertEqual(water.missing, 100)
        XCTAssertEqual(result.shoppingNeeds.first { $0.name == "Кофе" }?.required, 8)
        XCTAssertEqual(result.shoppingNeeds.first { $0.name == "Молоко" }?.required, 200)
        XCTAssertFalse(result.shoppingNeeds.contains { $0.name == "Чай" || $0.name == "Кефир" })
        let selected = ([food] + CourseBeverages.all).filter { slot.allRecipeIDs.contains($0.id) }
        XCTAssertEqual(selected.compactMap(\.kcal).reduce(0, +), 200)
        XCTAssertGreaterThan(selected.compactMap { $0.nutrients["calcium"]?.amount }.reduce(0, +), 0)
    }

    @MainActor
    func testWeekGeneratorKeepsFoodSeparateAndSuggestsVariedDrinkPairs() throws {
        let store = LadStore()
        store.state = .initial()
        store.state.members = [FamilyMember(id: "adult", name: "Test", goal: "", portion: 1, allergies: [], ageYears: 30)]
        store.state.selectedMemberID = "adult"
        for index in store.state.slots.indices { store.state.slots[index].memberIDs = ["adult"] }
        let foods = (0..<3).map { kind in
            Recipe(id: "food-\(kind)", title: "Food", caption: "", image: "", cuisine: "", minutes: 5,
                   kcal: 100, protein: 5, allergens: [],
                   ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")],
                   steps: ["Serve"], mealKinds: [kind])
        }
        let importedWater = Recipe(id: "imported-water", title: "Water under another name", caption: "", image: "", cuisine: "", minutes: 1,
                                   kcal: 0, protein: 0, allergens: [],
                                   ingredients: [Ingredient(name: "Вода", amount: 200, unit: "мл", category: "Напитки")], steps: ["Pour"])
        let course = LadCourse(id: "test-course", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "public", status: "published",
                               recipeIDs: foods.map(\.id) + [importedWater.id, CourseBeverages.waterID], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: foods + [importedWater], courses: [course])
        store.state.activeCourseIDs = [course.id]
        let original = store.state.slots
        store.proposeWeekMenu()
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertEqual(preview.changes.count, 21)
        XCTAssertTrue(preview.changes.allSatisfy { foods.map(\.id).contains($0.nextID) })
        XCTAssertTrue(preview.changes.allSatisfy { ($0.nextBeverageIDs ?? []).count == 2 })
        XCTAssertFalse(preview.changes.flatMap { $0.nextBeverageIDs ?? [] }.contains("course-drink-red-wine"))
        let firstDayDrinks = preview.changes.filter { $0.slotID.hasPrefix("0-") }.compactMap { $0.nextBeverageIDs?.last }
        XCTAssertGreaterThan(Set(firstDayDrinks).count, 1)
        store.applyReplan(preview)
        XCTAssertTrue(store.state.slots.allSatisfy { !$0.selectedBeverageIDs.isEmpty && !store.recipe($0).isBeverage })
        store.undoReplan()
        XCTAssertEqual(store.state.slots.map(\.recipeID), original.map(\.recipeID))
        XCTAssertEqual(store.state.slots.map(\.selectedBeverageIDs), original.map(\.selectedBeverageIDs))
    }

    @MainActor
    func testManualDrinkPairsAndExplicitNoDrinksSurviveGeneration() throws {
        let store = LadStore()
        store.state = .initial()
        let slot = store.slot(1, 1)
        XCTAssertNil(store.setBeverages([CourseBeverages.waterID, "course-drink-tea", "course-drink-tea"], for: slot))
        XCTAssertEqual(store.slot(1, 1).selectedBeverageIDs, [CourseBeverages.waterID, "course-drink-tea"])
        XCTAssertNil(store.toggleBeverage("course-drink-coffee", for: slot))
        XCTAssertEqual(store.slot(1, 1).selectedBeverageIDs.count, 3)
        store.proposeDayMenu(1)
        var preview = try XCTUnwrap(store.replanPreview)
        store.applyReplan(preview)
        XCTAssertEqual(store.slot(1, 1).selectedBeverageIDs, [CourseBeverages.waterID, "course-drink-tea", "course-drink-coffee"])
        XCTAssertNil(store.setBeverages([], for: store.slot(1, 1)))
        store.proposeDayMenu(1)
        preview = try XCTUnwrap(store.replanPreview)
        store.applyReplan(preview)
        XCTAssertTrue(store.slot(1, 1).selectedBeverageIDs.isEmpty)
        XCTAssertTrue(store.slot(1, 1).hasManualBeverages)
    }

    @MainActor
    func testDrinkRestrictionsAreAtomicAndDrinksCannotReplaceFood() throws {
        let store = LadStore()
        store.state = .initial()
        store.state.members[0].allergies = ["Молоко"]
        let slot = store.slot(1, 1)
        XCTAssertNil(store.setBeverages([CourseBeverages.waterID, "course-drink-tea"], for: slot))
        let selected = store.slot(1, 1).selectedBeverageIDs
        XCTAssertNotNil(store.setBeverages(["course-drink-coffee", "course-drink-milk"], for: slot))
        XCTAssertEqual(store.slot(1, 1).selectedBeverageIDs, selected)
        XCTAssertNotNil(store.setBeverages(["course-drink-red-wine"], for: slot))
        XCTAssertEqual(store.slot(1, 1).selectedBeverageIDs, selected)
        let water = try XCTUnwrap(CourseBeverages.all.first { $0.id == CourseBeverages.waterID })
        XCTAssertNotNil(store.assign(water, to: slot))
        XCTAssertNotNil(store.addDish(water, to: slot))
        XCTAssertFalse(store.chooserRecipes(for: slot, adding: true).contains { $0.isBeverage })
        var drinkOnly = slot
        drinkOnly.recipeID = water.id
        let result = PlanningCore.resolvePlan(slots: [drinkOnly], members: store.state.members, recipes: store.allRecipes,
                                              pantry: [], startDate: store.state.startDate)
        XCTAssertEqual(result.slots[slot.id]?.availability, .unavailable)
        XCTAssertTrue(result.shoppingNeeds.isEmpty)
        XCTAssertTrue(store.recipe(drinkOnly).isUnplanned)
    }

    @MainActor
    func testMissingFoodDoesNotCreateDrinkOnlyMealAndClearsOrphanDrinks() throws {
        let store = LadStore()
        store.state = .initial()
        let lunch = Recipe(id: "only-lunch", title: "Lunch", caption: "", image: "", cuisine: "", minutes: 10,
                           kcal: 100, protein: 5, allergens: [],
                           ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")], steps: ["Serve"], mealKinds: [1])
        let course = LadCourse(id: "lunch-only", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "public", status: "published", recipeIDs: [lunch.id], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [lunch], courses: [course])
        store.state.activeCourseIDs = [course.id]
        let index = try XCTUnwrap(store.state.slots.firstIndex { $0.id == "1-0" })
        store.state.slots[index].recipeID = Recipe.unplanned.id
        store.state.slots[index].setBeverages([CourseBeverages.waterID, "course-drink-coffee"])
        store.proposeDayMenu(1)
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertTrue(preview.changes.filter { $0.slotID == "1-0" || $0.slotID == "1-2" }.allSatisfy {
            $0.nextID == Recipe.unplanned.id && ($0.nextBeverageIDs ?? []).isEmpty
        })
        store.applyReplan(preview)
        XCTAssertTrue(store.slot(1, 0).selectedBeverageIDs.isEmpty)
        XCTAssertTrue(store.slot(1, 2).selectedBeverageIDs.isEmpty)
        XCTAssertEqual(store.slot(1, 1).recipeID, lunch.id)
        XCTAssertEqual(store.slot(1, 1).selectedBeverageIDs.count, 2)
    }

    @MainActor
    func testCoursePairProposesOptionalSecondDishAndUndoRestoresMeal() throws {
        let store = LadStore()
        store.state = .initial()
        let main = Recipe(id: "source-main", title: "Основное", caption: "", image: "", cuisine: "Домашняя",
                          minutes: 15, kcal: 100, protein: 5, allergens: [],
                          ingredients: [Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")],
                          steps: ["Приготовить"], allergensVerified: true, mealKinds: [1])
        var side = Recipe(id: "source-side", title: "Дополнение", caption: "", image: "", cuisine: "Домашняя",
                          minutes: 15, kcal: 80, protein: 2, allergens: [],
                          ingredients: [Ingredient(name: "Баклажан", amount: 100, unit: "г", category: "Овощи")],
                          steps: ["Приготовить"], allergensVerified: true, mealKinds: [1])
        side.isCourseSide = true
        let pair = CourseSuggestion(number: 1, lunchRecipeID: main.id, dinnerRecipeID: nil,
                                    lunchExtraRecipeIDs: [side.id])
        let course = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "weight-management", access: "members", status: "published",
                               recipeIDs: [main.id, side.id], days: nil, suggestedPairs: [pair])
        store.replaceCatalogForTesting(recipes: [main, side], courses: [course])
        store.state.activeCourseIDs = [course.id]
        XCTAssertFalse(store.chooserRecipes(for: store.slot(1, 1)).contains { $0.id == side.id })
        XCTAssertTrue(store.chooserRecipes(for: store.slot(1, 1), adding: true).contains { $0.id == side.id })
        store.state.pantryItems = [PantryItem(name: "Томаты", quantity: 1000, unit: "г", category: "Овощи")]
        let original = store.slot(1, 1)
        store.proposeDayMenu(1)
        let preview = try XCTUnwrap(store.replanPreview)
        let change = try XCTUnwrap(preview.changes.first { $0.slotID == original.id })
        XCTAssertEqual(change.nextID, main.id)
        XCTAssertEqual(change.nextExtraRecipeIDs, [side.id])
        store.applyReplan(preview)
        XCTAssertEqual(store.slot(1, 1).extraRecipeIDs, [side.id])
        XCTAssertTrue(store.shoppingNeeds.contains { $0.name == "Баклажан" })
        store.undoReplan()
        XCTAssertEqual(store.slot(1, 1).recipeID, original.recipeID)
        XCTAssertNil(store.slot(1, 1).extraRecipeIDs)
    }

    func testRecipeTargetedLunchTimeRuleIgnoresOtherLunches() throws {
        let ruleJSON = #"{"id":"oil-before-two","scope":"day","kind":"latestMealMinute","titleRu":"Масляный салат до 14:00","titleEn":"Oil salad before 14:00","titleUk":"Салат з олією до 14:00","recipeIDs":["oil-salad"],"mealKind":1,"minute":840}"#
        let rule = try JSONDecoder().decode(CourseRule.self, from: Data(ruleJSON.utf8))
        var course = LadCourse(id: "weight-week-pilot", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "weight-management", access: "members", status: "published",
                               recipeIDs: ["oil-salad", "soup"], days: nil, suggestedPairs: nil)
        course.rules = [rule]
        let schedule = MealSchedule(breakfastEnds: 11 * 60, lunchEnds: 15 * 60, dinnerEnds: 20 * 60)
        let soup = MealSlot(id: "lunch-0", day: 0, kind: 1, recipeID: "soup", memberIDs: ["one"])
        XCTAssertTrue(CourseRuleEngine.warnings(courses: [course], slots: [soup], recipes: [], schedule: schedule).isEmpty)
        var saladLunch = soup
        saladLunch.extraRecipeIDs = ["private:oil-salad"]
        let warnings = CourseRuleEngine.warnings(courses: [course], slots: [saladLunch], recipes: [], schedule: schedule)
        XCTAssertEqual(warnings.filter { $0.id.contains("oil-before-two") }.map(\.day), [0])
        let otherJSON = #"{"id":"late-other","scope":"day","kind":"earliestMealMinute","titleRu":"После 15:00","titleEn":"After 15:00","titleUk":"Після 15:00","recipeIDs":["different-salad"],"mealKind":1,"minute":900}"#
        var other = LadCourse(id: "another-course", titleRu: "Другой", titleEn: "Other", summaryRu: "", summaryEn: "",
                              category: "home", access: "members", status: "published",
                              recipeIDs: ["different-salad", "oil-salad"], days: nil, suggestedPairs: nil)
        other.rules = [try JSONDecoder().decode(CourseRule.self, from: Data(otherJSON.utf8))]
        XCTAssertFalse(CourseRuleEngine.warnings(courses: [course, other], slots: [saladLunch], recipes: [], schedule: schedule)
            .contains(where: \.isConflict))
        other.rules?[0].recipeIDs = ["oil-salad"]
        XCTAssertTrue(CourseRuleEngine.warnings(courses: [course, other], slots: [saladLunch], recipes: [], schedule: schedule)
            .contains(where: \.isConflict))
    }

    @MainActor
    func testRegenerateDayPrefersDifferentDishesAndFutureCanBeSkipped() {
        let store = LadStore()
        store.state = .initial(selectAllAvailableCourses: true)
        let tomorrow = store.slot(1, 0)
        store.toggleSkipped(tomorrow)
        XCTAssertTrue(store.isSkipped(tomorrow))
        store.proposeDayMenu(0)
        XCTAssertNotNil(store.replanPreview)
        XCTAssertTrue(store.replanPreview?.changes.contains(where: { $0.previousID != $0.nextID }) == true)
    }

    func testCourseCatalogueDecodesOneRevisionAndRejectsMissingDishes() throws {
        let recipe: [String: Any] = [
            "id": "course-dish", "title": "Тестовое блюдо", "caption": "Тест", "cuisine": "Домашняя",
            "minutes": 20, "allergens": [], "allergensVerified": true,
            "ingredients": [["name": "Томаты", "alternatives": ["Помидоры"], "amount": 100, "unit": "г", "category": "Овощи"]],
            "steps": ["Приготовить"], "stepImageIDs": ["dish-step-1"], "mealKinds": [1],
            "difficulty": "moderate", "nutrientPreparations": ["Томаты": "raw"]
        ]
        let course: [String: Any] = [
            "id": "home", "titleRu": "Домашняя кухня", "titleEn": "Home cooking",
            "summaryRu": "Тест", "summaryEn": "Test", "category": "home",
            "access": "free", "status": "published", "recipeIDs": ["course-dish"],
            "days": [["day": 1, "lunchRecipeID": "course-dish"]]
        ]
        func page(_ items: [[String: Any]], revision: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["revision": revision, "scope": "public", "items": items,
                                                     "nextCursor": NSNull()])
        }
        let recipeItem: [String: Any] = ["type": "recipe", "visibility": "public", "data": recipe]
        let courseItem: [String: Any] = ["type": "program", "visibility": "free", "data": course]
        let snapshot = try CourseCatalogAccess.decodePages([page([recipeItem, courseItem], revision: "r1")])
        XCTAssertEqual(snapshot.recipes.map(\.id), ["course-dish"])
        XCTAssertEqual(snapshot.recipes[0].stepImageIDs, ["dish-step-1"])
        XCTAssertEqual(snapshot.recipes[0].ingredients[0].alternatives, ["Помидоры"])
        XCTAssertEqual(snapshot.recipes[0].difficulty, .moderate)
        XCTAssertEqual(snapshot.recipes[0].nutrientPreparationByIngredient["Томаты"], "raw")
        XCTAssertEqual(snapshot.recipes[0].nutrients["vitamin_c"]?.coverage, 1)
        XCTAssertTrue(snapshot.recipes[0].remoteImage)
        var bundledRecipe = recipe
        bundledRecipe["imageSource"] = "bundled"
        let bundled = try CourseCatalogAccess.decodePages([
            page([["type": "recipe", "visibility": "public", "data": bundledRecipe], courseItem], revision: "r1")
        ])
        XCTAssertFalse(bundled.recipes[0].remoteImage)
        XCTAssertEqual(snapshot.courses.map(\.id), ["home"])
        XCTAssertEqual(snapshot.courses[0].days?.first?.lunchRecipeID, "course-dish")
        var stepLessRecipe = recipe
        stepLessRecipe["steps"] = [String]()
        XCTAssertThrowsError(try CourseCatalogAccess.decodePages([
            page([["type": "recipe", "visibility": "public", "data": stepLessRecipe]], revision: "r1")
        ]))
        XCTAssertThrowsError(try CourseCatalogAccess.decodePages([
            page([recipeItem], revision: "r1"), page([courseItem], revision: "r2")
        ]))
        var missing = course
        missing["recipeIDs"] = ["missing"]
        XCTAssertThrowsError(try CourseCatalogAccess.decodePages([
            page([recipeItem, ["type": "program", "visibility": "free", "data": missing]], revision: "r1")
        ]))
    }

    @MainActor
    func testLandscapeRecipePictureKeepsDetailWithinSmallPhoneWidth() throws {
        let recipe = try XCTUnwrap(Recipe.all.first { $0.id == "salmon" })
        let store = LadStore()
        store.state = .initial()
        let detail = NavigationStack { RecipeDetailView(recipe: recipe) }
            .environmentObject(store)
        let controller = UIHostingController(rootView: detail)
        controller.loadViewIfNeeded()
        let fitted = controller.sizeThatFits(in: CGSize(width: 320, height: 700))
        XCTAssertLessThanOrEqual(fitted.width, 321)
    }

    @MainActor
    func testCourseDisclosuresAndClockFitSmallPhoneInEveryLanguage() {
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let store = LadStore()
        store.state = .initial()
        var course = CourseCatalogAccess.bundledCourses[0]
        course.rules = [CourseRule(id: "morning", scope: "day", kind: "latestMealMinute",
                                   titleRu: "", titleEn: "", titleUk: "", mealKind: 0, minute: 660,
                                   preferredMinute: 600, minutesAfterWaking: 60),
                        CourseRule(id: "evening", scope: "day", kind: "latestMealMinute",
                                   titleRu: "", titleEn: "", titleUk: "", mealKind: 2, minute: 1140,
                                   windowStartMinute: 1080)]
        for language in ["ru", "en", "uk"] {
            UserDefaults.standard.set(language, forKey: L10n.languageKey)
            let views: [AnyView] = [AnyView(CourseTimingCard(courses: [course])),
                                   AnyView(CourseCatalogueCard(course: course)),
                                   AnyView(CollapsibleInfo(title: L10n.text("Описание и правила")) {
                                       Text(course.summary)
                                   })]
            for view in views {
                let controller = UIHostingController(rootView: view.environmentObject(store)
                    .environment(\.locale, Locale(identifier: language)))
                controller.loadViewIfNeeded()
                let fitted = controller.sizeThatFits(in: CGSize(width: 320, height: 700))
                XCTAssertLessThanOrEqual(fitted.width, 321, language)
                XCTAssertGreaterThan(fitted.height, 0, language)
            }
        }
    }

    func testSelectedCoursesSurviveWeekRollover() {
        XCTAssertEqual(URL(string: CourseCatalogAccess.defaultURL)?.scheme, "https")
        XCTAssertEqual(CourseCatalogAccess.bundledCourses.count, 1)
        XCTAssertEqual(Recipe.launchRecipes.count, 200)
        XCTAssertFalse(Recipe.all.first { $0.id == "salmon" }?.remoteImage ?? true)
        XCTAssertTrue(Recipe.all.allSatisfy { UIImage(named: $0.image) != nil })
        let available = Set(Recipe.all.map(\.id))
        XCTAssertTrue(CourseCatalogAccess.bundledCourses.allSatisfy { course in
            course.recipeIDs.allSatisfy { available.contains($0) }
        })
        var state = DemoState.initial()
        state.activeCourseIDs = ["home"]
        let next = DemoState.nextWeek(after: state, now: Calendar.current.date(byAdding: .day, value: 8, to: state.startDate)!)
        XCTAssertEqual(next.activeCourseIDs, ["home"])
        XCTAssertTrue(next.slots.allSatisfy { $0.recipeID == Recipe.unplanned.id })
    }

    func testPublicCaloriesAreRecalculatedFromIngredients() throws {
        let oats = try XCTUnwrap(Recipe.all.first { $0.id == "oats" })
        let estimate = try XCTUnwrap(oats.energyEstimate)
        XCTAssertTrue(estimate.unresolvedNames.isEmpty)
        XCTAssertEqual(oats.kcal, estimate.knownBatchKcal)
        XCTAssertGreaterThan(oats.kcal ?? 0, 310) // the old hard-coded figure omitted part of the recipe
        XCTAssertTrue(Recipe.all.allSatisfy { $0.energyEstimate?.unresolvedNames.isEmpty == true })
    }

    func testEveryBundledRecipeHasIngredientBasedMicronutrients() {
        XCTAssertEqual(Recipe.launchRecipes.count, 200)
        for recipe in Recipe.all {
            for key in ["protein", "fat", "carbohydrate", "fiber", "sodium"] {
                XCTAssertNotNil(recipe.nutrients[key], "\(recipe.id) \(key)")
            }
            XCTAssertNotNil(recipe.nutrients["vitamin_c"], recipe.id)
            XCTAssertNotNil(recipe.nutrients["iron"], recipe.id)
            XCTAssertNotNil(recipe.nutrients["potassium"], recipe.id)
            let invalid = recipe.nutrients.filter { !($0.value.amount >= 0 && (0...1).contains($0.value.coverage)) }
            XCTAssertTrue(invalid.isEmpty, "\(recipe.id): \(invalid)")
            XCTAssertTrue(recipe.nutrients.values.contains { $0.coverage > 0 }, recipe.id)
        }
    }

    func testCookingRetentionChangesVitaminCButNotSourceIngredientWeight() throws {
        let ingredient = Ingredient(name: "Брокколи", amount: 100, unit: "г", category: "Vegetable")
        let cooked = Recipe(id: "salmon", title: "Cooked", caption: "", image: "", cuisine: "",
                            minutes: 20, kcal: nil, protein: nil, allergens: [], ingredients: [ingredient], steps: ["Bake"])
        let raw = Recipe(id: "photo_apple_vegetable_salad", title: "Raw", caption: "", image: "", cuisine: "",
                         minutes: 5, kcal: nil, protein: nil, allergens: [], ingredients: [ingredient], steps: ["Serve"])
        let cookedC = try XCTUnwrap(NutrientEstimator.estimate(cooked)["vitamin_c"])
        let rawC = try XCTUnwrap(NutrientEstimator.estimate(raw)["vitamin_c"])
        XCTAssertEqual(rawC.amount, 89.2, accuracy: 0.01) // FDC 170379 per 100 g
        XCTAssertEqual(cookedC.amount, rawC.amount * 0.85, accuracy: 0.01) // USDA R6, 3771
        XCTAssertEqual(cooked.ingredients[0].amount, 100)
        XCTAssertNil(cooked.ingredients[0].aiEstimated)
        XCTAssertEqual(cookedC.coverage, 1)
    }

    func testMicronutrientsScaleByRecipeYieldAndUnresolvedIngredientIsNotZero() throws {
        var recipe = Recipe(id: "photo_apple_vegetable_salad", title: "Test", caption: "", image: "", cuisine: "",
                            minutes: 10, kcal: nil, protein: nil, allergens: [],
                            ingredients: [Ingredient(name: "Морковь", amount: 100, unit: "г", category: "Vegetable"),
                                          Ingredient(name: "Unknown food", amount: 100, unit: "г", category: "Other")],
                            steps: ["Serve"])
        recipe.baseServings = 2
        let iron = try XCTUnwrap(NutrientEstimator.estimate(recipe)["iron"])
        XCTAssertEqual(iron.amount, 0.3 / 2, accuracy: 0.05)
        XCTAssertEqual(iron.coverage, 0.5)
        XCTAssertEqual(iron.amount * 2, 0.3, accuracy: 0.05)
    }

    func testNewCourseIngredientsUseReviewedCookingRetention() throws {
        let examples: [(String, String, Double)] = [
            ("Гороховая крупа", "boiledDrained", 0.6), // USDA R6 521
            ("Говядина", "baked", 0.55),               // USDA R6 601
            ("Пшено", "boiledDrained", 0.8),           // USDA R6 358
            ("Гречка", "boiledDrained", 0.8)          // USDA R6 358
        ]
        for (name, method, factor) in examples {
            let ingredient = Ingredient(name: name, amount: 100, unit: "г", category: "Test")
            var cooked = Recipe(id: "private:retention-test", title: name, caption: "", image: "",
                                cuisine: "", minutes: 30, kcal: nil, protein: nil, allergens: [],
                                ingredients: [ingredient], steps: ["Cook"])
            cooked.nutrientPreparationByIngredient = [name: method]
            cooked.baseServings = 1
            var raw = cooked
            raw.nutrientPreparationByIngredient = [name: "raw"]
            let cookedB1 = try XCTUnwrap(NutrientEstimator.estimate(cooked)["vitamin_b1"], name)
            let rawB1 = try XCTUnwrap(NutrientEstimator.estimate(raw)["vitamin_b1"], name)
            XCTAssertGreaterThan(rawB1.amount, 0, name)
            XCTAssertEqual(cookedB1.amount, rawB1.amount * factor, accuracy: 0.0001, name)
            XCTAssertEqual(cookedB1.coverage, 1, name)
        }
    }

    func testEveryPrivateCourseDishHasAReviewedCookingPath() throws {
        let courseExamples = [
            ("photo_meat_mushroom_nests", "Куриное филе"),
            ("photo_cottage_bake", "Творог"),
            ("photo_chicken_rice_noodle_soup", "Куриное филе"),
            ("photo_vegetable_pilaf", "Бурый рис"),
            ("photo_vegetable_cheese_cutlets", "Брокколи"),
            ("photo_cheese_cookies", "Творог"),
            ("photo_fish_vegetables", "Минтай"),
            ("photo_buckwheat_cabbage_salad", "Гречка"),
            ("photo_cabbage_mushroom_cutlets", "Мясной фарш"),
            ("photo_zucchini_curd_fritters", "Цукини"),
            ("photo_zucchini_meat_cheese", "Цукини"),
            ("photo_beef_paprika_goulash", "Говядина"),
            ("photo_apple_vegetable_salad", "Капуста")
        ]
        XCTAssertEqual(courseExamples.count, 13)
        for (id, ingredientName) in courseExamples {
            let recipe = Recipe(id: "private:\(id)", title: id, caption: "", image: "", cuisine: "",
                                minutes: 20, kcal: nil, protein: nil, allergens: [],
                                ingredients: [Ingredient(name: ingredientName, amount: 100, unit: "г", category: "Test")],
                                steps: ["Prepare"])
            let iron = try XCTUnwrap(NutrientEstimator.estimate(recipe)["iron"], id)
            XCTAssertGreaterThan(iron.coverage, 0, id)
        }
    }

    @MainActor
    func testRemovingBreakfastParticipantReducesIngredientAndMicronutrientTotals() throws {
        let store = LadStore()
        store.state = .initial(selectAllAvailableCourses: true)
        let breakfast = store.slot(0, 0)
        let recipe = store.recipe(breakfast)
        let potassium = try XCTUnwrap(recipe.nutrients["potassium"])
        let before = store.participating(breakfast).reduce(0) { $0 + $1.portion }
        XCTAssertNil(store.toggleParticipant("igor", in: breakfast))
        let updated = store.slot(0, 0)
        let after = store.participating(updated).reduce(0) { $0 + $1.portion }
        XCTAssertLessThan(after, before)
        XCTAssertEqual(before - after, 1.25, accuracy: 0.001)
        XCTAssertLessThan(potassium.amount * after, potassium.amount * before)
        let flour = try XCTUnwrap(recipe.ingredients.first { $0.name == "Мука" })
        XCTAssertLessThan(try XCTUnwrap(flour.amount) * after / recipe.baseServings,
                          try XCTUnwrap(flour.amount) * before / recipe.baseServings)
    }

    func testChickenFilletCountHasExplicitEstimatedWeight() {
        let estimate = EnergyEstimator.evaluate([
            Ingredient(name: "Куриное филе", amount: 1, unit: "шт.", category: "Meat")
        ])
        XCTAssertTrue(estimate.unresolvedNames.isEmpty)
        XCTAssertTrue(estimate.usesEstimatedMeasures)
        XCTAssertEqual(estimate.knownBatchKcal, 240)
    }

    func testHouseholdMeasuresExposeGramEquivalentsWithoutChangingSourceAmount() {
        let examples: [(String, Double, String, Double)] = [
            ("Куриное филе", 1, "шт.", 200),
            ("Морковь", 1, "шт.", 75),
            ("Бурый рис", 1, "стакан", 180),
            ("Растительное масло", 1, "ч. л.", 5),
            ("Йогурт натуральный", 1, "ст. л.", 15),
            ("Чеснок", 1, "зуб.", 3),
            ("Минтай", 1, "филе", 150),
            ("Сельдерей", 1, "ломтик", 10),
            ("Разрыхлитель", 1, "щепотка", 0.5)
        ]
        for (name, amount, unit, grams) in examples {
            let ingredient = Ingredient(name: name, amount: amount, unit: unit, category: "Test")
            XCTAssertEqual(EnergyEstimator.estimatedGrams(for: ingredient), grams)
            XCTAssertEqual(ingredient.amount, amount)
            XCTAssertEqual(ingredient.unit, unit)
        }
    }

    func testAIInferredAmountIsVisibleAsUncertainShopping() {
        let recipe = Recipe(id: "estimate", title: "Test", caption: "", image: "", cuisine: "Test",
                            minutes: 10, kcal: nil, protein: nil, allergens: [],
                            ingredients: [Ingredient(name: "Rice", amount: 70, unit: "г", category: "Pantry",
                                                     aiEstimated: true)], steps: ["Cook"])
        let member = FamilyMember(id: "one", name: "One", goal: "", portion: 1, allergies: [])
        let slot = MealSlot(id: "0-1", day: 0, kind: 1, recipeID: recipe.id, memberIDs: [member.id])
        let plan = PlanningCore.resolvePlan(slots: [slot], members: [member], recipes: [recipe], pantry: [],
                                            startDate: Calendar.current.startOfDay(for: .now))
        XCTAssertEqual(plan.shoppingNeeds.first?.required, 70)
        XCTAssertEqual(plan.shoppingNeeds.first?.amountUnknown, false)
        XCTAssertEqual(plan.shoppingNeeds.first?.aiEstimated, true)
    }

    func testAdditionalDishContributesToSameMealShopping() throws {
        var soup = Recipe(id: "soup", title: "Суп", caption: "", image: "", cuisine: "Test",
                          minutes: 20, kcal: nil, protein: nil, allergens: [],
                          ingredients: [Ingredient(name: "Томаты", amount: 200, unit: "г", category: "Овощи")],
                          steps: ["Cook"])
        soup.baseServings = 2
        var side = Recipe(id: "side", title: "Салат", caption: "", image: "", cuisine: "Test",
                          minutes: 10, kcal: nil, protein: nil, allergens: [],
                          ingredients: [Ingredient(name: "Томаты", amount: 150, unit: "г", category: "Овощи")],
                          steps: ["Cut"])
        side.baseServings = 1
        let member = FamilyMember(id: "one", name: "One", goal: "", portion: 1, allergies: [])
        var slot = MealSlot(id: "0-1", day: 0, kind: 1, recipeID: soup.id, memberIDs: [member.id])
        slot.extraRecipeIDs = [side.id]
        let plan = PlanningCore.resolvePlan(slots: [slot], members: [member], recipes: [soup, side], pantry: [],
                                            startDate: Calendar.current.startOfDay(for: .now))
        XCTAssertEqual(plan.shoppingNeeds.first?.required, 250)
        XCTAssertEqual(plan.slots[slot.id]?.ingredients.first?.required, 250)
        let decoded = try JSONDecoder().decode(MealSlot.self, from: JSONEncoder().encode(slot))
        XCTAssertEqual(decoded.extraRecipeIDs, ["side"])
    }

    func testEstimatedRecipeYieldScalesIngredientsAndCalories() throws {
        let source: [String: Any] = [
            "id": "estimated", "title": "Test", "caption": "", "cuisine": "Test", "minutes": 20,
            "allergens": [], "allergensVerified": false, "steps": ["Cook"], "mealKinds": [1],
            "estimatedServings": 2,
            "ingredients": [["name": "Гречка", "amount": 70, "unit": "г", "category": "Pantry", "aiEstimated": true]]
        ]
        let payload = try JSONDecoder().decode(PrivateRecipePayload.self,
                                               from: JSONSerialization.data(withJSONObject: source))
        let recipe = try XCTUnwrap(payload.recipe())
        XCTAssertTrue(recipe.servingsEstimated)
        XCTAssertTrue(recipe.kcalEstimated)
        XCTAssertEqual(recipe.baseServings, 2)
        XCTAssertEqual(recipe.kcal, 120)
        let member = FamilyMember(id: "one", name: "One", goal: "", portion: 1, allergies: [])
        let slot = MealSlot(id: "0-1", day: 0, kind: 1, recipeID: recipe.id, memberIDs: [member.id])
        let plan = PlanningCore.resolvePlan(slots: [slot], members: [member], recipes: [recipe], pantry: [],
                                            startDate: Calendar.current.startOfDay(for: .now))
        XCTAssertEqual(plan.shoppingNeeds.first?.required, 35)
        XCTAssertEqual(plan.shoppingNeeds.first?.amountUnknown, false)
        XCTAssertEqual(plan.shoppingNeeds.first?.aiEstimated, true)
    }

    @MainActor
    func testSelectedCourseConstrainsNewMenuCandidatesWithoutChangingCurrentWeek() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let original = store.state.slots.map(\.recipeID)
        store.state.activeCourseIDs = []
        store.toggleCourse("mediterranean-ideas")
        XCTAssertEqual(store.state.slots.map(\.recipeID), original)
        store.proposeWeekMenu()
        let preview = try XCTUnwrap(store.replanPreview)
        let allowed = Set(try XCTUnwrap(store.selectedCourses.first).recipeIDs)
        XCTAssertTrue(preview.changes.allSatisfy { allowed.contains($0.nextID) })
    }

    @MainActor
    func testEmptyCourseSelectionCannotSuggestOrAssignDemoRecipes() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        store.state.activeCourseIDs = []
        let breakfast = store.slot(0, 0)
        XCTAssertTrue(store.chooserRecipes(for: breakfast).isEmpty)
        XCTAssertTrue(store.isOutsideSelectedCourses(breakfast.recipeID))
        store.proposeNotToday(breakfast)
        XCTAssertTrue(try XCTUnwrap(store.replanPreview).changes.isEmpty)
        store.proposeWeekMenu()
        XCTAssertTrue(try XCTUnwrap(store.replanPreview).changes.isEmpty)
        XCTAssertNotNil(store.assign(try XCTUnwrap(Recipe.all.first { $0.id == "oats" }), to: breakfast))
    }

    @MainActor
    func testRemovingLastCourseClearsUneatenMealsAndKeepsEatenHistory() {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let eaten = store.slot(0, 0)
        store.state.eatenIDs = Set(eaten.memberIDs.map { "\(eaten.id)-\($0)" })
        store.toggleCourse("lad-starter")
        XCTAssertFalse(store.hasSelectedCourses)
        XCTAssertTrue(store.selectedCourses.isEmpty)
        XCTAssertEqual(store.slot(0, 0).recipeID, eaten.recipeID)
        XCTAssertTrue(store.state.slots.filter { $0.id != eaten.id }
            .allSatisfy { $0.recipeID == Recipe.unplanned.id })
        XCTAssertTrue(store.shoppingNeeds.isEmpty)
        store.toggleCourse("mediterranean-ideas")
        XCTAssertTrue(store.hasSelectedCourses)
        XCTAssertTrue(store.state.slots.filter { $0.id != eaten.id }
            .allSatisfy { $0.recipeID == Recipe.unplanned.id })
    }

    @MainActor
    func testEmptyCatalogueCannotActAsAnImplicitSelectedSource() {
        let store = LadStore()
        store.state = .initial()
        store.replaceCatalogForTesting(recipes: [], courses: [])
        XCTAssertEqual(store.activeCourseIDs, [CourseAliases.mediterranean])
        XCTAssertFalse(store.hasSelectedCourses)
        XCTAssertTrue(store.selectedCourses.isEmpty)
        XCTAssertTrue(store.chooserRecipes(for: store.slot(0, 0)).isEmpty)
        XCTAssertTrue(store.shoppingNeeds.isEmpty)
    }

    @MainActor
    func testSelectAllThenClearSelectionLeavesNoUneatenMenu() {
        let store = LadStore()
        store.state = .initial()
        store.selectAllCourses()
        XCTAssertEqual(store.activeCourseIDs, Set(store.courses.map(\.id)))
        XCTAssertEqual(store.selectedCourses.count, store.courses.count)
        store.deselectAllCourses()
        XCTAssertFalse(store.hasSelectedCourses)
        XCTAssertTrue(store.state.slots.allSatisfy { $0.recipeID == Recipe.unplanned.id })
        XCTAssertTrue(store.shoppingNeeds.isEmpty)
    }

    func testFreshAccountCanStartWithEveryBundledCourseSelected() {
        let state = DemoState.initial(selectAllAvailableCourses: true)
        XCTAssertEqual(state.activeCourseIDs, Set(CourseCatalogAccess.bundledCourses.map(\.id)))
    }

    @MainActor
    func testClearingOutsideCoursesPreservesEatenMealsAndReleasesShopping() {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let eaten = store.slot(0, 0)
        store.state.eatenIDs = Set(eaten.memberIDs.map { "\(eaten.id)-\($0)" })
        store.state.activeCourseIDs = []
        XCTAssertGreaterThan(store.outsideFutureSlotCount, 0)
        store.clearFutureDishesOutsideCourses()
        XCTAssertEqual(store.slot(0, 0).recipeID, eaten.recipeID)
        XCTAssertTrue(store.isEaten(store.slot(0, 0)))
        XCTAssertEqual(store.slot(0, 1).recipeID, Recipe.unplanned.id)
        XCTAssertEqual(store.slot(1, 0).recipeID, Recipe.unplanned.id)
        XCTAssertTrue(store.shoppingNeeds.isEmpty)
    }

    @MainActor
    func testCourseMealTagsDriveTodayEvenAfterUsualMealTime() throws {
        let store = LadStore()
        store.state = .initial()
        let breakfast = Recipe(id: "private:tagged-breakfast", title: "Test breakfast", caption: "", image: "",
                               cuisine: "Test", minutes: 10, kcal: nil, protein: nil, allergens: [],
                               ingredients: [Ingredient(name: "Test oats", amount: nil, unit: "г", category: "Test")],
                               steps: ["Cook"], allergensVerified: false, mealKinds: [0])
        let lunch = Recipe(id: "private:tagged-lunch", title: "Test lunch", caption: "", image: "",
                           cuisine: "Test", minutes: 20, kcal: nil, protein: nil, allergens: [],
                           ingredients: [Ingredient(name: "Test beans", amount: nil, unit: "г", category: "Test")],
                           steps: ["Cook"], allergensVerified: false, mealKinds: [1])
        let course = LadCourse(id: "tagged-course", titleRu: "Тест", titleEn: "Test", summaryRu: "", summaryEn: "",
                               category: "weight-management", access: "members", status: "published",
                               recipeIDs: ["tagged-breakfast", "tagged-lunch"],
                               days: [CourseDay(day: 1, lunchRecipeID: "tagged-breakfast", dinnerRecipeID: nil)], suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [breakfast, lunch], courses: [course])
        store.toggleCourse(course.id)
        let late = try XCTUnwrap(Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: store.state.startDate))
        store.refreshClock(late)
        XCTAssertEqual(store.chooserRecipes(for: store.slot(0, 0)).map(\.id), [breakfast.id])
        XCTAssertEqual(store.chooserRecipes(for: store.slot(0, 1)).map(\.id), [lunch.id])
        XCTAssertTrue(store.chooserRecipes(for: store.slot(0, 2)).isEmpty)
        store.proposeDayMenu(0)
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertEqual(Set(preview.changes.map(\.nextID)), [breakfast.id, lunch.id, Recipe.unplanned.id])
        XCTAssertEqual(preview.reviewRecipeIDs, [breakfast.id, lunch.id])
        XCTAssertEqual(preview.lateCorrectionSlotIDs, ["0-0", "0-1", "0-2"])
        store.applyReplan(preview)
        XCTAssertEqual(store.slot(0, 0).recipeID, breakfast.id)
        XCTAssertEqual(store.slot(0, 1).recipeID, lunch.id)
        XCTAssertNil(store.recipe(store.slot(0, 0)).kcal)
        XCTAssertEqual(store.slot(0, 2).recipeID, Recipe.unplanned.id)
    }

    @MainActor
    func testUnverifiedCourseDraftCannotBypassLiveAllergyWithOldSlot() throws {
        let store = LadStore()
        store.state = .initial()
        let draft = Recipe(id: "private:allergy-draft", title: "Test dish", caption: "", image: "",
                           cuisine: "Test", minutes: 10, kcal: nil, protein: nil, allergens: [],
                           ingredients: [Ingredient(name: "Test item", amount: nil, unit: "г", category: "Test")],
                           steps: ["Cook"], allergensVerified: false, mealKinds: [1])
        let course = LadCourse(id: "allergy-course", titleRu: "Тест", titleEn: "Test", summaryRu: "", summaryEn: "",
                               category: "weight-management", access: "members", status: "published",
                               recipeIDs: ["allergy-draft"], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [draft], courses: [course])
        store.toggleCourse(course.id)
        store.refreshClock(store.state.startDate)
        let oldSlot = store.slot(0, 1)
        XCTAssertNotNil(store.assign(draft, to: oldSlot))
        XCTAssertNil(store.assign(draft, to: oldSlot, allowUnverifiedCourseDraft: true))
        store.state.slots[1].recipeID = "soup"
        store.state.members[0].allergies = ["Test allergen"]
        XCTAssertTrue(store.chooserRecipes(for: oldSlot).isEmpty)
        XCTAssertNotNil(store.assign(draft, to: oldSlot, allowUnverifiedCourseDraft: true))
        XCTAssertEqual(store.slot(0, 1).recipeID, "soup")
    }

    func testCatalogPagesAdvanceAndStopAtEnd() {
        XCTAssertEqual(CatalogPaging.nextLimit(current: 0, total: 50, step: 24), 24)
        XCTAssertEqual(CatalogPaging.nextLimit(current: 24, total: 50, step: 24), 48)
        XCTAssertEqual(CatalogPaging.nextLimit(current: 48, total: 50, step: 24), 50)
        XCTAssertEqual(CatalogPaging.nextLimit(current: 50, total: 50, step: 24), 50)
    }

    @MainActor
    func testDislikeIsPersonalPersistsAcrossWeekAndExcludesRecipeFromReplan() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let breakfast = store.slot(0, 0).recipeID
        XCTAssertTrue(store.isFavorite("salmon"))
        store.toggleDislike("salmon")
        XCTAssertTrue(store.isDisliked("salmon"))
        XCTAssertFalse(store.isFavorite("salmon"))
        store.toggleDislike(breakfast)
        store.proposeDayMenu(0)
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertNotEqual(preview.changes.first { $0.slotID == "0-0" }?.nextID, breakfast)
        let saved = try JSONEncoder().encode(store.state)
        let restored = try JSONDecoder().decode(DemoState.self, from: saved)
        XCTAssertTrue(restored.dislikes?.contains("anna|salmon") == true)
        store.toggleFavorite("salmon")
        XCTAssertTrue(store.isFavorite("salmon"))
        XCTAssertFalse(store.isDisliked("salmon"))
        store.state.selectedMemberID = "igor"
        XCTAssertFalse(store.isDisliked(breakfast))
    }

    @MainActor
    func testNotTodayOnlyAppliesAfterConfirmationAndUndoRestores() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let slot = store.slot(0, 2)
        store.proposeNotToday(slot)
        let preview = try XCTUnwrap(store.replanPreview)
        let replacement = try XCTUnwrap(preview.changes.first?.nextID)
        XCTAssertNotEqual(replacement, slot.recipeID)
        XCTAssertEqual(store.slot(0, 2).recipeID, slot.recipeID)
        XCTAssertTrue(store.state.avoidedRecipesBySlot?.isEmpty ?? true)
        store.applyReplan(preview)
        XCTAssertEqual(store.slot(0, 2).recipeID, replacement)
        XCTAssertTrue(store.state.avoidedRecipesBySlot?["0-2|anna"]?.contains(slot.recipeID) == true)
        store.proposeDayMenu(0)
        XCTAssertNotEqual(store.replanPreview?.changes.first { $0.slotID == slot.id }?.nextID, slot.recipeID)
        store.undoReplan()
        XCTAssertEqual(store.slot(0, 2).recipeID, slot.recipeID)
        XCTAssertFalse(store.state.avoidedRecipesBySlot?["0-2|anna"]?.contains(slot.recipeID) == true)
    }

    @MainActor
    func testNotTodayDoesNotReplaceEatenMeal() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let slot = store.slot(0, 1)
        store.toggleEaten(slot)
        store.proposeNotToday(slot)
        XCTAssertTrue(try XCTUnwrap(store.replanPreview).changes.isEmpty)
    }

    @MainActor
    func testNotTodayCanReplaceAnUneatenMealLaterTheSameDay() throws {
        let store = LadStore()
        store.state = .initial()
        let noon = Calendar.current.date(byAdding: .hour, value: 12, to: store.state.startDate)!
        store.refreshClock(noon)
        let breakfast = store.slot(0, 0)
        XCTAssertTrue(store.isPastWindow(breakfast))
        store.proposeNotToday(breakfast)
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertEqual(preview.lateCorrectionSlotID, breakfast.id)
        let replacement = try XCTUnwrap(preview.changes.first?.nextID)
        store.applyReplan(preview)
        XCTAssertEqual(store.slot(0, 0).recipeID, replacement)
        store.undoReplan()
        XCTAssertEqual(store.slot(0, 0).recipeID, breakfast.recipeID)
    }

    @MainActor
    func testNotTodayReadsLiveParticipantsInsteadOfAnOldSlotCopy() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let oldSlot = store.slot(0, 2)
        let index = try XCTUnwrap(store.state.slots.firstIndex(where: { $0.id == oldSlot.id }))
        store.state.slots[index].memberIDs = []
        store.proposeNotToday(oldSlot)
        XCTAssertTrue(try XCTUnwrap(store.replanPreview).changes.isEmpty)
    }

    @MainActor
    func testNotTodayDoesNotRecordDislikeForSomeoneOutsideTheMeal() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let slot = store.slot(0, 0)
        let index = try XCTUnwrap(store.state.slots.firstIndex(where: { $0.id == slot.id }))
        store.state.slots[index].memberIDs = ["igor"]
        store.proposeNotToday(slot)
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertFalse(preview.changes.isEmpty)
        XCTAssertNil(preview.pendingAvoid)
        store.applyReplan(preview)
        XCTAssertTrue(store.state.avoidedRecipesBySlot?.isEmpty ?? true)
    }

    @MainActor
    func testNotTodayOffersExplicitOutsideCourseFallbackWithoutSilentlyChangingCourse() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        store.state.activeCourseIDs = []
        let limited = LadCourse(id: "only-lunch", titleRu: "Test", titleEn: "Test", summaryRu: "", summaryEn: "",
                                category: "cuisine", access: "free", status: "published",
                                recipeIDs: ["soup", "vegetable-pasta", "lentil-stew"], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [], courses: [limited])
        store.toggleCourse("only-lunch")
        let breakfast = store.slot(0, 0)
        store.proposeNotToday(breakfast)
        let withinCourse = try XCTUnwrap(store.replanPreview)
        XCTAssertTrue(withinCourse.changes.isEmpty)
        XCTAssertEqual(withinCourse.outsideCourseSlotID, breakfast.id)

        store.proposeNotToday(breakfast, includeOutsideCourses: true)
        let outsideCourse = try XCTUnwrap(store.replanPreview)
        XCTAssertFalse(outsideCourse.changes.isEmpty)
        XCTAssertNil(outsideCourse.outsideCourseSlotID)
        XCTAssertEqual(store.activeCourseIDs, ["only-lunch"])
        XCTAssertEqual(store.slot(0, 0).recipeID, breakfast.recipeID)
    }

    @MainActor
    func testSecondNotTodayUndoRestoresTheImmediatelyPreviousRecipe() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let slot = store.slot(0, 0)
        store.proposeNotToday(slot)
        let first = try XCTUnwrap(store.replanPreview)
        store.applyReplan(first)
        let firstReplacement = store.slot(0, 0).recipeID
        XCTAssertNotEqual(firstReplacement, slot.recipeID)
        store.proposeNotToday(store.slot(0, 0))
        let second = try XCTUnwrap(store.replanPreview)
        XCTAssertFalse(second.changes.isEmpty)
        store.applyReplan(second)
        XCTAssertTrue(store.canUndoReplan)
        store.undoReplan()
        XCTAssertEqual(store.slot(0, 0).recipeID, firstReplacement)
    }

    @MainActor
    func testSharedMealAvoidsRecipesDislikedByAnotherParticipant() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let alternative = try XCTUnwrap(store.chooserRecipes(for: store.slot(0, 2)).first { $0.id != store.slot(0, 2).recipeID })
        store.state.dislikes = Set(Recipe.all.filter { $0.mealKinds.contains(2) && $0.id != alternative.id }
            .map { "igor|\($0.id)" })
        store.proposeNotToday(store.slot(0, 2))
        let proposed = try XCTUnwrap(store.replanPreview?.changes.first?.nextID)
        XCTAssertEqual(proposed, alternative.id)
    }

    func testIngredientCatalogIncludesEveryRecipeIngredientBeyondTwelveRows() {
        let privateDraft = Recipe(id: "private:test", title: "Черновик", caption: "", image: "", cuisine: "Домашняя", minutes: 10, kcal: nil, protein: nil, allergens: [], ingredients: [
            Ingredient(name: "Уникальный тестовый продукт", amount: 100, unit: "г", category: "Овощи и зелень")
        ], steps: ["Приготовить"])
        let publicOnly = PlanningCore.ingredientSuggestions(recipes: Recipe.all, pantry: [], query: "")
        let includingPrivate = PlanningCore.ingredientSuggestions(recipes: Recipe.all + [privateDraft], pantry: [], query: "")

        XCTAssertGreaterThan(publicOnly.count, 12)
        XCTAssertEqual(includingPrivate.count, publicOnly.count + 1)
        XCTAssertTrue(includingPrivate.contains { $0.name == "Уникальный тестовый продукт" })
    }

    func testProductSearchFindsAlternateLabelWithoutChangingDisplayName() {
        let suggestions = PlanningCore.ingredientSuggestions(recipes: Recipe.all, pantry: [], query: "помидор")
        XCTAssertEqual(Set(suggestions.map(\.name)), ["Томаты", "Томаты черри"])
        XCTAssertTrue(ProductNames.matches("Томаты", query: "помид"))
        XCTAssertTrue(ProductNames.matches("Томаты", query: "tomatoes"))
        XCTAssertTrue(ProductNames.matches("Томаты черри", query: "помидоры черри"))
        XCTAssertTrue(ProductNames.matches("Сушёный чеснок", query: "сухой чеснок"))
        XCTAssertFalse(ProductNames.matches("Томатная паста", query: "помидор"))
    }

    func testEnglishAndRussianResourcesAreBundled() throws {
        let englishPath = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try XCTUnwrap(Bundle(path: englishPath))
        XCTAssertEqual(english.localizedString(forKey: "Неделя", value: nil, table: "Localizable"), "Week")
        XCTAssertEqual(english.localizedString(forKey: "Томаты", value: nil, table: "Localizable"), "Tomatoes")
        XCTAssertNotNil(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testSynonymousPantryItemCoversRecipeAndReducesShopping() {
        let tomato = Ingredient(name: "Томаты", amount: 220, unit: "г", category: "Овощи и зелень")
        let pantry = [PantryItem(name: "Помидоры", quantity: 100, unit: "г", category: "Овощи и зелень")]
        XCTAssertEqual(PlanningCore.stock(for: tomato, pantry: pantry).known, 100)
        XCTAssertEqual(PlanningCore.key("Томаты", "г"), PlanningCore.key("Помидоры", "г"))
        XCTAssertNotEqual(PlanningCore.key("Томаты", "г"), PlanningCore.key("Томатная паста", "г"))
        XCTAssertEqual(PlanningCore.ingredientSuggestions(recipes: Recipe.all, pantry: pantry, query: "помидор").map(\.name), ["Томаты черри"])
    }

    func testShoppingCombinesSynonymousNamesAcrossRecipes() {
        func recipe(_ id: String, _ name: String, _ amount: Double) -> Recipe {
            Recipe(id: id, title: id, caption: "", image: "", cuisine: "Домашняя", minutes: 10,
                   kcal: nil, protein: nil, allergens: [], ingredients: [
                    Ingredient(name: name, amount: amount, unit: "г", category: "Овощи и зелень")
                   ], steps: ["Приготовить"])
        }
        let recipes = [recipe("a", "Томаты", 120), recipe("b", "Помидоры", 80)]
        let slots = [MealSlot(id: "a", day: 0, kind: 1, recipeID: "a", memberIDs: ["adult"]),
                     MealSlot(id: "b", day: 1, kind: 1, recipeID: "b", memberIDs: ["adult"])]
        let members = [FamilyMember(id: "adult", name: "Тест", goal: "", portion: 1, allergies: [])]
        let pantry = [PantryItem(name: "Помидор", quantity: 50, unit: "г", category: "Овощи и зелень")]

        let start = Calendar.current.startOfDay(for: .now)
        let needs = PlanningCore.shoppingNeeds(slots: slots, members: members, recipes: recipes, pantry: pantry,
                                               startDate: start, now: start)
        XCTAssertEqual(needs.count, 1)
        XCTAssertEqual(needs.first?.required, 200)
        XCTAssertEqual(needs.first?.missing, 150)
    }

    func testUnspecifiedIngredientAmountIsNotInventedOrCountedAsCovered() {
        let recipe = Recipe(id: "private:unknown", title: "Черновик", caption: "", image: "", cuisine: "Домашняя", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Укроп", amount: nil, unit: "г", category: "Овощи и зелень")
                            ], steps: ["Приготовить"])
        let pantry = [PantryItem(name: "Укроп", quantity: 20, unit: "г", category: "Овощи и зелень")]
        let readiness = PlanningCore.readiness(recipe, portions: 1, pantry: pantry)
        let slots = [MealSlot(id: "0-1", day: 0, kind: 1, recipeID: recipe.id, memberIDs: ["adult"])]
        let members = [FamilyMember(id: "adult", name: "Тест", goal: "", portion: 1, allergies: [])]

        XCTAssertEqual(readiness.covered, 0)
        XCTAssertEqual(readiness.uncertain, ["Укроп"])
        let start = Calendar.current.startOfDay(for: .now)
        let unresolved = PlanningCore.shoppingNeeds(slots: slots, members: members, recipes: [recipe], pantry: pantry,
                                                     startDate: start, now: start)
        XCTAssertEqual(unresolved.count, 1)
        XCTAssertTrue(unresolved[0].amountUnknown)
        XCTAssertEqual(unresolved[0].required, 0)
    }

    func testEveryPublicRecipeHasABundledPhoto() {
        for recipe in Recipe.all {
            XCTAssertFalse(recipe.image.isEmpty, "Missing image name for \(recipe.id)")
            XCTAssertNotNil(UIImage(named: recipe.image), "Missing bundled photo for \(recipe.id)")
        }
    }

    func testKnownPantryQuantityIsSubtractedFromShopping() {
        let recipe = Recipe.all.first { $0.id == "salmon" }!
        let slots = [MealSlot(id: "0-2", day: 0, kind: 2, recipeID: recipe.id, memberIDs: ["adult"])]
        let members = [FamilyMember(id: "adult", name: "Тест", goal: "Баланс", portion: 1, allergies: [])]
        let pantry = [PantryItem(name: "Картофель", quantity: 100, unit: "г", category: "Овощи и зелень")]

        let start = Calendar.current.startOfDay(for: .now)
        let needs = PlanningCore.shoppingNeeds(slots: slots, members: members, recipes: [recipe], pantry: pantry,
                                               startDate: start, now: start)
        let potato = needs.first { $0.name == "Картофель" }!
        XCTAssertEqual(potato.required, 180)
        XCTAssertEqual(potato.available, 100)
        XCTAssertEqual(potato.missing, 80)
        XCTAssertEqual(potato.sourceSlots, ["0-2"])
    }

    func testUnknownQuantityDoesNotFalselyCoverRecipe() {
        let recipe = Recipe.all.first { $0.id == "salmon" }!
        let pantry = [PantryItem(name: "Картофель", quantity: nil, unit: "г", category: "Овощи и зелень")]

        let match = PlanningCore.readiness(recipe, portions: 1, pantry: pantry)
        XCTAssertTrue(match.uncertain.contains("Картофель"))
        XCTAssertFalse(match.missing.contains("Картофель"))
        XCTAssertEqual(match.covered, 0)
    }

    func testExpiredStockIsNotCounted() {
        let ingredient = Ingredient(name: "Молоко", amount: 180, unit: "мл", category: "Молочные продукты")
        let expired = PantryItem(name: "Молоко", quantity: 500, unit: "мл", category: "Молочные продукты", expiresOn: Date(timeIntervalSince1970: 0))

        let stock = PlanningCore.stock(for: ingredient, pantry: [expired])
        XCTAssertEqual(stock.known, 0)
        XCTAssertFalse(stock.uncertain)
    }

    func testUnknownUnitsAreNotSilentlyCombined() {
        let ingredient = Ingredient(name: "Лимон", amount: 0.25, unit: "упаковка", category: "Овощи и зелень")
        let pantry = [PantryItem(name: "Лимон", quantity: 100, unit: "г", category: "Овощи и зелень")]

        XCTAssertEqual(PlanningCore.stock(for: ingredient, pantry: pantry).known, 0)
        XCTAssertTrue(PlanningCore.stock(for: ingredient, pantry: pantry).uncertain)
    }

    @MainActor
    func testOutOfStockOffersReplanAndCanUndoWithoutLosingManualShopping() throws {
        let store = LadStore()
        store.state = DemoState.initial()
        store.refreshClock(Calendar.current.date(byAdding: .hour, value: 7,
                                                  to: Calendar.current.startOfDay(for: store.state.startDate))!)
        store.state.extraShopping = ["Бумажные полотенца"]
        let target = store.slot(0, 1)
        let index = try XCTUnwrap(store.state.slots.firstIndex { $0.id == target.id })
        let potatoRecipe = try XCTUnwrap(store.allRecipes.first { $0.id == "photo2_potato_dill_yogurt" })
        store.state.slots[index].recipeID = potatoRecipe.id
        store.state.slots[index].extraRecipeIDs = []
        let potato = PantryItem(name: "Картофель", quantity: 2000, unit: "г", category: "Овощи и зелень")
        store.savePantryItem(potato)
        let original = store.slot(0, 1).recipeID

        store.markOut(potato)
        XCTAssertEqual(store.pantryItem(named: "Картофель", unit: "г")?.quantity, 0)
        XCTAssertEqual(store.slot(0, 1).recipeID, original, "Preview must not change the plan")
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertTrue(preview.changes.contains { $0.slotID == target.id && $0.nextID != original })
        store.applyReplan(preview)
        XCTAssertNotEqual(store.slot(0, 1).recipeID, original)
        store.undoReplan()
        XCTAssertEqual(store.slot(0, 1).recipeID, original)
        XCTAssertEqual(store.state.extraShopping, ["Бумажные полотенца"])
    }

    func testPrivateDraftCanOmitUnverifiedNutrition() throws {
        let data = Data(#"{"id":"draft","imageId":"draft","title":"Черновик","caption":"Проверить","cuisine":"Домашняя","minutes":20,"allergens":[],"allergensVerified":false,"ingredients":[{"name":"Овощ","amount":1,"unit":"шт.","category":"Овощи и зелень"}],"steps":["Приготовить."]}"#.utf8)
        let draft = try JSONDecoder().decode(PrivateRecipePayload.self, from: data)
        let cachedDraft = try JSONDecoder().decode(PrivateRecipePayload.self, from: JSONEncoder().encode(draft))
        let recipe = try XCTUnwrap(draft.recipe())

        XCTAssertEqual(cachedDraft.ingredients.first?.name, "Овощ")
        XCTAssertNil(recipe.kcal)
        XCTAssertNil(recipe.protein)
        XCTAssertTrue(recipe.isPrivate)
        XCTAssertFalse(recipe.allergensVerified)
        XCTAssertEqual(recipe.image, "draft")
    }

    func testPrivateDraftAcceptsExplicitlyUnknownIngredientQuantity() throws {
        let data = Data(#"{"id":"draft","title":"Черновик","caption":"","cuisine":"Домашняя","minutes":10,"allergens":[],"allergensVerified":false,"ingredients":[],"unquantifiedIngredients":[{"name":"Укроп","unit":"г","category":"Овощи и зелень"}],"steps":["Добавьте укроп."]}"#.utf8)
        let draft = try JSONDecoder().decode(PrivateRecipePayload.self, from: data)
        let recipe = try XCTUnwrap(draft.recipe())
        XCTAssertEqual(recipe.ingredients.first?.name, "Укроп")
        XCTAssertNil(recipe.ingredients.first?.amount)
    }

    func testDuplicatePrivateRecipeIDsRejectEntireSnapshot() {
        let recipe = #"{"id":"same","title":"Test","caption":"","cuisine":"Home","minutes":10,"allergens":[],"allergensVerified":true,"ingredients":[{"name":"Apple","amount":1,"unit":"pcs","category":"Fruit"}],"steps":["Cook"]}"#
        let data = Data("{\"recipes\":[\(recipe),\(recipe)]}".utf8)
        XCTAssertThrowsError(try PrivateRecipeAccess.decodeRecipes(data))
    }

    func testCompleteRecipeIsReadyWithoutManualVerificationFlag() throws {
        let recipe = Recipe(id: "private:draft", title: "Draft", caption: "", image: "", cuisine: "",
                            minutes: 10, kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")
                            ], steps: ["Cook"], allergensVerified: false)
        let day = Calendar.current.startOfDay(for: .now)
        let slot = MealSlot(id: "draft", day: 0, kind: 1, recipeID: recipe.id, memberIDs: ["adult"])
        let person = FamilyMember(id: "adult", name: "Test", goal: "", portion: 1, allergies: [])
        let pantry = [PantryItem(name: "Томаты", quantity: 100, unit: "г", category: "Овощи")]
        let result = PlanningCore.resolvePlan(slots: [slot], members: [person], recipes: [recipe], pantry: pantry,
                                              startDate: day, now: day)
        XCTAssertEqual(result.slots[slot.id]?.availability, .active)
        XCTAssertTrue(try XCTUnwrap(result.slots[slot.id]).isReady)
        XCTAssertEqual(result.shoppingNeeds.first?.required, 100)
    }

    func testOneStockCannotMakeTwoMealsReady() throws {
        let recipe = Recipe(id: "test-tomato", title: "Томаты", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Томаты", amount: 100, unit: "г", category: "Овощи")
                            ], steps: ["Приготовить"])
        let slots = [MealSlot(id: "0-1", day: 0, kind: 1, recipeID: recipe.id, memberIDs: ["adult"]),
                     MealSlot(id: "1-1", day: 1, kind: 1, recipeID: recipe.id, memberIDs: ["adult"])]
        let members = [FamilyMember(id: "adult", name: "Тест", goal: "", portion: 1, allergies: [])]
        let pantry = [PantryItem(name: "Помидоры", quantity: 100, unit: "г", category: "Овощи")]
        let day = Calendar.current.startOfDay(for: .now)
        let result = PlanningCore.resolvePlan(slots: slots, members: members, recipes: [recipe], pantry: pantry,
                                              startDate: day, now: day)

        XCTAssertTrue(try XCTUnwrap(result.slots["0-1"]).isReady)
        XCTAssertFalse(try XCTUnwrap(result.slots["1-1"]).isReady)
        XCTAssertEqual(result.slots["1-1"]?.ingredients.first?.shortage, 100)
        XCTAssertEqual(result.shoppingNeeds.first?.required, 200)
        XCTAssertEqual(result.shoppingNeeds.first?.available, 100)
        XCTAssertEqual(result.shoppingNeeds.first?.missing, 100)
        let extra = PlanningCore.readiness(recipe, portions: 1, pantry: result.freePantry, now: day)
        XCTAssertEqual(extra.missing, ["Томаты"])
    }

    func testPartialStockAndFutureExpiryStayVisible() throws {
        let recipe = Recipe(id: "test-milk", title: "Овсянка с молоком", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Молоко", amount: 200, unit: "мл", category: "Молочные продукты"),
                                Ingredient(name: "Овсянка", amount: 20, unit: "г", category: "Крупы")
                            ], steps: ["Приготовить"])
        let members = [FamilyMember(id: "adult", name: "Тест", goal: "", portion: 1, allergies: [])]
        let start = Calendar.current.startOfDay(for: .now)
        let expiringToday = PantryItem(name: "Молоко", quantity: 80, unit: "мл", category: "Молочные продукты", expiresOn: start)
        let today = [MealSlot(id: "0-0", day: 0, kind: 0, recipeID: recipe.id, memberIDs: ["adult"])]
        let tomorrow = [MealSlot(id: "1-0", day: 1, kind: 0, recipeID: recipe.id, memberIDs: ["adult"])]
        let todayResult = PlanningCore.resolvePlan(slots: today, members: members, recipes: [recipe],
                                                   pantry: [expiringToday], startDate: start, now: start)
        let tomorrowResult = PlanningCore.resolvePlan(slots: tomorrow, members: members, recipes: [recipe],
                                                      pantry: [expiringToday], startDate: start, now: start)
        XCTAssertEqual(todayResult.slots["0-0"]?.ingredients.first?.shortage, 120)
        XCTAssertEqual(tomorrowResult.slots["1-0"]?.ingredients.first?.shortage, 200)
    }

    func testMealSuggestionUsesLocalClockWithoutErasingBreakfast() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jerusalem"))
        let day = DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                                 year: 2026, month: 9, day: 23, hour: 0).date!
        let afternoon = calendar.date(byAdding: .hour, value: 16, to: day)!
        let evening = calendar.date(byAdding: .hour, value: 23, to: day)!
        XCTAssertEqual(MealTiming.suggestedKind(on: 0, currentDay: 0, now: afternoon,
                                                 schedule: .standard, calendar: calendar), 2)
        XCTAssertTrue(MealTiming.isPastWindow(day: 0, kind: 0, currentDay: 0, now: afternoon,
                                             schedule: .standard, calendar: calendar))
        XCTAssertNil(MealTiming.suggestedKind(on: 0, currentDay: 0, now: evening,
                                              schedule: .standard, calendar: calendar))
        XCTAssertEqual(MealTiming.suggestedKind(on: 1, currentDay: 0, now: evening,
                                                 schedule: .standard, calendar: calendar), 0)
    }

    func testPassedBreakfastRemainsPlannedUntilExplicitlySkipped() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jerusalem"))
        let day = DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                                 year: 2026, month: 9, day: 23, hour: 0).date!
        let noon = calendar.date(byAdding: .hour, value: 12, to: day)!
        let recipe = Recipe(id: "test-egg", title: "Egg", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Яйцо", amount: 2, unit: "шт.", category: "Молочные продукты")
                            ], steps: ["Cook"])
        let members = [FamilyMember(id: "adult", name: "Test", goal: "", portion: 1, allergies: [])]
        let slots = [MealSlot(id: "breakfast", day: 0, kind: 0, recipeID: recipe.id, memberIDs: ["adult"]),
                     MealSlot(id: "lunch", day: 0, kind: 1, recipeID: recipe.id, memberIDs: ["adult"])]
        let result = PlanningCore.resolvePlan(slots: slots, members: members, recipes: [recipe], pantry: [],
                                              startDate: day, now: noon, calendar: calendar)
        XCTAssertEqual(result.slots["breakfast"]?.availability, .past)
        XCTAssertEqual(result.slots["lunch"]?.availability, .active)
        XCTAssertEqual(result.shoppingNeeds.first?.required, 200)
        XCTAssertEqual(result.shoppingNeeds.first?.unit, "г")
        XCTAssertEqual(result.shoppingNeeds.first?.sourceSlots, ["breakfast", "lunch"])
        let skipped = PlanningCore.resolvePlan(slots: slots, members: members, recipes: [recipe], pantry: [],
                                               startDate: day, now: noon, calendar: calendar,
                                               skippedIDs: ["breakfast"])
        XCTAssertEqual(skipped.slots["breakfast"]?.availability, .skipped)
        XCTAssertEqual(skipped.shoppingNeeds.first?.required, 100)
        XCTAssertEqual(skipped.shoppingNeeds.first?.sourceSlots, ["lunch"])
    }

    func testPartlyEatenMealOnlyPlansRemainingParticipants() throws {
        let day = Calendar.current.startOfDay(for: .now)
        let recipe = Recipe(id: "eggs-test", title: "Eggs", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Яйцо", amount: 2, unit: "шт.", category: "Молочные продукты")
                            ], steps: ["Cook"])
        let people = [FamilyMember(id: "a", name: "A", goal: "", portion: 1, allergies: []),
                      FamilyMember(id: "b", name: "B", goal: "", portion: 1.5, allergies: [])]
        let slot = MealSlot(id: "s", day: 0, kind: 1, recipeID: recipe.id, memberIDs: ["a", "b"])
        let result = PlanningCore.resolvePlan(slots: [slot], members: people, recipes: [recipe], pantry: [],
                                              startDate: day, now: day, eatenIDs: ["s-a"])
        XCTAssertEqual(result.shoppingNeeds.first?.required, 150)
        XCTAssertEqual(result.slots["s"]?.availability, .active)
    }

    @MainActor
    func testOldPreviewCannotReplacePastMealButExplicitSameDayAssignmentCan() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        let breakfast = store.slot(0, 0)
        store.proposeNotToday(breakfast)
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertFalse(preview.changes.isEmpty)
        let noon = Calendar.current.date(byAdding: .hour, value: 12, to: store.state.startDate)!
        store.refreshClock(noon)
        store.applyReplan(preview)
        XCTAssertEqual(store.slot(0, 0).recipeID, breakfast.recipeID)
        XCTAssertNil(store.assign(Recipe.all.first { $0.id == "oats" }!, to: breakfast))
        XCTAssertEqual(store.slot(0, 0).recipeID, "oats")
    }

    @MainActor
    func testSkippingPastMealReleasesShoppingAndLoggingItRestoresTheFact() {
        let store = LadStore()
        store.state = .initial()
        let noon = Calendar.current.date(byAdding: .hour, value: 12, to: store.state.startDate)!
        store.refreshClock(noon)
        let breakfast = store.slot(0, 0)
        let before = store.shoppingNeeds.first { ProductNames.canonical($0.name) == ProductNames.canonical("Творог") }?.required ?? 0
        store.toggleSkipped(breakfast)
        XCTAssertTrue(store.isSkipped(breakfast))
        let after = store.shoppingNeeds.first { ProductNames.canonical($0.name) == ProductNames.canonical("Творог") }?.required ?? 0
        XCTAssertLessThan(after, before)
        store.toggleEaten(breakfast)
        XCTAssertFalse(store.isSkipped(breakfast))
        XCTAssertTrue(store.isEaten(breakfast))
        XCTAssertNotNil(store.toggleParticipant(store.currentMember.id, in: breakfast))
        XCTAssertTrue(store.slot(0, 0).memberIDs.contains(store.currentMember.id))
    }

    func testQuantityEditorParsesItsOwnRussianGrouping() {
        XCTAssertEqual(QuantityInput.parse("12\u{00A0}000,5", locale: Locale(identifier: "ru_RU")), 12_000.5)
        XCTAssertEqual(QuantityInput.parse("12,000.5", locale: Locale(identifier: "en_US")), 12_000.5)
        XCTAssertNil(QuantityInput.parse("12abc", locale: Locale(identifier: "ru_RU")))
    }

    @MainActor
    func testChildCannotKeepAdultWeightGoalInDomain() {
        let store = LadStore()
        store.state = .initial()
        var child = store.state.members[2]
        child.ageYears = 12
        child.goal = "Снижение"
        child.dailyEnergyTarget = 1200
        store.updateMember(child)
        XCTAssertEqual(store.state.members[2].goal, "Без цели по весу")
        XCTAssertNil(store.state.members[2].dailyEnergyTarget)
    }

    func testNewWeekKeepsPreferencesButNotOldMealFactsOrVariableParticipation() {
        var old = DemoState.initial()
        old.eatenIDs.insert("0-0-anna")
        old.slots[0].memberIDs = []
        old.extraShopping = ["Soap"]
        let nextDate = Calendar.current.date(byAdding: .day, value: 8, to: old.startDate)!
        let next = DemoState.nextWeek(after: old, now: nextDate)
        XCTAssertEqual(Calendar.current.startOfDay(for: next.startDate), Calendar.current.startOfDay(for: nextDate))
        XCTAssertTrue(next.eatenIDs.isEmpty)
        XCTAssertEqual(next.extraShopping, ["Soap"])
        XCTAssertTrue(next.slots.filter { $0.kind == 0 }.allSatisfy(\.memberIDs.isEmpty))
    }

    @MainActor
    func testPurchaseCreatesFreshLotAndDuplicateCommandIsIgnored() throws {
        let store = LadStore()
        store.state = .initial()
        let old = PantryItem(name: "Томаты", quantity: nil, unit: "г", category: "Овощи", expiresOn: Date(timeIntervalSince1970: 0))
        store.savePantryItem(old)
        let need = ShoppingNeed(id: "томат|г", name: "Томаты", unit: "г", category: "Овощи",
                                required: 200, available: 0, amountUnknown: true, aiEstimated: false,
                                sourceSlots: ["0-1"])
        store.addPurchasedToPantry(need, quantity: 150, commandID: "receipt-1")
        store.addPurchasedToPantry(need, quantity: 150, commandID: "receipt-1")
        XCTAssertEqual(store.pantry.count, 2)
        XCTAssertNil(store.pantry.first { $0.id != old.id }?.expiresOn)
        XCTAssertNil(store.pantry.first { $0.id == old.id }?.quantity)
        XCTAssertEqual(store.state.purchaseReceipts?.count, 1)
    }

    @MainActor
    func testStalePreviewAndLaterFactCannotBeUndoneIntoOldMeal() throws {
        let store = LadStore()
        store.state = .initial()
        let day = Calendar.current.startOfDay(for: .now)
        store.refreshClock(Calendar.current.date(byAdding: .hour, value: 7, to: day)!)
        let dinner = store.slot(0, 2)
        store.proposeNotToday(dinner)
        let stale = try XCTUnwrap(store.replanPreview)
        store.state.members[0].allergies.append("Рыба")
        store.applyReplan(stale)
        XCTAssertEqual(store.slot(0, 2).recipeID, dinner.recipeID)

        store.state.members[0].allergies = []
        store.proposeNotToday(dinner)
        let fresh = try XCTUnwrap(store.replanPreview)
        guard !fresh.changes.isEmpty else { return XCTFail("Expected a replacement") }
        store.applyReplan(fresh)
        let replacement = store.slot(0, 2).recipeID
        store.toggleEaten(store.slot(0, 2))
        store.undoReplan()
        XCTAssertEqual(store.slot(0, 2).recipeID, replacement)
    }
}

extension PlanningCoreTests {
    func testExpandedBreakfastsHaveCompleteQuantifiedIngredientsAndIndependentPhotos() throws {
        let added = Recipe.launchRecipes.filter { $0.image.hasPrefix("Breakfast-") }
        XCTAssertEqual(added.count, 10)
        XCTAssertEqual(Set(added.map(\.image)).count, 10)
        for recipe in added {
            XCTAssertEqual(recipe.mealKinds, [0], recipe.id)
            XCTAssertTrue(recipe.isPlanEligible, recipe.id)
            XCTAssertEqual(recipe.baseServings, 1)
            XCTAssertTrue(recipe.energyEstimate?.unresolvedNames.isEmpty == true, recipe.id)
            XCTAssertTrue((300...650).contains(try XCTUnwrap(recipe.kcal)), recipe.id)
            XCTAssertGreaterThan(try XCTUnwrap(recipe.nutrients["protein"]).amount, 15, recipe.id)
            XCTAssertNotNil(UIImage(named: recipe.image), recipe.id)
            XCTAssertTrue(recipe.ingredients.allSatisfy { $0.amount != nil && $0.amount! > 0 }, recipe.id)
        }
    }

    @MainActor func testSnackIsOffByDefaultAndEnabledOnlyForChosenPersonAndDay() throws {
        let store = LadStore(); store.state = .initial()
        let member = store.currentMember.id
        XCTAssertEqual(store.state.slots.count, 21)
        XCTAssertNil(store.preLunchSnack(on: 1))
        XCTAssertNil(store.setPreLunchSnack(true, on: 1, memberID: member))
        XCTAssertEqual(try XCTUnwrap(store.preLunchSnack(on: 1)).memberIDs, [member])
        XCTAssertEqual(store.mealKinds(on: 1, forMember: member), [0, 3, 1, 2])
        XCTAssertEqual(store.mealKinds(on: 1, forMember: "igor"), [0, 1, 2])
        XCTAssertNil(store.preLunchSnack(on: 0))
        XCTAssertNil(store.preLunchSnack(on: 2))
        let encoded = try JSONEncoder().encode(store.state)
        let decoded = try JSONDecoder().decode(DemoState.self, from: encoded)
        XCTAssertTrue(decoded.hasValidMealSlots)
        XCTAssertEqual(decoded.slots.filter { $0.kind == 3 }.count, 1)
        XCTAssertNil(store.setPreLunchSnack(false, on: 1, memberID: member))
        XCTAssertNil(store.preLunchSnack(on: 1))
        XCTAssertEqual(store.state.slots.count, 21)
        XCTAssertTrue(store.state.hasValidMealSlots)
    }

    @MainActor func testSnackChoiceRespectsAllergiesAndNeverSilentlyAddsAnUnsafeFood() throws {
        let store = LadStore(); store.state = .initial()
        store.state.members[0].allergies = ["Молоко"]
        let member = store.currentMember.id
        XCTAssertNil(store.setPreLunchSnack(true, on: 1, memberID: member))
        let snack = try XCTUnwrap(store.preLunchSnack(on: 1))
        XCTAssertEqual(snack.recipeID, "snack-apple-walnuts")
        XCTAssertFalse(AllergenMatching.conflicts(selected: ["Молоко"], recipe: store.recipe(snack).knownAllergens))
        XCTAssertNil(store.setPreLunchSnack(false, on: 1, memberID: member))
        store.state.members[0].allergies = ["Молоко", "Орехи"]
        XCTAssertNotNil(store.setPreLunchSnack(true, on: 1, memberID: member))
        XCTAssertNil(store.preLunchSnack(on: 1))
    }

    @MainActor func testSnackContributesToShoppingEnergyAndDiaryAndRemovalDoesNotEraseHistory() throws {
        let store = LadStore(); store.state = .initial()
        let member = store.currentMember
        let before = store.dayRecipes(for: member, day: 1).reduce(0.0) { $0 + Double($1.recipe.kcal ?? 0) * $1.portion }
        XCTAssertNil(store.setPreLunchSnack(true, on: 1, memberID: member.id))
        let slot = try XCTUnwrap(store.preLunchSnack(on: 1))
        let recipe = store.recipe(slot)
        let after = store.dayRecipes(for: member, day: 1).reduce(0.0) { $0 + Double($1.recipe.kcal ?? 0) * $1.portion }
        XCTAssertEqual(after - before, Double(try XCTUnwrap(recipe.kcal)) * member.portion, accuracy: 0.001)
        let need = try XCTUnwrap(store.planRequirements.shoppingNeeds.first { $0.name == "Йогурт греческий" && $0.sourceSlots.contains(slot.id) })
        XCTAssertGreaterThanOrEqual(need.required, 100 * member.portion)
        let draft = store.diaryDraft(for: slot)
        XCTAssertEqual(draft.mealKind, 3)
        XCTAssertEqual(draft.foods.first?.recipeID, recipe.id)
        XCTAssertNotNil(draft.kcal)
        XCTAssertNil(store.setPreLunchSnack(true, on: 0, memberID: member.id))
        let today = try XCTUnwrap(store.preLunchSnack(on: 0))
        store.toggleEaten(today)
        let recorded = try XCTUnwrap(store.diaryEntry(for: today))
        XCTAssertNotNil(store.setPreLunchSnack(false, on: 0, memberID: member.id))
        XCTAssertEqual(store.diaryEntry(for: today)?.id, recorded.id)
        XCTAssertNotNil(store.preLunchSnack(on: 0))
    }

    func testAutomaticPortionsIncludeFixedSnackEnergyWithoutTreatingItAsAMainMeal() throws {
        let member = portionProfile()
        let main = portionMeal()
        let snack = try XCTUnwrap(CourseSnacks.all.first)
        var slots = portionDay(main)
        slots.append(MealSlot(id: "0-3", day: 0, kind: 3, recipeID: snack.id, memberIDs: [member.id]))
        let recipes = [main, snack]
        let factor = try XCTUnwrap(PersonalPortions.foodMultiplier(member: member, day: 0, slots: slots,
                                                                  recipes: recipes, skippedIDs: []))
        XCTAssertEqual(factor, (2021 - Double(try XCTUnwrap(snack.kcal))) / 1500, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.multiplier(member: member, recipe: snack, day: 0, slots: slots,
                                                   recipes: recipes, skippedIDs: []), member.portion)
        slots.removeAll { $0.kind == 2 }
        XCTAssertNil(PersonalPortions.foodMultiplier(member: member, day: 0, slots: slots, recipes: recipes, skippedIDs: []))
    }

    @MainActor func testSnackTimeTracksPersonalLunchAndReminderUsesTheSameTime() throws {
        let store = LadStore(); store.state = .initial()
        XCTAssertEqual(store.mealSchedule.endMinute(for: 3), 13 * 60)
        store.updateMealSchedule(MealSchedule(breakfastEnds: 10 * 60, lunchEnds: 15 * 60, dinnerEnds: 19 * 60))
        XCTAssertEqual(store.mealSchedule.endMinute(for: 3), 14 * 60)
        XCTAssertNil(store.setPreLunchSnack(true, on: 1, memberID: store.currentMember.id))
        let reminder = try XCTUnwrap(MealReminder.future(state: store.state, now: store.now).first { $0.kind == 3 })
        XCTAssertEqual(Calendar.current.component(.hour, from: reminder.date), 14)
        XCTAssertEqual(Calendar.current.component(.minute, from: reminder.date), 0)
        let next = DemoState.nextWeek(after: store.state, now: store.now.addingTimeInterval(7 * 86400))
        XCTAssertFalse(next.slots.contains { $0.kind == 3 }) // hunger is chosen per day, not copied into every week
    }

    func testPortionShareUsesAgeGoalAndFilledBodyFieldsWithoutChangingMenuTargets() throws {
        func person(_ name: String, age: Int, goal: String) -> FamilyMember {
            FamilyMember(id: name, name: name, goal: goal, portion: 1, allergies: [], ageYears: age)
        }
        let maria = person("Мария", age: 35, goal: "Снижение")
        let sergey = person("Сергей", age: 39, goal: "Без цели по весу")
        let ester = person("Естер", age: 10, goal: "Без цели по весу")
        let beatrice = person("Беатрис", age: 5, goal: "Без цели по весу")
        XCTAssertEqual(PersonalPortions.profileShare(maria), 0.85, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.profileShare(sergey), 1, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.profileShare(ester), 0.80, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.profileShare(beatrice), 0.65, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.percent(PersonalPortions.profileShare(maria)), 85)
        XCTAssertEqual(PersonalPortions.percent(PersonalPortions.profileShare(beatrice)), 65)
        let food = portionMeal(kcal: 450)
        XCTAssertEqual(PersonalPortions.multiplier(member: maria, recipe: food, day: 0, slots: [], recipes: [food], skippedIDs: []), 0.85, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.multiplier(member: beatrice, recipe: food, day: 0, slots: [], recipes: [food], skippedIDs: []), 0.65, accuracy: 0.0001)
        let wine = try XCTUnwrap(CourseBeverages.all.first { $0.id == "course-drink-red-wine" })
        XCTAssertEqual(PersonalPortions.multiplier(member: beatrice, recipe: wine, day: 0, slots: [], recipes: [wine], skippedIDs: []), 1)
        XCTAssertNil(PersonalPortions.energyTarget(maria))
        XCTAssertNil(PersonalPortions.energyTarget(ester))
        XCTAssertNil(PersonalPortions.foodMultiplier(member: maria, day: 0, slots: portionDay(food), recipes: [food], skippedIDs: []))
        XCTAssertNil(WeightGap.targets(for: ester))
        XCTAssertNil(WeightGap.targets(for: beatrice))

        var gain = maria
        gain.goal = "Набор"
        XCTAssertEqual(PersonalPortions.profileShare(gain), 1.15, accuracy: 0.0001)
        var typed = maria
        typed.dailyEnergyTarget = 1800
        XCTAssertEqual(PersonalPortions.profileShare(typed), 0.9, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.energyTarget(typed), 1800)

        var measured = ester
        measured.heightCm = 140
        measured.weightKg = 32
        measured.energySex = .female
        measured.energyActivity = .inactive
        XCTAssertEqual(try XCTUnwrap(PersonalPortions.youthEnergy(measured)), 1589.53, accuracy: 0.01)
        XCTAssertEqual(PersonalPortions.profileShare(measured), 1589.53 / 2000, accuracy: 0.0001)
        measured.energyActivity = nil
        XCTAssertNil(PersonalPortions.youthEnergy(measured))
        XCTAssertEqual(PersonalPortions.profileShare(measured), 0.80, accuracy: 0.0001)
        measured.energyActivity = .inactive
        measured.energyContext = .specialDiet
        XCTAssertNil(PersonalPortions.plateEnergy(measured))
        XCTAssertEqual(PersonalPortions.profileShare(measured), 1)

        var manualAdult = maria
        manualAdult.automaticPortions = false
        XCTAssertEqual(PersonalPortions.multiplier(member: manualAdult, recipe: food, day: 0, slots: [], recipes: [food], skippedIDs: []), 1)
        var customChild = beatrice
        customChild.automaticPortions = false
        customChild.portion = 0.8
        XCTAssertEqual(PersonalPortions.profileShare(customChild), 0.8, accuracy: 0.0001)

        var legacy = person("Старый", age: 30, goal: "Баланс")
        legacy.ageYears = nil
        legacy.portion = 1.25
        XCTAssertEqual(PersonalPortions.profileShare(legacy), 1.25, accuracy: 0.0001)
        XCTAssertNil(PersonalPortions.energyTarget(legacy))

        var state = DemoState.initial()
        state.portionRulesVersion = nil
        state.members[2].ageYears = 5
        state.members[2].automaticPortions = false
        state.members[2].portion = 1
        state.migratePortionRules()
        XCTAssertNil(state.members[2].automaticPortions)
        XCTAssertEqual(state.portionRulesVersion, 1)
        state.members[2].automaticPortions = false
        state.members[2].portion = 0.8
        state.portionRulesVersion = nil
        state.migratePortionRules()
        XCTAssertEqual(state.members[2].automaticPortions, false)

        var reducing = portionProfile()
        reducing.goal = "Снижение"
        let fitted = try XCTUnwrap(PersonalPortions.foodMultiplier(member: reducing, day: 0, slots: portionDay(food), recipes: [food], skippedIDs: []))
        XCTAssertEqual(fitted, 2021 / 1350, accuracy: 0.0001)
        XCTAssertEqual(PersonalPortions.multiplier(member: reducing, recipe: food, day: 0, slots: portionDay(food), recipes: [food], skippedIDs: []),
                       min(fitted * 0.85, PersonalPortions.menuCeiling(reducing)), accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(PersonalPortions.energyTarget(reducing)), 2021, accuracy: 0.01)
        var incomplete = portionDay(food)
        incomplete.removeLast()
        XCTAssertNil(PersonalPortions.foodMultiplier(member: reducing, day: 0, slots: incomplete, recipes: [food], skippedIDs: []))
        XCTAssertEqual(PersonalPortions.multiplier(member: reducing, recipe: food, day: 0, slots: incomplete, recipes: [food], skippedIDs: []), 0.85, accuracy: 0.0001)
    }

    func testWeightGapUsesBodyWeightAndLeavesChildrenUnset() throws {
        let member = portionProfile()
        let targets = try XCTUnwrap(WeightGap.targets(for: member))
        XCTAssertEqual(targets.energy, 2021, accuracy: 0.01)
        XCTAssertEqual(targets.protein, max(0.8 * 60, 2021 * 0.10 / 4), accuracy: 0.01)
        XCTAssertEqual(targets.fat, 2021 * 0.20 / 9, accuracy: 0.01)
        XCTAssertEqual(targets.carbohydrate, 2021 * 0.45 / 4, accuracy: 0.01)
        XCTAssertEqual(targets.fiber, 2021 / 1000 * 14, accuracy: 0.01)
        XCTAssertEqual(WeightGap.remainder(consumed: 30, target: 50).missing, 20, accuracy: 0.001)
        var child = member
        child.ageYears = 12
        XCTAssertNil(WeightGap.targets(for: child))
        var pregnancy = member
        pregnancy.energyContext = .pregnancyOrLactation
        XCTAssertNil(WeightGap.targets(for: pregnancy))
        let targetsForClosure = targets
        let remaining = WeightGap.Intake(energy: 700, protein: 40, fat: 20, carbohydrate: 80, fiber: 10)
        func offered(protein: Double) -> WeightGap.Intake {
            WeightGap.Intake(energy: 500, protein: protein, fat: 10, carbohydrate: 40, fiber: 4)
        }
        XCTAssertGreaterThan(WeightGap.closure(offered: offered(protein: 40), remaining: remaining, targets: targetsForClosure),
                             WeightGap.closure(offered: offered(protein: 0), remaining: remaining, targets: targetsForClosure))
    }

    @MainActor func testAutomaticDayMenuFillsTheWeightGapAndKeepsAChosenDish() throws {
        let store = LadStore()
        store.state = .initial()
        store.refreshClock(store.state.startDate)
        var member = portionProfile()
        member.id = "anna"
        member.name = "Анна"
        store.state.members = [member]
        store.state.selectedMemberID = member.id
        func dish(_ id: String, protein: Int) -> Recipe {
            var recipe = Recipe(id: id, title: id, caption: "", image: "", cuisine: "", minutes: 20,
                                kcal: 500, protein: protein, allergens: [],
                                ingredients: [Ingredient(name: "Рис", amount: 100, unit: "г", category: "Крупы")],
                                steps: ["Cook"], allergensVerified: true, mealKinds: [2])
            recipe.nutrients = [
                "protein": NutrientValue(amount: Double(protein), unit: "г", source: "test", coverage: 1),
                "fat": NutrientValue(amount: 10, unit: "г", source: "test", coverage: 1),
                "carbohydrate": NutrientValue(amount: 40, unit: "г", source: "test", coverage: 1),
                "fiber": NutrientValue(amount: 2, unit: "г", source: "test", coverage: 1)
            ]
            return recipe
        }
        let plain = dish("gap-a-plain", protein: 0)
        let lean = dish("gap-b-lean", protein: 40)
        let course = LadCourse(id: "gap-course", titleRu: "Курс", titleEn: "Course", summaryRu: "", summaryEn: "",
                               category: "home", access: "free", status: "published",
                               recipeIDs: [plain.id, lean.id], days: nil, suggestedPairs: nil)
        store.replaceCatalogForTesting(recipes: [plain, lean], courses: [course])
        store.state.activeCourseIDs = [course.id]
        for index in store.state.slots.indices where store.state.slots[index].day == 0 {
            store.state.slots[index].recipeID = Recipe.unplanned.id
            store.state.slots[index].memberIDs = [member.id]
            store.state.slots[index].recipeChosenManually = nil
            store.state.slots[index].extraRecipeIDs = []
        }
        store.state.autoDayMenuStamp = nil
        store.fillTodayMenu()
        XCTAssertEqual(store.slot(0, 2).recipeID, lean.id)
        XCTAssertEqual(store.slot(0, 2).recipeChosenManually, false)
        XCTAssertTrue([plain.id, lean.id].contains(store.slot(1, 2).recipeID))
        XCTAssertEqual(store.slot(1, 2).recipeChosenManually, false)
        XCTAssertNil(store.assign(plain, to: store.slot(0, 2)))
        store.state.autoDayMenuStamp = "stale"
        store.state.members[0].weightKg = 72
        store.fillTodayMenu()
        XCTAssertEqual(store.slot(0, 2).recipeID, plain.id)
        XCTAssertEqual(store.slot(0, 2).recipeChosenManually, true)
    }

    @MainActor func testRegenerationPreservesSnackOptInAndCannotSwapItWithLunch() throws {
        let store = LadStore(); store.state = .initial()
        XCTAssertNil(store.setPreLunchSnack(true, on: 1, memberID: store.currentMember.id))
        let snack = try XCTUnwrap(store.preLunchSnack(on: 1))
        let lunch = try XCTUnwrap(Recipe.launchRecipes.first { $0.mealKinds == [1] })
        XCTAssertNotNil(store.assign(lunch, to: snack))
        store.proposeDayMenu(1)
        let preview = try XCTUnwrap(store.replanPreview)
        XCTAssertTrue(preview.changes.contains { $0.slotID == snack.id })
        store.applyReplan(preview)
        XCTAssertEqual(store.recipe(try XCTUnwrap(store.preLunchSnack(on: 1))).mealKinds, [3])
        XCTAssertEqual(store.state.slots.filter { $0.kind == 3 }.count, 1)
        var duplicate = store.state
        duplicate.slots.append(snack)
        XCTAssertFalse(duplicate.hasValidMealSlots)
    }
}
