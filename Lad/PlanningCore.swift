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
            return clampShare(fitted * goalScale(member), upper: 3)
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

    /// `profileShare` is a share of a 2,000 kcal reference day. The authored
    /// servings of a course do not add up to that: the default course gives
    /// roughly 650–1,100 kcal a day at one serving. Applying the share to
    /// those servings left children (65–80%) with a few hundred kcal a day.
    /// For anyone whose share comes from age, goal or a typed calorie figure,
    /// convert it to servings of the household's actual menu for that day.
    /// The relation between people stays the same (85% vs 100% vs 65%); only
    /// the absolute plate follows the menu. A day without three planned
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
        // Same UI limit as the adult opt-in path; callers show what is left.
        return min(3, max(0.4, (need - fixed) / menu))
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

    static func stepMinutes(_ recipe: Recipe) -> [Int] {
        let steps = recipe.steps
        guard !steps.isEmpty else { return [] }
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

    /// Household reading of one authored step. The recipe JSON stays the source of
    /// the grams; glasses and spoons are only the words on the cooking sheet.
    /// A glass is 250 ml. Cooking water and a spoon of frying oil are named here
    /// and are not added to the shopping list.
    static func spokenStep(recipe: Recipe, index: Int, portions: Double) -> String {
        guard recipe.steps.indices.contains(index) else { return "" }
        let step = recipe.steps[index]
        let original = L10n.text(step)
        let scale = (portions > 0 ? portions : 1) / (recipe.baseServings > 0 ? recipe.baseServings : 1)
        let boil = isBoil(step) || (stepMentionsLiquid(step) && !step.lowercased().contains("немного"))
        var shown = recipe.ingredients.filter { ($0.amount ?? 0) > 0 && mentions($0.name, in: step) }
        let grains = shown.filter { boilProfile(for: $0.name) != nil }
        let liquids = recipe.ingredients.filter { isCookingLiquid($0.name) && ($0.amount ?? 0) > 0 }
        let grain = grains.first
        let profile = grain.flatMap { boilProfile(for: $0.name) }
        let wantsLiquid = grain != nil && boil && profile?.pasta != true
        if wantsLiquid {
            for liquid in liquids where !shown.contains(where: { $0.id == liquid.id }) {
                shown.append(liquid)
            }
        }
        var measures: [String] = []
        var pastaLine: String?
        for ingredient in shown {
            guard let line = measurePhrase(ingredient, scale: scale) else { continue }
            if profile?.pasta == true && boilProfile(for: ingredient.name)?.pasta == true {
                pastaLine = line
            } else {
                measures.append(line)
            }
        }
        var cookingWater: Double?
        if wantsLiquid && liquids.isEmpty, let grain, let profile, !profile.pasta,
           let perGlass = gramsPerGlass(grain.name), perGlass > 0, let grams = scaledAmount(grain, scale: scale) {
            let ml = grams / perGlass * profile.water * glassML
            if ml >= 40 {
                cookingWater = ml
                if let water = glassPhrase(glasses: ml / glassML, food: "Вода", note: about(metric(roundedML(ml), mlUnit()))) {
                    measures.append(water)
                }
            }
        } else if profile?.pasta == true, let grain, let grams = scaledAmount(grain, scale: scale), grams > 0 {
            cookingWater = max(500, grams / 100 * 1000)
        } else {
            let listed = liquids.reduce(0.0) { sum, item in
                guard let amount = scaledAmount(item, scale: scale) else { return sum }
                return sum + amount
            }
            if listed >= 40 { cookingWater = listed }
        }
        let detailed = alreadyDetailed(step)
        let sweet = isSweetWithoutMeat(recipe) || recipe.isBeverage
        let action = kitchenKind(step: step, profile: profile, boiling: boil)
        let minutes = stepMinutes(recipe).indices.contains(index) ? stepMinutes(recipe)[index] : max(1, recipe.minutes)
        var sentences: [String] = []
        if !measures.isEmpty {
            sentences.append(L10n.format("На эту готовку: %@.", join(measures)))
        }
        if !sweet, let salt = saltCue(step: step, recipe: recipe, kind: action, waterML: cookingWater) {
            sentences.append(salt)
        }
        if !detailed, let method = methodSentence(recipe: recipe, step: step, kind: action, minutes: minutes, pastaLine: pastaLine, grain: grain, scale: scale) {
            sentences.append(method)
        }
        if detailed && !sweet && !hasDoneness(step) && [.boil, .pasta, .couscous, .fry, .stew, .bake, .pan, .steam, .simmer].contains(action) {
            sentences.append(L10n.text("Готово, когда середина мягкая и без сырого вкуса, а жидкость впиталась или почти выкипела."))
        }
        guard !sentences.isEmpty else { return original }
        return original + "\n\n" + sentences.joined(separator: " ")
    }

    private enum KitchenKind: Equatable {
        case pasta, couscous, boil, fry, stew, bake, pan, steam, simmer
        case chop, mix, serve, chill, cool, toast, mash, warm, shape, pound, wash, season, assemble, finish, plain
    }

    private static func kitchenKind(step: String, profile: (water: Double, pasta: Bool, couscous: Bool)?, boiling: Bool) -> KitchenKind {
        if profile?.pasta == true && boiling { return .pasta }
        if profile?.couscous == true && boiling { return .couscous }
        if profile != nil && boiling && profile?.pasta != true && !isContinuation(step) { return .boil }
        if isSteam(step) { return .steam }
        if isFry(step) { return .fry }
        if isStew(step) { return .stew }
        if isPan(step) { return .pan }
        if isBake(step) { return .bake }
        if isSimmer(step) || isContinuation(step) { return .simmer }
        if isBoil(step) || boiling { return .boil }
        if isChill(step) { return .chill }
        if isCool(step) { return .cool }
        if isToast(step) { return .toast }
        if isMash(step) { return .mash }
        if isWarm(step) { return .warm }
        if isShape(step) { return .shape }
        if isPound(step) { return .pound }
        if isChop(step) { return .chop }
        if isWash(step) { return .wash }
        if isSeason(step) { return .season }
        if isAssemble(step) { return .assemble }
        if isFinish(step) { return .finish }
        if isServe(step) { return .serve }
        if isMix(step) { return .mix }
        return .plain
    }

    /// Salt is named in the step only. It is not given a shopping weight.
    private static func saltCue(step: String, recipe: Recipe, kind: KitchenKind, waterML: Double?) -> String? {
        let named = saysSalt(step) || recipe.ingredients.contains { ProductNames.canonical($0.name) == ProductNames.canonical("Соль") }
        let timed = saysSaltTiming(step)
        switch kind {
        case .pasta, .couscous, .boil:
            if named && timed { return nil }
            if named { return L10n.text("Эту соль всыпьте в холодную воду до закипания, потом включайте огонь.") }
            return L10n.format("Соль всыпьте в холодную воду до закипания: %@. Размешайте и только потом включайте сильный огонь.", saltSpoon(waterML))
        case .fry, .pan:
            if named { return nil }
            return L10n.text("Посолите и поперчите со всех сторон до сковороды: щепотка соли и щепотка перца. На тарелке соль уже не пройдёт внутрь.")
        case .simmer:
            if named && timed { return nil }
            if named { return L10n.text("Эту соль вмешайте сейчас и попробуйте. Крышку снова закройте, огонь оставьте слабым.") }
            return L10n.text("Попробуйте сейчас. Если соли мало, досолите и размешайте. Крышку держите закрытой, огонь слабый.")
        case .stew:
            if named && timed { return nil }
            if named { return L10n.text("Эту соль кладите, когда закипит, и попробуйте за пять минут до конца.") }
            return L10n.format("Соль кладите, когда закипит, не в холодную воду: %@. За пять минут до конца попробуйте, при тушении соль чувствуется сильнее.", saltSpoon(waterML))
        case .bake:
            if named { return nil }
            return L10n.text("Посолите до духовки, не после: щепотка соли на куски. Противень поставьте на средний уровень уже горячей духовки.")
        case .serve where !isSweetWithoutMeat(recipe) && !isFruitPlate(recipe):
            if named { return nil }
            return L10n.text("Если соли мало, досолите в общей посуде и перемешайте. В тарелке соль останется сверху.")
        default:
            return nil
        }
    }

    private static func methodSentence(recipe: Recipe, step: String, kind: KitchenKind, minutes: Int, pastaLine: String?, grain: Ingredient?, scale: Double) -> String? {
        switch kind {
        case .pasta:
            guard let pastaLine else { return nil }
            let grams = grain.flatMap { scaledAmount($0, scale: scale) } ?? 0
            return L10n.format("На %@ возьмите большую кастрюлю воды, %@, чтобы она свободно двигалась. Когда вода бурно кипит, опустите пасту, сразу перемешайте и варите без крышки до мягкости, около %d минут. Откиньте, не промывайте.", pastaLine, potPhrase(max(0.5, grams / 100)), minutes)
        case .couscous:
            return L10n.format("Залейте крупу таким же объёмом кипятка, накройте и подождите около %d минут. Не мешайте, пока вода не впитается, затем разрыхлите вилкой.", minutes)
        case .boil where isContinuation(step):
            return L10n.format("Крышку держите закрытой, огонь слабый. Жидкость должна едва кипеть. Загляните один раз и снова накройте. Около %d минут, пока середина не станет мягкой.", minutes)
        case .boil where grain != nil:
            return L10n.format("Переберите крупу и промойте, пока вода не станет прозрачной. Залейте, на сильном огне доведите до кипения, снимите пену, накройте и варите на слабом огне около %d минут, пока вода не впитается, а крупа не станет мягкой. Снимите с огня и подержите под крышкой ещё 5 минут, затем разрыхлите вилкой.", minutes)
        case .boil:
            return L10n.format("Залейте холодной водой так, чтобы она покрывала продукты на два пальца. На сильном огне доведите до кипения, снимите пену, убавьте и варите около %d минут, пока середина не станет мягкой.", minutes)
        case .fry:
            let key = recipe.ingredients.contains(where: { isOil($0.name) })
                ? "Обсушите куски. Разогрейте сковороду, выложите в один слой и не двигайте, пока снизу не появится корочка, затем переверните. Внутри не должно остаться сырого. Около %d минут. Дайте минуту отдохнуть."
                : "Обсушите куски. Разогрейте сковороду со столовой ложкой масла, пока оно не станет жидким и подвижным. Выложите в один слой и не двигайте, пока снизу не появится корочка, затем переверните. Внутри не должно остаться сырого. Около %d минут. Дайте минуту отдохнуть."
            return L10n.format(key, minutes)
        case .pan:
            let key = panKey(recipe: recipe, step: step)
            return L10n.format(key, minutes)
        case .steam:
            return L10n.format("Налейте воду так, чтобы она не касалась продуктов. Накройте и держите пар. Готово, когда середина плотная, около %d минут.", minutes)
        case .simmer:
            return L10n.format("Держите слабый огонь и закрытую крышку. Жидкость должна едва кипеть, не булькать во весь рост. Загляните один раз и снова накройте. Около %d минут.", minutes)
        case .stew:
            let onion = recipe.ingredients.contains { ProductNames.canonical($0.name).contains("лук") && !ProductNames.canonical($0.name).contains("зелен") }
            let key = onion
                ? "Нарежьте куски одного размера. Сначала доведите лук до прозрачности на ложке масла, затем добавьте остальное. Накройте и тушите на слабом огне около %d минут, иногда помешивая, пока нож не входит легко. Если жидкость выкипела раньше, подлейте пару ложек горячей воды."
                : "Нарежьте куски одного размера. Накройте и тушите на слабом огне около %d минут, иногда помешивая, пока нож не входит легко. Если жидкость выкипела раньше, подлейте пару ложек горячей воды."
            return L10n.format(key, minutes)
        case .bake:
            return L10n.format("Духовку разогрейте заранее. Противень поставьте на средний уровень и готовьте около %d минут, пока край не зарумянится, а середина не схватится. В первую половину времени дверцу не открывайте.", minutes)
        case .chop where !specifiesCut(step):
            return L10n.text("Режьте куски одного размера, около 2 см: так они дойдут одновременно. Крупное останется сырым, когда мелкое уже размякнет.")
        case .chop:
            return L10n.text("Держите куски одного размера, как написано выше. Крупное останется сырым, когда мелкое уже размякнет. Кости, если они есть, выньте пальцами до нарезки.")
        case .mix:
            return L10n.text("Мешайте до ровного вида, проходясь по дну и стенкам, пока не останется сухих комков.")
        case .serve where isSweetWithoutMeat(recipe) || isFruitPlate(recipe):
            return L10n.text("Разложите сразу и перемешайте только перед едой, иначе фрукты дадут сок.")
        case .serve:
            return L10n.text("Нарежьте и положите в последнюю очередь, к уже готовому. Не держите это на огне.")
        case .chill:
            return L10n.text("Накройте и уберите в холодильник. На столе готовую еду не держите дольше двух часов. Достаньте незадолго до подачи.")
        case .cool:
            return L10n.text("Снимите с огня и дайте постоять, пока пар ослабнет. Йогурт, сметану и сырые фрукты кладите в тёплую, не кипящую еду.")
        case .toast:
            return L10n.text("Подсушите на сухой сковороде или в тостере, пока хлеб не станет сухим и слегка румяным. Не отходите: он сгорает меньше чем за минуту.")
        case .mash:
            return L10n.text("Разомните вилкой до ровной массы, без крупных кусков. Лимон и соль из этого шага вмешайте сейчас, пока масса ещё рыхлая.")
        case .warm:
            return L10n.format("Держите средний огонь и мешайте. Масло должно стать подвижным, а куски прогреться в середине, без чёрной корочки. Около %d минут.", minutes)
        case .shape:
            return L10n.text("Сформуйте куски одного размера и толщины мокрыми руками, чтобы они дошли одновременно.")
        case .pound:
            return L10n.text("Отбейте через плёнку до одной толщины. Посолите с обеих сторон до нагрева и сразу сверните, пока начинка не вытекла.")
        case .wash:
            return L10n.text("Промойте холодной водой и хорошо обсушите. Мокрые ягоды, зелень и рыба испортят вкус и не подрумянятся. Косточки и сердцевину удалите до готовки.")
        case .season:
            return L10n.text("Соль и перец из списка вмешайте в общую посуду. Сыр и зелень разложите по тарелкам в конце, иначе зелень потемнеет.")
        case .assemble:
            return L10n.text("Форму смажьте ложкой масла или застелите пергаментом. Разложите ровным слоем: соус и сыр сверху, чтобы край не высох раньше середины.")
        case .finish:
            if step.lowercased().contains("лим") || step.lowercased().contains("полей") {
                return L10n.text("Полейте в самом конце, уже без огня. В кипящей еде сок горчит.")
            }
            return L10n.text("Снимите с огня. Сыр и соус вмешайте в конце и оставьте на минуту под крышкой, пока сыр не начнёт тянуться.")
        case .plain:
            return nil
        }
    }

    private static func panKey(recipe: Recipe, step: String) -> String {
        if isDryPan(step) {
            return "Сковороду прогрейте до горячей, без масла. Выложите в один слой и не двигайте, пока низ не схватится, затем переверните. Около %d минут. Дайте минуту отдохнуть."
        }
        if recipe.ingredients.contains(where: { isOil($0.name) }) || step.lowercased().contains("масл") {
            return "Разогрейте сковороду с уже взятым маслом. Выложите в один слой и не двигайте, пока снизу не появится корочка, затем переверните. Около %d минут. Дайте минуту отдохнуть."
        }
        return "Разогрейте сковороду со столовой ложкой масла, пока оно не станет жидким. Выложите в один слой и не двигайте, пока снизу не появится корочка, затем переверните. Около %d минут. Дайте минуту отдохнуть."
    }

    private static func saysSalt(_ step: String) -> Bool {
        tokens(step).contains { word in
            word.hasPrefix("сол") || word.hasPrefix("посол") || word.contains("солите") || word.contains("солить") || word == "salt"
        }
    }

    private static func saysSaltTiming(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("до закипания") || text.contains("в холодн") || text.contains("в конце") || text.contains("в начале") || text.contains("до духов") || text.contains("до сковород")
    }

    private static func hasDoneness(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("мягк") || text.contains("корочк") || text.contains("впита") || text.contains("°") || text.contains("прозрач") || text.contains("сырого") || text.contains("схват") || text.contains("румян")
    }

    private static func specifiesCut(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("мелко") || text.contains("крупно") || text.contains("кубик") || text.contains("дольк") || text.contains("кружк") || text.contains("солом") || text.contains("см") || text.contains("тонк")
    }

    private static func isBake(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("запек") || text.contains("духов") || text.contains("выпек") || text.contains("пекит")
    }

    private static func isChop(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("нареж") || text.contains("нарез") || text.contains("пореж") || text.contains("нашинк") || text.contains("измельч") || text.contains("поруб") || text.contains("натри") || text.contains("разреж") || text.contains("раскрош")
    }

    private static func isMix(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("смеша") || text.contains("разотр") || text.contains("вмеша") || text.contains("взбей") || text.contains("перемеш") || text.contains("вымеша") || text.contains("соедини") || text.contains("размеша")
    }

    private static func isServe(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("подав") || text.contains("подай") || text.contains("разлож") || text.contains("перед едой")
    }

    private static func isContinuation(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("ещё") || text.contains("еще") || text.contains("продолж")
    }

    private static func isSteam(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("на пару") || text.contains("на пару")
    }

    private static func isPan(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("сковород") || text.contains("антипригар") || text.contains("с каждой стороны") || text.contains("с обеих сторон") || text.contains("без масла") || text.contains("наливайте")
    }

    private static func isDryPan(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("без масла") || text.contains("без добавления масла") || text.contains("сухой")
    }

    private static func isSimmer(_ step: String) -> Bool {
        let text = step.lowercased()
        if isContinuation(step) { return true }
        if text.contains("убавьте") || text.contains("умеренн") || text.contains("размягч") { return true }
        let lid = text.contains("крышкой") || text.contains("под крышкой")
        let starting = text.contains("промой") || text.contains("залей") || text.contains("в холод")
        return lid && !starting
    }

    private static func isChill(_ step: String) -> Bool {
        step.lowercased().contains("холодиль")
    }

    private static func isCool(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("остыт") || text.contains("остуд") || text.contains("постоять")
    }

    private static func isToast(_ step: String) -> Bool {
        step.lowercased().contains("подсуш")
    }

    private static func isMash(_ step: String) -> Bool {
        step.lowercased().contains("разомн")
    }

    private static func isWarm(_ step: String) -> Bool {
        step.lowercased().contains("прогре")
    }

    private static func isShape(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("сформу") || text.contains("сформир") || text.contains("сверн")
    }

    private static func isPound(_ step: String) -> Bool {
        step.lowercased().contains("отбей")
    }

    private static func isWash(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("промой") || text.contains("вымой") || text.contains("обсуш") || text.contains("размороз") || text.contains("сердцевин") || text.contains("кост")
    }

    private static func isSeason(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("посол") || text.contains("поперч")
    }

    private static func isAssemble(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("вылож") || text.contains("перелож") || text.contains("улож") || text.contains("пергамент") || text.contains("в форму")
    }

    private static func isFinish(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("лавров") || text.contains("перед подачей") || text.contains("полей") || text.contains("посыпь")
    }

    private static func isFruitPlate(_ recipe: Recipe) -> Bool {
        if recipe.ingredients.contains(where: { $0.category == "Рыба и мясо" }) { return false }
        let names = recipe.ingredients.map { ProductNames.canonical($0.name) }.joined(separator: " ")
        let fruit = ["яблок", "слив", "ягод", "банан", "груш", "клубник", "малин", "черник"]
        let savory = ["лук", "чеснок", "греч", "рис", "мяс", "рыб", "кури", "нут", "чечевиц"]
        return fruit.contains { names.contains($0) } && !savory.contains { names.contains($0) }
    }

    private static func saltSpoon(_ ml: Double?) -> String {
        let language = L10n.languageCode
        guard let ml, ml > 0 else {
            switch language {
            case "en": return "a teaspoon of salt per liter of water"
            case "uk": return "чайна ложка солі на літр води"
            default: return "чайная ложка соли на литр воды"
            }
        }
        if ml < 350 {
            switch language {
            case "en": return "half a teaspoon of salt"
            case "uk": return "половина чайної ложки солі"
            default: return "половина чайной ложки соли"
            }
        }
        if ml < 800 {
            switch language {
            case "en": return "a teaspoon of salt"
            case "uk": return "чайна ложка солі"
            default: return "чайная ложка соли"
            }
        }
        if ml < 1500 {
            switch language {
            case "en": return "a tablespoon of salt"
            case "uk": return "столова ложка солі"
            default: return "столовая ложка соли"
            }
        }
        switch language {
        case "en": return "a tablespoon of salt per liter of water"
        case "uk": return "столова ложка солі на кожен літр води"
        default: return "столовая ложка соли на каждый литр воды"
        }
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

    private static func mentions(_ name: String, in step: String) -> Bool {
        let words = tokens(step)
        guard !words.isEmpty else { return false }
        var stems = tokens(name).flatMap(wordStems) + tokens(ProductNames.canonical(name)).flatMap(wordStems)
        let key = ProductNames.canonical(name)
        let aliases = [
            "макароны": ["паст", "спагет", "лапш"],
            "картофель": ["картош"],
            "лук": ["луков"],
            "яйцо": ["яйц", "яиц"],
            "гречка": ["греч"]
        ]
        if let extra = aliases[key] { stems.append(contentsOf: extra.map(ProductNames.normalized)) }
        for stem in stems {
            let allowance = stem.count <= 3 ? 4 : 5
            for word in words {
                if rawNotFood.contains(word) && stem.hasPrefix("сыр") { continue }
                if word == stem || (word.hasPrefix(stem) && word.count - stem.count <= allowance) { return true }
            }
        }
        return false
    }

    private static func alreadyDetailed(_ step: String) -> Bool {
        let text = step.lowercased()
        if text.contains("°") || text.contains("минут") || text.contains("мин.") { return true }
        if text.contains("стакан") || text.contains("мл") { return true }
        if text.contains("под крышкой") { return true }
        return text.count >= 100
    }

    private static func isBoil(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("вар") || text.contains("кипят") || text.contains("залей") || text.contains("отвар")
    }

    private static func isFry(_ step: String) -> Bool {
        let text = step.lowercased()
        return text.contains("жар") || text.contains("обжар")
    }

    private static func isStew(_ step: String) -> Bool {
        step.lowercased().contains("туш")
    }

    private static func stepMentionsLiquid(_ step: String) -> Bool {
        tokens(step).contains { word in
            ["вод", "молок", "кефир", "бульон", "ряжен"].contains { word.hasPrefix($0) }
        }
    }

    private static func isCookingLiquid(_ name: String) -> Bool {
        let key = ProductNames.canonical(name)
        if key.contains("бульон") || key.contains("сок") { return true }
        return ["вода", "молоко", "кефир", "ряженка"].contains(key)
    }

    private static func isOil(_ name: String) -> Bool {
        ProductNames.canonical(name).contains("масл")
    }

    private static func isPepper(_ name: String) -> Bool {
        let key = ProductNames.canonical(name)
        return key.contains("перец") && !key.contains("сладк")
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

    private static func measurePhrase(_ ingredient: Ingredient, scale: Double) -> String? {
        guard let amount = scaledAmount(ingredient, scale: scale) else { return nil }
        let unit = ProductNames.normalized(ingredient.unit)
        let name = ingredient.name
        if unit == "шт." || unit == "шт" || unit == "филе" || unit == "зуб." {
            return countPhrase(amount, name: name, piece: pieceGrams(name))
        }
        let grams = unit == "л" || unit == "мл" ? amount : amount
        let asMilliliters = unit == "мл" || unit == "л" || isCookingLiquid(name) || isPourableDairy(name)
        if let one = pieceGrams(name), !asMilliliters, unit != "мл" {
            let count = grams / one
            let nearest = count.rounded()
            if nearest >= 1, nearest <= 4, abs(count - nearest) <= 0.28,
               let line = onePiece(Int(nearest), name: name, grams: grams, small: count < 0.95) {
                return line
            }
        }
        if let perGlass = gramsPerGlass(name), perGlass > 0, !asMilliliters {
            let glasses = grams / perGlass
            if glasses >= 0.2, let line = glassPhrase(glasses: glasses, food: name, note: metric(grams, gramUnit())) {
                return line
            }
        }
        if asMilliliters {
            let ml = isOil(name) ? grams / 0.91 : grams
            if ml >= 40, let line = glassPhrase(glasses: ml / glassML, food: name, note: metric(roundedML(ml), mlUnit())) {
                return line
            }
            if let spoon = spoonPhrase(ml: ml, name: name, gramsNote: metric(grams, unit == "мл" || unit == "л" ? mlUnit() : gramUnit())) {
                return spoon
            }
        } else if isOil(name) || isSpice(name) || grams <= 40 {
            let ml = isOil(name) ? grams / 0.91 : grams
            if grams < 1.5 && isSpice(name) {
                return pinchPhrase(name: name, note: metric(grams, gramUnit()))
            }
            if let spoon = spoonPhrase(ml: ml, name: name, gramsNote: metric(grams, gramUnit())) {
                return spoon
            }
        }
        let unitWord = (unit == "мл" || unit == "л") ? mlUnit() : gramUnit()
        let shown = (unit == "мл" || unit == "л") ? roundedML(grams) : grams
        return plainAmount(shown, unit: unitWord, name: name)
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

    private static func glassPhrase(glasses: Double, food: String, note: String) -> String? {
        guard glasses >= 0.2, glasses <= 12 else { return nil }
        let words = glassWords(snapGlass(glasses))
        let language = L10n.languageCode
        if language == "en" {
            return "\(words) of \(L10n.text(food).lowercased()) (\(note))"
        }
        if let genitive = genitive(food, language: language) {
            return "\(words) \(genitive) (\(note))"
        }
        return "\(L10n.text(food)) — \(words) (\(note))"
    }

    private static func snapGlass(_ raw: Double) -> Double {
        let marks = [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.33, 1.5, 1.67, 2, 2.5, 2.67, 3, 3.5, 4, 5, 6, 8, 10, 12]
        var best = raw
        var bestScore = 1.0
        var pool = marks
        if raw >= 1 { pool.append(raw.rounded()) }
        for mark in pool where mark > 0 {
            let score = abs(raw - mark) / mark
            if score < bestScore {
                bestScore = score
                best = mark
            }
        }
        if bestScore <= 0.12 { return best }
        return (raw * 10).rounded() / 10
    }

    private static func glassWords(_ count: Double) -> String {
        switch L10n.languageCode {
        case "en": return englishGlass(count)
        case "uk": return ukrainianGlass(count)
        default: return russianGlass(count)
        }
    }

    private static func russianGlass(_ count: Double) -> String {
        if near(count, 0.25) { return "четверть стакана" }
        if near(count, 0.33) { return "треть стакана" }
        if near(count, 0.5) { return "полстакана" }
        if near(count, 0.67) { return "две трети стакана" }
        if near(count, 0.75) { return "три четверти стакана" }
        if near(count, 1) { return "стакан" }
        if near(count, 1.25) { return "стакан с четвертью" }
        if near(count, 1.33) { return "один и треть стакана" }
        if near(count, 1.5) { return "полтора стакана" }
        if near(count, 1.67) { return "один и две трети стакана" }
        if near(count, 2) { return "два стакана" }
        if near(count, 2.5) { return "два с половиной стакана" }
        if near(count, 2.67) { return "два и две трети стакана" }
        if near(count, 3) { return "три стакана" }
        if near(count, 3.5) { return "три с половиной стакана" }
        if near(count, 4) { return "четыре стакана" }
        if near(count, count.rounded()) {
            let number = Int(count.rounded())
            return "\(number) \(ruForm(number, "стакан", "стакана", "стаканов"))"
        }
        return "\(decimal(count)) стакана"
    }

    private static func englishGlass(_ count: Double) -> String {
        if near(count, 0.25) { return "a quarter of a glass" }
        if near(count, 0.33) { return "a third of a glass" }
        if near(count, 0.5) { return "half a glass" }
        if near(count, 0.67) { return "two thirds of a glass" }
        if near(count, 0.75) { return "three quarters of a glass" }
        if near(count, 1) { return "a glass" }
        if near(count, 1.5) { return "one and a half glasses" }
        if near(count, 2) { return "two glasses" }
        if near(count, 3) { return "three glasses" }
        if near(count, 4) { return "four glasses" }
        if near(count, count.rounded()) {
            let number = Int(count.rounded())
            return "\(number) \(number == 1 ? "glass" : "glasses")"
        }
        return "\(decimal(count)) glasses"
    }

    private static func ukrainianGlass(_ count: Double) -> String {
        if near(count, 0.25) { return "чверть склянки" }
        if near(count, 0.33) { return "третина склянки" }
        if near(count, 0.5) { return "півсклянки" }
        if near(count, 0.67) { return "дві третини склянки" }
        if near(count, 0.75) { return "три чверті склянки" }
        if near(count, 1) { return "склянка" }
        if near(count, 1.5) { return "півтори склянки" }
        if near(count, 2) { return "дві склянки" }
        if near(count, 2.5) { return "дві з половиною склянки" }
        if near(count, 2.67) { return "дві і дві третини склянки" }
        if near(count, 3) { return "три склянки" }
        if near(count, 4) { return "чотири склянки" }
        if near(count, count.rounded()) {
            let number = Int(count.rounded())
            return "\(number) \(ruForm(number, "склянка", "склянки", "склянок"))"
        }
        return "\(decimal(count)) склянки"
    }

    private static func onePiece(_ count: Int, name: String, grams: Double, small: Bool) -> String? {
        let note = metric(grams, gramUnit())
        let key = ProductNames.canonical(name)
        let language = L10n.languageCode
        if count == 1 {
            let line: String
            switch (language, key) {
            case ("en", let key) where key == ProductNames.canonical("Куриное филе"):
                line = small ? "one small chicken breast" : "one chicken breast"
            case ("uk", let key) where key == ProductNames.canonical("Куриное филе"):
                line = small ? "одне невелике куряче філе" : "одне куряче філе"
            case (_, let key) where key == ProductNames.canonical("Куриное филе"):
                line = small ? "одна небольшая грудка" : "одна грудка"
            case ("en", let key) where key == ProductNames.canonical("Огурец"):
                line = small ? "one small cucumber" : "one cucumber"
            case ("uk", let key) where key == ProductNames.canonical("Огурец"):
                line = small ? "один невеликий огірок" : "один огірок"
            case (_, let key) where key == ProductNames.canonical("Огурец"):
                line = small ? "один небольшой огурец" : "один огурец"
            case ("en", let key) where key == ProductNames.canonical("Картофель"):
                line = "one potato"
            case ("uk", let key) where key == ProductNames.canonical("Картофель"):
                line = "одна картоплина"
            case (_, let key) where key == ProductNames.canonical("Картофель"):
                line = "одна картофелина"
            case ("en", let key) where key == ProductNames.canonical("Лук"):
                line = small ? "one small onion" : "one onion"
            case ("uk", let key) where key == ProductNames.canonical("Лук"):
                line = small ? "одна невелика цибулина" : "одна цибулина"
            case (_, let key) where key == ProductNames.canonical("Лук"):
                line = small ? "одна небольшая луковица" : "одна луковица"
            case ("en", let key) where key == ProductNames.canonical("Яйцо"):
                line = "one egg"
            case ("uk", let key) where key == ProductNames.canonical("Яйцо"):
                line = "одне яйце"
            case (_, let key) where key == ProductNames.canonical("Яйцо"):
                line = "одно яйцо"
            case ("en", _):
                line = "one \(L10n.text(name).lowercased())"
            default:
                let word = L10n.text(name).lowercased()
                line = language == "uk" ? "один \(word)" : "один \(word)"
            }
            return "\(line) (\(note))"
        }
        let food = language == "en" ? L10n.text(name).lowercased() : (genitive(name, language: language) ?? L10n.text(name).lowercased())
        return "\(count) \(food) (\(note))"
    }

    private static func countPhrase(_ count: Double, name: String, piece: Double?) -> String? {
        let language = L10n.languageCode
        let food = language == "en" ? L10n.text(name).lowercased() : (genitive(name, language: language) ?? L10n.text(name).lowercased())
        let words: String
        if near(count, 0.25) { words = language == "en" ? "a quarter of a" : (language == "uk" ? "чверть" : "четверть") }
        else if near(count, 0.5) { words = language == "en" ? "half a" : (language == "uk" ? "половина" : "половина") }
        else if near(count, 1) { words = language == "en" ? "one" : (language == "uk" ? "один" : "один") }
        else { words = decimal(count) }
        let note = piece.map { metric(count * $0, gramUnit()) }
        let body = language == "en" ? "\(words) \(food)" : "\(words) \(food)"
        if let note { return "\(body) (\(note))" }
        return body
    }

    private static func spoonPhrase(ml: Double, name: String, gramsNote: String) -> String? {
        guard ml >= 2, ml <= 70 else { return nil }
        let marks: [(Double, String, String, String)] = [
            (2.5, "половина чайной ложки", "half a teaspoon", "половина чайної ложки"),
            (5, "чайная ложка", "a teaspoon", "чайна ложка"),
            (7.5, "половина столовой ложки", "half a tablespoon", "половина столової ложки"),
            (15, "столовая ложка", "a tablespoon", "столова ложка"),
            (30, "две столовые ложки", "two tablespoons", "дві столові ложки"),
            (45, "три столовые ложки", "three tablespoons", "три столові ложки"),
            (60, "четыре столовые ложки", "four tablespoons", "чотири столові ложки")
        ]
        guard let best = marks.min(by: { abs($0.0 - ml) < abs($1.0 - ml) }), abs(best.0 - ml) / best.0 <= 0.2 else { return nil }
        let words = L10n.languageCode == "en" ? best.2 : (L10n.languageCode == "uk" ? best.3 : best.1)
        let language = L10n.languageCode
        if language == "en" { return "\(words) of \(L10n.text(name).lowercased()) (\(gramsNote))" }
        if let genitive = genitive(name, language: language) { return "\(words) \(genitive) (\(gramsNote))" }
        return "\(L10n.text(name)) — \(words) (\(gramsNote))"
    }

    private static func pinchPhrase(name: String, note: String) -> String {
        let language = L10n.languageCode
        let pinch = language == "en" ? "a pinch" : (language == "uk" ? "дрібка" : "щепотка")
        if language == "en" { return "\(pinch) of \(L10n.text(name).lowercased()) (\(note))" }
        if let genitive = genitive(name, language: language) { return "\(pinch) \(genitive) (\(note))" }
        return "\(L10n.text(name)) — \(pinch) (\(note))"
    }

    private static func plainAmount(_ amount: Double, unit: String, name: String) -> String {
        let note = metric(amount, unit)
        let language = L10n.languageCode
        if language == "en" { return "\(note) \(L10n.text(name).lowercased())" }
        if let genitive = genitive(name, language: language) { return "\(note) \(genitive)" }
        return "\(L10n.text(name)) — \(note)"
    }

    private static func genitive(_ name: String, language: String) -> String? {
        let key = ProductNames.canonical(name)
        let russian = [
            "гречка": "гречки", "рис": "риса", "бурый рис": "бурого риса", "булгур": "булгура",
            "пшено": "пшена", "овсяные хлопья": "овсяных хлопьев", "перловка": "перловки",
            "чечевица": "чечевицы", "чечевица красная": "красной чечевицы", "вода": "воды",
            "молоко": "молока", "кефир": "кефира", "макароны": "макарон", "куриное филе": "куриного филе",
            "огурец": "огурца", "томаты": "томатов", "кабачок": "кабачка", "сыр": "сыра",
            "лук": "лука", "морковь": "моркови", "филе индейки": "филе индейки", "яблоко": "яблока",
            "яйцо": "яйца", "картофель": "картофеля", "перец сладкий": "сладкого перца",
            "йогурт греческий": "греческого йогурта", "йогурт натуральный": "натурального йогурта",
            "оливковое масло": "оливкового масла", "растительное масло": "растительного масла",
            "хлеб": "хлеба", "банан": "банана", "лимон": "лимона", "нут": "нута", "фета": "феты",
            "творог": "творога", "грецкие орехи": "грецких орехов", "корица": "корицы",
            "чеснок": "чеснока", "укроп": "укропа", "капуста": "капусты", "говядина": "говядины",
            "лосось": "лосося", "тыква": "тыквы", "шпинат": "шпината", "сметана": "сметаны",
            "мука": "муки", "ржаная мука": "ржаной муки", "сахар": "сахара", "кускус": "кускуса"
        ]
        let ukrainian = [
            "гречка": "гречки", "рис": "рису", "бурый рис": "бурого рису", "булгур": "булгуру",
            "пшено": "пшона", "овсяные хлопья": "вівсяних пластівців", "вода": "води",
            "молоко": "молока", "кефир": "кефіру", "макароны": "макаронів",
            "куриное филе": "курячого філе", "огурец": "огірка", "томаты": "помідорів",
            "кабачок": "кабачка", "сыр": "сиру", "лук": "цибулі", "морковь": "моркви",
            "филе индейки": "філе індички", "яблоко": "яблука", "яйцо": "яйця",
            "картофель": "картоплі", "перец сладкий": "солодкого перцю",
            "йогурт греческий": "грецького йогурту", "йогурт натуральный": "натурального йогурту",
            "оливковое масло": "оливкової олії", "растительное масло": "олії",
            "хлеб": "хліба", "банан": "банана", "лимон": "лимона", "нут": "нуту",
            "творог": "кисломолочного сиру", "грецкие орехи": "волоських горіхів",
            "корица": "кориці", "чеснок": "часнику", "укроп": "кропу", "тыква": "гарбуза",
            "шпинат": "шпинату", "лосось": "лосося", "мука": "борошна", "сахар": "цукру"
        ]
        let source = language == "uk" ? ukrainian : russian
        let keyed = Dictionary(uniqueKeysWithValues: source.map { (ProductNames.canonical($0.key), $0.value) })
        return keyed[key]
    }

    private static func potPhrase(_ liters: Double) -> String {
        let rounded = max(0.5, (liters * 2).rounded() / 2)
        if abs(rounded - 1) < 0.01 {
            switch L10n.languageCode {
            case "en": return "about 1 liter"
            case "uk": return "близько літра"
            default: return "около литра"
            }
        }
        let number = decimal(rounded)
        switch L10n.languageCode {
        case "en": return "about \(number) liters"
        case "uk": return "близько \(number) л"
        default: return "около \(number) л"
        }
    }

    private static func join(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        if parts.count == 1 { return last }
        let conjunction = L10n.languageCode == "en" ? "and" : (L10n.languageCode == "uk" ? "і" : "и")
        return parts.dropLast().joined(separator: ", ") + " " + conjunction + " " + last
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

    private static func near(_ value: Double, _ target: Double) -> Bool {
        abs(value - target) < 0.02
    }

    private static func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 { return String(Int(rounded.rounded())) }
        let whole = Int(rounded)
        let fraction = Int((abs(rounded - Double(whole)) * 10).rounded())
        let separator = L10n.languageCode == "en" ? "." : ","
        return "\(whole)\(separator)\(fraction)"
    }

    private static func metric(_ value: Double, _ unit: String) -> String {
        let number = abs(value - value.rounded()) < 0.05 ? String(Int(value.rounded())) : decimal(value)
        return "\(number) \(unit)"
    }

    private static func gramUnit() -> String { L10n.languageCode == "en" ? "g" : "г" }
    private static func mlUnit() -> String { L10n.languageCode == "en" ? "ml" : "мл" }

    private static func about(_ text: String) -> String {
        switch L10n.languageCode {
        case "en": return "about \(text)"
        case "uk": return "близько \(text)"
        default: return "около \(text)"
        }
    }

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
