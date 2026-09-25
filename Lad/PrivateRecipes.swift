import Foundation
import Security
import SwiftUI

private struct PrivateCatalogResponse: Codable {
    let recipes: [PrivateRecipePayload]
}

private struct FamilyCloudResponse: Decodable {
    let members: [FamilyMember]
}

struct PrivateRecipePayload: Codable {
    let id: String
    let title: String
    let caption: String
    let cuisine: String
    let minutes: Int
    let kcal: Int?
    let protein: Int?
    let allergens: [String]
    let ingredients: [Ingredient]
    let unquantifiedIngredients: [Ingredient]?
    let steps: [String]
    let allergensVerified: Bool
    let mealKinds: [Int]?
    let nutrients: [String: NutrientValue]?
    let imageId: String?
    let imageSource: String?
    let stepImageIDs: [String?]?
    let difficulty: CookingDifficulty?
    let estimatedServings: Double?

    func recipe(privateAccess: Bool = true, remoteImage: Bool? = nil) -> Recipe? {
        guard id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              !title.isEmpty, minutes > 0, steps.count > 0 else { return nil }
        guard (kcal.map { $0 >= 0 } ?? true), (protein.map { $0 >= 0 } ?? true),
              !steps.isEmpty, steps.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              mealKinds?.allSatisfy({ (0...2).contains($0) }) ?? true,
              imageId.map({ $0.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil }) ?? true,
              stepImageIDs.map({ $0.count == steps.count && $0.allSatisfy { $0 == nil || $0?.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil } }) ?? true,
              ingredients.allSatisfy({ ingredient in
                  !ingredient.name.isEmpty && (ingredient.amount.map { $0.isFinite && $0 >= 0 } ?? true) &&
                  (ingredient.amountMax.map { maximum in maximum.isFinite && maximum >= (ingredient.amount ?? 0) } ?? true) &&
                  !ingredient.unit.isEmpty
              }),
              unquantifiedIngredients?.allSatisfy({ !$0.name.isEmpty && $0.amount == nil && !$0.unit.isEmpty }) ?? true,
              nutrients?.values.allSatisfy({ $0.amount.isFinite && $0.amount >= 0 && $0.coverage.isFinite && (0...1).contains($0.coverage) && !$0.unit.isEmpty && !$0.source.isEmpty }) ?? true else { return nil }
        guard estimatedServings.map({ $0.isFinite && (1...12).contains($0) }) ?? true else { return nil }
        let completeIngredients = ingredients + (unquantifiedIngredients ?? [])
        let estimate = EnergyEstimator.evaluate(completeIngredients)
        let calculatedPublicKcal = !privateAccess && imageSource == "bundled" && estimate.unresolvedNames.isEmpty
            ? estimate.knownBatchKcal : nil
        let calculatedPrivateKcal = privateAccess && estimatedServings != nil && estimate.unresolvedNames.isEmpty
            ? Int((Double(estimate.knownBatchKcal) / estimatedServings!).rounded()) : nil
        var recipe = Recipe(id: privateAccess ? "private:\(id)" : id, title: title, caption: caption,
                            image: imageId ?? "", cuisine: cuisine, minutes: minutes,
                            kcal: calculatedPublicKcal ?? calculatedPrivateKcal ?? kcal, protein: protein, allergens: allergens,
                            ingredients: completeIngredients, steps: steps, allergensVerified: allergensVerified,
                            mealKinds: mealKinds ?? [0, 1, 2], nutrients: nutrients ?? [:],
                            remoteImage: remoteImage ?? (imageSource != "bundled"),
                            stepImageIDs: stepImageIDs ?? [], difficulty: difficulty)
        recipe.energyEstimate = estimate
        recipe.baseServings = estimatedServings ?? 1
        recipe.servingsEstimated = estimatedServings != nil
        recipe.kcalEstimated = calculatedPrivateKcal != nil
        return recipe
    }
}

enum PrivateCatalogError: LocalizedError {
    case invalidURL, emptyToken, keychainFailure(OSStatus), invalidResponse, unauthorized, serverError, configurationChanged
    var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.text("Нужен адрес HTTPS-сервера.")
        case .emptyToken: L10n.text("Введите личный ключ доступа.")
        case .keychainFailure(let status): L10n.format("Не удалось сохранить ключ на устройстве (%d).", status)
        case .invalidResponse: L10n.text("Сервер вернул неподходящий каталог.")
        case .unauthorized: L10n.text("Ключ не принят сервером.")
        case .serverError: L10n.text("Закрытый каталог сейчас недоступен.")
        case .configurationChanged: L10n.text("Подключение изменилось во время загрузки. Обновите каталог.")
        }
    }
}

enum PrivateRecipeAccess {
    private static let urlKey = "lad.privateCatalogURL"
    private(set) static var catalogGeneration = 0
    private static let service = "app.lad.family.private-catalog"
    private static let account = "access-token"
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("private-recipes-v1.json")
    }
    static var savedURL: String? { UserDefaults.standard.string(forKey: urlKey) }
    static var catalogToken: String? { isConfigured ? token() : nil }
    static var isConfigured: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--screenshots") { return false }
        #endif
        return savedURL != nil && token() != nil
    }

    #if DEBUG
    static func importPilotProvisioning() -> String? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return "Не найдена папка аккаунта." }
        let urlFile = documents.appendingPathComponent("lad-pilot-url.txt")
        let tokenFile = documents.appendingPathComponent("lad-pilot-token.txt")
        guard let url = try? String(contentsOf: urlFile, encoding: .utf8),
              let token = try? String(contentsOf: tokenFile, encoding: .utf8) else { return nil }
        do {
            try save(url: url, token: token)
            try? FileManager.default.removeItem(at: urlFile)
            try? FileManager.default.removeItem(at: tokenFile)
            return nil
        } catch {
            return "Пилотное подключение: \(error.localizedDescription)"
        }
    }
    #endif

    static func save(url: String, token: String) throws {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parsed = URL(string: normalized), parsed.scheme == "https", parsed.host != nil,
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil else { throw PrivateCatalogError.invalidURL }
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedToken.isEmpty else { throw PrivateCatalogError.emptyToken }
        let previousAccountConfigured = savedURL != nil && self.token() != nil
        let changedAccount = savedURL != normalized || self.token() != normalizedToken
        let data = Data(normalizedToken.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result = SecItemAdd(add as CFDictionary, nil)
        if result == errSecDuplicateItem {
            let updates: [String: Any] = [kSecValueData as String: data]
            let updateResult = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            guard updateResult == errSecSuccess else { throw PrivateCatalogError.keychainFailure(updateResult) }
        } else if result != errSecSuccess {
            throw PrivateCatalogError.keychainFailure(result)
        }
        if changedAccount {
            removeCached()
            if previousAccountConfigured { removeCachedImages() }
            catalogGeneration += 1
        }
        UserDefaults.standard.set(normalized, forKey: urlKey)
        try CourseCatalogAccess.saveURL(normalized)
    }

    static func clear() {
        removeCached()
        removeCachedImages()
        catalogGeneration += 1
        CourseCatalogAccess.clearCache()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: urlKey)
    }

    private static func token() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fetch() async throws -> [Recipe] {
        let requestedURL = savedURL
        let requestedToken = token()
        let data = try await request(path: "/v1/recipes", maxBytes: 2_000_000)
        guard savedURL == requestedURL, token() == requestedToken else { throw PrivateCatalogError.configurationChanged }
        let recipes = try decodeRecipes(data)
        if let cacheURL {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
            var protectedURL = cacheURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? protectedURL.setResourceValues(resourceValues)
        }
        return recipes
    }

    static func cached() -> [Recipe] {
        guard isConfigured, let cacheURL, let data = try? Data(contentsOf: cacheURL), data.count <= 2_000_000 else { return [] }
        return (try? decodeRecipes(data)) ?? []
    }

    static func discardCached() { removeCached() }

    private static func removeCached() {
        guard let cacheURL else { return }
        try? FileManager.default.removeItem(at: cacheURL)
    }

    static func decodeRecipes(_ data: Data) throws -> [Recipe] {
        guard let catalog = try? JSONDecoder().decode(PrivateCatalogResponse.self, from: data) else { throw PrivateCatalogError.invalidResponse }
        let recipes = catalog.recipes.compactMap { $0.recipe() }
        guard recipes.count == catalog.recipes.count,
              Set(recipes.map(\.id)).count == recipes.count else { throw PrivateCatalogError.invalidResponse }
        return recipes
    }

    static func fetchFamily() async throws -> [FamilyMember] {
        let requestedURL = savedURL
        let requestedToken = token()
        let data = try await request(path: "/v1/family", maxBytes: 50_000)
        guard savedURL == requestedURL, token() == requestedToken else { throw PrivateCatalogError.configurationChanged }
        guard let profile = try? JSONDecoder().decode(FamilyCloudResponse.self, from: data),
              (1...12).contains(profile.members.count),
              Set(profile.members.map(\.id)).count == profile.members.count,
              profile.members.allSatisfy({ member in
                  member.id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil &&
                  !member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  member.name.count <= 80 &&
                  (member.ageYears.map { (0...120).contains($0) } ?? true) &&
                  (0.5...1.6).contains(member.portion)
              }) else { throw PrivateCatalogError.invalidResponse }
        return profile.members
    }

    static func fetchImage(id: String) async throws -> UIImage {
        guard id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil else { throw PrivateCatalogError.invalidURL }
        if let cached = cachedImage(id: id) { return cached }
        let requestedURL = savedURL
        let requestedToken = token()
        let data = try await request(path: "/v1/recipe-images/\(id)", maxBytes: 1_500_000, accept: "image/jpeg")
        guard savedURL == requestedURL, token() == requestedToken else { throw PrivateCatalogError.configurationChanged }
        guard data.starts(with: [0xff, 0xd8, 0xff]), let image = UIImage(data: data) else { throw PrivateCatalogError.invalidResponse }
        if let imageURL = imageCacheURL(id: id) {
            try? FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: imageURL, options: [.atomic, .completeFileProtection])
            var directoryURL = imageURL.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directoryURL.setResourceValues(values)
        }
        return image
    }

    private static func imageCacheURL(id: String) -> URL? {
        guard id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("recipe-images", isDirectory: true).appendingPathComponent("\(id).jpg")
    }

    private static func removeCachedImages() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: support.appendingPathComponent("recipe-images", isDirectory: true))
    }

    static func cachedImage(id: String) -> UIImage? {
        guard let imageURL = imageCacheURL(id: id),
              let data = try? Data(contentsOf: imageURL), data.count <= 1_500_000,
              data.starts(with: [0xff, 0xd8, 0xff]) else { return nil }
        return UIImage(data: data)
    }

    private static func request(path: String, maxBytes: Int, accept: String = "application/json") async throws -> Data {
        guard let base = savedURL, let token = token(), let url = URL(string: base + path) else { throw PrivateCatalogError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PrivateCatalogError.invalidResponse }
        #if DEBUG
        if path.hasPrefix("/v1/recipe-images/") {
            print("Lad image response: \(response.statusCode), \(data.count) bytes")
        }
        #endif
        if response.statusCode == 401 || response.statusCode == 403 { throw PrivateCatalogError.unauthorized }
        guard response.statusCode == 200 else { throw PrivateCatalogError.serverError }
        guard data.count <= maxBytes else { throw PrivateCatalogError.invalidResponse }
        return data
    }
}

struct RecipePicture: View {
    let recipe: Recipe
    @State private var remoteImage: UIImage?
    @State private var loadFailed = false
    @State private var retry = 0
    private var imageContext: String {
        "\(recipe.id)|\(recipe.image)|\(CourseCatalogAccess.savedURL ?? "")|\(PrivateRecipeAccess.catalogGeneration)|\(retry)"
    }
    var body: some View {
        GeometryReader { bounds in
            Group {
                if let remoteImage {
                    Image(uiImage: remoteImage).resizable().scaledToFill()
                } else if recipe.image.isEmpty || recipe.remoteImage || recipe.isUnavailable {
                    ZStack {
                        LinearGradient(colors: [Palette.paleSage, Palette.peach], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: recipe.isUnavailable ? "lock.slash" : "fork.knife")
                            .font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Palette.sage)
                        if loadFailed {
                            Button { retry += 1 } label: {
                                Label("Повторить загрузку фото", systemImage: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(7)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(8)
                        }
                    }
                } else {
                    Image(recipe.image).resizable().scaledToFill()
                }
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
            .clipped()
        }
        .task(id: imageContext) {
            remoteImage = nil
            loadFailed = false
            guard !recipe.image.isEmpty else { return }
            guard recipe.remoteImage else { return }
            do {
                let result = try await (recipe.isPrivate
                    ? PrivateRecipeAccess.fetchImage(id: recipe.image)
                    : CourseCatalogAccess.fetchPublicImage(id: recipe.image))
                if !Task.isCancelled { remoteImage = result }
            } catch {
                if !Task.isCancelled {
                    #if DEBUG
                    print("Lad image failed: \(recipe.image), \(error.localizedDescription)")
                    #endif
                    loadFailed = true
                }
            }
        }
    }
}

struct RecipeStepPicture: View {
    let imageID: String
    let privateAccess: Bool
    @State private var image: UIImage?

    private var imageContext: String {
        "\(imageID)|\(privateAccess)|\(CourseCatalogAccess.savedURL ?? "")|\(PrivateRecipeAccess.catalogGeneration)"
    }

    var body: some View {
        GeometryReader { bounds in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Palette.paleSage
                        Image(systemName: "photo")
                            .font(.system(size: 32, weight: .ultraLight))
                            .foregroundStyle(Palette.sage)
                    }
                }
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
            .clipped()
        }
        .task(id: imageContext) {
            image = nil
            let result = try? await (privateAccess
                ? PrivateRecipeAccess.fetchImage(id: imageID)
                : CourseCatalogAccess.fetchPublicImage(id: imageID))
            if !Task.isCancelled { image = result }
        }
    }
}
