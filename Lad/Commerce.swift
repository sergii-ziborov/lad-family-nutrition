import Foundation
import StoreKit
import SwiftUI

@MainActor final class AppPurchases: ObservableObject {
    static let shared = AppPurchases()
    nonisolated static let productID = "app.lad.complete"
    @Published private(set) var product: Product?
    @Published private(set) var hasFullCourse = false
    @Published private(set) var checkedEntitlements = false
    @Published private(set) var catalogProof: String?
    @Published private(set) var commerceReady = false
    @Published private(set) var storeEnvironment: AppStore.Environment?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    private var updates: Task<Void, Never>?
    private var entitlementRevision = 0

    var shouldShowAds: Bool { checkedEntitlements && !hasFullCourse }

    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in StoreKit.Transaction.updates {
                    guard let self else { return }
                    if self.applyVerified(result), case .verified(let transaction) = result { await transaction.finish() }
                }
            }
        }
        await refreshEntitlements()
        do { product = try await Product.products(for: [Self.productID]).first }
        catch { message = L10n.text("Не удалось загрузить покупку. Попробуйте позже.") }
        await refreshPurchaseAvailability()
    }

    var catalogBaseURL: String? {
        CourseCatalogAccess.savedURL.map { StoreCatalogRouting.baseURL($0, environment: storeEnvironment) }
    }

    func refreshPurchaseAvailability() async {
        commerceReady = await LaunchCatalogAccess.purchaseAvailable()
    }

    func refreshEntitlements() async {
        let revision = entitlementRevision
        var proof: String?
        var environment: AppStore.Environment?
        if let result = try? await AppTransaction.shared, case .verified(let app) = result {
            environment = app.environment
        }
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > .now }) ?? true else { continue }
            proof = result.jwsRepresentation
            environment = transaction.environment
        }
        guard revision == entitlementRevision else { return }
        entitlementRevision += 1
        if storeEnvironment != environment { commerceReady = false }
        storeEnvironment = environment
        catalogProof = proof
        hasFullCourse = proof != nil
        checkedEntitlements = true
    }

    private func applyVerified(_ result: VerificationResult<StoreKit.Transaction>) -> Bool {
        guard case .verified(let transaction) = result, transaction.productID == Self.productID else { return false }
        entitlementRevision += 1
        let active = transaction.revocationDate == nil && (transaction.expirationDate.map { $0 > .now } ?? true)
        if storeEnvironment != transaction.environment { commerceReady = false }
        storeEnvironment = transaction.environment
        catalogProof = active ? result.jwsRepresentation : nil
        hasFullCourse = active
        checkedEntitlements = true
        return true
    }

    func purchase() async {
        guard !isBusy, let product, commerceReady else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = L10n.text("Не удалось проверить покупку. Доступ не изменён.")
                    return
                }
                _ = applyVerified(result)
                await transaction.finish()
            case .pending: message = L10n.text("Покупка ожидает подтверждения.")
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = L10n.text("Покупка не завершена. Попробуйте ещё раз.") }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            await refreshPurchaseAvailability()
            if !hasFullCourse { message = L10n.text("Покупка полного курса не найдена для этого Apple Account.") }
        } catch { message = L10n.text("Не удалось восстановить покупки. Попробуйте позже.") }
    }
}

enum StoreCatalogRouting {
    static func baseURL(_ base: String, environment: AppStore.Environment?) -> String {
        environment == .sandbox ? base + "/sandbox" : base
    }

    static func environmentName(_ environment: AppStore.Environment?) -> String? {
        if environment == .production { return "Production" }
        if environment == .sandbox { return "Sandbox" }
        return nil
    }
}

enum LaunchCatalogAccess {
    private struct Status: Decodable {
        let purchaseReady: Bool
        let productID: String
        let storeEnvironment: String?
    }
    static func purchaseAvailable() async -> Bool {
        let environment = await AppPurchases.shared.storeEnvironment
        guard let expected = StoreCatalogRouting.environmentName(environment),
              let base = await AppPurchases.shared.catalogBaseURL,
              let url = URL(string: base + "/v3/status") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let status = try JSONDecoder().decode(Status.self, from: data)
            let currentBase = await AppPurchases.shared.catalogBaseURL
            let currentEnvironment = await AppPurchases.shared.storeEnvironment
            return base == currentBase && environment == currentEnvironment &&
                status.purchaseReady && status.productID == AppPurchases.productID && status.storeEnvironment == expected
        } catch { return false }
    }

    static func fetch() async throws -> CourseCatalogue {
        let proof = await AppPurchases.shared.catalogProof
        // The shipped course is already the full menu. An anonymous server
        // response is the old 50-dish preview and must not replace it.
        if proof == nil,
           let course = CourseCatalogAccess.bundledCourses.first(where: \.isCombinedDefaultMenu),
           let total = course.totalRecipeCount,
           course.recipeIDs.count == total,
           Recipe.launchRecipes.count == course.recipeIDs.count,
           Set(course.recipeIDs) == Set(Recipe.launchRecipes.map(\.id)) {
            return CourseCatalogue(revision: "bundled-launch", courses: CourseCatalogAccess.bundledCourses,
                                   recipes: Recipe.launchRecipes)
        }
        guard let base = await AppPurchases.shared.catalogBaseURL, let url = URL(string: base + "/v3/catalog") else {
            throw PrivateCatalogError.invalidURL
        }
        let environment = await AppPurchases.shared.storeEnvironment
        if proof != nil && StoreCatalogRouting.environmentName(environment) == nil {
            throw PrivateCatalogError.unauthorized
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if let proof { request.setValue(proof, forHTTPHeaderField: "X-Lad-Transaction") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard base == (await AppPurchases.shared.catalogBaseURL), proof == (await AppPurchases.shared.catalogProof) else {
            throw PrivateCatalogError.configurationChanged
        }
        guard let response = response as? HTTPURLResponse else { throw PrivateCatalogError.invalidResponse }
        if response.statusCode == 404 || response.statusCode == 503, proof == nil {
            return CourseCatalogue(revision: "bundled-launch", courses: CourseCatalogAccess.bundledCourses,
                                   recipes: Recipe.launchRecipes)
        }
        guard response.statusCode == 200, data.count < 2_000_000 else { throw PrivateCatalogError.serverError }
        let result = try CourseCatalogAccess.decodePages([data])
        guard result.courses.count == 1, let course = result.courses.first, course.isCombinedDefaultMenu,
              course.recipeIDs.count == (proof == nil ? 50 : course.totalRecipeCount ?? 0),
              result.recipes.count == course.recipeIDs.count,
              Set(course.breakfastRecipeIDs ?? []).isSubset(of: Set(course.recipeIDs)) else {
            throw PrivateCatalogError.invalidResponse
        }
        return result
    }
}

struct CompleteCourseOffer: View {
    @ObservedObject private var purchases = AppPurchases.shared
    @EnvironmentObject var store: LadStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Полный курс без рекламы", systemImage: purchases.hasFullCourse ? "checkmark.seal.fill" : "fork.knife")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
            Text(offerDetail)
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            if purchases.hasFullCourse {
                Label("Покупка подтверждена", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.sage)
                Button("Загрузить полный курс") { Task { await store.refreshCourseCatalog() } }
            } else if let product = purchases.product, purchases.commerceReady {
                Button { Task { await purchases.purchase() } } label: {
                    Text(L10n.format("Открыть полный курс за %@", product.displayPrice))
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(13)
                        .foregroundStyle(.white).background(Palette.sage, in: RoundedRectangle(cornerRadius: 13))
                }.disabled(purchases.isBusy)
            } else {
                Text("Покупка пока недоступна.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            if purchases.isBusy { ProgressView() }
            if let message = purchases.message { Text(message).font(.system(size: 12)).foregroundStyle(Palette.terracotta) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paleSage, in: RoundedRectangle(cornerRadius: 18))
    }

    private var offerDetail: String {
        if let course = store.courses.first(where: \.isCombinedDefaultMenu),
           let total = course.totalRecipeCount, course.recipeIDs.count >= total {
            return L10n.text("Полный курс уже в приложении.")
        }
        return L10n.text("50 блюд бесплатно. Полный курс без рекламы — разовая покупка.")
    }
}
