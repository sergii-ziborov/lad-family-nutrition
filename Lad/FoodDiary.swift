import Foundation

enum FoodPreparation: String, Codable, CaseIterable {
    case fresh, readyCold, microwave, stove, oven
    var reheated: Bool { ![.fresh, .readyCold].contains(self) }
    var label: String {
        switch self {
        case .fresh: return "Свежеприготовленное"
        case .readyCold: return "Готовое, без разогрева"
        case .microwave: return "Разогрел в микроволновке"
        case .stove: return "Разогрел на плите"
        case .oven: return "Разогрел в духовке"
        }
    }
}

struct DiaryFood: Identifiable, Codable {
    var id: String = UUID().uuidString
    var recipeID: String?
    var title: String
    var servings: Double
    var actualWeightGrams: Double? = nil
    var kcalPerServing: Double?
    // Raw title remains stable; catalogue translations are captured at logging
    // time so a later catalogue update cannot rewrite a historical meal.
    var localizedTitles: [String: String]? = nil
    var nutrientsPerServing: [String: NutrientValue]
    var reheatedNutrientsPerServing: [String: NutrientValue]? = nil
    var preparation: FoodPreparation = .fresh
    var preparedDishID: String? = nil
    var isBeverage: Bool = false

    init(recipe: Recipe, servings: Double) {
        recipeID = recipe.id
        title = recipe.title
        self.servings = servings
        kcalPerServing = recipe.kcal.map(Double.init)
        nutrientsPerServing = recipe.nutrients
        localizedTitles = ["en", "ru", "uk"].reduce(into: [:]) { result, language in
            if language == "ru" { result[language] = recipe.title }
            else if let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) {
                result[language] = NSLocalizedString(recipe.title, bundle: bundle, value: recipe.title, comment: "")
            }
        }
        if nutrientsPerServing["protein"] == nil, let protein = recipe.protein {
            nutrientsPerServing["protein"] = NutrientValue(amount: Double(protein), unit: "г", source: "", coverage: 1)
        }
        reheatedNutrientsPerServing = recipe.isBeverage ? nil : nutrientsPerServing.merging(NutrientEstimator.reheated(recipe), uniquingKeysWith: { _, reheated in reheated })
        isBeverage = recipe.isBeverage
    }

    init(title: String, servings: Double = 1, kcal: Double? = nil, nutrients: [String: NutrientValue] = [:]) {
        self.title = title
        self.servings = servings
        kcalPerServing = kcal
        nutrientsPerServing = nutrients
    }

    var kcal: Double? { kcalPerServing.map { $0 * servings } }
    var displayTitle: String { localizedTitles?[L10n.languageCode] ?? title }
    var nutrients: [String: NutrientValue] {
        let values = preparation.reheated ? (reheatedNutrientsPerServing ?? nutrientsPerServing) : nutrientsPerServing
        return values.mapValues { NutrientValue(amount: $0.amount * servings, unit: $0.unit, source: $0.source, coverage: $0.coverage) }
    }
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 300 &&
        servings.isFinite && servings > 0 && servings <= 20 &&
        (actualWeightGrams.map { $0.isFinite && $0 > 0 && $0 <= 10000 } ?? true) &&
        (kcalPerServing.map { $0.isFinite && $0 >= 0 && $0 <= 20000 } ?? true) &&
        nutrientsPerServing.values.allSatisfy { $0.amount.isFinite && $0.amount >= 0 }
    }
}

struct DiaryEntry: Identifiable, Codable {
    var id: String = UUID().uuidString
    var memberID: String
    var memberName: String
    var eatenAt: Date
    var mealKind: Int
    // Week + slot identity: 0-0 must not accidentally match next week's 0-0.
    var planKey: String? = nil
    var foods: [DiaryFood]
    var note: String = ""
    var timeEstimated: Bool = false
    var updatedAt: Date = .now
    var kcal: Double? {
        let values = foods.compactMap(\.kcal)
        return values.count == foods.count && !values.isEmpty ? values.reduce(0, +) : nil
    }
    var isValid: Bool { (0...3).contains(mealKind) && !foods.isEmpty && foods.count <= 30 &&
        foods.allSatisfy(\.isValid) && note.count <= 2000 && !memberID.isEmpty }
}

struct PreparedDish: Identifiable, Codable {
    var id: String = UUID().uuidString
    var food: DiaryFood
    var totalServings: Double
    var preparedAt: Date
    var useBy: Date
    var updatedAt: Date = .now
    var discardedAt: Date? = nil
    // A physical batch, not an endlessly reusable "ready" flag.
    func remaining(in entries: [DiaryEntry]) -> Double {
        guard discardedAt == nil else { return 0 }
        let used = entries.flatMap(\.foods).filter { $0.preparedDishID == id }.reduce(0) { $0 + $1.servings }
        return max(0, totalServings - used)
    }
}

enum DiaryCore {
    static func planKey(startDate: Date, slotID: String, memberID: String) -> String {
        "\(Int(startDate.timeIntervalSince1970))|\(slotID)|\(memberID)"
    }
    static func visible(_ state: DemoState) -> [DiaryEntry] {
        (state.diaryEntries ?? []).filter { entry in
            (state.diaryDeletedAt?[entry.id]).map { $0 < entry.updatedAt } ?? true
        }.sorted { ($0.eatenAt, $0.id) < ($1.eatenAt, $1.id) }
    }
    static func total(_ entries: [DiaryEntry], key: String) -> (amount: Double, unit: String, unknown: Int) {
        let foods = entries.flatMap(\.foods)
        let values = foods.compactMap { $0.nutrients[key] }
        return (values.reduce(0) { $0 + $1.amount }, values.first?.unit ?? "г", foods.count - values.count)
    }
    static func preparationLabel(_ kind: Int) -> String {
        L10n.text(["Завтрак", "Обед", "Ужин", "Перекус"][min(3, max(0, kind))])
    }
    static func csv(_ entries: [DiaryEntry]) -> String {
        // Stable machine-readable column names; an empty cell means unknown,
        // not zero. RFC 4180 quoting and spreadsheet formula-injection defense.
        let keys = NutrientGuide.displayOrder
        let columns = ["entry_id", "person", "eaten_at", "meal", "food", "base_servings", "actual_weight_g",
                       "preparation", "kcal", "time_estimated", "prepared_batch_id", "note"] + keys.flatMap { [$0, $0 + "_unit"] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso.timeZone = .current
        func number(_ value: Double?) -> String { value.map { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "" }
        func cell(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = ["=", "+", "-", "@"].contains(where: { trimmed.hasPrefix($0) }) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [columns.map(cell).joined(separator: ",")]
        for entry in entries.sorted(by: { $0.eatenAt < $1.eatenAt }) {
            for food in entry.foods {
                var values = [entry.id, entry.memberName, iso.string(from: entry.eatenAt), preparationLabel(entry.mealKind),
                              food.displayTitle, number(food.servings), number(food.actualWeightGrams),
                              L10n.text(food.preparation.label), number(food.kcal), entry.timeEstimated ? "true" : "false",
                              food.preparedDishID ?? "", entry.note]
                for key in keys {
                    let unit = food.nutrients[key]?.unit ?? ""
                    values += [number(food.nutrients[key]?.amount), ["г": "g", "мг": "mg", "мкг": "mcg", "мл": "ml"][unit] ?? unit]
                }
                rows.append(values.map(cell).joined(separator: ","))
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
    }
}

struct PersonalCloudSnapshot: Codable {
    var schemaVersion: Int = 1
    var state: DemoState
    var modifiedAt: Date
    var deviceID: String
    var language: String?

    static func merge(_ local: Self, _ remote: Self) -> Self {
        let remoteWins = (remote.modifiedAt, remote.deviceID) > (local.modifiedAt, local.deviceID)
        var result = remoteWins ? remote : local
        var deleted = local.state.diaryDeletedAt ?? [:]
        for (id, date) in remote.state.diaryDeletedAt ?? [:] { deleted[id] = max(deleted[id] ?? .distantPast, date) }
        var entries: [String: DiaryEntry] = [:]
        for entry in (local.state.diaryEntries ?? []) + (remote.state.diaryEntries ?? []) {
            if entries[entry.id].map({ $0.updatedAt <= entry.updatedAt }) ?? true { entries[entry.id] = entry }
        }
        result.state.diaryEntries = entries.values.sorted { $0.id < $1.id }
        result.state.diaryDeletedAt = deleted
        var batches: [String: PreparedDish] = [:]
        for batch in (local.state.preparedDishes ?? []) + (remote.state.preparedDishes ?? []) {
            if batches[batch.id].map({ $0.updatedAt <= batch.updatedAt }) ?? true { batches[batch.id] = batch }
        }
        result.state.preparedDishes = batches.values.sorted { $0.id < $1.id }
        result.state.ingredientPrices = FoodCost.merge(local.state.ingredientPrices ?? [], remote.state.ingredientPrices ?? [])
        // Weight history stays on this device, including when an older pilot
        // cloud snapshot is applied. It is never part of a CloudKit upload.
        result.state.weightEntries = local.state.weightEntries
        result.state.activeCourseIDs = CourseAliases.canonical(result.state.activeCourseIDs ?? [CourseAliases.mediterranean])
        // Reconcile meal marks against merged facts, including removed facts.
        for slot in result.state.slots {
            for member in result.state.members {
                let key = DiaryCore.planKey(startDate: result.state.startDate, slotID: slot.id, memberID: member.id)
                let hasHistory = entries.values.contains { $0.planKey == key }
                if hasHistory {
                    let mark = "\(slot.id)-\(member.id)"
                    if DiaryCore.visible(result.state).contains(where: { $0.planKey == key }) { result.state.eatenIDs.insert(mark) }
                    else { result.state.eatenIDs.remove(mark) }
                }
            }
        }
        return result
    }
}

extension LadStore {
    var diary: [DiaryEntry] { DiaryCore.visible(state) }
    func diaryEntry(for slot: MealSlot, memberID: String? = nil) -> DiaryEntry? {
        let key = DiaryCore.planKey(startDate: state.startDate, slotID: slot.id, memberID: memberID ?? currentMember.id)
        return diary.last { $0.planKey == key }
    }
    func diaryDraft(for slot: MealSlot) -> DiaryEntry {
        if let entry = diaryEntry(for: slot) { return entry }
        let day = Calendar.current.date(byAdding: .day, value: slot.day, to: state.startDate) ?? now
        let time = Calendar.current.isDate(day, inSameDayAs: now) ? now :
            Calendar.current.date(bySettingHour: mealSchedule.endMinute(for: slot.kind) / 60,
                                  minute: mealSchedule.endMinute(for: slot.kind) % 60, second: 0, of: day) ?? day
        let foods = recipes(slot).filter { !$0.isUnavailable }.map { recipe -> DiaryFood in
            let portions = portion(for: currentMember, recipe: recipe, slot: slot)
            var food = DiaryFood(recipe: recipe, servings: portions)
            if let batchID = slot.preparedDishIDs?[recipe.id],
               let batch = state.preparedDishes?.first(where: { $0.id == batchID && $0.discardedAt == nil }) {
                food = batch.food
                food.id = UUID().uuidString
                food.servings = portions
                food.preparedDishID = batchID
                food.preparation = .readyCold
            }
            return food
        }
        let planKey = DiaryCore.planKey(startDate: state.startDate, slotID: slot.id, memberID: currentMember.id)
        return DiaryEntry(id: "meal|" + planKey, memberID: currentMember.id, memberName: currentMember.name, eatenAt: min(time, now),
                          mealKind: slot.kind, planKey: DiaryCore.planKey(startDate: state.startDate, slotID: slot.id,
                                                                       memberID: currentMember.id), foods: foods)
    }
    @discardableResult func saveDiaryEntry(_ entry: DiaryEntry) -> Bool {
        guard entry.isValid, entry.eatenAt <= now.addingTimeInterval(60) else { return false }
        // Validate physical stock against all other facts before accepting edits.
        for batchID in Set(entry.foods.compactMap(\.preparedDishID)) {
            guard let batch = state.preparedDishes?.first(where: { $0.id == batchID }),
                  entry.eatenAt >= batch.preparedAt,
                  Calendar.current.startOfDay(for: entry.eatenAt) <= Calendar.current.startOfDay(for: batch.useBy),
                  entry.foods.filter({ $0.preparedDishID == batchID }).allSatisfy({ $0.recipeID == batch.food.recipeID }) else { return false }
            let needed = entry.foods.filter { $0.preparedDishID == batchID }.reduce(0) { $0 + $1.servings }
            if batch.discardedAt != nil {
                let previous = diary.first(where: { $0.id == entry.id })?.foods.filter { $0.preparedDishID == batchID }.reduce(0) { $0 + $1.servings } ?? 0
                guard needed <= previous + 0.001 else { return false }
                continue
            }
            guard needed <= batch.remaining(in: diary.filter { $0.id != entry.id }) + 0.001 else { return false }
        }
        var next = state
        var saved = entry
        saved.updatedAt = .now
        next.diaryEntries = (next.diaryEntries ?? []).filter { $0.id != entry.id } + [saved]
        next.diaryDeletedAt?.removeValue(forKey: entry.id)
        if let planKey = entry.planKey {
            for slot in next.slots where planKey == DiaryCore.planKey(startDate: next.startDate, slotID: slot.id, memberID: entry.memberID) {
                next.eatenIDs.insert("\(slot.id)-\(entry.memberID)")
                next.skippedSlotIDs?.remove(slot.id)
            }
        }
        state = next
        return true
    }
    func removeDiaryEntry(_ entry: DiaryEntry) {
        var next = state
        var deleted = next.diaryDeletedAt ?? [:]
        deleted[entry.id] = .now
        next.diaryDeletedAt = deleted
        if let planKey = entry.planKey {
            for slot in next.slots where planKey == DiaryCore.planKey(startDate: next.startDate, slotID: slot.id, memberID: entry.memberID) {
                next.eatenIDs.remove("\(slot.id)-\(entry.memberID)")
            }
        }
        state = next
    }
    var preparedDishes: [PreparedDish] {
        (state.preparedDishes ?? []).filter { $0.discardedAt == nil && $0.remaining(in: diary) > 0.001 }
            .sorted { $0.useBy < $1.useBy }
    }
    func savePreparedDish(_ dish: PreparedDish, cookedRecipe: Recipe? = nil, consumePantry: Bool = false) {
        guard dish.totalServings.isFinite, dish.totalServings > 0, dish.totalServings <= 100,
              dish.food.isValid, dish.useBy >= dish.preparedAt else { return }
        var next = state
        let isNew = !(next.preparedDishes ?? []).contains { $0.id == dish.id }
        if isNew && consumePantry, let recipe = cookedRecipe {
            var items = pantry.map(IngredientMeasures.normalized)
            for ingredient in recipe.ingredients.map(IngredientMeasures.normalized) {
                guard let amount = ingredient.amount else { continue }
                var needed = amount * dish.totalServings / max(1, recipe.baseServings)
                let indices = items.indices.sorted { (items[$0].expiresOn ?? .distantFuture) < (items[$1].expiresOn ?? .distantFuture) }
                for index in indices where needed > 0 && PlanningCore.key(items[index].name, items[index].unit) == PlanningCore.key(ingredient.name, ingredient.unit) {
                    guard let available = items[index].quantity,
                          items[index].expiresOn.map({ Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: dish.preparedAt) }) ?? true else { continue }
                    let taken = min(needed, max(0, available))
                    items[index].quantity = available - taken
                    needed -= taken
                }
            }
            next.pantryItems = items
        }
        next.preparedDishes = (next.preparedDishes ?? []).filter { $0.id != dish.id } + [dish]
        state = next
    }
    func discardPreparedDish(_ dish: PreparedDish) {
        guard let index = state.preparedDishes?.firstIndex(where: { $0.id == dish.id }) else { return }
        var next = state
        next.preparedDishes?[index].discardedAt = .now
        next.preparedDishes?[index].updatedAt = .now
        state = next
    }
    func attachPreparedDish(_ dish: PreparedDish, to slot: MealSlot) -> Bool {
        guard !isSkipped(slot), !state.eatenIDs.contains(where: { $0.hasPrefix(slot.id + "-") }),
              let recipeID = dish.food.recipeID, slot.allRecipeIDs.contains(recipeID),
              dish.remaining(in: diary) > 0, dish.discardedAt == nil,
              state.preparedDishes?.contains(where: { $0.id == dish.id && $0.discardedAt == nil }) == true,
              let index = state.slots.firstIndex(where: { $0.id == slot.id }) else { return false }
        let day = Calendar.current.date(byAdding: .day, value: slot.day, to: state.startDate) ?? now
        guard Calendar.current.startOfDay(for: day) <= Calendar.current.startOfDay(for: dish.useBy),
              Calendar.current.startOfDay(for: day) >= Calendar.current.startOfDay(for: dish.preparedAt) else { return false }
        var next = state
        var attached = next.slots[index].preparedDishIDs ?? [:]
        attached[recipeID] = dish.id
        next.slots[index].preparedDishIDs = attached
        state = next
        return true
    }
}
