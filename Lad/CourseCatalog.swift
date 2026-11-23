import Foundation
import CryptoKit
import UIKit

enum CourseAliases {
    static let mediterranean = "mediterranean-ideas"
    static func canonical(_ ids: Set<String>) -> Set<String> {
        Set(ids.map { $0 == "lad-starter" ? mediterranean : $0 })
    }
}

struct LadCourse: Identifiable, Codable {
    let id: String
    let titleRu: String
    let titleEn: String
    let summaryRu: String
    let summaryEn: String
    var summaryUk: String? = nil
    let category: String
    let access: String
    let status: String
    let recipeIDs: [String]
    let days: [CourseDay]?
    let suggestedPairs: [CourseSuggestion]?
    var rules: [CourseRule]? = nil
    var planningStyle: String? = nil
    var breakfastRecipeIDs: [String]? = nil
    var totalRecipeCount: Int? = nil

    var isCombinedDefaultMenu: Bool { planningStyle == "mediterranean-breakfast-weight-menu" }
    var usesWeightMenuRules: Bool { id == "weight-week-pilot" || isCombinedDefaultMenu }

    var title: String {
        if isCombinedDefaultMenu {
            switch L10n.languageCode {
            case "en": return "Healthy eating"
            case "uk": return "Здорове харчування"
            default: return "Здоровое питание"
            }
        }
        return L10n.languageCode == "en" ? titleEn : L10n.text(titleRu)
    }
    var summary: String {
        if L10n.languageCode == "en" { return summaryEn }
        if L10n.languageCode == "uk", let summaryUk { return summaryUk }
        return L10n.text(summaryRu)
    }
    var isFree: Bool { access == "free" }
    // Courses returned by the catalogue already passed its access filter.
    var availabilityLabel: String {
        if isCombinedDefaultMenu, let totalRecipeCount {
            return recipeIDs.count < totalRecipeCount ? L10n.format("Бесплатно: %d блюд", recipeIDs.count) : L10n.text("Полный курс")
        }
        return L10n.text(isFree ? "Бесплатный" : "Доступен")
    }
    var generalTimingRules: [CourseRule] {
        (rules ?? []).filter {
            $0.isTimingRule && ($0.recipeIDs ?? []).isEmpty &&
            $0.mealKind.map { (0..<3).contains($0) } == true &&
            $0.minute.map { (0...1440).contains($0) } == true
        }.sorted { ($0.mealKind ?? 0, $0.id) < ($1.mealKind ?? 0, $1.id) }
    }
}

// Editorial rules belong to a course, not to a recipe or to the whole app.
// All rules are advisory: planning may prefer a compliant choice, but people
// can always keep or choose a conflicting menu after seeing the warning.
struct CourseRule: Codable, Identifiable {
    let id: String
    let scope: String                 // meal, day, week
    let kind: String                  // allowedMealKinds, maxRecipeOccurrences,
                                      // minRecipeOccurrences, maxIngredientOccurrences,
                                      // avoidIngredientPair, latestMealMinute, earliestMealMinute, note
    let titleRu: String
    let titleEn: String
    let titleUk: String
    var recipeIDs: [String]? = nil
    var ingredientNames: [String]? = nil
    var pairedIngredientNames: [String]? = nil
    var allowedMealKinds: [Int]? = nil
    var mealKind: Int? = nil
    var limit: Int? = nil
    var minute: Int? = nil
    var preferredMinute: Int? = nil
    var minutesAfterWaking: Int? = nil
    var windowStartMinute: Int? = nil

    var isTimingRule: Bool { ["latestMealMinute", "earliestMealMinute"].contains(kind) }
    var timingLabel: String? {
        guard isTimingRule, let minute, (0...1440).contains(minute) else { return nil }
        return L10n.format(kind == "latestMealMinute" ? "до %@" : "после %@", Self.clock(minute))
    }
    var recommendedTimingLabel: String? {
        if let windowStartMinute, let minute, (0...1440).contains(minute), (0...minute).contains(windowStartMinute) {
            return "\(Self.clock(windowStartMinute))–\(Self.clock(minute))"
        }
        if let preferredMinute, (0...1440).contains(preferredMinute) {
            return L10n.format("до %@", Self.clock(preferredMinute))
        }
        return timingLabel
    }
    var timingDetails: String? {
        var parts: [String] = []
        if let windowStartMinute, let minute, (0...1440).contains(minute), (0...minute).contains(windowStartMinute) {
            parts.append(L10n.format("ориентир %@–%@", Self.clock(windowStartMinute), Self.clock(minute)))
        }
        if let preferredMinute, (0...1440).contains(preferredMinute) {
            parts.append(L10n.format("желательно до %@", Self.clock(preferredMinute)))
        }
        if let minutesAfterWaking, (1...1440).contains(minutesAfterWaking) {
            parts.append(L10n.format("в течение %d мин после пробуждения", minutesAfterWaking))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    var title: String {
        switch L10n.languageCode {
        case "en": titleEn
        case "uk": titleUk
        default: titleRu
        }
    }
}

struct CourseRuleWarning: Identifiable, Hashable {
    let id: String
    let scope: String
    let text: String
    let day: Int?
    let isConflict: Bool
    let excess: Int
}

enum CourseRuleEngine {
    static func visibleWarnings(courses: [LadCourse], slots: [MealSlot], recipes: [Recipe],
                                schedule: MealSchedule, skippedIDs: Set<String> = []) -> [CourseRuleWarning] {
        let timingRuleIDs = Set(courses.flatMap { course in
            (course.rules ?? []).filter { ["latestMealMinute", "earliestMealMinute"].contains($0.kind) }
                .map { "\(course.id)|\($0.id)" }
        })
        return warnings(courses: courses, slots: slots, recipes: recipes, schedule: schedule,
                        skippedIDs: skippedIDs).filter { warning in
            !timingRuleIDs.contains(where: { timingID in
                warning.id.hasPrefix(timingID + "|") || warning.id.contains("|" + timingID + "|") ||
                warning.id.hasSuffix("|" + timingID)
            })
        }
    }

    private static func rawID(_ id: String) -> String {
        id.hasPrefix("private:") ? String(id.dropFirst("private:".count)) : id
    }

    private static func names(_ recipeIDs: [String], recipes: [String: Recipe]) -> Set<String> {
        Set(recipeIDs.flatMap { recipes[rawID($0)]?.ingredients.map { $0.name.lowercased() } ?? [] })
    }

    static func warnings(courses: [LadCourse], slots: [MealSlot], recipes: [Recipe],
                         schedule: MealSchedule, skippedIDs: Set<String> = []) -> [CourseRuleWarning] {
        let active = slots.filter { $0.recipeID != Recipe.unplanned.id && !$0.memberIDs.isEmpty && !skippedIDs.contains($0.id) }
        let byID = Dictionary(recipes.map { (rawID($0.id), $0) }, uniquingKeysWith: { first, _ in first })
        var result: [CourseRuleWarning] = []
        let allRules = courses.flatMap { course in (course.rules ?? []).map { (course, $0) } }
        for (course, rule) in allRules {
            let targetIDs = Set(rule.recipeIDs ?? [])
            let ingredients = Set((rule.ingredientNames ?? []).map { $0.lowercased() })
            let paired = Set((rule.pairedIngredientNames ?? []).map { $0.lowercased() })
            let matchedSlots = active.filter { slot in
                !targetIDs.isDisjoint(with: Set(slot.allRecipeIDs.map(rawID)))
            }
            func append(_ day: Int? = nil, excess: Int = 1) {
                result.append(CourseRuleWarning(id: "\(course.id)|\(rule.id)|\(day.map(String.init) ?? "all")",
                                                scope: rule.scope, text: "\(course.title): \(rule.title)",
                                                day: day, isConflict: false, excess: excess))
            }
            switch rule.kind {
            case "allowedMealKinds":
                for slot in matchedSlots where !(rule.allowedMealKinds ?? []).contains(slot.kind) { append(slot.day) }
            case "maxRecipeOccurrences", "minRecipeOccurrences":
                let matched = rule.scope == "week" ? matchedSlots :
                    matchedSlots.filter { rule.mealKind == nil || $0.kind == rule.mealKind }
                func count(_ slots: [MealSlot]) -> Int {
                    slots.reduce(0) { total, slot in
                        total + slot.allRecipeIDs.map(rawID).filter { targetIDs.contains($0) }.count
                    }
                }
                if rule.scope == "week" {
                    let occurrences = count(matched)
                    if rule.kind == "maxRecipeOccurrences" && occurrences > (rule.limit ?? .max) { append(excess: occurrences - (rule.limit ?? .max)) }
                    if rule.kind == "minRecipeOccurrences" && occurrences < (rule.limit ?? 0) { append(excess: (rule.limit ?? 0) - occurrences) }
                } else {
                    let activeDays = Set(active.filter { rule.mealKind == nil || $0.kind == rule.mealKind }.map(\.day))
                    for day in activeDays {
                        let occurrences = count(matched.filter { $0.day == day })
                        if rule.kind == "maxRecipeOccurrences" && occurrences > (rule.limit ?? .max) { append(day, excess: occurrences - (rule.limit ?? .max)) }
                        if rule.kind == "minRecipeOccurrences" && occurrences < (rule.limit ?? 0) { append(day, excess: (rule.limit ?? 0) - occurrences) }
                    }
                }
            case "maxIngredientOccurrences":
                let matched = active.filter { slot in
                    (rule.mealKind == nil || slot.kind == rule.mealKind) &&
                    !names(slot.allRecipeIDs, recipes: byID).isDisjoint(with: ingredients)
                }
                if rule.scope == "week" && matched.count > (rule.limit ?? .max) { append(excess: matched.count - (rule.limit ?? .max)) }
                if rule.scope == "day" {
                    for day in Set(matched.map(\.day)) {
                        let count = matched.filter { $0.day == day }.count
                        if count > (rule.limit ?? .max) { append(day, excess: count - (rule.limit ?? .max)) }
                    }
                }
                if rule.scope == "meal" {
                    for slot in matched {
                        let count = names(slot.allRecipeIDs, recipes: byID).intersection(ingredients).count
                        if count > (rule.limit ?? .max) { append(slot.day, excess: count - (rule.limit ?? .max)) }
                    }
                }
            case "avoidIngredientPair":
                for slot in active where rule.mealKind == nil || slot.kind == rule.mealKind {
                    let present = names(slot.allRecipeIDs, recipes: byID)
                    if !present.isDisjoint(with: ingredients) && !present.isDisjoint(with: paired) { append(slot.day) }
                }
            case "latestMealMinute", "earliestMealMinute":
                if let kind = rule.mealKind, let minute = rule.minute,
                   (rule.kind == "latestMealMinute" ? schedule.endMinute(for: kind) > minute
                                                     : schedule.endMinute(for: kind) < minute) {
                    let affected = active.filter { slot in
                        slot.kind == kind && (targetIDs.isEmpty ||
                            !Set(slot.allRecipeIDs.map(rawID)).isDisjoint(with: targetIDs))
                    }
                    if !affected.isEmpty {
                        if rule.scope == "day" && !targetIDs.isEmpty {
                            for day in Set(affected.map(\.day)) { append(day) }
                        } else { append() }
                    }
                }
            default: break  // A note is displayed in the course, never scored as a violation.
            }
        }
        for left in allRules.indices {
            for right in allRules.indices where right > left {
                let (aCourse, a) = allRules[left]
                let (bCourse, b) = allRules[right]
                guard aCourse.id != bCourse.id, a.scope == b.scope else { continue }
                let shared = !Set(a.recipeIDs ?? []).isDisjoint(with: Set(b.recipeIDs ?? []))
                let disjointKinds = a.kind == "allowedMealKinds" && b.kind == "allowedMealKinds" && shared &&
                    Set(a.allowedMealKinds ?? []).isDisjoint(with: Set(b.allowedMealKinds ?? []))
                let sameTargets = !(a.recipeIDs ?? []).isEmpty && Set(a.recipeIDs ?? []) == Set(b.recipeIDs ?? [])
                let impossibleCount = sameTargets &&
                    ((a.kind == "maxRecipeOccurrences" && b.kind == "minRecipeOccurrences" && (a.limit ?? .max) < (b.limit ?? 0)) ||
                     (b.kind == "maxRecipeOccurrences" && a.kind == "minRecipeOccurrences" && (b.limit ?? .max) < (a.limit ?? 0)))
                let timeTargetsOverlap = (a.recipeIDs ?? []).isEmpty || (b.recipeIDs ?? []).isEmpty || shared
                let impossibleTime = timeTargetsOverlap && a.mealKind == b.mealKind && a.mealKind != nil &&
                    ((a.kind == "latestMealMinute" && b.kind == "earliestMealMinute" && (a.minute ?? .max) < (b.minute ?? 0)) ||
                     (b.kind == "latestMealMinute" && a.kind == "earliestMealMinute" && (b.minute ?? .max) < (a.minute ?? 0)))
                if disjointKinds || impossibleCount || impossibleTime {
                    result.append(CourseRuleWarning(id: "conflict|\(aCourse.id)|\(a.id)|\(bCourse.id)|\(b.id)",
                                                    scope: a.scope,
                                                    text: L10n.format("Правила курсов «%@» и «%@» конфликтуют: %@ / %@. Выбор остаётся за вами.",
                                                                      aCourse.title, bCourse.title, a.title, b.title),
                                                    day: nil, isConflict: true, excess: 1))
                }
            }
        }
        return Array(Dictionary(grouping: result, by: \.id).values.compactMap(\.first)).sorted { $0.id < $1.id }
    }
}

struct CourseDay: Codable, Identifiable {
    let day: Int
    let lunchRecipeID: String?
    let dinnerRecipeID: String?
    var id: Int { day }
}

struct CourseSuggestion: Codable, Identifiable {
    let number: Int
    let lunchRecipeID: String
    let dinnerRecipeID: String?
    var breakfastRecipeIDs: [String]? = nil
    var lunchExtraRecipeIDs: [String]? = nil
    var dinnerExtraRecipeIDs: [String]? = nil
    var drinkOptions: [String]? = nil
    var id: Int { number }
}

// Printed day numbers are provenance, not positions in a generated week.
// These preferences only rank compatible meals; they never lock a day or slot.
enum CourseWeekPreferences {
    private static func rawID(_ id: String) -> String {
        id.hasPrefix("private:") ? String(id.dropFirst("private:".count)) : id
    }

    static func pairingBonus(course: LadCourse?, lunchID: String, dinnerID: String) -> Double {
        guard let course, course.usesWeightMenuRules else { return 0 }
        let lunch = rawID(lunchID)
        let dinner = rawID(dinnerID)
        return (course.suggestedPairs ?? []).contains {
            $0.lunchRecipeID == lunch && $0.dinnerRecipeID == dinner
        } ? 18 : 0
    }

    static func recentRepeatPenalty(recipeID: String, day: Int, slots: [MealSlot]) -> Double {
        guard day > 0 else { return 0 }
        let count = slots.filter {
            $0.day >= max(0, day - 6) && $0.day < day && $0.recipeID == recipeID
        }.count
        return Double(count) * 22
    }
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
    static func suggestionsAreValid(_ course: LadCourse) -> Bool {
        course.suggestedPairs.map { pairs in
            pairs.count <= 100 && Set(pairs.map(\.number)).count == pairs.count &&
            pairs.allSatisfy { pair in
                (1...100).contains(pair.number) && course.recipeIDs.contains(pair.lunchRecipeID) &&
                (pair.dinnerRecipeID.map(course.recipeIDs.contains) ?? true)
            }
        } ?? true
    }

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
              let base = await AppPurchases.shared.catalogBaseURL, let url = URL(string: base + "/v3/recipe-images/\(id)") else {
            throw PrivateCatalogError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        if let proof = await AppPurchases.shared.catalogProof { request.setValue(proof, forHTTPHeaderField: "X-Lad-Transaction") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard await AppPurchases.shared.catalogBaseURL == base else { throw PrivateCatalogError.configurationChanged }
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
                          suggestionsAreValid(course),
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
