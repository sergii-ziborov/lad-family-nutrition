import XCTest
@testable import Lad

final class ReferencePricesTests: XCTestCase {
    @MainActor func testUnsetCountryUsesTheIsraelFeed() {
        let key = LadStore.referencePriceCountryKey
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(LadStore.referenceCountry(forRegion: "IL"), "IL")
        XCTAssertEqual(LadStore.referenceCountry(forRegion: "UA"), "UA")
        XCTAssertEqual(LadStore.referenceCountry(forRegion: "US"), "US")
        XCTAssertEqual(LadStore.referenceCountry(forRegion: nil), "IL")
        XCTAssertEqual(LadStore.storedPriceCountrySource(), "system")
        let phone = LadStore.referenceCountry(forRegion: Locale.current.region?.identifier)
        XCTAssertEqual(LadStore.storedReferencePriceCountry(), phone)
        let store = LadStore()
        store.state = .initial()
        XCTAssertEqual(store.referencePriceCountrySource, "system")
        XCTAssertEqual(store.referencePriceCountry, phone)
        let feed = store.referencePriceCatalog.records(country: phone)
        XCTAssertGreaterThan(feed.count, 8)
        XCTAssertEqual(store.ingredientPrices.filter { $0.reference?.method == "statistical-category-average" && $0.reference?.country == phone }.count, feed.count)
        if phone == "IL" {
            XCTAssertGreaterThan(store.ingredientPrices.filter { $0.reference?.method == ShelfPrices.method }.count, 20)
        }
        store.setReferencePriceCountry("")
        XCTAssertEqual(store.referencePriceCountrySource, "personal")
        XCTAssertEqual(store.referencePriceCountry, "")
        XCTAssertEqual(LadStore.storedReferencePriceCountry(), "")
        XCTAssertTrue(store.ingredientPrices.allSatisfy { $0.reference == nil })
        store.setReferencePriceCountry("UA")
        XCTAssertEqual(store.referencePriceCountry, "UA")
        XCTAssertGreaterThan(store.ingredientPrices.filter { $0.reference?.country == "UA" }.count, 8)
    }

    func testCountryPickerTagIsNeverEmpty() {
        XCTAssertEqual(ReferencePriceCountry.personal.pickerTag, "personal")
        XCTAssertEqual(ReferencePriceCountry.personal.id, "personal")
        XCTAssertEqual(ReferencePriceCountry.storedCountry(for: "personal"), "")
        XCTAssertEqual(ReferencePriceCountry.israel.pickerTag, "IL")
        XCTAssertEqual(ReferencePriceCountry.storedCountry(for: "IL"), "IL")
        for country in ReferencePriceCountry.allCases {
            XCTAssertFalse(country.id.isEmpty)
            XCTAssertEqual(country.id, country.pickerTag)
        }
    }

    func testBundledPricesHaveThreeCountriesAndPhysicalUnits() throws {
        let catalog = ReferencePriceCatalog.bundled
        XCTAssertEqual(Set(catalog.prices.map { $0.reference.country }), Set(["IL", "UA", "US"]))
        XCTAssertTrue(catalog.prices.allSatisfy(\.isValid))
        XCTAssertTrue(catalog.prices.allSatisfy { $0.reference.period <= String(catalog.retrievedAt.prefix(7)) })
        for country in ["IL", "UA", "US"] { XCTAssertGreaterThan(catalog.records(country: country).count, 8) }
        let eggs = try XCTUnwrap(catalog.records(country: "US").first { $0.productName == "Яйцо" })
        XCTAssertEqual(eggs.packageUnit, "шт.")
        XCTAssertEqual(eggs.packageQuantity, 12)
        let milk = try XCTUnwrap(catalog.records(country: "US").first { $0.productName == "Молоко" })
        XCTAssertEqual(milk.packageUnit, "мл")
        XCTAssertEqual(milk.packageQuantity, 3785.411784, accuracy: 0.000001)
    }

    func testPersonalPriceOverridesAReferenceEvenWhenItIsOlder() throws {
        let catalog = ReferencePriceCatalog.bundled
        let own = IngredientPrice(productName: "Молоко", packagePrice: 2, packageQuantity: 1000,
                                  packageUnit: "мл", currency: "USD", updatedAt: Date(timeIntervalSince1970: 1))
        let effective = catalog.effectivePrices(personal: [own], country: "US")
        let chosen = try XCTUnwrap(FoodCost.price(for: "Молоко", prices: effective))
        XCTAssertEqual(chosen.packagePrice, 2)
        XCTAssertNil(chosen.reference)
        XCTAssertTrue(effective.allSatisfy { $0.currency == "USD" })
        XCTAssertEqual(catalog.effectivePrices(personal: [own], country: "").count, 1)
    }

    func testReferenceCostsUseNativePackUnitsAndAreAlwaysApproximate() throws {
        let catalog = ReferencePriceCatalog.bundled
        let prices = catalog.effectivePrices(personal: [], country: "US")
        let milk = try XCTUnwrap(FoodCost.price(for: "Молоко", prices: prices))
        let cost = try XCTUnwrap(FoodCost.ingredient(Ingredient(name: "Молоко", amount: 250, unit: "мл", category: ""), prices: prices))
        XCTAssertEqual(cost.amount, milk.packagePrice * 250 / 3785.411784, accuracy: 0.000001)
        XCTAssertTrue(cost.approximate)
        let eggs = try XCTUnwrap(FoodCost.price(for: "Яйцо", prices: prices))
        let eggCost = try XCTUnwrap(FoodCost.ingredient(Ingredient(name: "Яйцо", amount: 100, unit: "г", category: ""), prices: prices))
        XCTAssertEqual(eggCost.amount, eggs.packagePrice / 6, accuracy: 0.000001)
        XCTAssertNil(FoodCost.price(for: "Неизвестный продукт", prices: prices))
    }

    func testDeletedPersonalPriceFallsBackWithoutResurrectingTheOldRecord() throws {
        let catalog = ReferencePriceCatalog.bundled
        var old = IngredientPrice(productName: "Молоко", packagePrice: 2, packageQuantity: 1000, packageUnit: "мл", currency: "USD")
        var deleted = old
        deleted.updatedAt = old.updatedAt.addingTimeInterval(5)
        deleted.deletedAt = deleted.updatedAt
        old.packagePrice = 99
        let effective = catalog.effectivePrices(personal: [old, deleted], country: "US")
        let result = try XCTUnwrap(FoodCost.price(for: "Молоко", prices: effective))
        XCTAssertNotNil(result.reference)
        XCTAssertNotEqual(result.packagePrice, 99)
    }

    func testPersonalPriceFormatRemainsBackwardCompatible() throws {
        let price = IngredientPrice(productName: "Яблоко", packagePrice: 4, packageQuantity: 1, packageUnit: "кг", currency: "UAH")
        let data = try JSONEncoder().encode(price)
        let decoded = try JSONDecoder().decode(IngredientPrice.self, from: data)
        XCTAssertNil(decoded.reference)
        XCTAssertEqual(decoded.packagePrice, 4)
    }

    func testUnknownCurrencyOrSourceIsRejectedWithoutReplacingTheCatalog() throws {
        let data = try JSONEncoder().encode(ReferencePriceCatalog.bundled)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var records = try XCTUnwrap(json["prices"] as? [[String: Any]])
        records[0]["currency"] = "USD"
        json["prices"] = records
        XCTAssertThrowsError(try ReferencePriceCatalog.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testShelfPacksFillIsraelGapsWithoutReplacingOfficialOrPersonalPrices() throws {
        let catalog = ReferencePriceCatalog.bundled
        XCTAssertTrue(catalog.prices.allSatisfy { $0.reference.method == "statistical-category-average" })
        let israel = catalog.effectivePrices(personal: [], country: "IL")
        XCTAssertTrue(israel.allSatisfy { $0.currency == "ILS" })
        XCTAssertEqual(FoodCost.price(for: "Яблоко", prices: israel)?.reference?.method, "statistical-category-average")
        XCTAssertEqual(FoodCost.price(for: "Гречка", prices: israel)?.reference?.method, ShelfPrices.method)
        XCTAssertNil(FoodCost.price(for: "Гречка", prices: catalog.effectivePrices(personal: [], country: "US"))?.reference)
        let yogurt = try XCTUnwrap(FoodCost.ingredient(
            Ingredient(name: "Йогурт греческий", amount: 594, unit: "г", category: ""), prices: israel))
        let yogurtPack = try XCTUnwrap(FoodCost.price(for: "Йогурт натуральный", prices: israel))
        XCTAssertEqual(yogurt.amount, yogurtPack.packagePrice * 594 / yogurtPack.packageQuantity, accuracy: 0.001)
        XCTAssertTrue(yogurt.approximate)
        let cream = try XCTUnwrap(FoodCost.ingredient(
            Ingredient(name: "Сметана", amount: 20, unit: "г", category: ""), prices: israel))
        XCTAssertGreaterThan(cream.amount, 0)
        let own = IngredientPrice(productName: "Гречка", packagePrice: 3, packageQuantity: 1000,
                                  packageUnit: "г", currency: "ILS", updatedAt: Date(timeIntervalSince1970: 1))
        let overridden = catalog.effectivePrices(personal: [own], country: "IL")
        XCTAssertEqual(FoodCost.price(for: "Гречка", prices: overridden)?.packagePrice, 3)
        XCTAssertNil(FoodCost.price(for: "Гречка", prices: overridden)?.reference)
        var deleted = own
        deleted.updatedAt = own.updatedAt.addingTimeInterval(5)
        deleted.deletedAt = deleted.updatedAt
        let restored = catalog.effectivePrices(personal: [deleted], country: "IL")
        XCTAssertEqual(FoodCost.price(for: "Гречка", prices: restored)?.reference?.method, ShelfPrices.method)
        XCTAssertTrue(catalog.effectivePrices(personal: [own], country: "").allSatisfy { $0.reference == nil })
        // Chain files sell these, but not as a weighed food pack: green onion is a bunch,
        // duck is a whole bird, and pollock, lovage and dried marjoram have no food row.
        // A gram price for them would be an invented weight.
        let unpackaged: Set<String> = ["Зелёный лук", "Любисток", "Майоран", "Минтай", "Утка"]
        var missing: Set<String> = []
        for recipe in Recipe.launchRecipes {
            for ingredient in recipe.ingredients where (ingredient.amount ?? 0) > 0 {
                guard let cost = FoodCost.ingredient(ingredient, prices: israel) else {
                    missing.insert(ingredient.name)
                    continue
                }
                XCTAssertEqual(cost.currency, "ILS", ingredient.name)
            }
        }
        XCTAssertEqual(missing, unpackaged)
    }

    func testChainFileUpdatesAKnownPackAndLeavesTheStatisticalPriceAlone() throws {
        let payload = """
        {"day":"20261121","currency":"ILS","method":"retail-shelf-median","source":"Shufersal PriceFull","items":[
          {"barcode":"7290100703458","name":"כוסמת 500 גרם","price":8.4,"quantity":1,"unit":"קילוגרם","stores":175,"currency":"ILS"},
          {"barcode":"00000000","name":"זר","price":3,"quantity":1,"unit":"יחידה","stores":4}
        ]}
        """.data(using: .utf8)!
        let snapshot = try ShelfFileSync.decode(payload)
        XCTAssertEqual(snapshot.day, "20261121")
        XCTAssertEqual(snapshot.quotes.count, 2)
        let shelf = ShelfPrices.applying(snapshot.quotes)
        XCTAssertEqual(shelf.count, ShelfPrices.records(country: "IL").count)
        let buckwheat = try XCTUnwrap(shelf.first { $0.productName == "Гречка" })
        XCTAssertEqual(buckwheat.packagePrice, 8.4)
        XCTAssertEqual(buckwheat.packageQuantity, 1000)
        XCTAssertEqual(buckwheat.packageUnit, "г")
        XCTAssertEqual(buckwheat.reference?.method, ShelfPrices.method)
        XCTAssertEqual(buckwheat.reference?.publisher, "Shufersal")
        XCTAssertEqual(buckwheat.reference?.sourceLabel, "כוסמת 500 גרם")
        let prices = ReferencePriceCatalog.bundled.effectivePrices(personal: [], country: "IL", shelf: shelf)
        XCTAssertEqual(FoodCost.price(for: "Яблоко", prices: prices)?.reference?.method, "statistical-category-average")
        XCTAssertEqual(FoodCost.price(for: "Гречка", prices: prices)?.packagePrice, 8.4)
        let unpackaged: Set<String> = ["Зелёный лук", "Любисток", "Майоран", "Минтай", "Утка"]
        XCTAssertTrue(unpackaged.allSatisfy { FoodCost.price(for: $0, prices: prices) == nil })
        let wrongUnit = ShelfFileQuote(barcode: "7290100703458", price: 3, quantity: 1, unit: "יחידה", name: "יחידה", stores: 2, day: "20261121")
        let unchanged = try XCTUnwrap(ShelfPrices.applying([wrongUnit]).first { $0.productName == "Гречка" })
        XCTAssertEqual(unchanged.packagePrice, 7.9)
        let statistical = """
        {"day":"20261121","currency":"ILS","method":"statistical-category-average","items":[{"barcode":"7290100703458","name":"x","price":1,"quantity":1,"unit":"גרם","stores":1}]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try ShelfFileSync.decode(statistical))
    }
}
