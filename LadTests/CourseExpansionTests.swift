import XCTest
@testable import Lad

final class CourseExpansionTests: XCTestCase {
    private struct Fixture: Decodable {
        let recipes: [PrivateRecipePayload]
        let baseRecipeIDs: [String: String]
    }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
            .appendingPathComponent("Fixtures/ExpandedCourseFixture.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Owner-only paid recipe fixture is not included in public source distribution.")
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testNewVariantsHaveUniqueIngredientsAndKeepTheirMealRoles() throws {
        let data = try fixture()
        XCTAssertEqual(data.recipes.count, 29)
        XCTAssertEqual(Set(data.recipes.map(\.id)).count, 29)
        XCTAssertEqual(data.recipes.filter { $0.mealKinds == [0] }.count, 9)
        XCTAssertEqual(data.recipes.filter { $0.mealKinds == [1] }.count, 10)
        XCTAssertEqual(data.recipes.filter { $0.mealKinds == [2] }.count, 10)
        var fingerprints = Set<String>()
        for payload in data.recipes {
            XCTAssertNotNil(data.baseRecipeIDs[payload.id], payload.id)
            let fingerprint = payload.ingredients.map { "\(ProductNames.canonical($0.name)):\($0.amount ?? 0)" }.sorted().joined(separator: "|")
            XCTAssertTrue(fingerprints.insert(fingerprint).inserted, payload.id)
            XCTAssertEqual(payload.mealKinds, [payload.id.hasPrefix("bf-") ? 0 : payload.id.hasPrefix("lunch-") ? 1 : 2], payload.id)
            XCTAssertTrue(payload.ingredients.allSatisfy { ($0.amount ?? 0) > 0 && ["г", "мл"].contains($0.unit) }, payload.id)
        }
    }

    func testNewVariantsHaveUsableEnergyProteinAndAllergenInformation() throws {
        for payload in try fixture().recipes {
            let recipe = try XCTUnwrap(payload.recipe(privateAccess: false), payload.id)
            XCTAssertTrue(recipe.isPlanEligible, recipe.id)
            XCTAssertTrue(try XCTUnwrap(recipe.energyEstimate).unresolvedNames.isEmpty, recipe.id)
            let energy = try XCTUnwrap(recipe.kcal)
            XCTAssertTrue((150...800).contains(energy), "\(recipe.id): \(energy)")
            if recipe.mealKinds == [0] {
                XCTAssertGreaterThanOrEqual(energy, 300, recipe.id)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(recipe.nutrients["protein"]).amount, 15, recipe.id)
            }
            XCTAssertEqual(Set(payload.nutrientPreparations?.keys.map { $0 } ?? []), Set(recipe.ingredients.map(\.name)), recipe.id)
            for allergen in IngredientAllergens.inferred(from: recipe.ingredients) {
                XCTAssertTrue(AllergenMatching.conflicts(selected: [allergen], recipe: payload.allergens), "\(recipe.id): \(allergen)")
            }
            XCTAssertEqual(recipe.baseServings, 1)
        }
    }
}
