import Foundation

enum EnergySex: String, Codable, CaseIterable {
    case female, male
    var label: String { self == .female ? "Женский" : "Мужской" }
}

enum EnergyActivity: String, Codable, CaseIterable {
    case inactive, lowActive, active, veryActive
    var label: String {
        switch self {
        case .inactive: return "Малоподвижный"
        case .lowActive: return "Немного активный"
        case .active: return "Активный"
        case .veryActive: return "Очень активный"
        }
    }
}

enum EnergyContext: String, Codable, CaseIterable {
    case standard, pregnancyOrLactation, specialDiet
    var label: String {
        switch self {
        case .standard: return "Обычный взрослый рацион"
        case .pregnancyOrLactation: return "Беременность или кормление"
        case .specialDiet: return "Особый рацион со специалистом"
        }
    }
}

enum PersonalPortions {
    // National Academies, Dietary Reference Intakes for Energy (2023).
    // Table 5-16 is the adult maintenance EER. Table 5-15 is the child and
    // adolescent EER, including the energy cost of growth from that chapter.
    // Body composition is neither requested nor inferred. Pregnancy,
    // breastfeeding and a specialist diet are excluded from both equations.
    // `energyTarget` and `foodMultiplier` stay on the adult opt-in path.
    // The plate size is a separate share so a filled age or goal still
    // changes the portion when that path does not run.
    static let sourceURL = URL(string: "https://www.nationalacademies.org/read/26818/chapter/7")!
    /// Label reference used only to turn a daily energy figure into a
    /// fraction of the authored adult serving. It is not a personal target.
    static let referenceEnergy = 2000.0
    static func estimatedEnergy(_ member: FamilyMember) -> Double? {
        guard let age = member.ageYears, (19...120).contains(age),
              let height = member.heightCm, height.isFinite, (50...250).contains(height),
              let weight = member.weightKg, weight.isFinite, (10...500).contains(weight),
              let sex = member.energySex, let activity = member.energyActivity,
              member.energyContext == .standard else { return nil }
        let coefficients: (Double, Double, Double, Double)
        switch (sex, activity) {
        case (.male, .inactive): coefficients = (753.07, -10.83, 6.50, 14.10)
        case (.male, .lowActive): coefficients = (581.47, -10.83, 8.30, 14.94)
        case (.male, .active): coefficients = (1004.82, -10.83, 6.52, 15.91)
        case (.male, .veryActive): coefficients = (-517.88, -10.83, 15.61, 19.11)
        case (.female, .inactive): coefficients = (584.90, -7.01, 5.72, 11.71)
        case (.female, .lowActive): coefficients = (575.77, -7.01, 6.60, 12.14)
        case (.female, .active): coefficients = (710.25, -7.01, 6.54, 12.34)
        case (.female, .veryActive): coefficients = (511.83, -7.01, 9.07, 12.56)
        }
        let value = coefficients.0 + coefficients.1 * Double(age) + coefficients.2 * height + coefficients.3 * weight
        return value.isFinite && value > 0 ? value : nil
    }

    /// Table 5-15 for ages 3–18. Activity, sex, height and weight are all
    /// required. A missing activity is not treated as inactive.
    static func youthEnergy(_ member: FamilyMember) -> Double? {
        guard let age = member.ageYears, (3...18).contains(age),
              let height = member.heightCm, height.isFinite, (50...250).contains(height),
              let weight = member.weightKg, weight.isFinite, (10...500).contains(weight),
              let sex = member.energySex, let activity = member.energyActivity,
              member.energyContext != .pregnancyOrLactation,
              member.energyContext != .specialDiet else { return nil }
        let coefficients: (Double, Double, Double, Double)
        switch (sex, activity) {
        case (.male, .inactive): coefficients = (-447.51, 3.68, 13.01, 13.15)
        case (.male, .lowActive): coefficients = (19.12, 3.68, 8.62, 20.28)
        case (.male, .active): coefficients = (-388.19, 3.68, 12.66, 20.46)
        case (.male, .veryActive): coefficients = (-671.75, 3.68, 15.38, 23.25)
        case (.female, .inactive): coefficients = (55.59, -22.25, 8.43, 17.07)
        case (.female, .lowActive): coefficients = (-297.54, -22.25, 12.77, 14.73)
        case (.female, .active): coefficients = (-189.55, -22.25, 11.74, 18.34)
        case (.female, .veryActive): coefficients = (-709.59, -22.25, 18.22, 14.25)
        }
        let growth: Double
        switch (sex, age) {
        case (.male, 3): growth = 20
        case (.female, 3): growth = 15
        case (_, 4...8): growth = 15
        case (.male, 9...13): growth = 25
        case (.female, 9...13): growth = 30
        case (_, 14...18): growth = 20
        default: growth = 0
        }
        let value = coefficients.0 + coefficients.1 * Double(age) + coefficients.2 * height + coefficients.3 * weight + growth
        return value.isFinite && value > 0 ? value : nil
    }

    /// Energy used for the plate. Nil context uses the ordinary adult equation
    /// here only. `estimatedEnergy` itself still requires an explicit standard
    /// context, so the menu target and the day fit do not change.
    static func plateEnergy(_ member: FamilyMember) -> Double? {
        guard !isSpecialContext(member) else { return nil }
        var ordinary = member
        if ordinary.energyContext == nil { ordinary.energyContext = .standard }
        if let adult = estimatedEnergy(ordinary) { return adult }
        return youthEnergy(member)
    }

    static func isSpecialContext(_ member: FamilyMember) -> Bool {
        member.energyContext == .pregnancyOrLactation || member.energyContext == .specialDiet
    }

    /// The app used to store `false` for every child. A slider that is still
    /// exactly 100% was that default, not a size the household chose.
    /// `DemoState.migratePortionRules` clears it once. After that, `false`
    /// means the person turned manual portions on.
    static func isExplicitManual(_ member: FamilyMember) -> Bool {
        member.automaticPortions == false
    }

    /// Household plate scale for an adult goal. 15% either way, and only when
    /// the person did not type their own daily calories. Not a prescribed diet.
    static func goalScale(_ member: FamilyMember) -> Double {
        guard (member.ageYears ?? 0) >= 18 else { return 1 }
        if let manual = member.dailyEnergyTarget, (1000...5000).contains(manual) { return 1 }
        switch member.goal {
        case "Снижение": return 0.85
        case "Набор": return 1.15
        default: return 1
        }
    }

    /// Sedentary midpoint from the Dietary Guidelines for Americans 2020–2025,
    /// Appendix 2, divided by the 2,000 kcal label reference. Used only when
    /// sex, height, weight or activity is missing, so those fields are not guessed.
    static func ageBandShare(_ age: Int) -> Double? {
        switch age {
        case 2...3: return 0.50
        case 4...8: return 0.65
        case 9...13: return 0.80
        case 14...18: return 1
        default: return nil
        }
    }

    static func usesCalculatedShare(_ member: FamilyMember) -> Bool {
        if isExplicitManual(member) || isSpecialContext(member) { return false }
        if member.ageYears != nil { return true }
        if let manual = member.dailyEnergyTarget, (1000...5000).contains(manual) { return true }
        return plateEnergy(member) != nil
    }

    /// Fraction of the authored serving. Manual mode and excluded life stages
    /// keep the stored slider. A typed daily calorie figure replaces the
    /// equation and the goal scale.
    static func profileShare(_ member: FamilyMember) -> Double {
        if isExplicitManual(member) || isSpecialContext(member) { return member.portion }
        if let manual = member.dailyEnergyTarget, (member.ageYears ?? 0) >= 18, (1000...5000).contains(manual) {
            return clampShare(Double(manual) / referenceEnergy, upper: 1.6)
        }
        if let energy = plateEnergy(member) {
            return clampShare(energy * goalScale(member) / referenceEnergy, upper: 1.6)
        }
        if let age = member.ageYears, let band = ageBandShare(age) {
            return clampShare(band * goalScale(member), upper: 1.6)
        }
        return clampShare(member.portion * goalScale(member), upper: 1.6)
    }

    /// The day the profile share stands for, once the plate follows the menu.
    /// Nil when the stored slider is used as is (manual, special, under 2).
    static func profileDailyEnergy(_ member: FamilyMember) -> Double? {
        guard usesCalculatedShare(member) else { return nil }
        if let age = member.ageYears, age < 2 { return nil }
        return profileShare(member) * referenceEnergy
    }

    static func percent(_ share: Double) -> Int {
        Int((share * 100).rounded())
    }

    private static func clampShare(_ value: Double, upper: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(upper, max(0.4, value))
    }

    static func energyTarget(_ member: FamilyMember) -> Double? {
        if (member.ageYears ?? 0) >= 18, let manual = member.dailyEnergyTarget, (1000...5000).contains(manual) {
            return Double(manual)
        }
        return member.automaticPortions == true ? estimatedEnergy(member) : nil
    }

    static func recipeIndex(_ recipes: [Recipe]) -> [String: Recipe] {
        Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func foodMultiplier(member: FamilyMember, day: Int, slots: [MealSlot], recipes: [Recipe],
                               skippedIDs: Set<String>) -> Double? {
        foodMultiplier(member: member, day: day, slots: slots, byID: recipeIndex(recipes), skippedIDs: skippedIDs)
    }

    static func foodMultiplier(member: FamilyMember, day: Int, slots: [MealSlot], byID: [String: Recipe],
                               skippedIDs: Set<String>) -> Double? {
        guard member.automaticPortions == true, estimatedEnergy(member) != nil,
              let target = energyTarget(member) else { return nil }
        let meals = slots.filter { $0.day == day && $0.memberIDs.contains(member.id) && !skippedIDs.contains($0.id) }
        // Do not redistribute a whole day's energy into an incomplete plan.
        let mainMeals = meals.filter { $0.kind != 3 }
        guard mainMeals.count == 3, Set(mainMeals.map(\.kind)) == Set(0..<3),
              meals.filter({ $0.kind == 3 }).count <= 1 else { return nil }
        var foodEnergy = 0.0
        var drinkEnergy = 0.0
        for meal in meals {
            guard let main = byID[meal.recipeID], !main.isBeverage else { return nil }
            for id in meal.allRecipeIDs {
                guard let dish = byID[id], !dish.isUnplanned, !dish.isUnavailable,
                      let kcal = dish.kcal, kcal >= 0 else { return nil }
                if dish.isBeverage || meal.kind == 3 { drinkEnergy += Double(kcal) * member.portion }
                else { foodEnergy += Double(kcal) }
            }
        }
        guard foodEnergy > 0, target > drinkEnergy else { return nil }
        // Guard against extreme scaling of an unsuitable menu; callers expose
        // the remaining energy difference. This is a UI limit, not a DRI norm.
        return min(3, max(0.5, (target - drinkEnergy) / foodEnergy))
    }

    static func multiplier(member: FamilyMember, recipe: Recipe, day: Int, slots: [MealSlot],
                           recipes: [Recipe], skippedIDs: Set<String>) -> Double {
        multiplier(member: member, recipe: recipe, day: day, slots: slots, byID: recipeIndex(recipes), skippedIDs: skippedIDs)
    }

    static func multiplier(member: FamilyMember, recipe: Recipe, day: Int, slots: [MealSlot],
                           byID: [String: Recipe], skippedIDs: Set<String>) -> Double {
        // Drink and optional snack doses stay at their chosen serving size.
        guard !recipe.isBeverage, !recipe.mealKinds.contains(3) else { return member.portion }
        return foodShare(member: member, day: day, slots: slots, byID: byID, skippedIDs: skippedIDs)
    }

    /// Servings of every food dish this person gets on `day`. It does not
    /// depend on the dish, so callers may compute it once per person and day.
    static func foodShare(member: FamilyMember, day: Int, slots: [MealSlot],
                          byID: [String: Recipe], skippedIDs: Set<String>) -> Double {
        if isExplicitManual(member) || isSpecialContext(member) { return member.portion }
        if let fitted = foodMultiplier(member: member, day: day, slots: slots, byID: byID, skippedIDs: skippedIDs) {
            return min(menuCeiling(member), clampShare(fitted * goalScale(member), upper: 3))
        }
        // A partial day is not rescaled onto the adult equation. The stored
        // serving remains the fallback only after that equation was requested.
        if member.automaticPortions == true, estimatedEnergy(member) != nil {
            return clampShare(member.portion * goalScale(member), upper: 1.6)
        }
        if let fitted = menuFittedShare(member: member, day: day, slots: slots, byID: byID, skippedIDs: skippedIDs) {
            return fitted
        }
        return profileShare(member)
    }

    /// One authored serving is already an adult plate. The default course is
    /// light (roughly 650–1,100 kcal a day at one serving), and stretching it
    /// to a whole day's energy doubled every dish: eight cottage-cheese
    /// pancakes for a breakfast, 1.5 servings for a five-year-old. A light
    /// menu may raise the plate by at most a quarter over the profile share,
    /// which is the plate of a 1,600 kcal reference day. The rest of the day
    /// comes from the optional snack, fruit or bread; Statistics shows the gap.
    static let maxMenuStretch = 1.25

    static func menuCeiling(_ member: FamilyMember) -> Double {
        profileShare(member) * maxMenuStretch
    }

    /// `profileShare` is a share of a 2,000 kcal reference day. The authored
    /// servings of a course do not add up to that: the default course gives
    /// roughly 650–1,100 kcal a day at one serving. Applying the share to
    /// those servings left children (65–80%) with a few hundred kcal a day.
    /// For anyone whose share comes from age, goal or a typed calorie figure,
    /// fit it to the household's actual menu for that day, within
    /// `maxMenuStretch`. The relation between people stays the same
    /// (85% vs 100% vs 65%). A day without three planned
    /// meals with known calories borrows the average of the complete days.
    static func menuFittedShare(member: FamilyMember, day: Int, slots: [MealSlot],
                                byID: [String: Recipe], skippedIDs: Set<String>) -> Double? {
        guard !isExplicitManual(member), !isSpecialContext(member), member.ageYears != nil ||
                (member.dailyEnergyTarget.map { (1000...5000).contains($0) } ?? false) else { return nil }
        // Infants are outside the age bands; keep their stored slider.
        if let age = member.ageYears, age < 2 { return nil }
        let need = profileShare(member) * referenceEnergy
        let menu = householdMenuEnergy(day: day, slots: slots, byID: byID, skippedIDs: skippedIDs) ?? {
            let days = Set(slots.map(\.day)).sorted()
            let complete = days.compactMap { householdMenuEnergy(day: $0, slots: slots, byID: byID, skippedIDs: skippedIDs) }
            return complete.isEmpty ? nil : complete.reduce(0, +) / Double(complete.count)
        }()
        guard let menu, menu > 0 else { return nil }
        let fixed = fixedEnergy(member: member, day: day, slots: slots, byID: byID, skippedIDs: skippedIDs)
        guard need > fixed else { return nil }
        // A hearty menu shrinks the plate; a light one stretches it only up to
        // the ceiling. Callers show what is left of the day.
        return min(menuCeiling(member), max(0.4, (need - fixed) / menu))
    }

    /// Food energy of one serving of each planned breakfast, lunch and dinner
    /// on `day`, independent of who eats which meal. Nil when a main meal is
    /// missing, skipped, unavailable or has unknown calories.
    static func householdMenuEnergy(day: Int, slots: [MealSlot], byID: [String: Recipe],
                                    skippedIDs: Set<String>) -> Double? {
        let mains = slots.filter { $0.day == day && $0.kind != 3 }
        guard Set(mains.map(\.kind)) == Set(0..<3),
              !mains.contains(where: { skippedIDs.contains($0.id) || $0.memberIDs.isEmpty }) else { return nil }
        var total = 0.0
        for meal in mains {
            guard let main = byID[meal.recipeID], !main.isBeverage, !main.isUnplanned, !main.isUnavailable else { return nil }
            for id in meal.allRecipeIDs {
                guard let dish = byID[id], !dish.isUnplanned, !dish.isUnavailable else { return nil }
                if dish.isBeverage { continue }
                guard let kcal = dish.kcal, kcal >= 0 else { return nil }
                total += Double(kcal)
            }
        }
        return total > 0 ? total : nil
    }

    /// Drinks and the optional snack keep their fixed size; their energy is
    /// taken out of the day before the food plate is sized.
    static func fixedEnergy(member: FamilyMember, day: Int, slots: [MealSlot], byID: [String: Recipe],
                            skippedIDs: Set<String>) -> Double {
        var total = 0.0
        for meal in slots where meal.day == day && meal.memberIDs.contains(member.id) && !skippedIDs.contains(meal.id) {
            for id in meal.allRecipeIDs {
                guard let dish = byID[id], let kcal = dish.kcal, dish.isBeverage || meal.kind == 3 else { continue }
                total += Double(kcal) * member.portion
            }
        }
        return total
    }
}

/// What an adult still lacks versus a weight-based maintenance estimate.
/// Protein uses the adult RDA of 0.8 g per kg (NIH ODS). Energy uses the same
/// National Academies equation as `PersonalPortions`. Fat, carbohydrate and
/// fiber use the lower AMDR bounds and the fiber adequate intake of 14 g per
/// 1,000 kcal. These are ranking and chart scales, not a prescribed diet.
enum WeightGap {
    static let proteinGramsPerKilogram = 0.8
    static let proteinEnergyFloor = 0.10
    static let carbohydrateEnergyFloor = 0.45
    static let fatEnergyFloor = 0.20
    static let fiberGramsPerThousandKcal = 14.0

    struct Targets: Equatable {
        var energy: Double
        var protein: Double
        var fat: Double
        var carbohydrate: Double
        var fiber: Double
    }

    struct Intake: Equatable {
        var energy: Double = 0
        var protein: Double = 0
        var fat: Double = 0
        var carbohydrate: Double = 0
        var fiber: Double = 0

        func gap(against targets: Targets) -> Intake {
            Intake(energy: max(0, targets.energy - energy),
                   protein: max(0, targets.protein - protein),
                   fat: max(0, targets.fat - fat),
                   carbohydrate: max(0, targets.carbohydrate - carbohydrate),
                   fiber: max(0, targets.fiber - fiber))
        }

        func adding(_ other: Intake) -> Intake {
            Intake(energy: energy + other.energy, protein: protein + other.protein,
                   fat: fat + other.fat, carbohydrate: carbohydrate + other.carbohydrate,
                   fiber: fiber + other.fiber)
        }
    }

    static func targets(for member: FamilyMember) -> Targets? {
        guard let age = member.ageYears, (19...120).contains(age),
              member.energyContext != .pregnancyOrLactation,
              member.energyContext != .specialDiet,
              let weight = member.weightKg, weight.isFinite, (10...500).contains(weight) else { return nil }
        let energy = PersonalPortions.energyTarget(member) ?? PersonalPortions.estimatedEnergy(member)
        guard let energy, energy.isFinite, energy > 0 else { return nil }
        let proteinFromWeight = proteinGramsPerKilogram * weight
        let proteinFromEnergy = energy * proteinEnergyFloor / 4
        return Targets(energy: energy,
                       protein: max(proteinFromWeight, proteinFromEnergy),
                       fat: energy * fatEnergyFloor / 9,
                       carbohydrate: energy * carbohydrateEnergyFloor / 4,
                       fiber: energy / 1000 * fiberGramsPerThousandKcal)
    }

    static func amount(_ targets: Targets, key: String) -> Double? {
        switch key {
        case "protein": return targets.protein
        case "fat": return targets.fat
        case "carbohydrate": return targets.carbohydrate
        case "fiber": return targets.fiber
        default: return nil
        }
    }

    /// Scale a bar to the target when one exists. `missing` is what is still short.
    static func remainder(consumed: Double, target: Double?) -> (scale: Double, missing: Double) {
        let consumed = consumed.isFinite ? max(0, consumed) : 0
        guard let target, target.isFinite, target > 0 else { return (consumed, 0) }
        return (max(consumed, target), max(0, target - consumed))
    }

    /// How much one serving closes the remaining gap, in about -0.35...1.
    /// Protein is counted twice because it is the term that comes straight from weight.
    /// Overflow past the remaining gap lowers the score. This only ranks meals.
    static func closure(offered: Intake, remaining: Intake, targets: Targets) -> Double {
        func part(_ have: Double, _ need: Double, _ target: Double) -> Double {
            guard target > 0, have.isFinite else { return 0 }
            let useful = min(max(0, have), max(0, need))
            let overflow = min(target, max(0, have - max(0, need)))
            return useful / target - 0.35 * overflow / target
        }
        let parts = [
            part(offered.energy, remaining.energy, targets.energy),
            part(offered.protein, remaining.protein, targets.protein),
            part(offered.protein, remaining.protein, targets.protein),
            part(offered.fat, remaining.fat, targets.fat),
            part(offered.carbohydrate, remaining.carbohydrate, targets.carbohydrate),
            part(offered.fiber, remaining.fiber, targets.fiber)
        ]
        return parts.reduce(0, +) / Double(parts.count)
    }
}

struct ShoppingNeed: Identifiable {
    let id: String
    let name: String
    let unit: String
    let category: String
    let required: Double
    let available: Double
    let amountUnknown: Bool
    let aiEstimated: Bool
    let sourceSlots: [String]

    var missing: Double { max(0, required - available) }
}

struct RecipeReadiness {
    let covered: Int
    let total: Int
    let missing: [String]
    let uncertain: [String]
}

enum SlotAvailability: Equatable {
    case active
    case past
    case eaten
    case noParticipants
    case unavailable
    case needsReview
    case skipped
}

struct ResolvedIngredient: Identifiable {
    let id: String
    let name: String
    let unit: String
    let category: String
    let required: Double?
    let allocated: Double
    let uncertain: Bool

    var shortage: Double? { required.map { max(0, $0 - allocated) } }
    var isReady: Bool { required != nil && (shortage ?? 0) < 0.001 && !uncertain }
}

struct SlotRequirements {
    let slotID: String
    let recipeID: String
    let availability: SlotAvailability
    let ingredients: [ResolvedIngredient]
    var preparedServings: Double = 0

    var isReady: Bool { availability == .active && ingredients.allSatisfy(\.isReady) }
    var hasUncertainty: Bool { ingredients.contains { $0.required == nil || $0.uncertain } }
    var shortageCount: Int { ingredients.filter { ($0.shortage ?? 0) > 0.001 }.count }
    var missingNames: [String] { ingredients.filter { ($0.shortage ?? 0) > 0.001 || $0.required == nil }.map(\.name) }
}

struct PlanRequirements {
    let slots: [String: SlotRequirements]
    let shoppingNeeds: [ShoppingNeed]
    let inventoryEmpty: Bool
    let freePantry: [PantryItem]
}

struct MealSchedule: Codable, Equatable {
    var breakfastEnds: Int = 10 * 60
    var lunchEnds: Int = 14 * 60
    var dinnerEnds: Int = 19 * 60
    // Resolved at runtime; optional for backwards-compatible personal schedules.
    var snackMinute: Int? = nil

    static let standard = MealSchedule()

    func endMinute(for kind: Int) -> Int {
        switch kind {
        case 0: breakfastEnds
        case 1: lunchEnds
        case 3: snackMinute ?? max(0, lunchEnds - 60)
        default: dinnerEnds
        }
    }

    var isValid: Bool {
        (0..<24 * 60).contains(breakfastEnds) && breakfastEnds < lunchEnds &&
        lunchEnds < dinnerEnds && dinnerEnds <= 24 * 60
    }
}

enum MealTiming {
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func suggestedKind(on day: Int, currentDay: Int, now: Date, schedule: MealSchedule,
                              calendar: Calendar = .current, eatenKinds: Set<Int> = []) -> Int? {
        guard day >= currentDay else { return nil }
        if day > currentDay { return (0..<3).first { !eatenKinds.contains($0) } }
        let minute = minuteOfDay(now, calendar: calendar)
        return (0..<3).first { !eatenKinds.contains($0) && minute < schedule.endMinute(for: $0) }
    }

    static func isPastWindow(day: Int, kind: Int, currentDay: Int, now: Date,
                             schedule: MealSchedule, calendar: Calendar = .current) -> Bool {
        day < currentDay || (day == currentDay && minuteOfDay(now, calendar: calendar) >= schedule.endMinute(for: kind))
    }
}

enum ProductNames {
    // Only interchangeable product names belong here. Related but different foods
    // (for example mushrooms and champignons, or lemon and lemon juice) stay separate.
    private static let equivalents: [[String]] = [
        ["томат", "томаты", "помидор", "помидоры", "tomato", "tomatoes"],
        ["кабачок", "кабачки", "цукини", "цуккини", "zucchini", "courgette"],
        ["картофель", "картошка", "картофелина", "картофелины", "potato", "potatoes"],
        ["морковь", "морковка", "морковки", "carrot", "carrots"],
        ["огурец", "огурцы", "cucumber", "cucumbers"],
        ["яблоко", "яблоки", "apple", "apples"],
        ["яйцо", "яйца", "egg", "eggs"],
        ["лук", "лук репчатый", "репчатый лук", "onion", "onions"],
        ["зеленый лук", "лук зеленый", "spring onion", "green onion"],
        ["перец сладкий", "сладкий перец", "болгарский перец"],
        ["сушеный чеснок", "сухой чеснок", "чеснок сушеный", "чеснок сухой"],
        ["капуста белокочанная", "белокочанная капуста"],
        ["капуста цветная", "цветная капуста"],
        ["йогурт натуральный", "натуральный йогурт", "natural yogurt", "plain yogurt", "натуральний йогурт"],
        ["йогурт греческий", "греческий йогурт", "greek yogurt", "грецький йогурт"],
        ["бурый рис", "brown rice", "бурий рис"],
        ["молоко", "milk"],
        ["творог", "cottage cheese", "кисломолочний сир"],
        ["сыр", "cheese", "сир"],
        ["куриное филе", "филе курицы"],
        ["гречка", "гречневая крупа", "buckwheat"],
        ["нут", "chickpeas", "chickpea"],
        ["булгур", "bulgur"],
        ["оливки", "olives"],
        ["грецкие орехи", "волоські горіхи", "walnuts"],
        ["шпинат", "spinach"]
    ].map { group in group.map { normalized($0) } }
    private static let canonicalNames = equivalents.reduce(into: [String: String]()) { result, group in
        guard let primary = group.first else { return }
        for name in group { result[name] = primary }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func canonical(_ name: String) -> String {
        let value = normalized(name)
        if let known = canonicalNames[value] { return known }
        return value.split(separator: " ").map { word in
            let token = String(word)
            return canonicalNames[token] ?? token
        }.joined(separator: " ")
    }

    static func matches(_ name: String, query: String) -> Bool {
        let label = normalized(name)
        let term = normalized(query)
        guard !term.isEmpty else { return true }
        if label.contains(term) { return true }
        let canonicalLabel = canonical(name)
        let canonicalTerm = canonical(query)
        if canonicalLabel == canonicalTerm || canonicalLabel.hasPrefix(canonicalTerm + " ") { return true }
        guard term.count >= 3 else { return false }
        return equivalents.contains { group in
            group.contains(where: { $0.contains(term) }) &&
            (group.contains(label) || label.split(separator: " ").contains { group.contains(String($0)) })
        }
    }
}

/// One menu warning: which products in the dish, for whom, and why.
struct DietCaution: Hashable, Identifiable {
    let products: [String]
    let people: [String]
    let reason: String
    var id: String { reason + "|" + products.joined(separator: ",") }
    var text: String {
        L10n.format("%@ — %@ (%@)", products.map { L10n.text($0) }.joined(separator: ", "),
                    people.joined(separator: ", "), L10n.text(reason))
    }
}

/// Warnings, never bans: a dish with wine still reaches a table with children
/// if the family chooses it, but the card says so. The automatic menu prefers
/// dishes without warnings for the people at that meal.
enum DietCautions {
    private static let alcohol: Set<String> = ["вино", "коньяк", "ликер", "пиво", "ром", "водка", "херес", "портвеин",
                                               "бренди", "виски", "сидр", "шампанское", "мартини", "кальвадос"]
    private static let liver: Set<String> = ["печень", "печени", "печенка"]

    static func isAlcohol(_ name: String) -> Bool { words(name).contains { alcohol.contains($0) } }

    /// Products of one dish that matter for a condition, in recipe order.
    static func products(_ recipe: Recipe, for condition: DietCondition) -> [String] {
        recipe.ingredients.map(\.name).filter { triggers(condition, $0) }
    }

    static func triggers(_ condition: DietCondition, _ name: String) -> Bool {
        let tokens = words(name)
        func starts(_ stems: [String]) -> Bool { tokens.contains { word in stems.contains { word.hasPrefix($0) } } }
        switch condition {
        case .pregnancy:
            return isAlcohol(name) || tokens.contains { liver.contains($0) } ||
                starts(["плесен", "горгонзол", "дорблю", "камамбер"]) || tokens.contains("бри")
        case .noSugar:
            return tokens.contains("мед") || starts(["сахар", "медов", "варень", "джем", "сироп", "сгущ", "шоколад", "мармелад",
                                                     "повидл", "карамел", "изюм", "кураг", "финик", "чернослив", "сухофрукт", "нутелл"])
        case .stomach:
            return isAlcohol(name) || starts(["уксус", "горчиц", "аджик", "хрен", "чили", "табаско", "васаби"])
        case .lowSalt:
            // Exact words where a stem would catch olive oil or celery.
            return tokens.contains { ["оливки", "маслины", "сельдь", "сельди"].contains($0) } ||
                starts(["соев", "фета", "брынз", "солен", "квашен", "каперс", "анчоус", "бекон", "колбас", "ветчин",
                        "пармезан", "аджик"])
        case .gout:
            return isAlcohol(name) || tokens.contains { liver.contains($0) } ||
                tokens.contains { ["сельдь", "сельди"].contains($0) } ||
                starts(["бульон", "скумбри", "сардин", "шпрот", "анчоус", "субпродукт"])
        case .eatingDisorder:
            return false
        }
    }

    /// Warnings for the dishes of one meal and the people at it. Children are
    /// people with a known age under 18; their only warning is alcohol, which
    /// is also flagged for anyone whose age is not filled in.
    static func cautions(for recipes: [Recipe], people: [FamilyMember]) -> [DietCaution] {
        var result: [DietCaution] = []
        let food = recipes.filter { !$0.isBeverage }
        func unique(_ names: [String]) -> [String] {
            var seen = Set<String>()
            return names.filter { seen.insert($0).inserted }
        }
        let drinks = unique(food.flatMap { $0.ingredients.map(\.name) }.filter(isAlcohol))
        let children = people.filter { ($0.ageYears ?? 99) < 18 }
        let unknownAge = people.filter { $0.ageYears == nil }
        if !drinks.isEmpty && !children.isEmpty {
            result.append(DietCaution(products: drinks, people: children.map(\.name), reason: "дети"))
        }
        if !drinks.isEmpty && !unknownAge.isEmpty {
            result.append(DietCaution(products: drinks, people: unknownAge.map(\.name), reason: "возраст не указан"))
        }
        for condition in DietCondition.allCases where condition != .eatingDisorder {
            let marked = people.filter { $0.conditions.contains(condition) }
            guard !marked.isEmpty else { continue }
            let found = unique(food.flatMap { products($0, for: condition) })
            if !found.isEmpty { result.append(DietCaution(products: found, people: marked.map(\.name), reason: condition.reason)) }
        }
        return result
    }

    private static func words(_ name: String) -> [String] {
        ProductNames.normalized(name).split { !$0.isLetter }.map(String.init)
    }
}

enum CookingGuide {
    /// Heat-cooked dishes name salt and pepper when the recipe left them unmeasured.
    /// The lines stay off the shopping list and do not invent a gram amount or a price.
    static func unmeasuredTaste(_ recipe: Recipe) -> [String] {
        guard !recipe.isBeverage, !recipe.steps.isEmpty, usesHeat(recipe), !isSweetWithoutMeat(recipe) else { return [] }
        let present = Set(recipe.ingredients.map { ProductNames.canonical($0.name) })
        var lines: [String] = []
        if !present.contains(ProductNames.canonical("Соль")) { lines.append("Соль") }
        if !present.contains(ProductNames.canonical("Чёрный перец")) { lines.append("Чёрный перец") }
        return lines
    }

    /// Minutes for each step: the recipe's own when it has them, otherwise the
    /// total spread by how much heat and knife work each step names.
    static func stepMinutes(_ recipe: Recipe) -> [Int] {
        let steps = recipe.steps
        guard !steps.isEmpty else { return [] }
        if recipe.stepMinutes.count == steps.count, recipe.stepMinutes.allSatisfy({ $0 >= 1 }) { return recipe.stepMinutes }
        let weights = steps.map(stepWeight)
        let weightSum = max(1, weights.reduce(0, +))
        let total = max(steps.count, recipe.minutes)
        var minutes = weights.map { max(1, Int((Double($0) * Double(total) / Double(weightSum)).rounded())) }
        var drift = minutes.reduce(0, +) - total
        var guardCount = 0
        while drift != 0, guardCount < steps.count * total + 4 {
            guardCount += 1
            if drift > 0, let index = minutes.indices.filter({ minutes[$0] > 1 }).max(by: { minutes[$0] < minutes[$1] }) {
                minutes[index] -= 1
                drift -= 1
            } else if drift < 0, let index = minutes.indices.max(by: { minutes[$0] < minutes[$1] }) {
                minutes[index] += 1
                drift += 1
            } else {
                break
            }
        }
        return minutes
    }

    private static func usesHeat(_ recipe: Recipe) -> Bool {
        let text = recipe.steps.joined(separator: " ").lowercased()
        return ["вар", "жар", "туш", "запек", "кипят", "нагре", "обжар"].contains { text.contains($0) }
    }

    private static func isSweetWithoutMeat(_ recipe: Recipe) -> Bool {
        let sweet = recipe.ingredients.contains {
            let name = ProductNames.canonical($0.name)
            return name.contains("сахар") || name == ProductNames.canonical("Мёд") || name == ProductNames.canonical("Шоколад")
        }
        let meat = recipe.ingredients.contains { $0.category == "Рыба и мясо" }
        return sweet && !meat
    }

    private static func stepWeight(_ step: String) -> Int {
        let text = step.lowercased()
        var weight = 1
        if text.contains("вар") || text.contains("туш") || text.contains("запек") || text.contains("кипят") { weight += 2 }
        if text.contains("жар") || text.contains("обжар") { weight += 2 }
        if text.contains("нарез") || text.contains("нареж") || text.contains("пореж") || text.contains("нашинк") { weight += 1 }
        if text.contains("нагре") { weight += 1 }
        return weight
    }

    /// One row of the list under a cooking step: the product, the amount for
    /// everyone at the table, and an optional kitchen measure as a hint.
    struct StepAmount: Hashable {
        let name: String
        let amount: String
        let hint: String?
    }

    /// The authored step in the reader's language. Amounts are shown apart from
    /// the sentence, so it stays readable whatever the family size is.
    static func stepText(recipe: Recipe, index: Int) -> String {
        guard recipe.steps.indices.contains(index) else { return "" }
        return L10n.text(recipe.steps[index])
    }

    /// Scaled amounts for the ingredients a step names first. Ingredients that no
    /// step names are listed with the first step, so every amount is visible while
    /// cooking. A grain boiled in this step gets its water when the recipe lists no
    /// liquid, and its salt when the step says to salt and salt is not listed.
    /// That water and salt are kitchen hints and stay off the shopping list.
    static func stepAmounts(recipe: Recipe, index: Int, portions: Double) -> [StepAmount] {
        guard recipe.steps.indices.contains(index) else { return [] }
        let scale = (portions > 0 ? portions : 1) / (recipe.baseServings > 0 ? recipe.baseServings : 1)
        let steps = recipe.steps
        let step = steps[index]
        let measured = recipe.ingredients.filter { ($0.amount ?? 0) > 0 }
        var rows: [StepAmount] = []
        let names = measured.map(\.name)
        for item in measured {
            let first = steps.firstIndex { mentions(item.name, in: $0, among: names) }
            guard first == index || (first == nil && index == 0) else { continue }
            if let row = amountRow(item, scale: scale) { rows.append(row) }
        }
        guard isBoil(step),
              let grain = measured.first(where: { boilProfile(for: $0.name) != nil && mentions($0.name, in: step) }),
              let profile = boilProfile(for: grain.name),
              !steps[..<index].contains(where: { isBoil($0) && mentions(grain.name, in: $0) }),
              let grams = scaledAmount(grain, scale: scale) else { return rows }
        let liquids = recipe.ingredients.filter { isCookingLiquid($0.name) && ($0.amount ?? 0) > 0 }
        var waterML: Double?
        if profile.pasta {
            waterML = max(1000, grams * 10)
            if liquids.isEmpty, let ml = waterML {
                rows.append(StepAmount(name: L10n.text("Вода"), amount: "≈ " + metricText(ml, liquid: true), hint: nil))
            }
        } else if liquids.isEmpty, let perGlass = gramsPerGlass(grain.name), perGlass > 0 {
            let ml = grams / perGlass * profile.water * glassML
            waterML = ml
            if ml >= 40 {
                rows.append(StepAmount(name: L10n.text("Вода"), amount: metricText(roundedML(ml), liquid: true), hint: glassHint(ml / glassML)))
            }
        } else {
            waterML = liquids.compactMap { scaledAmount($0, scale: scale) }.reduce(0, +)
        }
        let saltListed = recipe.ingredients.contains { ProductNames.canonical($0.name) == ProductNames.canonical("Соль") }
        if saysSalt(step), !saltListed {
            let drained = profile.pasta || recipe.nutrientPreparationByIngredient[grain.name] == "boiledDrained"
            let glasses = grams / (gramsPerGlass(grain.name) ?? 200)
            let teaspoons = drained ? (waterML ?? 1000) / 1000 : glasses * 0.5
            rows.append(StepAmount(name: L10n.text("Соль"), amount: spoonText(teaspoons: max(0.25, teaspoons)), hint: nil))
        }
        return rows
    }

    /// Amount as a cook reads it: metric rounded to what a kitchen scale shows,
    /// counts kept as counts, and a glass or spoon measure as a hint.
    private static func amountRow(_ ingredient: Ingredient, scale: Double) -> StepAmount? {
        guard let value = scaledAmount(ingredient, scale: scale) else { return nil }
        let unit = ProductNames.normalized(ingredient.unit)
        let name = L10n.text(ingredient.name)
        guard ["г", "гр", "кг", "мл", "л"].contains(unit) else {
            let grams = IngredientMeasures.normalized(ingredient).amount.map { $0 * scale }
            let count = fraction(value, marks: quarters)
            return StepAmount(name: name, amount: "\(count) \(L10n.text(ingredient.unit))",
                              hint: grams.flatMap { $0 >= 5 ? "≈ " + metricText($0, liquid: false) : nil })
        }
        let liquid = unit == "мл" || unit == "л"
        let key = ProductNames.canonical(ingredient.name)
        if isSpice(ingredient.name) && !liquid && value < 1.5 {
            return StepAmount(name: name, amount: pinchWord(), hint: nil)
        }
        var hint: String?
        if let perGlass = gramsPerGlass(ingredient.name), !liquid, boilProfile(for: ingredient.name)?.pasta != true, value / perGlass >= 0.2 {
            hint = glassHint(value / perGlass)
        } else if liquid || isCookingLiquid(ingredient.name) || isPourableDairy(ingredient.name) || isOil(ingredient.name) {
            let ml = isOil(ingredient.name) && !liquid ? value / 0.91 : value
            hint = ml >= 40 ? glassHint(ml / glassML) : spoonHint(teaspoons: ml / 5)
        } else if isSpice(ingredient.name), value <= 20 {
            hint = spoonHint(teaspoons: key == ProductNames.canonical("Соль") ? value / 6 : value / 2.5)
        } else if let piece = pieceGrams(ingredient.name) {
            let count = value / piece
            if count >= 0.4 && count <= 8 { hint = "≈ \(fraction(count, marks: halves)) \(pieceWord(count))" }
        }
        return StepAmount(name: name, amount: metricText(liquid ? roundedML(value) : value, liquid: liquid), hint: hint)
    }

    /// Kitchen-scale rounding: halves under 10, whole numbers under 100, fives
    /// under a kilo, then kilos or liters with one decimal.
    static func metricText(_ value: Double, liquid: Bool) -> String {
        let english = L10n.languageCode == "en"
        if value >= 1000 {
            let unit = liquid ? (english ? "L" : "л") : (english ? "kg" : "кг")
            return "\(decimal(value / 1000)) \(unit)"
        }
        let shown: Double
        if value < 10 { shown = max(0.5, (value * 2).rounded() / 2) }
        else if value < 100 { shown = value.rounded() }
        else { shown = (value / 5).rounded() * 5 }
        return "\(decimal(shown)) \(liquid ? mlUnit() : gramUnit())"
    }

    private static let quarters: [(Double, String)] = [(0, ""), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾"), (1, "")]
    private static let halves: [(Double, String)] = [(0, ""), (0.5, "½"), (1, "")]

    private static func fraction(_ value: Double, marks: [(Double, String)]) -> String {
        let whole = value.rounded(.down)
        let rest = value - whole
        guard let best = marks.min(by: { abs($0.0 - rest) < abs($1.0 - rest) }) else { return decimal(value) }
        let count = Int(whole) + (best.0 == 1 ? 1 : 0)
        if best.1.isEmpty { return count == 0 ? decimal(value) : String(count) }
        return count == 0 ? best.1 : "\(count)\(best.1)"
    }

    private static func glassHint(_ glasses: Double) -> String? {
        guard glasses >= 0.2, glasses <= 16 else { return nil }
        let text = fraction(glasses, marks: quarters)
        let whole = Int(text) ?? 0
        let partial = whole == 0
        let word: String
        switch L10n.languageCode {
        case "en": word = (whole == 1 || (partial && glasses < 1)) ? "cup" : "cups"
        case "uk": word = partial ? "склянки" : ruForm(whole, "склянка", "склянки", "склянок")
        default: word = partial ? "стакана" : ruForm(whole, "стакан", "стакана", "стаканов")
        }
        return "≈ \(text) \(word)"
    }

    private static func spoonText(teaspoons: Double) -> String {
        let english = L10n.languageCode == "en"
        if teaspoons >= 2.5 {
            return "\(fraction(teaspoons / 3, marks: halves)) \(english ? "tbsp" : "ст. л.")"
        }
        return "\(fraction(teaspoons, marks: quarters)) \(english ? "tsp" : "ч. л.")"
    }

    private static func spoonHint(teaspoons: Double) -> String? {
        guard teaspoons >= 0.2, teaspoons <= 24 else { return nil }
        return "≈ " + spoonText(teaspoons: teaspoons)
    }

    private static func pinchWord() -> String {
        switch L10n.languageCode {
        case "en": return "a pinch"
        case "uk": return "дрібка"
        default: return "щепотка"
        }
    }

    private static func pieceWord(_ count: Double) -> String {
        switch L10n.languageCode {
        case "en": return count <= 1 ? "piece" : "pieces"
        default: return "шт."
        }
    }

    private static func saysSalt(_ step: String) -> Bool {
        tokens(step).contains { word in
            word.hasPrefix("сол") || word.hasPrefix("посол") || word.contains("солите") || word.contains("солить") || word == "salt"
        }
    }

    private static func isPourableDairy(_ name: String) -> Bool {
        let key = ProductNames.canonical(name)
        return key.contains("йогурт") || key.contains("кефир") || key.contains("молок") || key.contains("сливк") || key.contains("ряжен")
    }

    private static func isSpice(_ name: String) -> Bool {
        let key = ProductNames.canonical(name)
        let marks = ["корица", "орегано", "паприка", "куркума", "имбирь", "гвоздика", "майоран", "любисток", "перец", "соль", "тимьян", "розмарин", "зира", "тмин", "мускат"]
        return marks.contains { key.contains($0) } && !key.contains("сладк")
    }

    private static let glassML = 250.0
    private static let rawNotFood: Set<String> = ["сырого", "сырым", "сырая", "сырое", "сырые", "сырой", "сырую"]

    private static func tokens(_ text: String) -> [String] {
        ProductNames.normalized(text).split { !$0.isLetter }.map(String.init)
    }

    private static func wordStems(_ word: String) -> [String] {
        let word = ProductNames.normalized(word)
        guard word.count >= 3 else { return [] }
        var stems = [word]
        if word.count == 4 { stems.append(String(word.prefix(3))) }
        if word.count >= 5 { stems.append(String(word.prefix(word.count - 1))) }
        if word.count >= 6 {
            stems.append(String(word.prefix(word.count - 2)))
            stems.append(String(word.prefix(4)))
        }
        if word.count >= 7 { stems.append(String(word.prefix(5))) }
        return stems.filter { $0.count >= 3 }
    }

    static func mentions(_ name: String, in step: String) -> Bool {
        let stems = nameStems(name)
        return tokens(step).contains { strength(stems, word: $0) > 0 }
    }

    /// Like `mentions`, but a word counts only for the product it resembles most
    /// among the recipe's own: «гречку» names buckwheat, not Greek yogurt, and
    /// «лимонным» names lemon juice rather than a lemon.
    static func mentions(_ name: String, in step: String, among names: [String]) -> Bool {
        let own = nameStems(name)
        let others = names.filter { $0 != name }.map(nameStems)
        return tokens(step).contains { word in
            let mine = strength(own, word: word)
            return mine > 0 && others.allSatisfy { strength($0, word: word) <= mine }
        }
    }

    private static func nameStems(_ name: String) -> [String] {
        var stems = tokens(name).flatMap(wordStems) + tokens(ProductNames.canonical(name)).flatMap(wordStems)
        let aliases = [
            "макароны": ["паст", "спагет", "лапш"],
            "картофель": ["картош"],
            "лук": ["луков"],
            "яйцо": ["яйц", "яиц"],
            "гречка": ["греч"]
        ]
        if let extra = aliases[ProductNames.canonical(name)] { stems.append(contentsOf: extra.map(ProductNames.normalized)) }
        return stems
    }

    /// Length of the longest stem that the word starts with; 0 when none fits.
    private static func strength(_ stems: [String], word: String) -> Int {
        var best = 0
        for stem in stems {
            if rawNotFood.contains(word) && stem.hasPrefix("сыр") { continue }
            let allowance = stem.count <= 3 ? 4 : 5
            if word == stem || (word.hasPrefix(stem) && word.count - stem.count <= allowance) { best = max(best, stem.count) }
        }
        return best
    }

    private static func isBoil(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("вар") || text.contains("кипят") || text.contains("залей") || text.contains("отвар")
    }

    private static func isFry(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("жар") || text.contains("обжар")
    }

    private static func isCookingLiquid(_ name: String) -> Bool {
        let key = ProductNames.canonical(name)
        // Lemon juice is a seasoning, not the liquid a grain cooks in.
        if key.contains("бульон") || (key.contains("сок") && !key.contains("лимон")) { return true }
        return ["вода", "молоко", "кефир", "ряженка"].contains(key)
    }

    private static func isOil(_ name: String) -> Bool {
        ProductNames.canonical(name).contains("масл")
    }

    /// Volume of water for one volume of dry grain. Pasta uses a pot, not this ratio.
    /// Buckwheat as a side is 1:2; millet and rolled oats are the 1:3 porridge ratio.
    private static func boilProfile(for name: String) -> (water: Double, pasta: Bool, couscous: Bool)? {
        let key = ProductNames.canonical(name)
        let table: [String: (Double, Bool, Bool)] = [
            "гречка": (2, false, false),
            "рис": (2, false, false),
            "бурый рис": (2.5, false, false),
            "булгур": (2, false, false),
            "пшено": (3, false, false),
            "овсяные хлопья": (3, false, false),
            "перловка": (3, false, false),
            "киноа": (2, false, false),
            "чечевица красная": (2, false, false),
            "чечевица": (3, false, false),
            "макароны": (0, true, false),
            "кускус": (1, false, true)
        ]
        let keyed = Dictionary(uniqueKeysWithValues: table.map { (ProductNames.canonical($0.key), $0.value) })
        if let hit = keyed[key] { return hit }
        if key.contains("рис") { return (2, false, false) }
        if key.contains("чечевиц") { return (key.contains("красн") ? 2 : 3, false, false) }
        if key.contains("макарон") || key.contains("паст") || key.contains("спагет") || key.contains("лапш") { return (0, true, false) }
        if key.contains("овсян") || key.contains("хлоп") { return (3, false, false) }
        if key.contains("булгур") { return (2, false, false) }
        if key.contains("пшен") { return (3, false, false) }
        if key.contains("кускус") || key.contains("кус кус") { return (1, false, true) }
        return nil
    }

    /// Approximate dry weight of a 250 ml glass. Display only.
    private static func gramsPerGlass(_ name: String) -> Double? {
        let key = ProductNames.canonical(name)
        let table: [String: Double] = [
            "гречка": 210, "рис": 230, "бурый рис": 210, "булгур": 190, "пшено": 200,
            "овсяные хлопья": 90, "перловка": 230, "киноа": 180, "чечевица": 210,
            "чечевица красная": 190, "нут": 200, "манная крупа": 200, "мука": 160,
            "ржаная мука": 140, "рисовая мука": 160, "сахар": 200, "макароны": 100, "кускус": 180
        ]
        let keyed = Dictionary(uniqueKeysWithValues: table.map { (ProductNames.canonical($0.key), $0.value) })
        if let exact = keyed[key] { return exact }
        if key.contains("рис") { return 220 }
        if key.contains("мук") { return 160 }
        if key.contains("чечевиц") { return 200 }
        if key.contains("овсян") || key.contains("хлоп") { return 90 }
        if key.contains("макарон") || key.contains("паст") || key.contains("спагет") { return 100 }
        return nil
    }

    private static func pieceGrams(_ name: String) -> Double? {
        let key = ProductNames.canonical(name)
        let table: [String: Double] = [
            "огурец": 150, "лук": 110, "морковь": 75, "кабачок": 200, "томаты": 120,
            "куриное филе": 200, "филе индейки": 170, "яблоко": 150, "банан": 118,
            "яйцо": 50, "картофель": 150, "перец сладкий": 120, "лимон": 58,
            "апельсин": 130, "брокколи": 250, "баклажан": 250, "свекла": 150, "тыква": 200
        ]
        let keyed = Dictionary(uniqueKeysWithValues: table.map { (ProductNames.canonical($0.key), $0.value) })
        return keyed[key]
    }

    private static func scaledAmount(_ ingredient: Ingredient, scale: Double) -> Double? {
        guard let amount = ingredient.amount, amount > 0 else { return nil }
        let unit = ProductNames.normalized(ingredient.unit)
        switch unit {
        case "кг": return amount * 1000 * scale
        case "л": return amount * 1000 * scale
        default: return amount * scale
        }
    }

    private static func ruForm(_ number: Int, _ one: String, _ few: String, _ many: String) -> String {
        let value = abs(number) % 100
        if value >= 11 && value <= 14 { return many }
        switch value % 10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }

    private static func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 { return String(Int(rounded.rounded())) }
        let whole = Int(rounded)
        let fraction = Int((abs(rounded - Double(whole)) * 10).rounded())
        let separator = L10n.languageCode == "en" ? "." : ","
        return "\(whole)\(separator)\(fraction)"
    }

    private static func gramUnit() -> String { L10n.languageCode == "en" ? "g" : "г" }

    private static func mlUnit() -> String { L10n.languageCode == "en" ? "ml" : "мл" }

    private static func roundedML(_ value: Double) -> Double {
        (value / 10).rounded() * 10
    }
}

enum PlanningCore {
    static func key(_ name: String, _ unit: String) -> String {
        ProductNames.canonical(name) + "|" + ProductNames.normalized(unit)
    }

    static func ingredientSuggestions(recipes: [Recipe], pantry: [PantryItem], query: String) -> [Ingredient] {
        let stocked = Set(pantry.map(IngredientMeasures.normalized).map { key($0.name, $0.unit) })
        var unique: [String: Ingredient] = [:]
        for ingredient in recipes.flatMap(\.ingredients).map(IngredientMeasures.normalized) {
            let id = key(ingredient.name, ingredient.unit)
            if !stocked.contains(id) && ProductNames.matches(ingredient.name, query: query) && unique[id] == nil {
                unique[id] = ingredient
            }
        }
        return unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func stock(for ingredient: Ingredient, pantry: [PantryItem], now: Date = .now) -> (known: Double, uncertain: Bool) {
        let ingredient = IngredientMeasures.normalized(ingredient)
        let active = pantry.map(IngredientMeasures.normalized).filter {
            ProductNames.canonical($0.name) == ProductNames.canonical(ingredient.name) &&
            ($0.expiresOn.map { Calendar.current.startOfDay(for: $0) >= Calendar.current.startOfDay(for: now) } ?? true)
        }
        let matching = active.filter { key($0.name, $0.unit) == key(ingredient.name, ingredient.unit) }
        let incomparable = active.contains {
            key($0.name, $0.unit) != key(ingredient.name, ingredient.unit) && ($0.quantity ?? 1) > 0
        }
        return (matching.compactMap(\.quantity).reduce(0, +), matching.contains { $0.quantity == nil } || incomparable)
    }

    static func readiness(_ recipe: Recipe, portions: Double, pantry: [PantryItem], now: Date = .now) -> RecipeReadiness {
        var covered = 0
        var missing: [String] = []
        var uncertain: [String] = []
        for ingredient in recipe.ingredients.map(IngredientMeasures.normalized) {
            guard let amount = ingredient.amount, amount > 0 else {
                uncertain.append(ingredient.name)
                continue
            }
            let stock = stock(for: ingredient, pantry: pantry, now: now)
            let required = amount * portions / max(1, recipe.baseServings)
            if stock.known >= required {
                covered += 1
            } else if stock.uncertain {
                uncertain.append(ingredient.name)
            } else {
                missing.append(ingredient.name)
            }
        }
        return RecipeReadiness(covered: covered, total: recipe.ingredients.count, missing: missing, uncertain: uncertain)
    }

    static func resolvePlan(slots: [MealSlot], members: [FamilyMember], recipes: [Recipe], pantry: [PantryItem],
                            startDate: Date, now: Date = .now, calendar: Calendar = .current,
                            eatenIDs: Set<String> = [], skippedIDs: Set<String> = [],
                            schedule: MealSchedule = .standard, preparedDishes: [PreparedDish] = [],
                            diary: [DiaryEntry] = [], recipesByID knownIndex: [String: Recipe]? = nil,
                            stopBeforeSlotID: String? = nil, onlySlotID: String? = nil) -> PlanRequirements {
        // Pantry is allocated in time order, so a slot's result depends only on
        // earlier slots. Ranking resolves the earlier slots once
        // (`stopBeforeSlotID`, then `freePantry`) and each candidate alone
        // (`onlySlotID`). `slots` still carries the whole plan for portions.
        struct Aggregate {
            var ingredient: Ingredient
            var required: Double
            var allocated: Double
            var uncertain: Bool
            var aiEstimated: Bool
            var sourceSlots: [String]
        }
        struct Lot {
            let key: String
            let product: String
            let name: String
            let unit: String
            let category: String
            let expiresOn: Date?
            var remaining: Double?
        }
        let membersByID = members.reduce(into: [String: FamilyMember]()) { result, member in
            if result[member.id] == nil { result[member.id] = member }
        }
        let recipesByID = knownIndex ?? recipes.reduce(into: [String: Recipe]()) { result, recipe in
            if result[recipe.id] == nil { result[recipe.id] = recipe }
        }
        var lots = pantry.map(IngredientMeasures.normalized).map { item in
            Lot(key: key(item.name, item.unit), product: ProductNames.canonical(item.name),
                name: item.name, unit: item.unit, category: item.category,
                expiresOn: item.expiresOn, remaining: item.quantity.map { max(0, $0) })
        }.sorted { left, right in
            switch (left.expiresOn, right.expiresOn) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.key < right.key
            }
        }
        var totals: [String: Aggregate] = [:]
        var resolvedSlots: [String: SlotRequirements] = [:]
        let batches = Dictionary(preparedDishes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var foodShares: [String: Double] = [:]
        var readyRemaining = batches.mapValues { $0.remaining(in: diary) }
        let firstDay = calendar.startOfDay(for: startDate)
        let currentDay = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: now)).day ?? 0
        for slot in slots.sorted(by: { ($0.day, $0.chronologicalOrder, $0.id) < ($1.day, $1.chronologicalOrder, $1.id) }) {
            if slot.id == stopBeforeSlotID { break }
            if let onlySlotID, slot.id != onlySlotID { continue }
            let participants = slot.memberIDs.compactMap { membersByID[$0] }
            let status: SlotAvailability
            if skippedIDs.contains(slot.id) { status = .skipped }
            else if participants.isEmpty { status = .noParticipants }
            else if participants.allSatisfy({ eatenIDs.contains("\(slot.id)-\($0.id)") }) { status = .eaten }
            else if recipesByID[slot.recipeID]?.isBeverage == true { status = .unavailable }
            else if slot.allRecipeIDs.contains(where: { recipesByID[$0] == nil || recipesByID[$0]?.isUnavailable == true }) { status = .unavailable }
            else if slot.allRecipeIDs.contains(where: { recipesByID[$0]?.isPlanEligible == false }) { status = .needsReview }
            else if MealTiming.isPastWindow(day: slot.day, kind: slot.kind, currentDay: currentDay,
                                            now: now, schedule: schedule, calendar: calendar) { status = .past }
            else { status = .active }
            guard status == .active || status == .needsReview || status == .past,
                  recipesByID[slot.recipeID] != nil else {
                resolvedSlots[slot.id] = SlotRequirements(slotID: slot.id, recipeID: slot.recipeID, availability: status, ingredients: [])
                continue
            }
            let useDate = calendar.date(byAdding: .day, value: slot.day, to: firstDay) ?? firstDay
            var grouped: [String: (ingredient: Ingredient, amount: Double, unresolved: Bool, aiEstimated: Bool)] = [:]
            var readyUsed = 0.0
            for dish in slot.allRecipeIDs.compactMap({ recipesByID[$0] }) {
              var portions = participants.filter { !eatenIDs.contains("\(slot.id)-\($0.id)") }.reduce(0.0) { sum, member in
                  if dish.isBeverage || dish.mealKinds.contains(3) { return sum + member.portion }
                  let cacheKey = "\(member.id)|\(slot.day)"
                  if let share = foodShares[cacheKey] { return sum + share }
                  let share = PersonalPortions.foodShare(member: member, day: slot.day, slots: slots,
                                                         byID: recipesByID, skippedIDs: skippedIDs)
                  foodShares[cacheKey] = share
                  return sum + share
              }
              if let id = slot.preparedDishIDs?[dish.id], let batch = batches[id],
                 batch.food.recipeID == dish.id, batch.discardedAt == nil,
                 calendar.startOfDay(for: batch.preparedAt) <= useDate,
                 calendar.startOfDay(for: batch.useBy) >= useDate {
                  let used = min(portions, readyRemaining[id] ?? 0)
                  portions -= used
                  readyUsed += used
                  readyRemaining[id] = (readyRemaining[id] ?? 0) - used
              }
              guard portions > 0.001 else { continue }
              for ingredient in dish.ingredients.map(IngredientMeasures.normalized) {
                let id = key(ingredient.name, ingredient.unit)
                var entry = grouped[id] ?? (ingredient, 0, false, false)
                if let amount = ingredient.amount, amount > 0 {
                    entry.amount += amount * portions / max(1, dish.baseServings)
                }
                else { entry.unresolved = true }
                if ingredient.aiEstimated == true { entry.aiEstimated = true }
                grouped[id] = entry
              }
            }
            var lines: [ResolvedIngredient] = []
            for id in grouped.keys.sorted() {
                guard let group = grouped[id] else { continue }
                var toAllocate = group.amount
                var allocated = 0.0
                for index in lots.indices where toAllocate > 0.001 && lots[index].key == id {
                    if let expiry = lots[index].expiresOn,
                       calendar.startOfDay(for: expiry) < calendar.startOfDay(for: useDate) { continue }
                    let taken = min(toAllocate, lots[index].remaining ?? 0)
                    lots[index].remaining = (lots[index].remaining ?? 0) - taken
                    allocated += taken
                    toAllocate -= taken
                }
                let uncertainStock = lots.contains { lot in
                    guard lot.product == ProductNames.canonical(group.ingredient.name) else { return false }
                    if let expiry = lot.expiresOn,
                       calendar.startOfDay(for: expiry) < calendar.startOfDay(for: useDate) { return false }
                    return lot.remaining == nil || (lot.key != id && (lot.remaining ?? 0) > 0)
                }
                let uncertain = group.unresolved || (toAllocate > 0.001 && uncertainStock)
                lines.append(ResolvedIngredient(id: id, name: group.ingredient.name, unit: group.ingredient.unit,
                                                category: group.ingredient.category,
                                                required: group.amount > 0 ? group.amount : nil,
                                                allocated: allocated, uncertain: uncertain))
                var entry = totals[id] ?? Aggregate(ingredient: group.ingredient, required: 0, allocated: 0,
                                                    uncertain: false, aiEstimated: false, sourceSlots: [])
                entry.required += group.amount
                entry.allocated += allocated
                entry.uncertain = entry.uncertain || group.unresolved || (toAllocate > 0.001 && uncertainStock)
                entry.aiEstimated = entry.aiEstimated || group.aiEstimated
                if !entry.sourceSlots.contains(slot.id) { entry.sourceSlots.append(slot.id) }
                totals[id] = entry
            }
            resolvedSlots[slot.id] = SlotRequirements(slotID: slot.id, recipeID: slot.recipeID,
                                                      availability: status, ingredients: lines, preparedServings: readyUsed)
        }
        let needs = totals.map { id, aggregate in
            ShoppingNeed(id: id, name: aggregate.ingredient.name, unit: aggregate.ingredient.unit,
                                category: aggregate.ingredient.category, required: aggregate.required,
                                available: aggregate.allocated, amountUnknown: aggregate.uncertain,
                                aiEstimated: aggregate.aiEstimated,
                                sourceSlots: aggregate.sourceSlots)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let freePantry = lots.map {
            PantryItem(name: $0.name, quantity: $0.remaining, unit: $0.unit,
                       category: $0.category, expiresOn: $0.expiresOn)
        }
        return PlanRequirements(slots: resolvedSlots, shoppingNeeds: needs,
                                inventoryEmpty: pantry.isEmpty, freePantry: freePantry)
    }

    static func shoppingNeeds(slots: [MealSlot], members: [FamilyMember], recipes: [Recipe], pantry: [PantryItem],
                              startDate: Date = .now, now: Date = .now, calendar: Calendar = .current,
                              eatenIDs: Set<String> = [], skippedIDs: Set<String> = []) -> [ShoppingNeed] {
        resolvePlan(slots: slots, members: members, recipes: recipes, pantry: pantry,
                    startDate: startDate, now: now, calendar: calendar, eatenIDs: eatenIDs,
                    skippedIDs: skippedIDs).shoppingNeeds
    }
}

enum CatalogPaging {
    static func nextLimit(current: Int, total: Int, step: Int) -> Int {
        min(total, max(0, current) + max(1, step))
    }
}

enum QuantityInput {
    static func parse(_ input: String, locale: Locale = .current) -> Double? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        guard let number = formatter.number(from: value) else { return nil }
        let result = number.doubleValue
        return result.isFinite && result >= 0 ? result : nil
    }
}
