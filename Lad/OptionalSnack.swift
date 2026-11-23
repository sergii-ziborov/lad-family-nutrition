import SwiftUI

// Small optional foods, like the separately selected drinks, are not counted
// as additional main-course recipes or silently inserted into every day.
enum CourseSnacks {
    static let kind = 3
    static let mealOrder = [0, 3, 1, 2]
    static let all: [Recipe] = [
        make(id: "snack-yogurt-berries", title: "Йогурт с ягодами", image: "Ingredient-greek-yogurt",
             ingredients: [Ingredient(name: "Йогурт греческий", amount: 100, unit: "г", category: "Молочные продукты"),
                           Ingredient(name: "Ягоды", amount: 50, unit: "г", category: "Овощи и зелень")],
             steps: ["Вымойте свежие ягоды или разморозьте их в холодильнике. Добавьте к йогурту."]),
        make(id: "snack-apple-walnuts", title: "Яблоко и грецкие орехи", image: "Ingredient-apple",
             ingredients: [Ingredient(name: "Яблоко", amount: 100, unit: "г", category: "Овощи и зелень"),
                           Ingredient(name: "Грецкие орехи", amount: 10, unit: "г", category: "Бакалея")],
             steps: ["Вымойте яблоко, удалите сердцевину и взвесьте съедобную часть. Отмерьте орехи; подайте их измельчёнными."]),
        make(id: "snack-curd-cucumber", title: "Творог с огурцом", image: "Ingredient-cottage-cheese",
             ingredients: [Ingredient(name: "Творог", amount: 80, unit: "г", category: "Молочные продукты"),
                           Ingredient(name: "Огурец", amount: 80, unit: "г", category: "Овощи и зелень")],
             steps: ["Вымойте и нарежьте огурец. Подайте с отмеренным творогом."])
    ]

    private static func make(id: String, title: String, image: String, ingredients: [Ingredient], steps: [String]) -> Recipe {
        let energy = EnergyEstimator.evaluate(ingredients)
        var recipe = Recipe(id: id, title: title, caption: "Небольшой перекус по желанию, если завтрака не хватило.",
                            image: image, cuisine: "Домашняя", minutes: 5, kcal: energy.knownBatchKcal, protein: nil,
                            allergens: IngredientAllergens.inferred(from: ingredients), ingredients: ingredients,
                            steps: steps, allergensVerified: true, mealKinds: [kind])
        recipe.energyEstimate = energy
        recipe.kcalEstimated = true
        recipe.nutrientPreparationByIngredient = Dictionary(uniqueKeysWithValues: ingredients.map { ($0.name, "raw") })
        recipe.nutrients = NutrientEstimator.estimate(recipe)
        return recipe
    }
}

extension DemoState {
    var planningSchedule: MealSchedule {
        var result = mealSchedule ?? .standard
        // With no personal lunch time, use the default course's preferred 14:00.
        result.snackMinute = max(0, (mealSchedule?.lunchEnds ?? 14 * 60) - 60)
        return result
    }

    var hasValidMealSlots: Bool {
        let main = slots.filter { $0.kind != CourseSnacks.kind }
        let expected = Set((0..<7).flatMap { day in (0..<3).map { "\(day)-\($0)" } })
        return main.count == 21 && Set(main.map(\.id)) == expected &&
            Set(slots.map(\.id)).count == slots.count && slots.count <= 28 &&
            slots.allSatisfy { (0..<7).contains($0.day) && (0...3).contains($0.kind) && $0.id == "\($0.day)-\($0.kind)" }
    }
}

extension LadStore {
    var offersPreLunchSnack: Bool { selectedCourses.contains(where: \.isCombinedDefaultMenu) }

    func mealKinds(on day: Int, forMember memberID: String? = nil) -> [Int] {
        CourseSnacks.mealOrder.filter { kind in
            guard kind == CourseSnacks.kind else { return true }
            return state.slots.contains { $0.day == day && $0.kind == kind && !$0.memberIDs.isEmpty &&
                (memberID.map($0.memberIDs.contains) ?? true) }
        }
    }

    func preLunchSnack(on day: Int) -> MealSlot? { state.slots.first { $0.day == day && $0.kind == CourseSnacks.kind } }

    func setPreLunchSnack(_ enabled: Bool, on day: Int, memberID: String) -> String? {
        guard offersPreLunchSnack, (currentDay..<7).contains(day), state.members.contains(where: { $0.id == memberID }) else {
            return L10n.text("Перекус можно включить для текущего или будущего дня выбранного меню.")
        }
        let existing = preLunchSnack(on: day)
        guard enabled != (existing?.memberIDs.contains(memberID) == true) else { return nil }
        guard !state.eatenIDs.contains("\(day)-3-\(memberID)") else {
            return L10n.text("Съеденный перекус сохранён в дневнике. Измените запись о съеденном, если нужно исправление.")
        }
        var next = state
        if enabled {
            var proposed = existing ?? MealSlot(id: "\(day)-3", day: day, kind: 3,
                                               recipeID: Recipe.unplanned.id, memberIDs: [])
            proposed.memberIDs.append(memberID)
            let options = CourseSnacks.all.filter { candidate in
                incompatibility(proposed, recipe: candidate) == nil && !participating(proposed).contains {
                    state.dislikes?.contains("\($0.id)|\(candidate.id)") == true
                }
            }
            let eatenBySomeone = state.eatenIDs.contains { $0.hasPrefix("\(proposed.id)-") }
            guard let chosen = options.first(where: { $0.id == proposed.recipeID }) ?? (eatenBySomeone ? nil : options.first) else {
                return L10n.text("Нет подходящего перекуса с учётом ограничений участников. Можно записать другую еду в дневнике.")
            }
            proposed.recipeID = chosen.id
            if let index = next.slots.firstIndex(where: { $0.id == proposed.id }) { next.slots[index] = proposed }
            else { next.slots.append(proposed) }
            next.skippedSlotIDs?.remove(proposed.id)
        } else if let index = next.slots.firstIndex(where: { $0.id == existing?.id }) {
            next.slots[index].memberIDs.removeAll { $0 == memberID }
            if next.slots[index].memberIDs.isEmpty {
                next.skippedSlotIDs?.remove(next.slots[index].id)
                next.slots.remove(at: index)
            }
        }
        state = next
        return nil
    }
}

struct OptionalSnackControl: View {
    @EnvironmentObject var store: LadStore
    let day: Int
    @State private var warning: String?
    private var enabled: Bool { store.preLunchSnack(on: day)?.memberIDs.contains(store.currentMember.id) == true }
    private var eaten: Bool { store.state.eatenIDs.contains("\(day)-3-\(store.currentMember.id)") }
    var body: some View {
        if store.offersPreLunchSnack {
            Toggle(isOn: Binding(get: { enabled }, set: {
                warning = store.setPreLunchSnack($0, on: day, memberID: store.currentMember.id)
            })) {
                Label("Перекус, если не наелись", systemImage: "carrot")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }.tint(Palette.sage).disabled(day < store.currentDay || eaten)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Palette.paleSage.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                .alert(L10n.text("Перекус"), isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
                    Button("Понятно", role: .cancel) { warning = nil }
                } message: { Text(warning ?? "") }
        }
    }
}
