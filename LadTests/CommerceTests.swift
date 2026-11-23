import XCTest
import StoreKitTest
import StoreKit
import Combine
@testable import Lad

final class CommerceTests: XCTestCase {
    @MainActor
    func testDisabledBetaAdsHaveAValidSDKIdentifierWithoutAnAdUnit() throws {
        let appID = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String)
        XCTAssertNotNil(appID.range(of: "^ca-app-pub-[0-9]+~[0-9]+$", options: .regularExpression))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "GADDelayAppMeasurementInit") as? Bool, true)
        if ReleasePolicy.isStoreRelease && appID.contains("3940256099942544") {
            XCTAssertNil(AdvertisingService.shared.bannerID)
            XCTAssertFalse(AdvertisingService.shared.canShowBanner)
        }
    }

    @MainActor
    func testReleaseCatalogCannotUnlockPaidRecipesFromLegacyBundle() throws {
        guard ReleasePolicy.isStoreRelease else { throw XCTSkip("Run this packaging regression with the Release configuration") }
        XCTAssertNil(Bundle.main.url(forResource: "legacy-recipes", withExtension: "json"))
        XCTAssertEqual(Recipe.all.count, 163)
        XCTAssertEqual(Set(Recipe.all.map(\.id)), Set(Recipe.launchRecipes.map(\.id)))
        let store = LadStore()
        store.returnToFreeCatalog()
        let courseDish = "photo3_kefir_chicken_fillet"
        XCTAssertTrue(store.allRecipes.contains { $0.id == courseDish })
        XCTAssertNotNil(Recipe.all.first { $0.id == "salmon" })
        let historyID = "photo_cottage_bake"
        XCTAssertNil(Recipe.all.first { $0.id == historyID })
        store.state.slots[0].recipeID = historyID
        store.returnToFreeCatalog()
        XCTAssertEqual(store.state.slots[0].recipeID, historyID, "Access changes must preserve personal history identifiers")
        XCTAssertTrue(store.recipe(store.state.slots[0]).isUnavailable)
        store.state.slots[0].recipeID = courseDish
        XCTAssertFalse(store.recipe(store.state.slots[0]).isUnavailable)
    }

    func testSandboxAndProductionUseSeparateCatalogs() {
        let base = "https://catalog.example"
        XCTAssertEqual(StoreCatalogRouting.baseURL(base, environment: .production), base)
        XCTAssertEqual(StoreCatalogRouting.baseURL(base, environment: .sandbox), base + "/sandbox")
        XCTAssertNil(StoreCatalogRouting.environmentName(.xcode))
        XCTAssertNil(StoreCatalogRouting.environmentName(nil))
        XCTAssertEqual(StoreCatalogRouting.environmentName(.sandbox), "Sandbox")
        XCTAssertEqual(StoreCatalogRouting.environmentName(.production), "Production")
    }

    @MainActor
    func testVerifiedPurchaseDisablesAdsAndRefundRevokesAccess() async throws {
        let session = try SKTestSession(configurationFileNamed: "Lad")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let purchases = AppPurchases.shared
        await purchases.start()
        XCTAssertFalse(purchases.hasFullCourse)
        XCTAssertTrue(purchases.shouldShowAds)
        let unlocked = expectation(description: "Verified purchase updates access")
        let unlockObservation = purchases.$hasFullCourse.filter { $0 }.prefix(1).sink { _ in unlocked.fulfill() }
        let purchased = try await session.buyProduct(identifier: AppPurchases.productID)
        XCTAssertEqual(purchased.productID, AppPurchases.productID)
        await fulfillment(of: [unlocked], timeout: 5)
        _ = unlockObservation
        XCTAssertTrue(purchases.hasFullCourse)
        XCTAssertNotNil(purchases.catalogProof)
        XCTAssertFalse(purchases.shouldShowAds)
        await purchased.finish()
        let restored = AppPurchases()
        await restored.refreshEntitlements()
        XCTAssertTrue(restored.hasFullCourse, "Verified ownership must survive a new store instance")
        let revoked = expectation(description: "Refund removes access")
        let revokeObservation = purchases.$hasFullCourse.filter { !$0 }.prefix(1).sink { _ in revoked.fulfill() }
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        await fulfillment(of: [revoked], timeout: 5)
        _ = revokeObservation
        XCTAssertFalse(purchases.hasFullCourse)
        XCTAssertTrue(purchases.catalogProof == nil)
        XCTAssertTrue(purchases.shouldShowAds)
    }
}
