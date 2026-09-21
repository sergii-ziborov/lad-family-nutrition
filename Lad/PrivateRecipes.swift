import Foundation
import Security
import SwiftUI

private struct PrivateCatalogResponse: Decodable {
    let recipes: [PrivateRecipePayload]
}

private struct PrivateRecipePayload: Decodable {
    let id: String
    let title: String
    let caption: String
    let cuisine: String
    let minutes: Int
    let kcal: Int
    let protein: Int
    let allergens: [String]
    let ingredients: [Ingredient]
    let steps: [String]
    let allergensVerified: Bool

    func recipe() -> Recipe? {
        guard id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              !title.isEmpty, minutes > 0, steps.count > 0 else { return nil }
        return Recipe(id: "private:\(id)", title: title, caption: caption, image: "", cuisine: cuisine, minutes: minutes, kcal: kcal, protein: protein, allergens: allergens, ingredients: ingredients, steps: steps, allergensVerified: allergensVerified)
    }
}

enum PrivateCatalogError: LocalizedError {
    case invalidURL, emptyToken, keychainFailure, invalidResponse, unauthorized, serverError
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Нужен адрес HTTPS-сервера."
        case .emptyToken: "Введите личный ключ доступа."
        case .keychainFailure: "Не удалось сохранить ключ на устройстве."
        case .invalidResponse: "Сервер вернул неподходящий каталог."
        case .unauthorized: "Ключ не принят сервером."
        case .serverError: "Закрытый каталог сейчас недоступен."
        }
    }
}

enum PrivateRecipeAccess {
    private static let urlKey = "lad.privateCatalogURL"
    private static let service = "app.lad.family.private-catalog"
    private static let account = "access-token"
    static var savedURL: String? { UserDefaults.standard.string(forKey: urlKey) }
    static var isConfigured: Bool { savedURL != nil && token() != nil }

    static func save(url: String, token: String) throws {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parsed = URL(string: normalized), parsed.scheme == "https", parsed.host != nil,
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil else { throw PrivateCatalogError.invalidURL }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PrivateCatalogError.emptyToken }
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw PrivateCatalogError.keychainFailure }
        UserDefaults.standard.set(normalized, forKey: urlKey)
    }

    static func clear() {
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
        guard let base = savedURL, let token = token(), let url = URL(string: base + "/v1/recipes") else { throw PrivateCatalogError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PrivateCatalogError.invalidResponse }
        if response.statusCode == 401 || response.statusCode == 403 { throw PrivateCatalogError.unauthorized }
        guard response.statusCode == 200 else { throw PrivateCatalogError.serverError }
        guard data.count <= 2_000_000,
              let catalog = try? JSONDecoder().decode(PrivateCatalogResponse.self, from: data) else { throw PrivateCatalogError.invalidResponse }
        let recipes = catalog.recipes.compactMap { $0.recipe() }
        guard recipes.count == catalog.recipes.count else { throw PrivateCatalogError.invalidResponse }
        return recipes
    }
}

struct RecipePicture: View {
    let recipe: Recipe
    var body: some View {
        Group {
            if recipe.isPrivate || recipe.isUnavailable {
                ZStack {
                    LinearGradient(colors: [Palette.paleSage, Palette.peach], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: recipe.isUnavailable ? "lock.slash" : "fork.knife")
                        .font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Palette.sage)
                }
            } else {
                Image(recipe.image).resizable().scaledToFill()
            }
        }
    }
}
