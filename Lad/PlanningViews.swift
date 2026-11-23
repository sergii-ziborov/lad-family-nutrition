import SwiftUI

struct WeekView: View {
    @EnvironmentObject var store: LadStore
    @State private var editingSlot: MealSlot?
    @State private var addingSlot: MealSlot?
    @State private var warning: String?
    @State private var confirmClearOutside = false
    @State private var showMealTimes = false
    @State private var diaryDraft: DiaryEntry?
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(eyebrow: "МЕНЮ ДЛЯ ВСЕХ", title: "Неделя")
                if store.hasSelectedCourses {
                DayPicker()
                VStack(alignment: .leading, spacing: 9) {
                    let portions = store.dayRecipes(for: store.currentMember, day: store.selectedDay)
                    let dayRecipes = portions.map(\.recipe)
                    let energy = Int(portions.reduce(0.0) { $0 + Double($1.recipe.kcal ?? 0) * $1.portion }.rounded())
                    let protein = Int(portions.reduce(0.0) {
                        $0 + ($1.recipe.nutrients["protein"]?.amount ?? Double($1.recipe.protein ?? 0)) * $1.portion
                    }.rounded())
                    Text(dayRecipes.isEmpty ? L10n.format("В этот день %@ не участвует в плане", store.currentMember.name) :
                         dayRecipes.allSatisfy { $0.kcal != nil && ($0.nutrients["protein"] != nil || $0.protein != nil) } ?
                         L10n.format("План для %@: ~%d ккал · белок ~%d г", store.currentMember.name, energy, protein) :
                         dayRecipes.allSatisfy { $0.kcal != nil } ?
                         L10n.format("План для %@: ~%d ккал", store.currentMember.name, energy) :
                         L10n.format("План для %@", store.currentMember.name))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                    DayNutrientSummary(day: store.selectedDay)
                    MenuActionButton(title: "Время еды", icon: "clock") {
                        showMealTimes = true
                    }
                    if store.canUndoReplan {
                        Button("Отменить подбор") { store.undoReplan() }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                    }
                    if store.outsideFutureSlotCount > 0 {
                        Button { confirmClearOutside = true } label: {
                            Label(L10n.format("Убрать блюда вне курсов: %d", store.outsideFutureSlotCount),
                                  systemImage: "xmark.circle")
                        }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.terracotta)
                    }
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
                SectionHeading(title: store.dateLabel(store.selectedDay).capitalized,
                               trailing: L10n.format("%d ПРИЁМА ПИЩИ",
                                                     store.mealKinds(on: store.selectedDay, forMember: store.currentMember.id).filter {
                                                         let slot = store.slot(store.selectedDay, $0)
                                                         return !slot.memberIDs.isEmpty && !store.isSkipped(slot) &&
                                                             !store.recipe(slot).isUnplanned
                                                     }.count))
                OptionalSnackControl(day: store.selectedDay)
                ForEach(store.mealKinds(on: store.selectedDay, forMember: store.currentMember.id), id: \.self) { kind in
                    let slot = store.slot(store.selectedDay, kind)
                    let recipe = store.recipe(slot)
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink { RecipeDetailView(recipe: recipe, slot: slot) } label: {
                            HStack(spacing: 14) {
                                RecipePicture(recipe: recipe, thumbnail: true).frame(width: 72, height: 72).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.kinds[kind].uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Palette.terracotta)
                                    Text(L10n.text(recipe.title)).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                                    Text(L10n.format("%d мин · %d за столом", recipe.minutes, store.participating(slot).count))
                                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    if !recipe.isUnplanned && store.isOutsideSelectedCourses(slot.recipeID, for: slot) {
                                        Text("Вне выбранных курсов")
                                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.terracotta)
                                    }
                                    if let notice = store.mealCardNotice(for: slot) {
                                        Text(notice)
                                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.terracotta)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(L10n.format("Открыть рецепт: %@", L10n.text(recipe.title)))
                        ForEach(slot.extraRecipeIDs ?? [], id: \.self) { extraID in
                            if let extra = store.allRecipes.first(where: { $0.id == extraID }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Palette.sage)
                                    NavigationLink { RecipeDetailView(recipe: extra, slot: slot) } label: {
                                        Text(L10n.text(extra.title)).font(.system(size: 13, weight: .medium))
                                    }
                                    Spacer()
                                    if slot.day >= store.currentDay && !store.state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                                        Button { store.removeExtraDish(extraID, from: slot) } label: {
                                            Image(systemName: "xmark.circle").accessibilityLabel(L10n.text("Убрать дополнительное блюдо"))
                                        }
                                    }
                                }.foregroundStyle(Palette.ink).padding(.top, 7)
                            }
                        }
                        if store.hasSelectedCourses && !recipe.isUnplanned {
                            MealBeveragesView(slot: slot)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                            .padding(.top, 8)
                        }
                        Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 15)
                        PersonDots(members: store.participating(slot))
                        MealActions(slot: slot, onEdit: { editingSlot = $0 }) {
                            diaryDraft = store.diaryDraft(for: slot)
                        }
                        if slot.day >= store.currentDay && !store.isSkipped(slot) &&
                           !recipe.isUnplanned && !store.state.eatenIDs.contains(where: { $0.hasPrefix("\(slot.id)-") }) {
                            Button { addingSlot = slot } label: {
                                Label("Добавить ещё блюдо к приёму", systemImage: "plus.circle")
                            }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                            .padding(.top, 8)
                        }
                        HStack(spacing: 8) {
                            ForEach(store.state.members) { person in
                                Button { warning = store.toggleParticipant(person.id, in: slot) } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: slot.memberIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                        Text(person.name)
                                    }.font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(slot.memberIDs.contains(person.id) ? Palette.sage : Palette.muted)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.top, 15)
                        if let issue = store.incompatibility(slot) {
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11)).foregroundStyle(Palette.terracotta).padding(.top, 9)
                        }
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 22))
                }
                } else {
                    MenuSourceEmptyState()
                }
            }.padding(.horizontal, 21).padding(.top, 12).padding(.bottom, 24)
        }.background(Palette.canvas.ignoresSafeArea())
            .onAppear { store.maintainsDayMenu = true; store.scheduleDayMenuFill() }
            .sheet(isPresented: $showMealTimes) { MealTimesSheet() }
            .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
            .sheet(item: $editingSlot) { slot in RecipeChooser(slot: slot) { recipe, allowDraft in
                warning = store.assign(recipe, to: slot, allowUnverifiedCourseDraft: allowDraft)
                if warning == nil { editingSlot = nil }
            }}
            .sheet(item: $diaryDraft) { DiaryEntryEditor(entry: $0) }
            .sheet(item: $addingSlot) { slot in RecipeChooser(slot: slot, adding: true) { recipe, allowDraft in
                warning = store.addDish(recipe, to: slot, allowUnverifiedCourseDraft: allowDraft)
                if warning == nil { addingSlot = nil }
            }}
            .alert("Проверьте ограничения", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
                Button("Понятно", role: .cancel) { warning = nil }
            } message: { Text(warning ?? "") }
            .confirmationDialog("Очистить будущие блюда вне выбранных курсов?", isPresented: $confirmClearOutside) {
                Button("Очистить будущий план") { store.clearFutureDishesOutsideCourses() }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text("Отмеченные съеденными блюда останутся в истории. Пустые приёмы можно заполнить после выбора курса и пересчёта меню.")
            }
    }
}

struct DayNutrientSummary: View {
    @EnvironmentObject var store: LadStore
    let day: Int
    @State private var isExpanded = false

    private struct Macro {
        let key: String
        let grams: Double
        let unit: String
        let color: Color
        var energy: Double {
            switch key {
            case "protein", "carbohydrate": return grams * 4
            case "fat": return grams * 9
            default: return 0
            }
        }
    }

    private var portions: [(recipe: Recipe, portion: Double)] {
        store.dayRecipes(for: store.currentMember, day: day).filter {
            !$0.recipe.isBeverage || !$0.recipe.nutrients.isEmpty
        }
    }
    private var availableKeys: Set<String> {
        Set(portions.flatMap { $0.recipe.nutrients.keys })
    }
    private var macros: [Macro] {
        let colors = ["protein": Palette.sage, "fat": Palette.terracotta,
                      "carbohydrate": Palette.ink.opacity(0.55), "fiber": Palette.muted]
        return NutrientGuide.primaryKeys.compactMap { key in
            let values = portions.compactMap { item in item.recipe.nutrients[key].map { (value: $0, portion: item.portion) } }
            guard let first = values.first else { return nil }
            let total = values.reduce(0) { $0 + $1.value.amount * $1.portion }
            guard total > 0 else { return nil }
            return Macro(key: key, grams: total, unit: first.value.unit, color: colors[key] ?? Palette.sage)
        }
    }
    private var energyParts: [Macro] { macros.filter { $0.energy > 0 } }
    private var energyTotal: Double { energyParts.reduce(0) { $0 + $1.energy } }
    private var mealEnergy: [(kind: Int, kcal: Int)] {
        store.mealKinds(on: day, forMember: store.currentMember.id).compactMap { kind in
            let slot = store.slot(day, kind)
            guard slot.memberIDs.contains(store.currentMember.id), !store.isSkipped(slot) else { return nil }
            let kcal = store.recipes(slot).filter { !$0.isUnplanned && !$0.isUnavailable }.reduce(0.0) { sum, recipe in
                sum + Double(recipe.kcal ?? 0) * store.portion(for: store.currentMember, recipe: recipe, slot: slot)
            }
            guard kcal > 0 else { return nil }
            return (kind, Int(kcal.rounded()))
        }
    }
    private var gapTargets: WeightGap.Targets? { WeightGap.targets(for: store.currentMember) }
    private var consumedEnergy: Double {
        portions.reduce(0) { $0 + Double($1.recipe.kcal ?? 0) * $1.portion }
    }
    private func missingText(_ missing: Double, unit: String) -> String? {
        guard missing >= 0.5 else { return nil }
        let number = missing >= 10
            ? String(Int(missing.rounded()))
            : missing.formatted(.number.precision(.fractionLength(0...1)))
        return L10n.format("Не хватает ~%@", "\(number) \(L10n.text(unit))")
    }

    var body: some View {
        if !availableKeys.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Нутриенты за день", systemImage: "leaf")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                if energyTotal > 0 {
                    Text("Доля энергии").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                    WeightedBars(parts: energyParts.map { ($0.color, $0.energy) }).frame(height: 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.text("Доля энергии"))
                        .accessibilityValue(energyParts.map { part in
                            "\(NutrientGuide.name(part.key)) \(Int((part.energy / energyTotal * 100).rounded()))%"
                        }.joined(separator: ", "))
                    ForEach(energyParts, id: \.key) { part in
                        HStack(spacing: 8) {
                            Circle().fill(part.color).frame(width: 8, height: 8)
                            Text(NutrientGuide.name(part.key))
                            Spacer(minLength: 8)
                            Text("\(Int((part.energy / energyTotal * 100).rounded()))%")
                                .foregroundStyle(Palette.sage)
                        }.font(.system(size: 12))
                    }
                }
                if !macros.isEmpty {
                    ForEach(macros, id: \.key) { macro in
                        let target = gapTargets.flatMap { WeightGap.amount($0, key: macro.key) }
                        let fitted = WeightGap.remainder(consumed: macro.grams, target: target)
                        let scale = target == nil ? (macros.map(\.grams).max() ?? macro.grams) : fitted.scale
                        let missing = target == nil ? 0 : fitted.missing
                        if scale > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(NutrientGuide.name(macro.key))
                                    Spacer(minLength: 8)
                                    Text("\(macro.grams.formatted(.number.precision(.fractionLength(0...2)))) \(L10n.text(macro.unit))")
                                        .foregroundStyle(Palette.sage)
                                }.font(.system(size: 12))
                                if let gap = missingText(missing, unit: macro.unit) {
                                    Text(gap).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }
                                WeightedBars(parts: [(macro.color, macro.grams), (Palette.line, max(0, scale - macro.grams))].filter { $0.1 > 0 })
                                    .frame(height: 8)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                if let target = gapTargets?.energy, target > 0, consumedEnergy > 0 {
                    let fitted = WeightGap.remainder(consumed: consumedEnergy, target: target)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Ккал за день")
                            Spacer(minLength: 8)
                            Text("\(Int(consumedEnergy.rounded()))")
                                .foregroundStyle(Palette.sage)
                        }.font(.system(size: 12))
                        if let gap = missingText(fitted.missing, unit: "ккал") {
                            Text(gap).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        WeightedBars(parts: [(Palette.sage, consumedEnergy), (Palette.line, max(0, fitted.scale - consumedEnergy))].filter { $0.1 > 0 })
                            .frame(height: 8)
                            .accessibilityHidden(true)
                    }
                }
                if let peak = mealEnergy.map(\.kcal).max(), peak > 0 {
                    Text("Ккал по приёмам").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                        .padding(.top, 2)
                    ForEach(mealEnergy, id: \.kind) { meal in
                        let share = meal.kind == 3 ? nil : gapTargets.map { $0.energy / 3 }
                        let fitted = WeightGap.remainder(consumed: Double(meal.kcal), target: share)
                        let scale = share == nil ? Double(peak) : fitted.scale
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(store.kinds[meal.kind])
                                Spacer(minLength: 8)
                                Text("\(meal.kcal)")
                                    .foregroundStyle(Palette.sage)
                            }.font(.system(size: 12))
                            if let gap = missingText(share == nil ? 0 : fitted.missing, unit: "ккал") {
                                Text(gap).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            WeightedBars(parts: [(Palette.sage, Double(meal.kcal)), (Palette.line, max(0, scale - Double(meal.kcal)))].filter { $0.1 > 0 })
                                .frame(height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                }
                let extraKeys = NutrientGuide.visibleKeys(available: availableKeys.subtracting(NutrientGuide.primaryKeys), expanded: true)
                if isExpanded {
                    ForEach(extraKeys, id: \.self) { key in
                        let values = portions.compactMap { item in item.recipe.nutrients[key].map { (value: $0, portion: item.portion) } }
                        if let first = values.first {
                            let total = values.reduce(0) { $0 + $1.value.amount * $1.portion }
                            HStack(spacing: 6) {
                                Text(NutrientGuide.name(key))
                                Spacer(minLength: 8)
                                Text("\(total.formatted(.number.precision(.fractionLength(0...2)))) \(L10n.text(first.value.unit))")
                                    .foregroundStyle(Palette.sage)
                            }.font(.system(size: 12))
                        }
                    }
                }
                if !extraKeys.isEmpty {
                    Button { withAnimation { isExpanded.toggle() } } label: {
                        Label(isExpanded ? L10n.text("Свернуть") : L10n.format("Ещё нутриенты: %d", extraKeys.count),
                              systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                        .accessibilityValue(isExpanded ? L10n.text("Раскрыто") : L10n.text("Свёрнуто"))
                }
            }.padding(.top, 9)
        }
    }
}

private struct WeightedBars: View {
    let parts: [(Color, Double)]
    var body: some View {
        WeightedBarLayout(weights: parts.map(\.1)) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Capsule().fill(part.0)
            }
        }
    }
}

private struct WeightedBarLayout: Layout {
    let weights: [Double]
    var spacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 10)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = weights.reduce(0, +)
        guard total > 0, !subviews.isEmpty else { return }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let usable = max(0, bounds.width - gaps)
        var x = bounds.minX
        for index in subviews.indices {
            let weight = index < weights.count ? max(0, weights[index]) : 0
            let width = usable * weight / total
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY),
                                  proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

struct NutrientRoleLine: View {
    let key: String
    var body: some View {
        if let entry = NutrientGuide.entries[key] {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.role).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Link(destination: entry.sourceURL) {
                    Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Palette.sage)
                }.accessibilityLabel(L10n.format("Источник: %@", entry.sourceURL.host == "ods.od.nih.gov" ? "NIH ODS" : "FDA"))
            }
        }
    }
}

struct RecipeChooser: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    let slot: MealSlot
    var adding: Bool = false
    let onChoose: (Recipe, Bool) -> Void
    @State private var visibleCount = 12
    @State private var pendingDraft: Recipe?
    private var candidates: [Recipe] {
        let ranked = store.chooserRecipes(for: slot, adding: adding).filter { !adding || !slot.allRecipeIDs.contains($0.id) }.map { recipe in
            let match = adding ? store.requirements(for: recipe, addingTo: slot) : store.requirements(for: recipe, replacing: slot)
            return (recipe: recipe, ready: match?.isReady == true,
                    problems: (match?.shortageCount ?? .max) + (match?.hasUncertainty == true ? 1 : 0))
        }
        return ranked.sorted { left, right in
            if left.ready != right.ready { return left.ready }
            if left.problems != right.problems { return left.problems < right.problems }
            return left.recipe.title < right.recipe.title
        }.map(\.recipe)
    }
    var body: some View {
        let options = candidates
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(options.prefix(visibleCount))) { recipe in
                        Button {
                            if recipe.isPlanEligible { onChoose(recipe, false) }
                            else { pendingDraft = recipe }
                        } label: {
                            HStack(spacing: 12) {
                                RecipePicture(recipe: recipe, thumbnail: true).frame(width: 75, height: 75).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(L10n.text(recipe.title)).font(.system(size: 16, weight: .semibold))
                                    Text(String(format: L10n.text("%d мин · %@"), recipe.minutes, L10n.text(DishVoice.cuisine(for: recipe))))
                                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    if let notice = adding ? store.mealCardNotice(for: recipe, addingTo: slot) : store.mealCardNotice(for: recipe, replacing: slot) {
                                        Text(notice)
                                            .font(.system(size: 11)).foregroundStyle(Palette.terracotta)
                                            .lineLimit(2)
                                    } else if !recipe.isPlanEligible {
                                        Text("Уточните количества ингредиентов")
                                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.terracotta)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Palette.sage)
                            }.foregroundStyle(Palette.ink).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    if visibleCount < options.count {
                        ProgressView("Загружаем ещё блюда…")
                            .padding(12)
                            .onAppear { visibleCount = CatalogPaging.nextLimit(current: visibleCount, total: options.count, step: 12) }
                    }
                    if options.isEmpty {
                        Text(store.hasSelectedCourses
                             ? "В выбранных курсах нет совместимого блюда с тегом этого приёма. Проверьте участников и ограничения."
                             : "Выберите курс в каталоге, чтобы появились блюда для этого приёма.")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                }.padding(20)
            }.background(Palette.canvas.ignoresSafeArea()).navigationTitle(adding ? "Добавить блюдо" : "Выбрать блюдо")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .alert("Укажите недостающие количества", isPresented: Binding(get: { pendingDraft != nil }, set: { if !$0 { pendingDraft = nil } })) {
            Button("Добавить в план") {
                if let recipe = pendingDraft { onChoose(recipe, true) }
                pendingDraft = nil
            }
            Button("Отмена", role: .cancel) { pendingDraft = nil }
        } message: {
            Text("Для расчёта покупок укажите недостающие количества ингредиентов.")
        }
    }
}

struct RecipesView: View {
    @EnvironmentObject var store: LadStore
    @State private var query = ""
    @State private var filter = "Все"
    @State private var visibleCount = 12
    private var filters: [String] {
        ["Все", "Завтрак", "Обед", "Ужин", "Перекус", "Есть дома", "Не хватает", "Нравится"]
    }
    private var results: [Recipe] {
        store.visibleRecipes.filter { recipe in
            guard !recipe.isBeverage,
                  (!store.courses.contains(where: \.isCombinedDefaultMenu) || store.courses.contains { $0.recipeIDs.contains(recipe.id) } ||
                   (filter == "Перекус" && store.offersPreLunchSnack && recipe.mealKinds == [3])),
                  (query.isEmpty || recipe.title.localizedCaseInsensitiveContains(query) ||
                   L10n.text(recipe.title).localizedCaseInsensitiveContains(query)) else { return false }
            if let kind = ["Завтрак", "Обед", "Ужин", "Перекус"].firstIndex(of: filter) { return recipe.mealKinds.contains(kind) }
            switch filter {
            case "Нравится": return store.isFavorite(recipe.id)
            case "Есть дома":
                let readiness = store.readiness(recipe)
                return !recipe.ingredients.isEmpty && readiness.missing.isEmpty && readiness.uncertain.isEmpty
            case "Не хватает":
                let readiness = store.readiness(recipe)
                return !readiness.missing.isEmpty || !readiness.uncertain.isEmpty
            default: return true
            }
        }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                PageTitle(eyebrow: "ИДЕИ ДЛЯ СТОЛА", title: "Каталог")
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField(L10n.text("Найти блюдо"), text: $query).font(.system(size: 15))
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 15))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { name in
                            Button { filter = name } label: {
                                Text(L10n.text(name)).font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 15).padding(.vertical, 10)
                                    .background(filter == name ? Palette.sage : .white, in: Capsule())
                                    .foregroundStyle(filter == name ? .white : Palette.ink)
                            }
                        }
                    }
                }.contentMargins(.trailing, 21)
                SectionHeading(title: "Блюда курса",
                               trailing: L10n.format("%d БЛЮДА", results.count))
                ForEach(Array(results.prefix(visibleCount))) { recipe in
                    ZStack(alignment: .bottomTrailing) {
                        NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                RecipePicture(recipe: recipe).frame(height: 148).frame(maxWidth: .infinity).clipped()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.text(DishVoice.cuisine(for: recipe)).uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Palette.terracotta)
                                    Text(L10n.text(recipe.title)).font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                                    Text(recipe.mealKinds.map { store.kinds[$0] }.joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                    Text(recipe.kcal.map { L10n.format("%d мин · ~%d ккал", recipe.minutes, $0) } ??
                                         L10n.format("%d мин", recipe.minutes))
                                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).padding(.trailing, 56)
                            }.background(.white, in: RoundedRectangle(cornerRadius: 22)).clipShape(RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                        VStack(spacing: 2) {
                            Button { store.toggleFavorite(recipe.id) } label: {
                                Image(systemName: store.isFavorite(recipe.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.system(size: 18)).foregroundStyle(store.isFavorite(recipe.id) ? Palette.sage : Palette.muted).frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(store.isFavorite(recipe.id) ? "Убрать отметку нравится" : "Нравится")
                            Button { store.toggleDislike(recipe.id) } label: {
                                Image(systemName: store.isDisliked(recipe.id) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                    .font(.system(size: 18)).foregroundStyle(store.isDisliked(recipe.id) ? Palette.terracotta : Palette.muted)
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(store.isDisliked(recipe.id) ? "Убрать отметку не нравится" : "Не нравится")
                        }.padding(8)
                    }
                }
                if visibleCount < results.count {
                    ProgressView("Загружаем ещё рецепты…")
                        .frame(maxWidth: .infinity).padding(14)
                        .onAppear { visibleCount = CatalogPaging.nextLimit(current: visibleCount, total: results.count, step: 12) }
                }
                if results.isEmpty { Text(filter == "Закрытые" ? "Подключите закрытую библиотеку или обновите каталог." : "Пока ничего не нашли. Попробуйте другой запрос.").foregroundStyle(Palette.muted) }
            }.padding(.horizontal, 21).padding(.top, 12).padding(.bottom, 24)
        }.background(Palette.canvas.ignoresSafeArea())
            .onChange(of: query) { _, _ in visibleCount = 12 }
            .onChange(of: filter) { _, _ in visibleCount = 12 }
            .onChange(of: store.allRecipes.count) { _, _ in visibleCount = 12 }
    }
}

struct RecipeDetailView: View {
    @EnvironmentObject var store: LadStore
    let recipe: Recipe
    var slot: MealSlot? = nil
    @State private var showCooking = false
    @State private var showReady = false
    @State private var justCooked = false
    @State private var showAllNutrients = false
    private var portions: Double {
        slot.map { meal in store.participating(meal).reduce(0) { $0 + store.portion(for: $1, recipe: recipe, slot: meal) } } ?? 1
    }
    private var availableNutrients: Set<String> { Set(NutrientGuide.displayOrder.filter { nutrientValue($0) != nil }) }
    var body: some View {
        ScrollViewReader { scroll in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 21) {
                RecipePicture(recipe: recipe).frame(height: 310).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                VStack(alignment: .leading, spacing: 9) {
                    Text(L10n.text(DishVoice.cuisine(for: recipe)).uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.8).foregroundStyle(Palette.terracotta)
                    Text(recipe.mealKinds.map { store.kinds[$0] }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(L10n.text(recipe.title)).font(.system(size: 33, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text(DishVoice.story(for: recipe)).font(.system(size: 16)).foregroundStyle(Palette.ink).lineSpacing(4)
                    servingsNote
                }
                HStack(spacing: 18) {
                    Button { store.toggleFavorite(recipe.id) } label: {
                        Label(store.isFavorite(recipe.id) ? "Нравится" : "Нравится?", systemImage: store.isFavorite(recipe.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    Button { store.toggleDislike(recipe.id) } label: {
                        Label(store.isDisliked(recipe.id) ? "Не нравится" : "Не нравится?", systemImage: store.isDisliked(recipe.id) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                Label(L10n.format("%d мин", recipe.minutes), systemImage: "clock")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
                if let slot, let issue = store.incompatibility(slot) {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.terracotta)
                        .padding(15).background(Palette.peach.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Ингредиенты", trailing: slot == nil ? "1 ПОРЦИЯ" : "НА ВСЕХ")
                    if !recipe.knownAllergens.isEmpty {
                        Label(L10n.format("Аллергены: %@", recipe.knownAllergens.map(L10n.text).joined(separator: ", ")),
                              systemImage: "leaf")
                            .font(.system(size: 12)).foregroundStyle(Palette.terracotta)
                    }
                    if let slot, let notice = store.mealCardNotice(for: slot) {
                        Text(notice)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.terracotta)
                    }
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, sourceIngredient in
                        let ingredient = IngredientMeasures.normalized(sourceIngredient)
                        NavigationLink { IngredientDetailView(name: ingredient.name) } label: {
                        HStack(spacing: 10) {
                            IngredientPhoto(name: ingredient.name).frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(([ingredient.name] + (ingredient.alternatives ?? [])).map(L10n.text).joined(separator: " / "))
                                .font(.system(size: 15))
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 3) {
                                if recipe.baseServings > 0, let cost = FoodCost.ingredient(ingredient, prices: store.ingredientPrices, multiplier: portions / recipe.baseServings) {
                                    Text((cost.approximate ? "≈ " : "") + FoodCost.money(cost.amount, currency: cost.currency))
                                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                                } else if ingredient.amount != nil {
                                    Text("нет цены").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                                }
                                if let amount = ingredient.amount, amount > 0 {
                                    Text((ingredient.aiEstimated == true ? "≈" : "") + (ingredient.amountMax.map { maxAmount in
                                        "\((amount * portions / recipe.baseServings).formatted(.number.precision(.fractionLength(0...1))))–\((maxAmount * portions / recipe.baseServings).formatted(.number.precision(.fractionLength(0...1)))) \(L10n.text(ingredient.unit))"
                                    } ?? "\((amount * portions / recipe.baseServings).formatted(.number.precision(.fractionLength(0...1)))) \(L10n.text(ingredient.unit))"))
                                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.sage)
                                } else {
                                    Text("уточнить").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                                }
                            }
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }.foregroundStyle(Palette.ink).padding(.vertical, 5)
                        }.buttonStyle(.plain)
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }
                    ForEach(CookingGuide.unmeasuredTaste(recipe), id: \.self) { name in
                        HStack(spacing: 10) {
                            IngredientPhoto(name: name).frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(L10n.text(name)).font(.system(size: 15)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 6)
                            Text("по вкусу").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.sage)
                        }.padding(.vertical, 5)
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }
                }
                if !recipe.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "Приготовление")
                        let minutes = CookingGuide.stepMinutes(recipe)
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.format("≈ %d мин", minutes.indices.contains(index) ? minutes[index] : 1))
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
                                Text(CookingGuide.spokenStep(recipe: recipe, index: index, portions: portions))
                                    .font(.system(size: 15)).foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                RecipeCostSummary(recipe: recipe, servings: portions, people: slot.map { store.participating($0).count })
                nutritionSection.id("recipe-nutrients")
                participantSection
                if !recipe.isBeverage && !recipe.isUnavailable {
                    Button { justCooked = false; showReady = true } label: {
                        Label("Уже готово / разогрел", systemImage: "microwave")
                            .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18).background(Palette.paleSage, in: RoundedRectangle(cornerRadius: 17))
                    }.buttonStyle(.plain)
                }
                Button { showCooking = true } label: {
                    HStack { Image(systemName: "flame"); Text("Начать готовить"); Spacer(); Image(systemName: "arrow.right") }
                        .font(.system(size: 15, weight: .semibold)).padding(19).foregroundStyle(.white)
                        .background(Palette.sage, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).disabled(recipe.isUnavailable || (slot.map { store.incompatibility($0) != nil } ?? false))
                    .opacity(recipe.isUnavailable || (slot.map { store.incompatibility($0) != nil } ?? false) ? 0.5 : 1)
            }.padding(.horizontal, 21).padding(.top, 12).padding(.bottom, 120)
        }.background(Palette.canvas.ignoresSafeArea()).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCooking, onDismiss: { if justCooked { showReady = true } }) {
                CookingView(recipe: recipe, portions: portions) { justCooked = true }
            }
            .sheet(isPresented: $showReady, onDismiss: { justCooked = false }) {
                ReadyDishSheet(recipe: recipe, slot: slot, justCooked: justCooked, portions: max(1, portions))
            }
            .sheet(item: $store.replanPreview) { preview in ReplanPreviewSheet(preview: preview) }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--screenshot-all-nutrients") { showAllNutrients = true }
                if ProcessInfo.processInfo.arguments.contains("--screenshot-nutrients") {
                    DispatchQueue.main.async { scroll.scrollTo("recipe-nutrients", anchor: .top) }
                }
                #endif
            }
        }
    }
    /// One line that explains the numbers below: what the recipe is written
    /// for, and by how much it is scaled for the people at this meal.
    @ViewBuilder private var servingsNote: some View {
        let base = recipe.baseServings.formatted(.number.precision(.fractionLength(0...1)))
        VStack(alignment: .leading, spacing: 3) {
            if recipe.baseServings > 0 {
                Label(L10n.format("Рецепт рассчитан на %@ порц.", base), systemImage: "book.closed")
            }
            if let slot, recipe.baseServings > 0, !store.participating(slot).isEmpty {
                let scale = (portions / recipe.baseServings).formatted(.number.precision(.fractionLength(0...1)))
                Label(L10n.format("Готовим на %d чел. — количества ниже уже умножены ×%@", store.participating(slot).count, scale),
                      systemImage: "person.2")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.sage)
    }
    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title)).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.text(value)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Нутриенты", trailing: slot == nil ? "1 ПОРЦИЯ" : "НА ВСЕХ")
            detailMetric("КАЛОРИИ", recipe.kcal.map { L10n.format("~%d ккал", Int(Double($0) * portions)) } ?? L10n.text("нет данных"))
            ForEach(NutrientGuide.visibleKeys(available: availableNutrients, expanded: showAllNutrients), id: \.self) { key in
                if let value = nutrientValue(key) {
                    HStack {
                        Text(NutrientGuide.name(key)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\((value.amount * portions).formatted(.number.precision(.fractionLength(0...1)))) \(L10n.text(value.unit))")
                            .foregroundStyle(Palette.sage)
                    }.font(.system(size: 14, weight: .medium))
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
            }
            let moreCount = availableNutrients.subtracting(NutrientGuide.primaryKeys).count
            if moreCount > 0 {
                Button { withAnimation { showAllNutrients.toggle() } } label: {
                    HStack {
                        Text(showAllNutrients ? L10n.text("Свернуть") : L10n.format("Ещё нутриенты: %d", moreCount))
                        Spacer()
                        Image(systemName: showAllNutrients ? "chevron.up" : "chevron.down")
                    }.font(.system(size: 14, weight: .semibold)).padding(.vertical, 7)
                }.buttonStyle(.plain).foregroundStyle(Palette.sage)
                    .accessibilityValue(showAllNutrients ? L10n.text("Раскрыто") : L10n.text("Свёрнуто"))
            }
            if recipe.nutrients.isEmpty {
                Text("Данные по витаминам и минералам пока отсутствуют.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
    @ViewBuilder private var participantSection: some View {
        if let slot {
            VStack(alignment: .leading, spacing: 12) {
                Text("Одна кухня — разные порции").font(.system(size: 16, weight: .semibold))
                ForEach(store.participating(slot)) { member in
                    let factor = store.portion(for: member, recipe: recipe, slot: slot)
                    let amount = factor.formatted(.number.precision(.fractionLength(0...1)))
                    HStack {
                        Text(member.name).font(.system(size: 14))
                        Spacer()
                        Text(recipe.kcal.map { L10n.format("%@ порц. · ~%d ккал", amount, Int(Double($0) * factor)) } ??
                             L10n.format("%@ порц. · ккал неизвестны", amount))
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.sage)
                    }
                }
                Text("Порция следует за возрастом и целью каждого. Под лёгкое меню она растёт не больше чем на четверть, остальное дадут перекус или фрукты. Ручной размер задаётся в профиле.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(18).background(Palette.paleSage.opacity(0.65), in: RoundedRectangle(cornerRadius: 19))
            Button("Предложить другое") {
                store.proposeNotToday(slot)
            }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.terracotta)
        }
    }
    private func nutrientValue(_ key: String) -> NutrientValue? {
        if let value = recipe.nutrients[key] { return value }
        if key == "protein", let protein = recipe.protein {
            return NutrientValue(amount: Double(protein), unit: "г", source: "", coverage: 1)
        }
        return nil
    }
}

struct CookingView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    let portions: Double
    var completed: () -> Void = {}
    @State private var step = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(L10n.text(recipe.title)).font(.system(size: 22, weight: .semibold, design: .serif)).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 27)).foregroundStyle(Palette.muted) }
                }
                ProgressView(value: Double(step + 1), total: Double(recipe.steps.count)).tint(Palette.sage)
                Text(L10n.format("ШАГ %d ИЗ %d", step + 1, recipe.steps.count))
                    .font(.system(size: 12, weight: .bold)).tracking(1.7).foregroundStyle(Palette.terracotta)
                if recipe.stepImageIDs.indices.contains(step), let imageID = recipe.stepImageIDs[step] {
                    RecipeStepPicture(imageID: imageID, privateAccess: recipe.isPrivate)
                        .frame(height: 235)
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                        .accessibilityLabel(L10n.format("Изображение шага %d", step + 1))
                }
                Text(CookingGuide.spokenStep(recipe: recipe, index: step, portions: portions))
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.format("≈ %d мин", CookingGuide.stepMinutes(recipe)[step]))
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.sage)
                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Назад") { step -= 1 }
                            .font(.system(size: 16, weight: .semibold))
                            .padding(18)
                            .foregroundStyle(Palette.sage)
                    }
                    Button {
                        if step + 1 < recipe.steps.count { step += 1 } else { completed(); dismiss() }
                    } label: {
                        Text(L10n.text(step + 1 < recipe.steps.count ? "Следующий шаг" : "Готово"))
                            .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(18)
                            .background(Palette.sage, in: RoundedRectangle(cornerRadius: 17)).foregroundStyle(.white)
                    }
                }
            }
            .padding(25).padding(.top, 14)
        }.background(Palette.canvas.ignoresSafeArea())
            .presentationDragIndicator(.visible)
    }
}

struct PrivateCatalogSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var token = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34)).foregroundStyle(Palette.sage)
                        .frame(width: 68, height: 68).background(Palette.paleSage, in: RoundedRectangle(cornerRadius: 20))
                    Text("Облако для семьи").font(.system(size: 27, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text("Подключите семейный сервер по адресу и ключу доступа.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("https://адрес-сервера", text: $serverURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).textContentType(.URL)
                            .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
                        SecureField("Личный ключ доступа", text: $token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
                    }
                    Text(L10n.text(store.privateCatalogStatus)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(L10n.text(store.familyCloudStatus)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Button {
                        busy = true
                        Task {
                            await store.connectPrivateCatalog(url: serverURL, token: token)
                            token = ""
                            busy = false
                        }
                    } label: {
                        Text(busy ? "Подключаем…" : "Подключить облако")
                            .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(17)
                            .foregroundStyle(.white).background(Palette.sage, in: RoundedRectangle(cornerRadius: 15))
                    }.disabled(busy)
                    if PrivateRecipeAccess.isConfigured {
                        HStack {
                            Button("Обновить") {
                                Task {
                                    await store.refreshPrivateRecipes()
                                    await store.refreshFamily()
                                }
                            }
                            Spacer()
                            Button("Отключить", role: .destructive) { store.disconnectPrivateCatalog(); token = "" }
                        }.font(.system(size: 14, weight: .semibold)).padding(.top, 4)
                    }
                    Text("Ключ доступа можно отозвать. Уже сохранённые копии рецептов останутся у получателя.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 12)
                }.padding(21)
            }.background(Palette.canvas.ignoresSafeArea())
                .navigationTitle("Каталог").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }.onAppear { serverURL = store.privateCatalogURL }
    }
}
