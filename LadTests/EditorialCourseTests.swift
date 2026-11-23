import XCTest
@testable import Lad

final class EditorialCourseTests: XCTestCase {
    private struct Baseline: Decodable {
        let ingredients: [Ingredient]
        let estimatedServings: Double?
        let mealKinds: [Int]
        let kcal: Int?
        let protein: Int?
        let nutrientPreparations: [String: String]?
        let nutritionEdibleYield: [String: Double]?
    }
    private struct Fixture: Decodable {
        let recipes: [PrivateRecipePayload]
        let baselineFacts: [String: Baseline]
        let course: LadCourse
        let previousMainPairs: [[String]]
        let replacedBodyIDs: [String]
    }
    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
            .appendingPathComponent("Fixtures/EditorialCourseFixture.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("The owner-only complete course is not distributed with public source.")
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testEditorialCourseRetainsAllFoodAmountsPortionsAndNutritionInputs() throws {
        let data = try fixture()
        XCTAssertEqual(data.recipes.count, 150)
        XCTAssertEqual(Set(data.recipes.map(\.id)), Set(data.baselineFacts.keys))
        XCTAssertEqual(data.replacedBodyIDs.count, 106)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for payload in data.recipes {
            let old = try XCTUnwrap(data.baselineFacts[payload.id])
            XCTAssertEqual(try encoder.encode(payload.ingredients), try encoder.encode(old.ingredients), payload.id)
            XCTAssertEqual(payload.estimatedServings, old.estimatedServings, payload.id)
            XCTAssertEqual(payload.mealKinds, old.mealKinds, payload.id)
            XCTAssertEqual(payload.kcal, old.kcal, payload.id)
            XCTAssertEqual(payload.protein, old.protein, payload.id)
            XCTAssertEqual(payload.nutrientPreparations, old.nutrientPreparations, payload.id)
            XCTAssertEqual(payload.nutritionEdibleYield, old.nutritionEdibleYield, payload.id)
            let recipe = try XCTUnwrap(payload.recipe(privateAccess: false), payload.id)
            XCTAssertTrue(recipe.isPlanEligible, payload.id)
            if let images = payload.stepImageIDs {
                XCTAssertEqual(images.count, payload.steps.count, payload.id)
            }
        }
    }

    func testFullCourseCookingTextIsLocalizedAndNewExamplesKeepMealRoles() throws {
        let data = try fixture()
        let original = UserDefaults.standard.string(forKey: L10n.languageKey)
        defer { UserDefaults.standard.set(original, forKey: L10n.languageKey) }
        let oldPairs = Set(data.previousMainPairs.map { $0.joined(separator: "|") })
        let byID = Dictionary(uniqueKeysWithValues: data.recipes.map { ($0.id, $0) })
        XCTAssertEqual(data.course.suggestedPairs?.count, 56)
        for pair in data.course.suggestedPairs ?? [] {
            let lunch = try XCTUnwrap(byID[pair.lunchRecipeID])
            let dinnerID = try XCTUnwrap(pair.dinnerRecipeID)
            XCTAssertFalse(oldPairs.contains(pair.lunchRecipeID + "|" + dinnerID))
            XCTAssertEqual(lunch.mealKinds, [1])
            XCTAssertNotEqual(lunch.courseRole, "side")
            XCTAssertEqual(byID[dinnerID]?.mealKinds, [2])
            for side in pair.lunchExtraRecipeIDs ?? [] { XCTAssertEqual(byID[side]?.mealKinds, [1]) }
        }
        for language in ["en", "uk"] {
            UserDefaults.standard.set(language, forKey: L10n.languageKey)
            let folder = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let stringsURL = URL(fileURLWithPath: folder).appendingPathComponent("Localizable.strings")
            let table = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: stringsURL),
                                            options: [], format: nil) as? [String: String])
            for payload in data.recipes {
                for text in [payload.title, payload.caption] + payload.steps {
                    let localized = L10n.text(text)
                    XCTAssertFalse(localized.isEmpty, payload.id)
                    XCTAssertEqual(localized, try XCTUnwrap(table[text], "\(language): \(payload.id): \(text)"))
                    if language == "en" {
                        XCTAssertNil(localized.range(of: "[А-Яа-яЁёІіЇїЄєҐґ]", options: .regularExpression), payload.id)
                    }
                }
            }
        }
    }
}
