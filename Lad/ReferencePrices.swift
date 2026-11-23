import Foundation

enum ReferencePriceCountry: String, CaseIterable, Identifiable {
    case personal = "", israel = "IL", ukraine = "UA", unitedStates = "US"
    var id: String { pickerTag }
    // SwiftUI treats an empty tag as no selection, so the personal option needs a real tag.
    var pickerTag: String { rawValue.isEmpty ? "personal" : rawValue }
    static func storedCountry(for tag: String) -> String { tag == "personal" ? "" : tag }
    var title: String {
        switch self {
        case .personal: return L10n.text("Только мои цены")
        case .israel: return L10n.text("Израиль · ILS")
        case .ukraine: return L10n.text("Украина · UAH")
        case .unitedStates: return L10n.text("США · USD")
        }
    }
}

struct PriceReference: Codable {
    let country: String
    let period: String
    let publisher: String
    let sourceURL: String
    let licenseURL: String
    let seriesID: String
    let sourceLabel: String
    let method: String

    var isValid: Bool {
        guard ["IL", "UA", "US"].contains(country),
              period.range(of: "^20[0-9]{2}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil,
              !publisher.isEmpty, !seriesID.isEmpty, !sourceLabel.isEmpty,
              method == "statistical-category-average", let url = URL(string: sourceURL),
              url.scheme == "https", let host = url.host?.lowercased(),
              let license = URL(string: licenseURL), license.scheme == "https" else { return false }
        let allowed: [String: Set<String>] = [
            "IL": ["www.cbs.gov.il", "cbs.gov.il"],
            "UA": ["data.gov.ua", "stat.gov.ua", "www.stat.gov.ua"],
            "US": ["api.bls.gov", "www.bls.gov", "bls.gov"]
        ]
        return allowed[country]?.contains(host) == true
    }

    func isStale(asOf date: Date = .now) -> Bool {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd"
        guard let observed = format.date(from: period + "-01") else { return true }
        return date.timeIntervalSince(observed) > 120 * 86_400
    }
}

struct ReferencePriceRecord: Codable {
    let productName: String
    let packagePrice: Double
    let packageQuantity: Double
    let packageUnit: String
    let currency: String
    let reference: PriceReference

    var price: IngredientPrice {
        IngredientPrice(productName: productName, packagePrice: packagePrice, packageQuantity: packageQuantity,
                        packageUnit: packageUnit, currency: currency, reference: reference)
    }
    var isValid: Bool {
        price.isValid && reference.isValid && packagePrice > 0 && packagePrice < 1_000_000 &&
            currency == ["IL": "ILS", "UA": "UAH", "US": "USD"][reference.country]
    }
}

struct ReferencePriceCatalog: Codable {
    let schemaVersion: Int
    let retrievedAt: String
    let prices: [ReferencePriceRecord]
    static let empty = ReferencePriceCatalog(schemaVersion: 1, retrievedAt: "", prices: [])

    static func decode(_ data: Data) throws -> ReferencePriceCatalog {
        guard data.count <= 2_000_000 else { throw PrivateCatalogError.invalidResponse }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        let keys = catalog.prices.map { $0.reference.country + "|" + ProductNames.canonical($0.productName) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard catalog.schemaVersion == 1, !catalog.prices.isEmpty, catalog.prices.count <= 1000,
              let retrieved = formatter.date(from: catalog.retrievedAt), retrieved <= Date().addingTimeInterval(86_400),
              Set(keys).count == keys.count,
              Set(catalog.prices.map { $0.reference.country }) == Set(["IL", "UA", "US"]),
              catalog.prices.allSatisfy({ $0.isValid && $0.reference.period <= String(catalog.retrievedAt.prefix(7)) }) else {
            throw PrivateCatalogError.invalidResponse
        }
        return catalog
    }

    static var bundled: ReferencePriceCatalog {
        guard let url = Bundle.main.url(forResource: "reference-prices", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? decode(data) else { return .empty }
        return catalog
    }
    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Lad", isDirectory: true).appendingPathComponent("reference-prices.json")
    }
    static var current: ReferencePriceCatalog {
        let shipped = bundled
        guard let url = cacheURL, let data = try? Data(contentsOf: url), let cached = try? decode(data),
              cached.retrievedAt >= shipped.retrievedAt else { return shipped }
        return cached
    }
    func cache() {
        guard let url = Self.cacheURL, let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
    func records(country: String) -> [ReferencePriceRecord] {
        prices.filter { $0.reference.country == country }
    }
    func effectivePrices(personal: [IngredientPrice], country: String, shelf: [IngredientPrice]? = nil) -> [IngredientPrice] {
        let overrides = FoodCost.merge([], personal).filter { $0.deletedAt == nil && $0.isValid }
        let overrideIDs = Set(overrides.map(\.id))
        let official = records(country: country).map(\.price).filter { !overrideIDs.contains($0.id) }
        let covered = overrideIDs.union(official.map(\.id))
        // A shelf pack fills a product the statistical feed does not sell as a series.
        // It is not a country average and never replaces one, or a personal price.
        let shelfRows = shelf ?? ShelfPrices.records(country: country)
        let shelfPrices = shelfRows.filter { !covered.contains($0.id) }
        return overrides + official + shelfPrices
    }
}

enum ShelfPrices {
    static let method = "retail-shelf-median"
    private struct File: Codable {
        let observedOn: String
        let prices: [Row]
    }
    private struct Row: Codable {
        let productName: String
        let packagePrice: Double
        let packageQuantity: Double
        let packageUnit: String
        let currency: String
        let country: String
        let barcode: String
        let sourceURL: String
        let sourceLabel: String
        let chains: Int
    }
    private static let rows: [IngredientPrice] = load()
    private static func load() -> [IngredientPrice] {
        guard let url = Bundle.main.url(forResource: "shelf-prices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.observedOn.range(of: "^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$", options: .regularExpression) != nil
        else { return [] }
        let period = String(file.observedOn.prefix(7))
        var seen: Set<String> = []
        return file.prices.compactMap { row in
            let id = ProductNames.canonical(row.productName)
            guard seen.insert(id).inserted, row.chains >= 1, !row.sourceLabel.isEmpty,
                  row.country == "IL", row.currency == "ILS",
                  row.barcode.range(of: "^[0-9]{8,14}$", options: .regularExpression) != nil,
                  let source = URL(string: row.sourceURL), source.scheme == "https",
                  source.host?.lowercased() == "wizbi.store" else { return nil }
            let price = IngredientPrice(
                productName: row.productName, packagePrice: row.packagePrice,
                packageQuantity: row.packageQuantity, packageUnit: row.packageUnit,
                currency: row.currency,
                reference: PriceReference(
                    country: row.country, period: period, publisher: "WizStore",
                    sourceURL: row.sourceURL, licenseURL: "https://wizbi.store/en",
                    seriesID: "shelf-" + row.barcode, sourceLabel: row.sourceLabel, method: method))
            return price.isValid ? price : nil
        }
    }
    static func records(country: String) -> [IngredientPrice] {
        country == "IL" ? rows : []
    }

    static func barcode(of price: IngredientPrice) -> String? {
        guard let series = price.reference?.seriesID, series.hasPrefix("shelf-") else { return nil }
        let code = String(series.dropFirst("shelf-".count))
        guard code.range(of: "^[0-9]{8,14}$", options: .regularExpression) != nil else { return nil }
        return code
    }

    /// Replaces the bundled pack price with the chain file's median for the same barcode.
    /// A quote whose unit is not the bundled pack is left untouched. No new product is added.
    static func applying(_ quotes: [ShelfFileQuote]) -> [IngredientPrice] {
        let byCode = Dictionary(quotes.map { ($0.barcode, $0) }, uniquingKeysWith: { _, next in next })
        return records(country: "IL").map { row in
            guard let code = barcode(of: row), let quote = byCode[code], quote.stores >= 1,
                  let pack = ShelfFileSync.pack(quantity: quote.quantity, unit: quote.unit, matching: row.packageUnit),
                  quote.price.isFinite, quote.price > 0, quote.price < 1_000_000,
                  let period = ShelfFileSync.period(quote.day) else { return row }
            var updated = row
            updated.packagePrice = quote.price
            updated.packageQuantity = pack.quantity
            updated.packageUnit = pack.unit
            updated.reference = PriceReference(
                country: "IL", period: period, publisher: "Shufersal",
                sourceURL: "https://prices.shufersal.co.il/",
                licenseURL: "https://prices.shufersal.co.il/",
                seriesID: "shelf-" + code,
                sourceLabel: quote.name.isEmpty ? (row.reference?.sourceLabel ?? "") : quote.name,
                method: method)
            return updated.isValid ? updated : row
        }
    }
}

struct ShelfFileQuote: Codable, Equatable {
    var barcode: String
    var price: Double
    var quantity: Double
    var unit: String
    var name: String
    var stores: Int
    var day: String
}

struct ShelfFileSnapshot: Codable, Equatable {
    var day: String
    var quotes: [ShelfFileQuote]
}

enum ShelfFileSync {
    static let endpoint = URL(string: "https://46.225.60.104/ladlekin/api/v1/barcodes")!

    static func fetch(barcodes: [String]) async throws -> ShelfFileSnapshot {
        var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        parts?.queryItems = barcodes.map { URLQueryItem(name: "code", value: $0) }
        guard let url = parts?.url else { throw PrivateCatalogError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Ladlekin/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PrivateCatalogError.invalidResponse }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> ShelfFileSnapshot {
        guard data.count <= 1_000_000 else { throw PrivateCatalogError.invalidResponse }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.method == ShelfPrices.method, payload.currency == "ILS", period(payload.day) != nil else {
            throw PrivateCatalogError.invalidResponse
        }
        let quotes = payload.items.compactMap { item -> ShelfFileQuote? in
            guard item.barcode.range(of: "^[0-9]{8,14}$", options: .regularExpression) != nil,
                  item.stores >= 1, item.price.isFinite, item.price > 0, item.quantity.isFinite, item.quantity > 0 else { return nil }
            return ShelfFileQuote(barcode: item.barcode, price: item.price, quantity: item.quantity,
                                   unit: item.unit, name: item.name, stores: item.stores, day: payload.day)
        }
        guard !quotes.isEmpty else { throw PrivateCatalogError.invalidResponse }
        return ShelfFileSnapshot(day: payload.day, quotes: quotes)
    }

    static func period(_ day: String) -> String? {
        guard day.range(of: "^20[0-9]{6}$", options: .regularExpression) != nil else { return nil }
        let month = day.dropFirst(4).prefix(2)
        guard let monthNumber = Int(month), (1...12).contains(monthNumber) else { return nil }
        return "\(day.prefix(4))-\(month)"
    }

    static func pack(quantity: Double, unit: String, matching target: String) -> (quantity: Double, unit: String)? {
        guard quantity.isFinite, quantity > 0, let measure = measure(quantity: quantity, unit: unit) else { return nil }
        let pack: (Double, String)?
        switch (measure, target) {
        case let (.grams(grams), "г"): pack = (grams, "г")
        case let (.grams(grams), "кг"): pack = (grams / 1000, "кг")
        case let (.milliliters(milliliters), "мл"): pack = (milliliters, "мл")
        case let (.milliliters(milliliters), "л"): pack = (milliliters / 1000, "л")
        case let (.pieces(pieces), "шт."): pack = (pieces, "шт.")
        default: pack = nil
        }
        guard let pack, pack.0.isFinite, pack.0 > 0 else { return nil }
        return pack
    }

    private enum ChainMeasure {
        case grams(Double)
        case milliliters(Double)
        case pieces(Double)
    }

    private static func measure(quantity: Double, unit: String) -> ChainMeasure? {
        let cleaned = unit
            .replacingOccurrences(of: "״", with: "")
            .replacingOccurrences(of: "׳", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch cleaned {
        case "גרם", "גר", "ג": return .grams(quantity)
        case "קילוגרם", "קג": return .grams(quantity * 1000)
        case "מיליליטר", "מל": return .milliliters(quantity)
        case "ליטר", "ל": return .milliliters(quantity * 1000)
        case "יחידה", "יחידות", "יח": return .pieces(quantity)
        default: return nil
        }
    }

    private struct Payload: Decodable {
        let day: String
        let currency: String
        let method: String
        let items: [Item]
    }
    private struct Item: Decodable {
        let barcode: String
        let name: String
        let price: Double
        let quantity: Double
        let unit: String
        let stores: Int
    }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Lad", isDirectory: true).appendingPathComponent("shelf-file.json")
    }

    static func load() -> ShelfFileSnapshot? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ShelfFileSnapshot.self, from: data),
              period(snapshot.day) != nil, !snapshot.quotes.isEmpty else { return nil }
        return snapshot
    }

    static func save(_ snapshot: ShelfFileSnapshot) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
}

extension LadStore {
    static let referencePriceCountryKey = "lad.referencePriceCountry"
    static func referenceCountry(forRegion identifier: String?) -> String {
        switch identifier {
        case "UA": return "UA"
        case "US": return "US"
        default: return "IL"
        }
    }
    /// `system` follows the phone region. `personal` is an explicit empty choice.
    /// `IL`, `UA` and `US` are explicit countries. A missing value stays `system`.
    static func storedPriceCountrySource() -> String {
        switch UserDefaults.standard.object(forKey: referencePriceCountryKey) {
        case nil: return "system"
        case let value as String where value.isEmpty: return "personal"
        case let value as String where value == "system" || (ReferencePriceCountry(rawValue: value) != nil && !value.isEmpty):
            return value
        default: return "system"
        }
    }
    static func resolvedReferencePriceCountry(source: String) -> String {
        if source == "personal" { return "" }
        if let country = ReferencePriceCountry(rawValue: source), !country.rawValue.isEmpty { return country.rawValue }
        return referenceCountry(forRegion: Locale.current.region?.identifier)
    }
    static func storedReferencePriceCountry() -> String {
        resolvedReferencePriceCountry(source: storedPriceCountrySource())
    }
    static func priceCountrySourceTitle(_ source: String) -> String {
        switch source {
        case "system": return L10n.text("Страна как на телефоне")
        case "personal": return L10n.text("Только мои цены")
        default: return ReferencePriceCountry(rawValue: source)?.title ?? source
        }
    }
    func setReferencePriceCountry(_ country: String) {
        let source: String
        switch country {
        case "system": source = "system"
        case "", "personal": source = "personal"
        case "IL", "UA", "US": source = country
        default: return
        }
        referencePriceCountrySource = source
        referencePriceCountry = Self.resolvedReferencePriceCountry(source: source)
        UserDefaults.standard.set(source == "personal" ? "" : source, forKey: Self.referencePriceCountryKey)
        referencePriceStatus = nil
    }
    func refreshReferencePrices(announce: Bool = true) async {
        guard !isUpdatingReferencePrices else { return }
        isUpdatingReferencePrices = true
        if announce { referencePriceStatus = nil }
        defer { isUpdatingReferencePrices = false }
        async let official = refreshOfficialPrices()
        async let shelf = refreshShelfFile()
        let officialOK = await official
        let shelfOK = await shelf
        guard announce else { return }
        referencePriceStatus = (officialOK || shelfOK)
            ? L10n.text("Цены обновлены")
            : L10n.text("Не удалось обновить. Сохранённые цены доступны.")
    }

    private func refreshOfficialPrices() async -> Bool {
        guard let base = CourseCatalogAccess.savedURL, let url = URL(string: base + "/v3/prices") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            guard base == CourseCatalogAccess.savedURL, (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let updated = try ReferencePriceCatalog.decode(data)
            guard updated.retrievedAt >= referencePriceCatalog.retrievedAt else { return false }
            referencePriceCatalog = updated
            updated.cache()
            return true
        } catch {
            return false
        }
    }

    /// The phone names the pack. The server answers with the median from the chain's published price file.
    private func refreshShelfFile() async -> Bool {
        let codes = ShelfPrices.records(country: "IL").compactMap { ShelfPrices.barcode(of: $0) }
        guard !codes.isEmpty else { return false }
        do {
            let snapshot = try await ShelfFileSync.fetch(barcodes: codes)
            shelfFileSnapshot = snapshot
            ShelfFileSync.save(snapshot)
            return true
        } catch {
            return false
        }
    }
}
