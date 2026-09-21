import XCTest
import UIKit
@testable import Lad

final class PlanningCoreTests: XCTestCase {
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

        let needs = PlanningCore.shoppingNeeds(slots: slots, members: members, recipes: [recipe], pantry: pantry)
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
    }

    @MainActor
    func testOutOfStockOffersReplanAndCanUndoWithoutLosingManualShopping() {
        let store = LadStore()
        store.state = DemoState.initial()
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
        let recipe = try XCTUnwrap(draft.recipe())

        XCTAssertNil(recipe.kcal)
        XCTAssertNil(recipe.protein)
        XCTAssertTrue(recipe.isPrivate)
        XCTAssertFalse(recipe.allergensVerified)
        XCTAssertEqual(recipe.image, "draft")
    }
}
