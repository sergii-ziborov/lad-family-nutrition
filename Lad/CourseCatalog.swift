import Foundation
import CryptoKit
import UIKit

struct LadCourse: Identifiable, Codable {
    let id: String
    let titleRu: String
    let titleEn: String
    let summaryRu: String
    let summaryEn: String
    let category: String
    let access: String
    let status: String
    let recipeIDs: [String]
    let days: [CourseDay]?

    var title: String { Locale.current.language.languageCode?.identifier == "en" ? titleEn : titleRu }
    var summary: String { Locale.current.language.languageCode?.identifier == "en" ? summaryEn : summaryRu }
    var isFree: Bool { access == "free" }
}

struct CourseDay: Codable, Identifiable {
    let day: Int
    let lunchRecipeID: String?
    let dinnerRecipeID: String?
    var id: Int { day }
}

private enum CatalogueItem: Decodable {
    case recipe(PrivateRecipePayload, visibility: String)
    case course(LadCourse)

    private enum CodingKeys: String, CodingKey { case type, visibility, data }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let type = try values.decode(String.self, forKey: .type)
        switch type {
        case "recipe":
            self = .recipe(try values.decode(PrivateRecipePayload.self, forKey: .data),
                           visibility: try values.decode(String.self, forKey: .visibility))
        case "program":
            self = .course(try values.decode(LadCourse.self, forKey: .data))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: values, debugDescription: "Unknown catalogue item")
        }
    }
}

private struct CataloguePage: Decodable {
    let revision: String
    let scope: String
    let items: [CatalogueItem]
    let nextCursor: String?
}

struct CourseCatalogue {
    let revision: String
    let courses: [LadCourse]
    let recipes: [Recipe]
}

enum CourseCatalogAccess {
    private static let urlKey = "lad.catalogURL"
    static let defaultURL = "https://116.203.99.11"
    private struct BundledCourses: Decodable { let programs: [LadCourse] }
    static var bundledCourses: [LadCourse] {
        guard let url = Bundle.main.url(forResource: "public-recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(BundledCourses.self, from: data) else { return [] }
        return bundle.programs.filter { $0.status == "published" && $0.isFree }
    }
    static var savedURL: String? {
        UserDefaults.standard.string(forKey: urlKey) ?? PrivateRecipeAccess.savedURL ?? defaultURL
    }

    static func saveURL(_ raw: String) throws {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parsed = URL(string: normalized), parsed.scheme == "https", parsed.host != nil,
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil else {
            throw PrivateCatalogError.invalidURL
        }
        if PrivateRecipeAccess.isConfigured, PrivateRecipeAccess.savedURL != normalized {
            throw PrivateCatalogError.configurationChanged
        }
        if savedURL != normalized { clearCache() }
        UserDefaults.standard.set(normalized, forKey: urlKey)
    }

    static func clearCache() {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let paths = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for path in paths where path.lastPathComponent.hasPrefix("course-catalog-") {
            try? FileManager.default.removeItem(at: path)
        }
    }

    static func fetchPublicImage(id: String) async throws -> UIImage {
        guard id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              let base = savedURL, let url = URL(string: base + "/v1/recipe-images/\(id)") else {
            throw PrivateCatalogError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard savedURL == base else { throw PrivateCatalogError.configurationChanged }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count <= 1_500_000, data.starts(with: [0xff, 0xd8, 0xff]),
              let image = UIImage(data: data) else { throw PrivateCatalogError.invalidResponse }
        return image
    }

    private static func cacheURL(for url: String, token: String?) -> URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let identity = Data((url + "|" + (token ?? "public")).utf8)
        let digest = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("course-catalog-\(digest).json")
    }

    static func fetch() async throws -> CourseCatalogue {
        guard let base = savedURL else { throw PrivateCatalogError.invalidURL }
        let token = PrivateRecipeAccess.savedURL == base ? PrivateRecipeAccess.catalogToken : nil
        var pages: [Data] = []
        var totalBytes = 0
        var cursor: String?
        var revision: String?
        var visited = Set<String>()
        do {
            for _ in 0..<100 {
                guard var components = URLComponents(string: base + "/v2/catalog") else { throw PrivateCatalogError.invalidURL }
                if let cursor { components.queryItems = [URLQueryItem(name: "cursor", value: cursor)] }
                guard let url = components.url else { throw PrivateCatalogError.invalidURL }
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard savedURL == base, (PrivateRecipeAccess.savedURL == base ? PrivateRecipeAccess.catalogToken : nil) == token else {
                    throw PrivateCatalogError.configurationChanged
                }
                guard let response = response as? HTTPURLResponse else { throw PrivateCatalogError.invalidResponse }
                if response.statusCode == 401 || response.statusCode == 403 {
                    clearCache()
                    throw PrivateCatalogError.unauthorized
                }
                guard response.statusCode == 200, data.count <= 2_000_000 else { throw PrivateCatalogError.serverError }
                totalBytes += data.count
                guard totalBytes <= 20_000_000 else { throw PrivateCatalogError.invalidResponse }
                let page = try JSONDecoder().decode(CataloguePage.self, from: data)
                guard page.scope == (token == nil ? "public" : "member"),
                      revision == nil || revision == page.revision else { throw PrivateCatalogError.invalidResponse }
                revision = page.revision
                pages.append(data)
                if let next = page.nextCursor {
                    guard visited.insert(next).inserted else { throw PrivateCatalogError.invalidResponse }
                    cursor = next
                } else {
                    let result = try decodePages(pages)
                    if let cache = cacheURL(for: base, token: token) {
                        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if let encoded = try? JSONEncoder().encode(pages) {
                            try? encoded.write(to: cache, options: [.atomic, .completeFileProtection])
                            var protectedURL = cache
                            var values = URLResourceValues()
                            values.isExcludedFromBackup = true
                            try? protectedURL.setResourceValues(values)
                        }
                    }
                    return result
                }
            }
            throw PrivateCatalogError.invalidResponse
        } catch {
            if case PrivateCatalogError.unauthorized = error { throw error }
            if case PrivateCatalogError.configurationChanged = error { throw error }
            if let cache = cacheURL(for: base, token: token), let data = try? Data(contentsOf: cache),
               data.count <= 20_000_000, let pages = try? JSONDecoder().decode([Data].self, from: data),
               let snapshot = try? decodePages(pages) { return snapshot }
            throw error
        }
    }

    static func decodePages(_ pages: [Data]) throws -> CourseCatalogue {
        guard !pages.isEmpty else { throw PrivateCatalogError.invalidResponse }
        var revision: String?
        var recipes: [Recipe] = []
        var courses: [LadCourse] = []
        for data in pages {
            let page = try JSONDecoder().decode(CataloguePage.self, from: data)
            guard revision == nil || revision == page.revision else { throw PrivateCatalogError.invalidResponse }
            revision = page.revision
            for item in page.items {
                switch item {
                case .recipe(let payload, let visibility):
                    guard visibility == "public" || visibility == "private",
                          let recipe = payload.recipe(privateAccess: visibility == "private") else {
                        throw PrivateCatalogError.invalidResponse
                    }
                    recipes.append(recipe)
                case .course(let course):
                    guard course.status == "published", ["free", "members"].contains(course.access),
                          !course.titleRu.isEmpty, !course.titleEn.isEmpty,
                          course.days.map({ days in
                              days.count <= 31 && Set(days.map(\.day)).count == days.count &&
                              days.allSatisfy { day in
                                  (1...31).contains(day.day) &&
                                  [day.lunchRecipeID, day.dinnerRecipeID].compactMap { $0 }
                                      .allSatisfy(course.recipeIDs.contains)
                              }
                          }) ?? true else { throw PrivateCatalogError.invalidResponse }
                    courses.append(course)
                }
            }
        }
        guard Set(recipes.map(\.id)).count == recipes.count, Set(courses.map(\.id)).count == courses.count,
              let revision else { throw PrivateCatalogError.invalidResponse }
        let available = Set(recipes.map(\.id))
        guard courses.allSatisfy({ course in course.recipeIDs.allSatisfy { id in
            course.isFree ? available.contains(id) :
                (available.contains(id) || available.contains("private:\(id)"))
        } }) else { throw PrivateCatalogError.invalidResponse }
        return CourseCatalogue(revision: revision, courses: courses, recipes: recipes)
    }
}
