import SwiftUI
import UniformTypeIdentifiers

struct TodayDiaryCard: View {
    @EnvironmentObject var store: LadStore
    @State private var draft: DiaryEntry?
    private var date: Date { Calendar.current.date(byAdding: .day, value: store.selectedDay, to: store.state.startDate) ?? store.now }
    private var entries: [DiaryEntry] { store.diary.filter { $0.memberID == store.currentMember.id && Calendar.current.isDate($0.eatenAt, inSameDayAs: date) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: "Дневник питания")
                NavigationLink { FoodDiaryReport(initialDate: date) } label: {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 21))
                }.accessibilityLabel(L10n.text("Дневник и отчёты"))
            }
            if entries.isEmpty {
                Text("Запишите фактически съеденное — даже если этого не было в меню.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            } else {
                Text(L10n.format("Записей: %d · известно %.0f ккал", entries.count, entries.flatMap(\.foods).compactMap(\.kcal).reduce(0, +)))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.sage)
                if entries.flatMap(\.foods).contains(where: { $0.kcal == nil }) {
                    Text("Неизвестные значения не включены в сумму.").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            Button {
                draft = DiaryEntry(memberID: store.currentMember.id, memberName: store.currentMember.name,
                                   eatenAt: Calendar.current.isDate(date, inSameDayAs: store.now) ? store.now : min(date, store.now), mealKind: 3, foods: [])
            } label: {
                Label("Съел что-то другое", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }.disabled(Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: store.now))
            NavigationLink { PreparedFoodView() } label: {
                Label(L10n.format("Готовая еда и остатки: %d", store.preparedDishes.count), systemImage: "takeoutbag.and.cup.and.straw")
                    .font(.system(size: 13))
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paleSage.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
            .sheet(item: $draft) { DiaryEntryEditor(entry: $0) }
    }
}

struct DiaryEntryEditor: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State var entry: DiaryEntry
    @State private var showFoods = false
    @State private var showManual = false
    @State private var warning = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.memberName).font(.headline)
                    DatePicker("Когда съел", selection: $entry.eatenAt, in: ...Date.now)
                    Picker("Приём пищи", selection: $entry.mealKind) {
                        ForEach(0..<4) { Text(DiaryCore.preparationLabel($0)).tag($0) }
                    }
                    if entry.timeEstimated { Text("Время перенесено из старой отметки; его можно уточнить.").font(.caption).foregroundStyle(Palette.muted) }
                }
                ForEach($entry.foods) { $food in
                    Section {
                        HStack {
                            Text(food.displayTitle).font(.headline)
                            Spacer()
                            Button(role: .destructive) { entry.foods.removeAll { $0.id == food.id } } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel(L10n.text("Убрать из записи"))
                        }
                        HStack {
                            Text("Базовых порций")
                            Spacer()
                            TextField("Количество", value: $food.servings, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        }
                        Stepper(L10n.format("Порция: %.2f", food.servings), value: $food.servings, in: 0.05...20, step: 0.25)
                        HStack {
                            Text("Фактический вес, г")
                            Spacer()
                            TextField("Необязательно", value: $food.actualWeightGrams, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
                        }
                        if !food.isBeverage {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Приготовление")
                                Picker("Приготовление", selection: $food.preparation) {
                                    ForEach(FoodPreparation.allCases, id: \.self) { Text(L10n.text($0.label)).tag($0) }
                                }.labelsHidden().pickerStyle(.menu)
                            }
                            let matching = store.preparedDishes.filter { $0.food.recipeID == food.recipeID && food.recipeID != nil }
                            if !matching.isEmpty {
                                Menu {
                                    Button("Без привязки к остаткам") { food.preparedDishID = nil }
                                    ForEach(matching) { batch in
                                        Button(L10n.format("Готово %@ · осталось %.2f порции", batch.preparedAt.formatted(date: .abbreviated, time: .omitted), batch.remaining(in: store.diary))) {
                                            let amount = food.servings
                                            food = batch.food
                                            food.id = UUID().uuidString
                                            food.servings = amount
                                            food.preparedDishID = batch.id
                                            food.preparation = .readyCold
                                        }
                                    }
                                } label: { Label("Взять из готовых остатков", systemImage: "takeoutbag.and.cup.and.straw") }
                            }
                            if food.preparedDishID != nil { Text("Порция будет списана из готовой еды.").font(.caption).foregroundStyle(Palette.sage) }
                        }
                        Text(food.kcal.map { L10n.format("На эту порцию: %.0f ккал", $0) } ?? L10n.text("Калорийность не указана"))
                            .font(.caption).foregroundStyle(Palette.sage)
                        if food.preparation.reheated {
                            Text("Потери витаминов при повторном разогреве учтены там, где есть коэффициенты USDA. Для разных приборов используется одна модель.")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                    } footer: {
                        Text("Нутриенты пересчитываются по доле базовой порции. Вес сохраняется как ваша отметка, без выдуманного веса готового блюда.")
                    }
                }
                Section {
                    Button { showFoods = true } label: { Label("Добавить блюдо из каталога", systemImage: "books.vertical") }
                    Button { showManual = true } label: { Label("Записать свою еду", systemImage: "square.and.pencil") }
                    TextField("Заметка", text: $entry.note, axis: .vertical).lineLimit(2...5)
                }
                if let kcal = entry.kcal {
                    Section { Text(L10n.format("Всего: %.0f ккал", kcal)).font(.headline) }
                }
            }
            .navigationTitle("Что я съел").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        entry.timeEstimated = false
                        if store.saveDiaryEntry(entry) { dismiss() } else { warning = true }
                    }.disabled(!entry.isValid)
                }
            }
            .sheet(isPresented: $showFoods) {
                DiaryFoodPicker { recipe in entry.foods.append(DiaryFood(recipe: recipe, servings: store.state.members.first(where: { $0.id == entry.memberID })?.portion ?? 1)) }
            }
            .sheet(isPresented: $showManual) { ManualDiaryFoodSheet { entry.foods.append($0) } }
            .alert("Проверьте запись", isPresented: $warning) { Button("Готово", role: .cancel) {} } message: {
                Text("Проверьте количество, дату и остаток готовой еды. Нельзя списать больше, чем осталось, или записать еду из будущего.")
            }
        }
    }
}

struct DiaryFoodPicker: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let select: (Recipe) -> Void
    private var recipes: [Recipe] {
        store.visibleRecipes.filter { !$0.isUnavailable && !$0.isUnplanned &&
            (query.isEmpty || L10n.text($0.title).localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        NavigationStack {
            List(recipes) { recipe in
                Button { select(recipe); dismiss() } label: {
                    HStack {
                        RecipePicture(recipe: recipe, thumbnail: true).frame(width: 48, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(L10n.text(recipe.title)).foregroundStyle(Palette.ink)
                    }
                }
            }.searchable(text: $query, prompt: "Поиск блюда")
                .navigationTitle("Что вы съели")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }
}

struct ManualDiaryFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var fat: Double?
    @State private var carbs: Double?
    @State private var weight: Double?
    let save: (DiaryFood) -> Void
    private var food: DiaryFood {
        var nutrients: [String: NutrientValue] = [:]
        for (key, value) in [("protein", protein), ("fat", fat), ("carbohydrate", carbs)] {
            if let value { nutrients[key] = NutrientValue(amount: value, unit: "г", source: L10n.text("Введено пользователем"), coverage: 1) }
        }
        var result = DiaryFood(title: name.trimmingCharacters(in: .whitespacesAndNewlines), kcal: kcal, nutrients: nutrients)
        result.actualWeightGrams = weight
        return result
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название еды", text: $name)
                    numberRow("Вес съеденного, г", value: $weight)
                }
                Section {
                    numberRow("Калории, ккал", value: $kcal)
                    numberRow("Белки, г", value: $protein)
                    numberRow("Жиры, г", value: $fat)
                    numberRow("Углеводы, г", value: $carbs)
                } header: { Text("На всю съеденную порцию") } footer: {
                    Text("Можно оставить пустым. Введите данные с упаковки или свои значения; неизвестное не считается нулём.")
                }
            }.navigationTitle("Своя еда")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Добавить") { save(food); dismiss() }.disabled(!food.isValid) }
                }
        }
    }
    private func numberRow(_ label: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(L10n.text(label))
            Spacer()
            TextField("Необязательно", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120)
        }
    }
}

struct ReadyDishSheet: View {
    @EnvironmentObject var store: LadStore
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    var slot: MealSlot?
    var justCooked = false
    @State private var total: Double
    @State private var eaten: Double
    @State private var eatNow: Bool
    @State private var tomorrow = false
    @State private var preparation: FoodPreparation = .readyCold
    @State private var batchID = "new"
    @State private var useBy = Date.now
    @State private var warning = false
    @State private var consumePantry = false
    @State private var batchUUID = UUID().uuidString
    @State private var diaryUUID = UUID().uuidString
    init(recipe: Recipe, slot: MealSlot? = nil, justCooked: Bool = false, portions: Double = 1) {
        self.recipe = recipe; self.slot = slot; self.justCooked = justCooked
        _total = State(initialValue: max(0.25, portions)); _eaten = State(initialValue: min(1, max(0.25, portions)))
        _eatNow = State(initialValue: !justCooked)
        _preparation = State(initialValue: justCooked ? .fresh : .readyCold)
    }
    private var matches: [PreparedDish] { store.preparedDishes.filter { $0.food.recipeID == recipe.id } }
    private var existing: PreparedDish? { matches.first { $0.id == batchID } }
    private var available: Double { existing.map { $0.remaining(in: store.diary) } ?? total }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.text(recipe.title)).font(.headline)
                    if !justCooked && !matches.isEmpty {
                        Picker("Готовая еда", selection: $batchID) {
                            Text("Новая готовая порция").tag("new")
                            ForEach(matches) { batch in Text(batch.preparedAt.formatted(date: .abbreviated, time: .shortened)).tag(batch.id) }
                        }
                    }
                    if existing == nil {
                        HStack { Text("Всего готово, базовых порций"); TextField("Количество", value: $total, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        if justCooked { Toggle("Списать использованные продукты", isOn: $consumePantry) }
                    } else {
                        Text(L10n.format("Осталось: %.2f базовых порций", available))
                    }
                } footer: { if justCooked { Text("Списываются только известные количества продуктов. Неуказанный запас не обнуляется.") } }
                Section {
                    Toggle("Съел сейчас", isOn: $eatNow)
                    if eatNow {
                        HStack { Text("Съел, базовых порций"); TextField("Количество", value: $eaten, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Приготовление")
                            Picker("Приготовление", selection: $preparation) {
                                ForEach(FoodPreparation.allCases, id: \.self) { Text(L10n.text($0.label)).tag($0) }
                            }.labelsHidden().pickerStyle(.menu)
                        }
                    }
                    Toggle("Осталось на завтра", isOn: $tomorrow)
                    Text(L10n.format("После этой записи останется %.2f порции", max(0, available - (eatNow ? eaten : 0))))
                        .font(.caption).foregroundStyle(Palette.sage)
                    DatePicker("Использовать до", selection: $useBy, in: Date.now..., displayedComponents: .date)
                } footer: { Text("Дата — ваша отметка хранения, не гарантия безопасности. Разогрев не продлевает срок хранения автоматически.") }
            }.navigationTitle(L10n.text(justCooked ? "Блюдо готово" : "Готовая еда"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(!available.isFinite || available <= 0 || available > 100 || (eatNow && (!eaten.isFinite || eaten <= 0 || eaten > available || eaten > 20))) }
                }
                .onChange(of: tomorrow) { _, selected in
                    let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                    if !selected { useBy = .now }
                    else if Calendar.current.startOfDay(for: useBy) < Calendar.current.startOfDay(for: nextDay) { useBy = nextDay }
                }
                .onChange(of: useBy) { _, date in tomorrow = Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: .now) }
                .onChange(of: batchID) { _, _ in if let existing { useBy = existing.useBy } }
                .onAppear {
                    guard !justCooked else { return }
                    if let id = slot?.preparedDishIDs?[recipe.id], let batch = matches.first(where: { $0.id == id }) {
                        batchID = id; useBy = batch.useBy
                        eaten = min(store.currentMember.portion, batch.remaining(in: store.diary))
                    }
                }
                .alert("Не удалось записать", isPresented: $warning) { Button("Готово", role: .cancel) {} } message: { Text("Проверьте количество готовой еды и порцию.") }
        }
    }
    private func save() {
        let previousState = store.state
        var batch = existing ?? PreparedDish(id: batchUUID, food: DiaryFood(recipe: recipe, servings: 1), totalServings: total, preparedAt: .now, useBy: useBy)
        batch.useBy = useBy; batch.updatedAt = .now
        store.savePreparedDish(batch, cookedRecipe: recipe, consumePantry: justCooked && consumePantry)
        if let slot { _ = store.attachPreparedDish(batch, to: slot) }
        if eatNow {
            var food = batch.food
            food.id = UUID().uuidString; food.servings = eaten; food.preparation = preparation; food.preparedDishID = batch.id
            var entry = slot.map { store.diaryDraft(for: $0) } ?? DiaryEntry(id: diaryUUID, memberID: store.currentMember.id, memberName: store.currentMember.name, eatenAt: .now, mealKind: 3, foods: [])
            if let slot, store.diaryEntry(for: slot) == nil { entry.foods = [] }
            entry.eatenAt = .now
            entry.foods.removeAll { $0.recipeID == recipe.id }
            entry.foods.append(food)
            if !store.saveDiaryEntry(entry) { store.state = previousState; warning = true; return }
        }
        dismiss()
    }
}

struct PreparedFoodView: View {
    @EnvironmentObject var store: LadStore
    @State private var draft: DiaryEntry?
    @State private var discard: PreparedDish?
    @State private var planning: PreparedDish?
    @State private var warning = false
    @State private var planningWarning = ""
    var body: some View {
        List {
            if store.preparedDishes.isEmpty { Text("Готовых остатков пока нет. Их можно записать в карточке блюда.").foregroundStyle(Palette.muted) }
            ForEach(store.preparedDishes) { batch in
                VStack(alignment: .leading, spacing: 9) {
                    Text(batch.food.displayTitle).font(.headline)
                    Text(L10n.format("Осталось %.2f порции · до %@", batch.remaining(in: store.diary), batch.useBy.formatted(date: .abbreviated, time: .omitted))).font(.caption).foregroundStyle(Palette.muted)
                    HStack {
                        Button("Съел / разогрел") {
                            var food = batch.food
                            food.id = UUID().uuidString; food.servings = min(1, batch.remaining(in: store.diary)); food.preparedDishID = batch.id; food.preparation = .readyCold
                            draft = DiaryEntry(memberID: store.currentMember.id, memberName: store.currentMember.name, eatenAt: .now, mealKind: 3, foods: [food])
                        }
                        Spacer()
                        Button("В меню") { planning = batch }
                    }.font(.system(size: 13, weight: .semibold)).buttonStyle(.borderless)
                    Button("Не осталось", role: .destructive) { discard = batch }
                        .font(.system(size: 12)).buttonStyle(.borderless)
                }.padding(.vertical, 5)
                    .swipeActions { Button("Не осталось", role: .destructive) { discard = batch } }
            }
        }.navigationTitle("Готовая еда и остатки").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $draft) { DiaryEntryEditor(entry: $0) }
            .sheet(item: $planning) { batch in
                NavigationStack {
                    List {
                        Text("Выберите запланированное блюдо, которое возьмёте из готовых остатков.").font(.caption)
                        ForEach(store.state.slots.filter { slot in
                            let date = Calendar.current.date(byAdding: .day, value: slot.day, to: store.state.startDate) ?? store.now
                            return slot.day >= store.currentDay && !store.isSkipped(slot) && !store.state.eatenIDs.contains(where: { $0.hasPrefix(slot.id + "-") }) &&
                                Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: batch.useBy)
                        }) { slot in
                            Button(L10n.format("%@ · %@", store.dateLabel(slot.day), store.kinds[slot.kind])) {
                                if !slot.allRecipeIDs.contains(batch.food.recipeID ?? ""), let recipe = store.allRecipes.first(where: { $0.id == batch.food.recipeID }) {
                                    if let issue = store.assign(recipe, to: slot) { planningWarning = issue; warning = true; return }
                                }
                                let current = store.state.slots.first(where: { $0.id == slot.id }) ?? slot
                                if store.attachPreparedDish(batch, to: current) { planning = nil }
                                else { planningWarning = L10n.text("Проверьте дату хранения, остаток и отметки о съеденном."); warning = true }
                            }
                        }
                    }.navigationTitle("Использовать готовое")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { planning = nil } } }
                        .alert("Не удалось добавить", isPresented: $warning) { Button("Готово", role: .cancel) {} } message: { Text(planningWarning) }
                }
            }
            .confirmationDialog("Не осталось готовой еды?", isPresented: Binding(get: { discard != nil }, set: { if !$0 { discard = nil } }), titleVisibility: .visible) {
                Button("Не осталось", role: .destructive) { if let discard { store.discardPreparedDish(discard) }; discard = nil }
            } message: { Text("Записи о съеденном сохранятся. Остаток больше не будет предлагаться.") }
    }
}

struct DiaryExport: Identifiable {
    let id = UUID()
    let url: URL
    let prompt: String?
}

struct FoodDiaryReport: View {
    @EnvironmentObject var store: LadStore
    @State private var date: Date
    @State private var endDate: Date
    @State private var period = 0
    @State private var allPeople = false
    @State private var showNutrients = false
    @State private var draft: DiaryEntry?
    @State private var deletion: DiaryEntry?
    @State private var export: DiaryExport?
    @State private var exportError = false
    init(initialDate: Date = .now) { _date = State(initialValue: initialDate); _endDate = State(initialValue: initialDate) }
    private var range: DateInterval {
        let calendar = Calendar.current
        let start = period == 1 ? (calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date) : calendar.startOfDay(for: date)
        let end = period == 1 ? (calendar.date(byAdding: .day, value: 7, to: start) ?? start) : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: period == 2 ? max(date, endDate) : date)) ?? date
        return DateInterval(start: start, end: end)
    }
    private var entries: [DiaryEntry] {
        store.diary.filter { $0.eatenAt >= range.start && $0.eatenAt < range.end && (allPeople || $0.memberID == store.currentMember.id) }
    }
    private var foods: [DiaryFood] { entries.flatMap(\.foods) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Период отчёта", selection: $period) { Text("День").tag(0); Text("Неделя").tag(1); Text("Период").tag(2) }.pickerStyle(.segmented)
                DatePicker("Дата", selection: $date, displayedComponents: .date)
                if period == 2 { DatePicker("По дату", selection: $endDate, in: date..., displayedComponents: .date) }
                Toggle("Все профили", isOn: $allPeople)
                if !allPeople { Text(store.currentMember.name).font(.headline) }
                reportSummary
                Button { share(forAI: false) } label: { Label("CSV", systemImage: "square.and.arrow.up") }
                    .font(.system(size: 14, weight: .semibold)).disabled(entries.isEmpty)
                Text("Файл содержит личный дневник. Приложение не отправляет его автоматически; получателя выбираете вы.")
                    .font(.caption).foregroundStyle(Palette.muted)
                if entries.isEmpty { Text("За этот период записей нет.").foregroundStyle(Palette.muted) }
                ForEach(entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(DiaryCore.preparationLabel(entry.mealKind)).font(.headline)
                            Spacer()
                            Text(entry.eatenAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.muted)
                        }
                        if allPeople { Text(entry.memberName).font(.subheadline).foregroundStyle(Palette.sage) }
                        ForEach(entry.foods) { food in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(food.displayTitle).font(.system(size: 15, weight: .medium))
                                Text(L10n.format("%.2f базовой порции · %@", food.servings, L10n.text(food.preparation.label)))
                                    .font(.caption).foregroundStyle(Palette.muted)
                                if let weight = food.actualWeightGrams { Text(L10n.format("Фактический вес: %.0f г", weight)).font(.caption).foregroundStyle(Palette.muted) }
                            }
                        }
                        if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(Palette.muted) }
                        HStack {
                            Button("Изменить") { draft = entry }
                            Spacer()
                            Button("Удалить запись", role: .destructive) { deletion = entry }
                        }.font(.system(size: 13, weight: .semibold))
                    }.padding(17).background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(21)
        }.background(Palette.canvas.ignoresSafeArea()).navigationTitle("Дневник и отчёты").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        draft = DiaryEntry(memberID: store.currentMember.id, memberName: store.currentMember.name,
                                           eatenAt: Calendar.current.isDate(date, inSameDayAs: store.now) ? store.now : min(date, store.now),
                                           mealKind: 3, foods: [])
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L10n.text("Записать свою еду"))
                        .disabled(Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: store.now))
                }
            }
            .sheet(item: $draft) { DiaryEntryEditor(entry: $0) }
            .sheet(item: $export) { DiaryShareSheet(export: $0) }
            .alert("Не удалось создать CSV", isPresented: $exportError) { Button("Готово", role: .cancel) {} }
            .confirmationDialog("Удалить запись?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Удалить запись", role: .destructive) { if let deletion { store.removeDiaryEntry(deletion) }; deletion = nil }
            }
    }
    private var reportSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeading(title: "Фактически съедено")
            Text(L10n.format("Известно %.0f ккал", foods.compactMap(\.kcal).reduce(0, +)))
                .font(.system(size: 25, weight: .semibold, design: .rounded)).foregroundStyle(Palette.sage)
            let unknown = foods.filter { $0.kcal == nil }.count
            if unknown > 0 { Text(L10n.format("Без калорийности: %d. Итог неполный.", unknown)).font(.caption).foregroundStyle(Palette.muted) }
            let available = Set(foods.flatMap { $0.nutrients.keys })
            ForEach(NutrientGuide.visibleKeys(available: available, expanded: showNutrients), id: \.self) { key in
                let total = DiaryCore.total(entries, key: key)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(NutrientGuide.name(key)); Spacer(); Text("\(total.amount.formatted(.number.precision(.fractionLength(0...1)))) \(L10n.text(total.unit))").foregroundStyle(Palette.sage) }.font(.system(size: 14, weight: .medium))
                    NutrientRoleLine(key: key)
                    if total.unknown > 0 { Text(L10n.format("Нет данных у %d позиций", total.unknown)).font(.caption2).foregroundStyle(Palette.muted) }
                }
            }
            if !available.subtracting(NutrientGuide.primaryKeys).isEmpty {
                Button(L10n.text(showNutrients ? "Свернуть нутриенты" : "Все нутриенты")) { withAnimation { showNutrients.toggle() } }.font(.system(size: 13, weight: .semibold))
            }
        }.padding(18).background(Palette.paleSage.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
    }
    private func share(forAI: Bool) {
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lad-export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let url = folder.appendingPathComponent("Lad-food-diary.csv")
            try Data(DiaryCore.csv(entries).utf8).write(to: url, options: [.atomic, .completeFileProtection])
            let prompt = forAI ? L10n.text("Проанализируй мой дневник питания из CSV: что и сколько я съел, итоги по дням, калории и нутриенты. Пустые ячейки означают отсутствие данных, не ноль. Учитывай отметки разогрева. Не делай диагнозов и не придумывай неизвестные значения. Дай краткое резюме и вопросы для уточнения.") : nil
            export = DiaryExport(url: url, prompt: prompt)
        } catch { exportError = true }
    }
}

struct DiaryShareSheet: UIViewControllerRepresentable {
    let export: DiaryExport
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [export.url]
        if let prompt = export.prompt { items.append(prompt) }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: export.url.deletingLastPathComponent()) }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
