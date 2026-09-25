import XCTest
import UIKit
import SwiftUI
@testable import Lad

final class PlanningCoreTests: XCTestCase {
    func testCourseCatalogueDecodesOneRevisionAndRejectsMissingDishes() throws {
        let recipe: [String: Any] = [
            "id": "course-dish", "title": "Тестовое блюдо", "caption": "Тест", "cuisine": "Домашняя",
            "minutes": 20, "allergens": [], "allergensVerified": true,
            "ingredients": [["name": "Томаты", "alternatives": ["Помидоры"], "amount": 100, "unit": "г", "category": "Овощи"]],
            "steps": ["Приготовить"], "stepImageIDs": ["dish-step-1"], "mealKinds": [1],
            "difficulty": "moderate"
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

    func testSelectedCoursesSurviveWeekRollover() {
        XCTAssertEqual(URL(string: CourseCatalogAccess.defaultURL)?.scheme, "https")
        XCTAssertEqual(CourseCatalogAccess.bundledCourses.count, 2)
        XCTAssertEqual(Recipe.all.count, 9)
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
        let allowed = Set(["soup", "vegetable-pasta", "lentil-stew"])
        XCTAssertTrue(preview.changes.allSatisfy { $0.slotID.hasSuffix("-0")
            ? $0.nextID == Recipe.unplanned.id : allowed.contains($0.nextID) })
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
                               days: [CourseDay(day: 1, lunchRecipeID: "tagged-breakfast", dinnerRecipeID: nil)])
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
                               recipeIDs: ["allergy-draft"], days: nil)
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
        store.toggleCourse("mediterranean-ideas")
        let breakfast = store.slot(0, 0)
        store.proposeNotToday(breakfast)
        let withinCourse = try XCTUnwrap(store.replanPreview)
        XCTAssertTrue(withinCourse.changes.isEmpty)
        XCTAssertEqual(withinCourse.outsideCourseSlotID, breakfast.id)

        store.proposeNotToday(breakfast, includeOutsideCourses: true)
        let outsideCourse = try XCTUnwrap(store.replanPreview)
        XCTAssertFalse(outsideCourse.changes.isEmpty)
        XCTAssertNil(outsideCourse.outsideCourseSlotID)
        XCTAssertEqual(store.activeCourseIDs, ["mediterranean-ideas"])
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
        store.state.dislikes = Set(Recipe.all.filter { $0.mealKinds.contains(2) && $0.id != "lentil-stew" }
            .map { "igor|\($0.id)" })
        store.proposeNotToday(store.slot(0, 2))
        let proposed = try XCTUnwrap(store.replanPreview?.changes.first?.nextID)
        XCTAssertEqual(proposed, "lentil-stew")
    }

    func testIngredientCatalogIncludesEveryRecipeIngredientBeyondTwelveRows() {
        let privateDraft = Recipe(id: "private:test", title: "Черновик", caption: "", image: "", cuisine: "Домашняя", minutes: 10, kcal: nil, protein: nil, allergens: [], ingredients: [
            Ingredient(name: "Свёкла", amount: 100, unit: "г", category: "Овощи и зелень")
        ], steps: ["Приготовить"])
        let publicOnly = PlanningCore.ingredientSuggestions(recipes: Recipe.all, pantry: [], query: "")
        let includingPrivate = PlanningCore.ingredientSuggestions(recipes: Recipe.all + [privateDraft], pantry: [], query: "")

        XCTAssertGreaterThan(publicOnly.count, 12)
        XCTAssertEqual(includingPrivate.count, publicOnly.count + 1)
        XCTAssertTrue(includingPrivate.contains { $0.name == "Свёкла" })
    }

    func testProductSearchFindsAlternateLabelWithoutChangingDisplayName() {
        let suggestions = PlanningCore.ingredientSuggestions(recipes: Recipe.all, pantry: [], query: "помидор")
        XCTAssertEqual(suggestions.map(\.name), ["Томаты"])
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
        XCTAssertTrue(PlanningCore.ingredientSuggestions(recipes: Recipe.all, pantry: pantry, query: "помидор").isEmpty)
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

    func testDifferentUnitsAreNotSilentlyCombined() {
        let ingredient = Ingredient(name: "Лимон", amount: 0.25, unit: "шт.", category: "Овощи и зелень")
        let pantry = [PantryItem(name: "Лимон", quantity: 100, unit: "г", category: "Овощи и зелень")]

        XCTAssertEqual(PlanningCore.stock(for: ingredient, pantry: pantry).known, 0)
        XCTAssertTrue(PlanningCore.stock(for: ingredient, pantry: pantry).uncertain)
    }

    @MainActor
    func testOutOfStockOffersReplanAndCanUndoWithoutLosingManualShopping() {
        let store = LadStore()
        store.state = DemoState.initial()
        store.refreshClock(Calendar.current.date(byAdding: .hour, value: 7,
                                                  to: Calendar.current.startOfDay(for: store.state.startDate))!)
        store.state.extraShopping = ["Бумажные полотенца"]
        let potato = PantryItem(name: "Картофель", quantity: 2000, unit: "г", category: "Овощи и зелень")
        store.savePantryItem(potato)
        let original = store.slot(0, 2).recipeID

        store.markOut(potato)
        XCTAssertEqual(store.pantryItem(named: "Картофель", unit: "г")?.quantity, 0)
        XCTAssertEqual(store.slot(0, 2).recipeID, original, "Preview must not change the plan")
        XCTAssertNotNil(store.replanPreview)
        if let preview = store.replanPreview, !preview.changes.isEmpty {
            store.applyReplan(preview)
            XCTAssertNotEqual(store.slot(0, 2).recipeID, original)
            store.undoReplan()
            XCTAssertEqual(store.slot(0, 2).recipeID, original)
        }
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

    func testUnverifiedDraftNeverClaimsReadyWhileNeedsRemainVisible() throws {
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
        XCTAssertEqual(result.slots[slot.id]?.availability, .needsReview)
        XCTAssertFalse(try XCTUnwrap(result.slots[slot.id]).isReady)
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
        let recipe = Recipe(id: "test-milk", title: "Молоко", caption: "", image: "", cuisine: "", minutes: 10,
                            kcal: nil, protein: nil, allergens: [], ingredients: [
                                Ingredient(name: "Молоко", amount: 200, unit: "мл", category: "Молочные продукты")
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
        XCTAssertEqual(result.shoppingNeeds.first?.required, 4)
        XCTAssertEqual(result.shoppingNeeds.first?.sourceSlots, ["breakfast", "lunch"])
        let skipped = PlanningCore.resolvePlan(slots: slots, members: members, recipes: [recipe], pantry: [],
                                               startDate: day, now: noon, calendar: calendar,
                                               skippedIDs: ["breakfast"])
        XCTAssertEqual(skipped.slots["breakfast"]?.availability, .skipped)
        XCTAssertEqual(skipped.shoppingNeeds.first?.required, 2)
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
        XCTAssertEqual(result.shoppingNeeds.first?.required, 3)
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
